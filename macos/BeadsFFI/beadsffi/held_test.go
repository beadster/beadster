package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/steveyegge/beads/internal/storage/embeddeddolt"
	"github.com/steveyegge/beads/issueops"
)

// U8b's questions, answered on a real bd project: what an open costs, whether a held
// read-only store blocks bd writers, and whether it sees what they wrote.
func TestHeldReadOnlyStore(t *testing.T) {
	src := os.Getenv("FIXTURE_MANY")
	dir := ""
	if src != "" {
		dir = filepath.Join(t.TempDir(), "many")
		if err := os.CopyFS(dir, os.DirFS(src)); err != nil {
			t.Fatal(err)
		}
		dir = filepath.Join(dir, ".beads")
	} else {
		dir = newWorkspace(t)
	}
	ctx := context.Background()
	db := databaseName(dir)

	start := time.Now()
	for i := 0; i < 3; i++ {
		st, err := embeddeddolt.OpenReadOnly(ctx, dir, db, "main")
		if err != nil {
			t.Fatal(err)
		}
		rd, _ := st.IssueReader()
		_, _ = rd.Ready(ctx, issueops.ReadyRequest{})
		st.Close()
	}
	t.Logf("open + ready + close: %v each", time.Since(start)/3)

	held, err := embeddeddolt.OpenReadOnly(ctx, dir, db, "main")
	if err != nil {
		t.Fatal(err)
	}
	defer held.Close()
	rd, _ := held.IssueReader()
	start = time.Now()
	for i := 0; i < 3; i++ {
		_, _ = rd.Ready(ctx, issueops.ReadyRequest{})
	}
	t.Logf("ready on a held store: %v each", time.Since(start)/3)
	before, _ := rd.List(ctx, issueops.ListRequest{})

	start = time.Now()
	bdIn(t, dir, "create", "Written while the app holds the store", "-p", "0")
	t.Logf("bd create while held: %v", time.Since(start))

	after, _ := rd.List(ctx, issueops.ListRequest{})
	t.Logf("held store sees the new bead: %v (%d → %d rows)", len(after.Items) > len(before.Items), len(before.Items), len(after.Items))
	// measured 2026-10-07 on the 2,000-bead fixture: open+ready+close 192 ms, ready on a held
	// store 148 ms, bd create while held 1.2 s (not blocked), and the held store did NOT see
	// the new bead. so the engine keeps opening per call: a held store saves ~44 ms and goes stale
	fresh, err := embeddeddolt.OpenReadOnly(ctx, dir, db, "main")
	if err != nil {
		t.Fatal(err)
	}
	defer fresh.Close()
	frd, _ := fresh.IssueReader()
	now, _ := frd.List(ctx, issueops.ListRequest{Limit: intp(0)})
	found := false
	for _, is := range now.Items {
		found = found || is.Title == "Written while the app holds the store"
	}
	if !found {
		t.Fatal("a fresh open must see what bd wrote")
	}
}

func intp(n int) *int { return &n }
