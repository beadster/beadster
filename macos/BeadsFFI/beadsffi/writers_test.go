package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
)

// P5: the engine and a bd process write one embedded project at the same time, the way
// beadster and an agent will. Every write from both sides must land; a lock collision must
// come back typed (CodeBusy), never as a lost write or a corrupt store.
func TestTwoWriters(t *testing.T) {
	dir := newWorkspace(t)
	bd := bdBinary(t)
	e := NewEngine()
	h := call(t, e, map[string]any{"op": "open", "beads_dir": dir}).Handle
	const n = 15

	var wg sync.WaitGroup
	var bdErrs, appBusy, appErrs []string
	var mu sync.Mutex
	wg.Add(2)
	go func() {
		defer wg.Done()
		for i := 0; i < n; i++ {
			cmd := exec.Command(bd, "create", fmt.Sprintf("agent %d", i), "--json")
			cmd.Dir = filepath.Dir(dir)
			cmd.Env = append(os.Environ(), "HOME="+filepath.Dir(dir), "BEADS_DIR="+dir, "BD_ACTOR=agent",
				"DO_NOT_TRACK=1", "BD_DISABLE_METRICS=1", "BD_DISABLE_EVENT_FLUSH=1")
			if out, err := cmd.CombinedOutput(); err != nil {
				mu.Lock()
				bdErrs = append(bdErrs, string(out))
				mu.Unlock()
			}
		}
	}()
	go func() {
		defer wg.Done()
		for i := 0; i < n; i++ {
			r := call(t, e, map[string]any{"op": "create", "handle": h, "actor": "beadster", "title": fmt.Sprintf("app %d", i)})
			if r.Error != nil {
				mu.Lock()
				if r.Error.Code == CodeBusy {
					appBusy = append(appBusy, r.Error.Message)
				} else {
					appErrs = append(appErrs, r.Error.Code+": "+r.Error.Message)
				}
				mu.Unlock()
			}
		}
	}()
	wg.Wait()

	list := call(t, e, map[string]any{"op": "list", "handle": h, "limit": 0})
	if list.Error != nil {
		t.Fatalf("list after: %+v", list.Error)
	}
	var agent, app int
	for _, is := range list.Issues {
		switch {
		case len(is.Title) > 6 && is.Title[:6] == "agent ":
			agent++
		case len(is.Title) > 4 && is.Title[:4] == "app ":
			app++
		}
	}
	t.Logf("landed: agent %d/%d, app %d/%d; app busy %d, app other errors %d, bd errors %d",
		agent, n, app, n, len(appBusy), len(appErrs), len(bdErrs))
	for _, m := range appErrs {
		t.Logf("app error: %s", m)
	}
	for _, m := range bdErrs {
		t.Logf("bd error: %s", m)
	}
	if len(appErrs) > 0 {
		t.Fatalf("app writes failed with untyped errors")
	}
	if app != n-len(appBusy) || agent != n-len(bdErrs) {
		t.Fatalf("a write was lost: agent %d (want %d), app %d (want %d)", agent, n-len(bdErrs), app, n-len(appBusy))
	}
	if len(appBusy) > 0 {
		t.Fatalf("app writes came back busy %d times: the engine should wait for the lock", len(appBusy))
	}
}

// Different projects are read side by side; every answer stays right.
func TestParallelProjects(t *testing.T) {
	e := NewEngine()
	var handles []int64
	for i := 0; i < 4; i++ {
		handles = append(handles, call(t, e, map[string]any{"op": "open", "beads_dir": newWorkspace(t)}).Handle)
	}
	var wg sync.WaitGroup
	errs := make(chan string, 40)
	for _, h := range handles {
		for j := 0; j < 5; j++ {
			wg.Add(1)
			go func(h int64) {
				defer wg.Done()
				r := call(t, e, map[string]any{"op": "ready", "handle": h})
				if r.Error != nil || len(r.Issues) != 2 {
					errs <- fmt.Sprintf("handle %d: %+v %d", h, r.Error, len(r.Issues))
				}
			}(h)
		}
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		t.Error(e)
	}
}
