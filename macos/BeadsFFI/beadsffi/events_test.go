package main

import (
	"testing"
	"time"
)

// Every bd write lands in the audit log; reading after a cursor returns only what is new,
// in order, and the cursor survives JSON (the app keeps it per project).
func TestEventsAfterCursor(t *testing.T) {
	dir := newWorkspace(t)
	e := NewEngine()
	h := call(t, e, map[string]any{"op": "open", "beads_dir": dir}).Handle

	all := call(t, e, map[string]any{"op": "events", "handle": h})
	if all.Error != nil || len(all.Events) == 0 || all.Next == nil {
		t.Fatalf("first read: %+v %d", all.Error, len(all.Events))
	}
	quiet := call(t, e, map[string]any{"op": "events", "handle": h, "after": all.Next})
	if quiet.Error != nil || len(quiet.Events) != 0 || quiet.Next.ID != all.Next.ID {
		t.Fatalf("nothing new should read empty: %+v %d", quiet.Error, len(quiet.Events))
	}

	start := time.Now()
	bdIn(t, dir, "create", "From an agent", "-p", "1")
	bdIn(t, dir, "create", "Second from an agent", "-p", "2")
	fresh := call(t, e, map[string]any{"op": "events", "handle": h, "after": all.Next})
	t.Logf("two bd creates visible after %v (bd process time included)", time.Since(start))
	if fresh.Error != nil || len(fresh.Events) != 2 {
		t.Fatalf("new events: %+v %d", fresh.Error, len(fresh.Events))
	}
	if string(fresh.Events[0].EventType) != "created" || fresh.Events[0].Actor != "fixture" {
		t.Fatalf("event: %+v", fresh.Events[0])
	}
	if !fresh.Events[0].CreatedAt.Before(fresh.Events[1].CreatedAt) && fresh.Events[0].ID == fresh.Events[1].ID {
		t.Fatal("events out of order")
	}

	// paging: limit 1 walks them one at a time without loss
	one := call(t, e, map[string]any{"op": "events", "handle": h, "after": all.Next, "limit": 1})
	two := call(t, e, map[string]any{"op": "events", "handle": h, "after": one.Next, "limit": 1})
	if len(one.Events) != 1 || len(two.Events) != 1 || one.Events[0].ID == two.Events[0].ID || !one.HasMore {
		t.Fatalf("paging: %d %d more=%v", len(one.Events), len(two.Events), one.HasMore)
	}
}
