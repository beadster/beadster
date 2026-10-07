package main

import (
	"context"
	"errors"
	"fmt"

	"github.com/steveyegge/beads/internal/storage/embeddeddolt"
	"github.com/steveyegge/beads/internal/types"
	"github.com/steveyegge/beads/issueops"
	"github.com/steveyegge/beads/memoryops"
)

// Failure codes for writes beads refused on purpose.
const (
	// a compare-and-set guard did not hold: someone changed the bead first (bd exits 13)
	CodeConflict = "conflict"
	// the bead is claimed by someone else, or already claimed
	CodeClaimed = "claimed"
	// beads refused the change itself: closing a blocked bead or one with open children,
	// a cycle, a self-dependency, a release with no claim
	CodeRefused = "refused"
)

// writeOp runs one write on a store opened writable. Every op goes through the same
// beads role bd uses, so ids, validation, hooks-free audit events and history are bd's.
func writeOp(ctx context.Context, st *embeddeddolt.EmbeddedDoltStore, req Request) Response {
	switch req.Op {
	case "create", "update", "close_issue", "reopen":
		lc, err := st.IssueLifecycle()
		if err != nil {
			return fail(CodeBeads, err)
		}
		return lifecycleOp(ctx, lc, req)
	case "claim":
		cl, err := st.IssueClaimer()
		if err != nil {
			return fail(CodeBeads, err)
		}
		res, err := cl.Claim(ctx, issueops.ClaimRequest{Actor: req.Actor, IssueID: req.ID})
		if err != nil {
			return writeFailure(err)
		}
		return Response{Issue: res.Issue, Changed: true}
	case "release":
		rl, err := st.Releaser()
		if err != nil {
			return fail(CodeBeads, err)
		}
		res, err := rl.Release(ctx, issueops.ReleaseRequest{Actor: req.Actor, IssueID: req.ID, ExpectedAssignee: req.ExpectedAssignee, Force: req.Force})
		if err != nil {
			return writeFailure(err)
		}
		return Response{Issue: res.Issue, Changed: true}
	case "link", "unlink":
		de, err := st.DependencyEditor()
		if err != nil {
			return fail(CodeBeads, err)
		}
		if req.Op == "link" {
			kind := req.LinkType
			if kind == "" {
				kind = string(types.DepBlocks)
			}
			_, err = de.AddDependencies(ctx, issueops.AddDependenciesRequest{Actor: req.Actor,
				Edges: []issueops.DependencyEdge{{IssueID: req.ID, DependsOnID: req.Target, Type: types.DependencyType(kind)}}})
		} else {
			_, err = de.RemoveDependency(ctx, issueops.RemoveDependencyRequest{Actor: req.Actor, IssueID: req.ID, DependsOnID: req.Target})
		}
		if err != nil {
			return writeFailure(err)
		}
		return Response{Changed: true}
	case "comment":
		cm, err := st.Commenter()
		if err != nil {
			return fail(CodeBeads, err)
		}
		if _, err := cm.AddComment(ctx, issueops.AddCommentRequest{Author: req.Actor, IssueID: req.ID, Text: req.Text}); err != nil {
			return writeFailure(err)
		}
		return Response{Changed: true}
	case "approve_gate":
		// bd gate resolve: closing the gate bead releases what it holds
		lc, err := st.IssueLifecycle()
		if err != nil {
			return fail(CodeBeads, err)
		}
		reason := req.Reason
		if reason == "" {
			reason = "approved by " + req.Actor
		}
		res, err := lc.Close(ctx, issueops.CloseRequest{Actor: req.Actor, IssueID: req.ID, Reason: reason, Force: true})
		if err != nil {
			return writeFailure(err)
		}
		return Response{Issue: res.Issue, Changed: res.Changed}
	case "reject_gate":
		// beads has no reject: the gate stays closed to the work, and the reason goes on the
		// gate as a comment for whoever (agent or person) is waiting on it
		cm, err := st.Commenter()
		if err != nil {
			return fail(CodeBeads, err)
		}
		text := "Rejected by " + req.Actor
		if req.Reason != "" {
			text += ": " + req.Reason
		}
		if _, err := cm.AddComment(ctx, issueops.AddCommentRequest{Author: req.Actor, IssueID: req.ID, Text: text}); err != nil {
			return writeFailure(err)
		}
		return Response{Changed: true}
	case "remember", "forget":
		mem, err := st.Memories()
		if err != nil {
			return fail(CodeBeads, err)
		}
		if req.Op == "remember" {
			_, err = mem.Remember(ctx, memoryops.RememberRequest{Key: req.Key, Content: req.Text})
		} else {
			_, err = mem.Forget(ctx, memoryops.ForgetRequest{Key: req.Key})
		}
		if err != nil {
			return writeFailure(err)
		}
		return Response{Changed: true}
	}
	return fail(CodeBadRequest, fmt.Errorf("unknown op %q", req.Op))
}

func lifecycleOp(ctx context.Context, lc issueops.Lifecycle, req Request) Response {
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
		if req.Assignee != nil {
			issue.Assignee = *req.Assignee
		}
		res, err := lc.Create(ctx, issueops.CreateRequest{Actor: req.Actor, Issue: issue, ParentID: req.Parent})
		if err != nil {
			return writeFailure(err)
		}
		return Response{Issue: res.Issue, Changed: true}
	case "update":
		ur := issueops.UpdateRequest{Actor: req.Actor, IssueID: req.ID, Patch: patchFrom(req), ExpectedAssignee: req.ExpectedAssignee}
		if req.ExpectedStatus != nil {
			s := types.Status(*req.ExpectedStatus)
			ur.ExpectedStatus = &s
		}
		res, err := lc.Update(ctx, ur)
		if err != nil {
			return writeFailure(err)
		}
		return Response{Issue: res.Issue, Changed: res.Changed}
	case "reopen":
		res, err := lc.Reopen(ctx, issueops.ReopenRequest{Actor: req.Actor, IssueID: req.ID, Reason: req.Reason})
		if err != nil {
			return writeFailure(err)
		}
		return Response{Issue: res.Issue, Changed: true}
	default: // close_issue
		res, err := lc.Close(ctx, issueops.CloseRequest{Actor: req.Actor, IssueID: req.ID, Reason: req.Reason, Force: req.Force})
		if err != nil {
			return writeFailure(err)
		}
		return Response{Issue: res.Issue, Changed: res.Changed}
	}
}

func patchFrom(req Request) issueops.IssuePatch {
	var p issueops.IssuePatch
	set := func(v *string, f *issueops.Field[string]) {
		if v != nil {
			*f = issueops.Field[string]{Set: true, Value: *v}
		}
	}
	set(req.Title, &p.Title)
	set(req.Description, &p.Description)
	set(req.Design, &p.Design)
	set(req.Acceptance, &p.AcceptanceCriteria)
	set(req.Notes, &p.Notes)
	set(req.Assignee, &p.Assignee)
	if req.Priority != nil {
		p.Priority = issueops.Field[int]{Set: true, Value: *req.Priority}
	}
	if req.IssueType != nil {
		p.IssueType = issueops.Field[types.IssueType]{Set: true, Value: types.IssueType(*req.IssueType)}
	}
	if req.NewStatus != nil {
		p.Status = issueops.Field[types.Status]{Set: true, Value: types.Status(*req.NewStatus)}
	}
	p.Labels.Add = req.AddLabels
	p.Labels.Remove = req.RemoveLabels
	return p
}

// writeFailure types the refusals beads raises on purpose; anything else keeps beads' text.
func writeFailure(err error) Response {
	switch {
	case errors.Is(err, issueops.ErrAssigneeMismatch), errors.Is(err, issueops.ErrStatusMismatch),
		errors.Is(err, issueops.ErrVersionMismatch):
		return fail(CodeConflict, err)
	case errors.Is(err, issueops.ErrAlreadyClaimed), errors.Is(err, issueops.ErrNotOwner),
		errors.Is(err, issueops.ErrNotClaimable):
		return fail(CodeClaimed, err)
	case errors.Is(err, issueops.ErrCloseBlocked), errors.Is(err, issueops.ErrCloseOpenChildren),
		errors.Is(err, issueops.ErrDependencyCycle), errors.Is(err, issueops.ErrSelfDependency),
		errors.Is(err, issueops.ErrNotClaimed), errors.Is(err, issueops.ErrNotReleasable):
		return fail(CodeRefused, err)
	case errors.Is(err, issueops.ErrValidation):
		return fail(CodeBadRequest, err)
	}
	return notFoundOr(err)
}
