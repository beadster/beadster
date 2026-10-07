// Package main is beadster's bridge to beads: the same storage, ids, validation and history
// the bd CLI uses, called in-process from the sandboxed Mac app. It is built INSIDE a pinned
// beads checkout (scripts/build-beadsffi.sh copies it to <beads>/beadsffi) because the
// read-only embedded open lives in beads' internal packages.
//
// Every call is JSON in, JSON out. engine.go holds the logic and is tested with go test;
// ffi.go only exports it to C.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/steveyegge/beads/internal/configfile"
	"github.com/steveyegge/beads/internal/storage"
	"github.com/steveyegge/beads/internal/storage/embeddeddolt"
	"github.com/steveyegge/beads/internal/storage/schema"
	"github.com/steveyegge/beads/internal/types"
	"github.com/steveyegge/beads/issueops"
)

// Request is one call from Swift.
type Request struct {
	Op     string `json:"op"`
	Handle int64  `json:"handle,omitempty"`
	// open
	BeadsDir string `json:"beads_dir,omitempty"`
	// reads
	ID     string `json:"id,omitempty"`
	Status string `json:"status,omitempty"`
	Limit  *int   `json:"limit,omitempty"`
	// writes
	Actor       string  `json:"actor,omitempty"`
	Title       *string `json:"title,omitempty"`
	Description *string `json:"description,omitempty"`
	Priority    *int    `json:"priority,omitempty"`
	IssueType   *string `json:"issue_type,omitempty"`
	Assignee    *string `json:"assignee,omitempty"`
	NewStatus   *string `json:"new_status,omitempty"`
	Reason      string  `json:"reason,omitempty"`
	Design         *string  `json:"design,omitempty"`
	Acceptance     *string  `json:"acceptance_criteria,omitempty"`
	Notes          *string  `json:"notes,omitempty"`
	AddLabels      []string `json:"add_labels,omitempty"`
	RemoveLabels   []string `json:"remove_labels,omitempty"`
	Parent         string   `json:"parent,omitempty"`
	Target         string   `json:"target,omitempty"`
	LinkType       string   `json:"link_type,omitempty"`
	Text           string   `json:"text,omitempty"`
	Key            string   `json:"key,omitempty"`
	Force          bool     `json:"force,omitempty"`
	// compare-and-set guards: the write lands only if the bead still has these values
	ExpectedStatus   *string `json:"expected_status,omitempty"`
	ExpectedAssignee *string `json:"expected_assignee,omitempty"`
	// events: read the audit log after this cursor (nil: from the start)
	After *Cursor `json:"after,omitempty"`
	// list filters
	FilterType     string `json:"filter_type,omitempty"`
	FilterAssignee string `json:"filter_assignee,omitempty"`
	Label          string `json:"label,omitempty"`
	TitleContains  string `json:"title_contains,omitempty"`
	All            bool   `json:"all,omitempty"` // closed beads too, like bd list --all
	IncludeGates   bool   `json:"include_gates,omitempty"` // bd list hides gate beads unless asked
}

// Response is one answer to Swift. Exactly one of Error or the payload fields is set.
type Response struct {
	Error   *Failure                 `json:"error,omitempty"`
	Handle  int64                    `json:"handle,omitempty"`
	Project *ProjectInfo             `json:"project,omitempty"`
	Issues  []*types.IssueWithCounts `json:"issues,omitempty"`
	Issue   *types.Issue             `json:"issue,omitempty"`
	Details *types.IssueDetails      `json:"details,omitempty"`
	HasMore bool                     `json:"has_more,omitempty"`
	Blocked  []*types.BlockedIssue        `json:"blocked,omitempty"`
	History  []HistoryEntry               `json:"history,omitempty"`
	Memories map[string]string            `json:"memories,omitempty"`
	Progress *types.MoleculeProgressStats `json:"progress,omitempty"`
	Events   []*types.Event               `json:"events,omitempty"`
	Next     *Cursor                      `json:"next,omitempty"`
	Changed bool                     `json:"changed,omitempty"`
}

// Failure keeps beads' own error text: a failure report carries the raw error.
type Failure struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	// schema_ahead / schema_behind: the database's schema version and this build's
	DBVersion     int `json:"db_version,omitempty"`
	BinaryVersion int `json:"binary_version,omitempty"`
}

// ProjectInfo describes an opened workspace.
type ProjectInfo struct {
	BeadsDir string `json:"beads_dir"`
	Database string `json:"database"`
	Mode     string `json:"mode"`
}

// Failure codes Swift switches on.
const (
	CodeBadRequest  = "bad_request"
	CodeNoBeads     = "no_beads"
	CodeServerMode  = "server_mode"
	// the database was written by a NEWER beads: read nothing, ask for an app update
	CodeSchemaAhead = "schema_ahead"
	// the database is OLDER than this beads: reading needs a migration, which only the
	// person can allow (op "migrate"); bd on their machine may still be the old one
	CodeSchemaBehind = "schema_behind"
	CodeNotFound    = "not_found"
	CodeNoHandle    = "no_handle"
	CodeBeads       = "beads"
	CodeBusy        = "busy"
)

type workspace struct {
	beadsDir string
	database string
	// one call at a time per project, like the CLI's one command per process; different
	// projects run side by side
	mu sync.Mutex
}

// Engine owns open workspaces. Calls on one project are serialized (embedded Dolt has one
// writer, and the CLI it mirrors runs one command per process); different projects run in
// parallel. mu guards only the handle table.
type Engine struct {
	mu     sync.Mutex
	next   int64
	opened map[int64]*workspace
}

func NewEngine() *Engine { return &Engine{opened: map[int64]*workspace{}} }

// The app sends nothing: beads' usage metrics and their flush are off before any beads code
// runs (internal/metrics reads these at init time).
func init() {
	for _, k := range []string{"DO_NOT_TRACK", "BD_DISABLE_METRICS", "BD_DISABLE_EVENT_FLUSH"} {
		_ = os.Setenv(k, "1")
	}
}

// Call runs one request and always answers with JSON.
func (e *Engine) Call(raw []byte) []byte {
	var req Request
	if err := json.Unmarshal(raw, &req); err != nil {
		return encode(fail(CodeBadRequest, err))
	}
	return encode(e.dispatch(context.Background(), req))
}

func (e *Engine) dispatch(ctx context.Context, req Request) Response {
	switch req.Op {
	case "open":
		return e.open(ctx, req)
	case "close":
		e.mu.Lock()
		delete(e.opened, req.handle())
		e.mu.Unlock()
		return Response{}
	case "migrate":
		return e.migrate(ctx, req)
	}
	e.mu.Lock()
	ws, ok := e.opened[req.handle()]
	e.mu.Unlock()
	if !ok {
		return fail(CodeNoHandle, fmt.Errorf("no open workspace for handle %d", req.handle()))
	}
	ws.mu.Lock()
	defer ws.mu.Unlock()
	switch req.Op {
	case "ready", "list", "show", "blocked", "history", "memories", "molecule_progress", "events":
		return e.read(ctx, ws, req)
	case "create", "update", "close_issue", "reopen", "claim", "release", "link", "unlink",
		"comment", "approve_gate", "reject_gate", "remember", "forget":
		return e.write(ctx, ws, req)
	default:
		return fail(CodeBadRequest, fmt.Errorf("unknown op %q", req.Op))
	}
}

func (r Request) handle() int64 { return r.Handle }


func encode(r Response) []byte {
	b, err := json.Marshal(r)
	if err != nil {
		b, _ = json.Marshal(fail(CodeBeads, err))
	}
	return b
}

func fail(code string, err error) Response {
	if code == CodeBeads && isLockError(err) {
		code = CodeBusy
	}
	return Response{Error: &Failure{Code: code, Message: err.Error()}}
}

// isLockError: another writer still holds the embedded database after beads' own wait.
// TestTwoWriters saw beads wait it out every time; this keeps a timeout typed if it ever shows.
func isLockError(err error) bool {
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "exclusive lock") || strings.Contains(msg, "database is locked") ||
		strings.Contains(msg, "lock held")
}

// open checks the workspace with a read-only open, which writes nothing and refuses a schema
// that is ahead of or behind this beads build. Nothing is migrated here, ever.
func (e *Engine) open(ctx context.Context, req Request) Response {
	dir := filepath.Clean(req.BeadsDir)
	if _, err := os.Stat(filepath.Join(dir, "embeddeddolt")); err != nil {
		if cfg, cerr := configfile.Load(dir); cerr == nil && cfg != nil && cfg.IsDoltServerMode() {
			return fail(CodeServerMode, fmt.Errorf("%s uses a Dolt SQL server", dir))
		}
		return fail(CodeNoBeads, fmt.Errorf("no embedded beads database in %s", dir))
	}
	database := databaseName(dir)
	st, err := embeddeddolt.OpenReadOnly(ctx, dir, database, "main")
	if err != nil {
		return classifyOpen(err)
	}
	if err := st.Close(); err != nil {
		return fail(CodeBeads, err)
	}
	e.mu.Lock()
	e.next++
	h := e.next
	e.opened[h] = &workspace{beadsDir: dir, database: database}
	e.mu.Unlock()
	return Response{Handle: h, Project: &ProjectInfo{BeadsDir: dir, Database: database, Mode: "embedded"}}
}

func classifyOpen(err error) Response {
	var ahead *schema.SchemaSkewError
	if errors.As(err, &ahead) {
		r := fail(CodeSchemaAhead, err)
		r.Error.DBVersion, r.Error.BinaryVersion = ahead.DBVersion, ahead.BinaryVersion
		return r
	}
	var behind *schema.SchemaBehindError
	if errors.As(err, &behind) {
		r := fail(CodeSchemaBehind, err)
		r.Error.DBVersion, r.Error.BinaryVersion = behind.DBVersion, behind.BinaryVersion
		return r
	}
	return fail(CodeBeads, err)
}

// migrate brings an OLDER database up to this build's schema. Only on the person's
// explicit yes: after it, a bd older than this build refuses the project.
func (e *Engine) migrate(ctx context.Context, req Request) Response {
	dir := filepath.Clean(req.BeadsDir)
	database := databaseName(dir)
	if _, err := os.Stat(filepath.Join(dir, "embeddeddolt")); err != nil {
		return fail(CodeNoBeads, fmt.Errorf("no embedded beads database in %s", dir))
	}
	ro, err := embeddeddolt.OpenReadOnly(ctx, dir, database, "main")
	if err == nil {
		_ = ro.Close()
		return Response{} // already current
	}
	var behind *schema.SchemaBehindError
	if !errors.As(err, &behind) {
		return classifyOpen(err) // ahead or broken: never written to
	}
	st, err := embeddeddolt.Open(ctx, dir, database, "main")
	if err != nil {
		return fail(CodeBeads, err)
	}
	if err := st.Close(); err != nil {
		return fail(CodeBeads, err)
	}
	return Response{Changed: true}
}

func databaseName(dir string) string {
	if cfg, err := configfile.Load(dir); err == nil && cfg != nil && cfg.GetDoltDatabase() != "" {
		return cfg.GetDoltDatabase()
	}
	return "beads"
}

func (e *Engine) read(ctx context.Context, ws *workspace, req Request) Response {
	st, err := embeddeddolt.OpenReadOnly(ctx, ws.beadsDir, ws.database, "main")
	if err != nil {
		return classifyOpen(err)
	}
	defer st.Close()
	if r, ok := extraRead(ctx, st, req); ok {
		return r
	}
	rd, err := st.IssueReader()
	if err != nil {
		return fail(CodeBeads, err)
	}
	switch req.Op {
	case "ready":
		// bd ready's own default is priority order; the library's empty Sort means "hybrid"
		page, err := rd.Ready(ctx, issueops.ReadyRequest{Limit: req.Limit, Sort: string(types.SortPolicyPriority)})
		if err != nil {
			return fail(CodeBeads, err)
		}
		return Response{Issues: page.Items, HasMore: page.HasMore}
	case "list":
		page, err := rd.List(ctx, listRequest(req))
		if err != nil {
			return fail(CodeBeads, err)
		}
		return Response{Issues: page.Items, HasMore: page.HasMore}
	default: // show
		d, err := rd.Get(ctx, issueops.GetRequest{ID: req.ID, IncludeDependents: true, IncludeComments: true})
		if err != nil {
			if errors.Is(err, storage.ErrNotFound) {
				return fail(CodeNotFound, err)
			}
			return fail(CodeBeads, err)
		}
		return Response{Details: d}
	}
}

// write opens the store writable only after open() proved the schema matches, so the
// writable open's migration step has nothing to do.
func (e *Engine) write(ctx context.Context, ws *workspace, req Request) Response {
	if req.Actor == "" {
		return fail(CodeBadRequest, errors.New("actor is required for writes"))
	}
	guard, err := embeddeddolt.OpenReadOnly(ctx, ws.beadsDir, ws.database, "main")
	if err != nil {
		return classifyOpen(err)
	}
	if err := guard.Close(); err != nil {
		return fail(CodeBeads, err)
	}
	st, err := embeddeddolt.Open(ctx, ws.beadsDir, ws.database, "main")
	if err != nil {
		return fail(CodeBeads, err)
	}
	defer st.Close()
	return writeOp(ctx, st, req)
}

func notFoundOr(err error) Response {
	if errors.Is(err, storage.ErrNotFound) {
		return fail(CodeNotFound, err)
	}
	return fail(CodeBeads, err)
}
