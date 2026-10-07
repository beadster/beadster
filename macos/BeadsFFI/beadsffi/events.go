package main

import (
	"context"
	"time"

	"github.com/steveyegge/beads/internal/storage"
	"github.com/steveyegge/beads/internal/storage/embeddeddolt"
)

// Cursor is where the app last read the audit log: the newest event's time and id.
// beads pages the log by exactly this pair (storage.EventCursor), so nothing is skipped
// or read twice, even for events in the same second.
type Cursor struct {
	At time.Time `json:"at"`
	ID string    `json:"id"`
}

// events reads the audit log every bd mutation writes (the always-on events table, not the
// opt-in events journal: turning that on would be a config write in the person's project).
func events(ctx context.Context, st *embeddeddolt.EmbeddedDoltStore, req Request) Response {
	var cur storage.EventCursor
	if req.After != nil {
		cur = storage.EventCursor{CreatedAt: req.After.At, ID: req.After.ID}
	}
	limit := 500
	if req.Limit != nil && *req.Limit > 0 {
		limit = *req.Limit
	}
	evs, err := st.EventsSince(ctx, cur, req.ID, limit)
	if err != nil {
		return fail(CodeBeads, err)
	}
	r := Response{Events: evs, Next: req.After}
	if n := len(evs); n > 0 {
		r.Next = &Cursor{At: evs[n-1].CreatedAt, ID: evs[n-1].ID}
		r.HasMore = n == limit
	}
	return r
}
