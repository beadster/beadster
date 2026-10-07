package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// The tests build a real workspace with the same beads build: bd init, then the engine.
// BD points at a bd binary built from this checkout (scripts/build-beadsffi.sh builds it).
func bdBinary(t *testing.T) string {
	t.Helper()
	bd := os.Getenv("BD")
	if bd == "" {
		t.Skip("BD not set: run through scripts/build-beadsffi.sh")
	}
	return bd
}

func newWorkspace(t *testing.T) string {
	t.Helper()
	bd := bdBinary(t)
	dir := t.TempDir()
	run := func(args ...string) string {
		cmd := exec.Command(bd, args...)
		cmd.Dir = dir
		cmd.Env = append(os.Environ(), "HOME="+dir, "BEADS_DIR="+filepath.Join(dir, ".beads"), "BD_ACTOR=fixture",
			"DO_NOT_TRACK=1", "BD_DISABLE_METRICS=1", "BD_DISABLE_EVENT_FLUSH=1")
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("bd %v: %v\n%s", args, err, out)
		}
		return string(out)
	}
	run("init", "--prefix", "fx", "--quiet")
	run("create", "First bead", "-p", "1", "--json")
	run("create", "Second bead", "-p", "3", "--json")
	return filepath.Join(dir, ".beads")
}

func call(t *testing.T, e *Engine, req map[string]any) Response {
	t.Helper()
	b, _ := json.Marshal(req)
	var r Response
	if err := json.Unmarshal(e.Call(b), &r); err != nil {
		t.Fatalf("decode: %v", err)
	}
	return r
}

func TestOpenReadWrite(t *testing.T) {
	dir := newWorkspace(t)
	e := NewEngine()
	open := call(t, e, map[string]any{"op": "open", "beads_dir": dir})
	if open.Error != nil {
		t.Fatalf("open: %+v", open.Error)
	}
	h := open.Handle

	ready := call(t, e, map[string]any{"op": "ready", "handle": h})
	if ready.Error != nil || len(ready.Issues) != 2 {
		t.Fatalf("ready: %+v %d", ready.Error, len(ready.Issues))
	}
	if ready.Issues[0].Priority != 1 {
		t.Fatalf("ready order: first has P%d", ready.Issues[0].Priority)
	}

	created := call(t, e, map[string]any{"op": "create", "handle": h, "actor": "beadster", "title": "From the app", "priority": 0})
	if created.Error != nil || created.Issue == nil || created.Issue.Title != "From the app" {
		t.Fatalf("create: %+v", created.Error)
	}
	id := created.Issue.ID

	upd := call(t, e, map[string]any{"op": "update", "handle": h, "actor": "beadster", "id": id, "new_status": "in_progress"})
	if upd.Error != nil || !upd.Changed || string(upd.Issue.Status) != "in_progress" {
		t.Fatalf("update: %+v", upd.Error)
	}

	closed := call(t, e, map[string]any{"op": "close_issue", "handle": h, "actor": "beadster", "id": id, "reason": "done"})
	if closed.Error != nil || string(closed.Issue.Status) != "closed" {
		t.Fatalf("close: %+v", closed.Error)
	}

	show := call(t, e, map[string]any{"op": "show", "handle": h, "id": id})
	if show.Error != nil || show.Details == nil {
		t.Fatalf("show: %+v", show.Error)
	}
}

func TestErrors(t *testing.T) {
	e := NewEngine()
	if r := call(t, e, map[string]any{"op": "open", "beads_dir": t.TempDir()}); r.Error == nil || r.Error.Code != CodeNoBeads {
		t.Fatalf("empty dir: %+v", r.Error)
	}
	if r := call(t, e, map[string]any{"op": "ready", "handle": 99}); r.Error == nil || r.Error.Code != CodeNoHandle {
		t.Fatalf("no handle: %+v", r.Error)
	}
	if r := call(t, e, map[string]any{"op": "nope", "handle": 0}); r.Error == nil {
		t.Fatal("unknown op accepted")
	}
	var bad Response
	_ = json.Unmarshal(e.Call([]byte("{")), &bad)
	if bad.Error == nil || bad.Error.Code != CodeBadRequest {
		t.Fatalf("bad json: %+v", bad.Error)
	}

	dir := newWorkspace(t)
	h := call(t, e, map[string]any{"op": "open", "beads_dir": dir}).Handle
	if r := call(t, e, map[string]any{"op": "show", "handle": h, "id": "fx-nope"}); r.Error == nil || r.Error.Code != CodeNotFound {
		t.Fatalf("missing bead: %+v", r.Error)
	}
	if r := call(t, e, map[string]any{"op": "create", "handle": h, "title": "x"}); r.Error == nil || r.Error.Code != CodeBadRequest {
		t.Fatalf("write without actor: %+v", r.Error)
	}
}
