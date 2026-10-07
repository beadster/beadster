package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// bdIn runs the pinned bd inside a test workspace.
func bdIn(t *testing.T, beadsDir string, args ...string) string {
	t.Helper()
	cmd := exec.Command(bdBinary(t), args...)
	cmd.Dir = filepath.Dir(beadsDir)
	cmd.Env = append(os.Environ(), "HOME="+filepath.Dir(beadsDir), "BEADS_DIR="+beadsDir, "BD_ACTOR=fixture",
		"DO_NOT_TRACK=1", "BD_DISABLE_METRICS=1", "BD_DISABLE_EVENT_FLUSH=1")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("bd %v: %v\n%s", args, err, out)
	}
	return string(out)
}

func TestReads(t *testing.T) {
	dir := newWorkspace(t)
	e := NewEngine()
	h := call(t, e, map[string]any{"op": "open", "beads_dir": dir}).Handle
	ready := call(t, e, map[string]any{"op": "ready", "handle": h})
	first, second := ready.Issues[0].ID, ready.Issues[1].ID

	// second waits on first; a memory; a label; a title edit for history
	bdIn(t, dir, "dep", "add", second, first)
	bdIn(t, dir, "remember", "Use npm run deploy.", "--key", "deploy")
	bdIn(t, dir, "label", "add", first, "sync")
	bdIn(t, dir, "update", first, "--title", "First bead, renamed")

	blocked := call(t, e, map[string]any{"op": "blocked", "handle": h})
	if blocked.Error != nil || len(blocked.Blocked) != 1 || blocked.Blocked[0].ID != second ||
		len(blocked.Blocked[0].BlockedBy) != 1 || blocked.Blocked[0].BlockedBy[0] != first {
		t.Fatalf("blocked: %+v %+v", blocked.Error, blocked.Blocked)
	}

	mem := call(t, e, map[string]any{"op": "memories", "handle": h})
	if mem.Error != nil || mem.Memories["deploy"] != "Use npm run deploy." {
		t.Fatalf("memories: %+v %v", mem.Error, mem.Memories)
	}

	hist := call(t, e, map[string]any{"op": "history", "handle": h, "id": first})
	if hist.Error != nil || len(hist.History) < 2 {
		t.Fatalf("history: %+v %d entries", hist.Error, len(hist.History))
	}
	titles := map[string]bool{}
	for _, h := range hist.History {
		if h.Issue != nil {
			titles[h.Issue.Title] = true
		}
		if h.Commit == "" || h.Date.IsZero() {
			t.Fatalf("history entry without commit or date: %+v", h)
		}
	}
	if !titles["First bead"] || !titles["First bead, renamed"] {
		t.Fatalf("history titles: %v", titles)
	}

	byLabel := call(t, e, map[string]any{"op": "list", "handle": h, "label": "sync"})
	if byLabel.Error != nil || len(byLabel.Issues) != 1 || byLabel.Issues[0].ID != first {
		t.Fatalf("list by label: %+v %d", byLabel.Error, len(byLabel.Issues))
	}
	byTitle := call(t, e, map[string]any{"op": "list", "handle": h, "title_contains": "renamed"})
	if byTitle.Error != nil || len(byTitle.Issues) != 1 {
		t.Fatalf("list by title: %+v %d", byTitle.Error, len(byTitle.Issues))
	}
}

func TestMoleculeProgress(t *testing.T) {
	dir := newWorkspace(t)
	formulas := filepath.Join(dir, "formulas")
	if err := os.MkdirAll(formulas, 0o755); err != nil {
		t.Fatal(err)
	}
	src := filepath.Join(os.Getenv("BEADS_SRC"), "examples", "formulas", "quick-check.formula.toml")
	b, err := os.ReadFile(src)
	if err != nil {
		t.Skipf("BEADS_SRC not set: %v", err)
	}
	if err := os.WriteFile(filepath.Join(formulas, "quick-check.formula.toml"), b, 0o644); err != nil {
		t.Fatal(err)
	}
	bdIn(t, dir, "mol", "pour", "quick-check")
	e := NewEngine()
	h := call(t, e, map[string]any{"op": "open", "beads_dir": dir}).Handle
	list := call(t, e, map[string]any{"op": "list", "handle": h, "filter_type": "molecule"})
	if list.Error != nil || len(list.Issues) != 1 {
		t.Fatalf("molecules: %+v %d", list.Error, len(list.Issues))
	}
	mol := list.Issues[0].ID
	steps := call(t, e, map[string]any{"op": "list", "handle": h, "parent": mol, "all": true, "include_gates": true})
	if steps.Error != nil || len(steps.Issues) != 4 {
		t.Fatalf("steps of the molecule: %+v %d", steps.Error, len(steps.Issues))
	}
	p := call(t, e, map[string]any{"op": "molecule_progress", "handle": h, "id": mol})
	if p.Error != nil || p.Progress == nil || p.Progress.Total != 4 || p.Progress.Completed != 0 {
		t.Fatalf("progress: %+v %+v", p.Error, p.Progress)
	}
}

// The list config is read once and reused; a ready (the app's re-count after a change) or a
// write reads it fresh. Only the config is kept: a bead bd adds shows on the next list.
func TestListConfigIsReadOncePerRefresh(t *testing.T) {
	dir := newWorkspace(t)
	e := NewEngine()
	h := call(t, e, map[string]any{"op": "open", "beads_dir": dir}).Handle
	first := call(t, e, map[string]any{"op": "list", "handle": h, "limit": 0})
	ws := e.opened[h]
	if ws.listConfig == nil {
		t.Fatal("the first list should keep its config")
	}
	bdIn(t, dir, "create", "Added by bd while the config was kept", "-p", "2")
	again := call(t, e, map[string]any{"op": "list", "handle": h, "limit": 0})
	if len(again.Issues) != len(first.Issues)+1 {
		t.Fatalf("a bead bd added must show: %d then %d", len(first.Issues), len(again.Issues))
	}
	call(t, e, map[string]any{"op": "ready", "handle": h})
	if ws.listConfig != nil {
		t.Fatal("ready must drop the kept config")
	}
}
