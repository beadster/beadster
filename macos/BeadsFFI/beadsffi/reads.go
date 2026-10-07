package main

import (
	"context"
	"time"

	"github.com/steveyegge/beads/internal/storage/embeddeddolt"
	"github.com/steveyegge/beads/internal/storage/memoryops"
	"github.com/steveyegge/beads/internal/types"
	"github.com/steveyegge/beads/issueops"
)

// HistoryEntry is one Dolt commit that touched a bead: who, when, and the bead as it was.
// beads' own storage.HistoryEntry has no JSON tags, so the wire shape is ours.
type HistoryEntry struct {
	Commit    string       `json:"commit"`
	Committer string       `json:"committer"`
	Date      time.Time    `json:"date"`
	Issue     *types.Issue `json:"issue"`
}

// extraRead answers the reads beyond ready/list/show. ok is false for an op it does not own.
func extraRead(ctx context.Context, st *embeddeddolt.EmbeddedDoltStore, req Request) (Response, bool) {
	switch req.Op {
	case "blocked":
		blocked, err := st.GetBlockedIssues(ctx, types.WorkFilter{})
		if err != nil {
			return fail(CodeBeads, err), true
		}
		return Response{Blocked: blocked}, true
	case "history":
		entries, err := st.History(ctx, req.ID)
		if err != nil {
			return notFoundOr(err), true
		}
		out := make([]HistoryEntry, 0, len(entries))
		for _, e := range entries {
			out = append(out, HistoryEntry{Commit: e.CommitHash, Committer: e.Committer, Date: e.CommitDate, Issue: e.Issue})
		}
		return Response{History: out}, true
	case "memories":
		all, err := st.GetAllConfig(ctx)
		if err != nil {
			return fail(CodeBeads, err), true
		}
		return Response{Memories: memoryops.MemoriesFromConfig(all)}, true
	case "molecule_progress":
		p, err := st.GetMoleculeProgress(ctx, req.ID)
		if err != nil {
			return notFoundOr(err), true
		}
		return Response{Progress: p}, true
	}
	return Response{}, false
}

// listRequest maps the app's list filters onto beads' own request; beads normalizes the rest.
func listRequest(req Request) issueops.ListRequest {
	lr := issueops.ListRequest{Status: req.Status, Limit: req.Limit, Assignee: req.FilterAssignee,
		IssueType: req.FilterType, TitleContains: req.TitleContains}
	if req.Label != "" {
		lr.Labels = []string{req.Label}
	}
	return lr
}
