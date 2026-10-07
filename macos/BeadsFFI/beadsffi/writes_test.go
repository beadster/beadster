package main

import (
	"encoding/json"
	"strings"
	"testing"
)

// bdShow is the oracle: what bd itself says about a bead after the engine wrote it.
func bdShow(t *testing.T, dir, id string) map[string]any {
	t.Helper()
	var rows []map[string]any
	out := bdIn(t, dir, "show", id, "--json", "--include-comments")
	if err := json.Unmarshal([]byte(out[strings.Index(out, "["):]), &rows); err != nil || len(rows) != 1 {
		t.Fatalf("bd show %s: %v\n%s", id, err, out)
	}
	return rows[0]
}

func TestWrites(t *testing.T) {
	dir := newWorkspace(t)
	e := NewEngine()
	h := call(t, e, map[string]any{"op": "open", "beads_dir": dir}).Handle
	w := func(req map[string]any) Response {
		req["handle"], req["actor"] = h, "beadster"
		return call(t, e, req)
	}
	ready := call(t, e, map[string]any{"op": "ready", "handle": h})
	a, b := ready.Issues[0].ID, ready.Issues[1].ID

	// update: fields and labels land as bd sees them
	if r := w(map[string]any{"op": "update", "id": a, "notes": "from the app", "add_labels": []string{"sync", "ui"}, "priority": 0}); r.Error != nil || !r.Changed {
		t.Fatalf("update: %+v", r.Error)
	}
	if s := bdShow(t, dir, a); s["notes"] != "from the app" || s["priority"].(float64) != 0 || len(s["labels"].([]any)) != 2 {
		t.Fatalf("bd sees after update: %v", s)
	}

	// compare-and-set: a stale expected status writes nothing and says conflict
	if r := w(map[string]any{"op": "update", "id": a, "new_status": "in_progress", "expected_status": "closed"}); r.Error == nil || r.Error.Code != CodeConflict {
		t.Fatalf("stale status guard: %+v", r.Error)
	}
	if s := bdShow(t, dir, a); s["status"] != "open" {
		t.Fatalf("guarded write landed: %v", s["status"])
	}

	// claim, someone else's claim is refused, release
	if r := w(map[string]any{"op": "claim", "id": a}); r.Error != nil || r.Issue.Assignee != "beadster" {
		t.Fatalf("claim: %+v", r.Error)
	}
	if r := call(t, e, map[string]any{"op": "claim", "handle": h, "actor": "claude-1", "id": a}); r.Error == nil || r.Error.Code != CodeClaimed {
		t.Fatalf("second claim: %+v", r.Error)
	}
	if r := w(map[string]any{"op": "release", "id": a}); r.Error != nil {
		t.Fatalf("release: %+v", r.Error)
	}
	if s := bdShow(t, dir, a); s["assignee"] != nil && s["assignee"] != "" {
		t.Fatalf("still assigned after release: %v", s["assignee"])
	}

	// link: b waits on a; the reverse would be a cycle; unlink
	if r := w(map[string]any{"op": "link", "id": b, "target": a}); r.Error != nil {
		t.Fatalf("link: %+v", r.Error)
	}
	if r := w(map[string]any{"op": "link", "id": a, "target": b}); r.Error == nil || r.Error.Code != CodeRefused {
		t.Fatalf("cycle: %+v", r.Error)
	}
	if blocked := call(t, e, map[string]any{"op": "blocked", "handle": h}); len(blocked.Blocked) != 1 {
		t.Fatalf("b should be blocked: %d", len(blocked.Blocked))
	}
	if r := w(map[string]any{"op": "unlink", "id": b, "target": a}); r.Error != nil {
		t.Fatalf("unlink: %+v", r.Error)
	}

	// comment
	if r := w(map[string]any{"op": "comment", "id": a, "text": "Looked at it."}); r.Error != nil {
		t.Fatalf("comment: %+v", r.Error)
	}
	if s := bdShow(t, dir, a); len(s["comments"].([]any)) != 1 {
		t.Fatalf("bd sees no comment")
	}

	// create under a parent, close, reopen
	child := w(map[string]any{"op": "create", "title": "Child", "parent": a})
	if child.Error != nil {
		t.Fatalf("create child: %+v", child.Error)
	}
	if r := w(map[string]any{"op": "close_issue", "id": child.Issue.ID, "reason": "done"}); r.Error != nil {
		t.Fatalf("close: %+v", r.Error)
	}
	if r := w(map[string]any{"op": "reopen", "id": child.Issue.ID}); r.Error != nil || string(r.Issue.Status) != "open" {
		t.Fatalf("reopen: %+v", r.Error)
	}

	// memories
	if r := w(map[string]any{"op": "remember", "key": "deploy", "text": "npm run deploy"}); r.Error != nil {
		t.Fatalf("remember: %+v", r.Error)
	}
	if !strings.Contains(bdIn(t, dir, "memories", "--json"), "npm run deploy") {
		t.Fatal("bd memories misses the fact")
	}
	if r := w(map[string]any{"op": "forget", "key": "deploy"}); r.Error != nil {
		t.Fatalf("forget: %+v", r.Error)
	}
}

func TestGates(t *testing.T) {
	dir := newWorkspace(t)
	e := NewEngine()
	h := call(t, e, map[string]any{"op": "open", "beads_dir": dir}).Handle
	work := call(t, e, map[string]any{"op": "ready", "handle": h}).Issues[0].ID
	bdIn(t, dir, "gate", "create", "--type=human", "--blocks", work, "--reason", "Approve the deploy")

	gates := call(t, e, map[string]any{"op": "list", "handle": h, "filter_type": "gate", "include_gates": true})
	if gates.Error != nil || len(gates.Issues) != 1 || gates.Issues[0].AwaitType != "human" {
		t.Fatalf("list gates: %+v %d", gates.Error, len(gates.Issues))
	}
	// a plain list hides gate beads, like bd list; asking for the gate type returns them
	for _, is := range call(t, e, map[string]any{"op": "list", "handle": h}).Issues {
		if string(is.IssueType) == "gate" {
			t.Fatal("a plain list returned a gate")
		}
	}
	blocked := call(t, e, map[string]any{"op": "blocked", "handle": h})
	if len(blocked.Blocked) != 1 || blocked.Blocked[0].ID != work {
		t.Fatalf("work should wait on the gate: %+v", blocked.Blocked)
	}
	gate := blocked.Blocked[0].BlockedBy[0]

	if r := call(t, e, map[string]any{"op": "reject_gate", "handle": h, "actor": "anton", "id": gate, "reason": "not today"}); r.Error != nil {
		t.Fatalf("reject: %+v", r.Error)
	}
	if s := bdShow(t, dir, gate); s["status"] == "closed" || len(s["comments"].([]any)) != 1 {
		t.Fatalf("reject must leave the gate open with a comment: %v", s)
	}

	if r := call(t, e, map[string]any{"op": "approve_gate", "handle": h, "actor": "anton", "id": gate}); r.Error != nil {
		t.Fatalf("approve: %+v", r.Error)
	}
	if s := bdShow(t, dir, gate); s["status"] != "closed" || s["close_reason"] != "approved by anton" {
		t.Fatalf("approve: %v %v", s["status"], s["close_reason"])
	}
	ready := call(t, e, map[string]any{"op": "ready", "handle": h})
	found := false
	for _, is := range ready.Issues {
		found = found || is.ID == work
	}
	if !found {
		t.Fatal("approved work is not ready")
	}
}
