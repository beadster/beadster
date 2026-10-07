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
	Changed bool                     `json:"changed,omitempty"`
}

// Failure keeps beads' own error text: a failure report carries the raw error.
type Failure struct {
	Code    string `json:"code"`
	Message string `json:"message"`
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
	CodeSchemaDrift = "schema_drift"
	CodeNotFound    = "not_found"
	CodeNoHandle    = "no_handle"
	CodeBeads       = "beads"
	CodeBusy        = "busy"
)

type workspace struct {
	beadsDir string
	database string
}

// Engine owns open workspaces. Calls are serialized: embedded Dolt has one writer, and the
// CLI it mirrors runs one command per process.
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
	e.mu.Lock()
	defer e.mu.Unlock()
	return encode(e.dispatch(context.Background(), req))
}

func (e *Engine) dispatch(ctx context.Context, req Request) Response {
	switch req.Op {
	case "open":
		return e.open(ctx, req)
	case "close":
		delete(e.opened, req.handle())
		return Response{}
	}
	ws, ok := e.opened[req.handle()]
	if !ok {
		return fail(CodeNoHandle, fmt.Errorf("no open workspace for handle %d", req.handle()))
	}
	switch req.Op {
	case "ready", "list", "show":
		return e.read(ctx, ws, req)
	case "create", "update", "close_issue":
		return e.write(ctx, ws, req)
	default:
		return fail(CodeBadRequest, fmt.Errorf("unknown op %q", req.Op))
	}
}

func (r Request) handle() int64 { return r.Handle }

func containsFold(s, sub string) bool { return strings.Contains(strings.ToLower(s), strings.ToLower(sub)) }

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
	database := "beads"
	if cfg, err := configfile.Load(dir); err == nil && cfg != nil {
		database = cfg.GetDoltDatabase()
	}
	st, err := embeddeddolt.OpenReadOnly(ctx, dir, database, "main")
	if err != nil {
		return classifyOpen(err)
	}
	if err := st.Close(); err != nil {
		return fail(CodeBeads, err)
	}
	e.next++
	e.opened[e.next] = &workspace{beadsDir: dir, database: database}
	return Response{Handle: e.next, Project: &ProjectInfo{BeadsDir: dir, Database: database, Mode: "embedded"}}
}

func classifyOpen(err error) Response {
	msg := err.Error()
	for _, s := range []string{"schema", "migration", "newer", "older"} {
		if containsFold(msg, s) {
			return fail(CodeSchemaDrift, err)
		}
	}
	return fail(CodeBeads, err)
}

func (e *Engine) read(ctx context.Context, ws *workspace, req Request) Response {
	st, err := embeddeddolt.OpenReadOnly(ctx, ws.beadsDir, ws.database, "main")
	if err != nil {
		return classifyOpen(err)
	}
	defer st.Close()
	rd, err := st.IssueReader()
	if err != nil {
		return fail(CodeBeads, err)
	}
	switch req.Op {
	case "ready":
		page, err := rd.Ready(ctx, issueops.ReadyRequest{Limit: req.Limit})
		if err != nil {
			return fail(CodeBeads, err)
		}
		return Response{Issues: page.Items, HasMore: page.HasMore}
	case "list":
		page, err := rd.List(ctx, issueops.ListRequest{Status: req.Status, Limit: req.Limit})
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
	lc, err := st.IssueLifecycle()
	if err != nil {
		return fail(CodeBeads, err)
	}
	switch req.Op {
	case "create":
		if req.Title == nil {
			return fail(CodeBadRequest, errors.New("title is required"))
		}
		issue := &types.Issue{Title: *req.Title, Status: types.StatusOpen, Priority: 2, IssueType: types.TypeTask}
		if req.Description != nil {
			issue.Description = *req.Description
		}
		if req.Priority != nil {
			issue.Priority = *req.Priority
		}
		if req.IssueType != nil {
			issue.IssueType = types.IssueType(*req.IssueType)
		}
		res, err := lc.Create(ctx, issueops.CreateRequest{Actor: req.Actor, Issue: issue})
		if err != nil {
			return fail(CodeBeads, err)
		}
		return Response{Issue: res.Issue, Changed: true}
	case "update":
		patch := issueops.IssuePatch{}
		if req.Title != nil {
			patch.Title = issueops.Field[string]{Set: true, Value: *req.Title}
		}
		if req.Description != nil {
			patch.Description = issueops.Field[string]{Set: true, Value: *req.Description}
		}
		if req.Priority != nil {
			patch.Priority = issueops.Field[int]{Set: true, Value: *req.Priority}
		}
		if req.Assignee != nil {
			patch.Assignee = issueops.Field[string]{Set: true, Value: *req.Assignee}
		}
		if req.NewStatus != nil {
			patch.Status = issueops.Field[types.Status]{Set: true, Value: types.Status(*req.NewStatus)}
		}
		res, err := lc.Update(ctx, issueops.UpdateRequest{Actor: req.Actor, IssueID: req.ID, Patch: patch})
		if err != nil {
			return notFoundOr(err)
		}
		return Response{Issue: res.Issue, Changed: res.Changed}
	default: // close_issue
		res, err := lc.Close(ctx, issueops.CloseRequest{Actor: req.Actor, IssueID: req.ID, Reason: req.Reason})
		if err != nil {
			return notFoundOr(err)
		}
		return Response{Issue: res.Issue, Changed: res.Changed}
	}
}

func notFoundOr(err error) Response {
	if errors.Is(err, storage.ErrNotFound) {
		return fail(CodeNotFound, err)
	}
	return fail(CodeBeads, err)
}
