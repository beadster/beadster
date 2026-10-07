package main

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/steveyegge/beads/internal/storage/embeddeddolt"
	"github.com/steveyegge/beads/internal/storage/schema"
)

// moveSchema rewrites the newest schema_migrations row to fake a database written by an
// older (delta < 0) or newer (delta > 0) beads, and commits it like bd would.
func moveSchema(t *testing.T, beadsDir string, delta int) {
	t.Helper()
	ctx := context.Background()
	db, done, err := embeddeddolt.OpenSQL(ctx, filepath.Join(beadsDir, "embeddeddolt"), databaseName(beadsDir), "main")
	if err != nil {
		t.Fatalf("open sql: %v", err)
	}
	defer done()
	latest := schema.LatestVersion()
	var q string
	if delta < 0 {
		q = "DELETE FROM schema_migrations WHERE version = ?"
	} else {
		q = "INSERT INTO schema_migrations (version) VALUES (? + 50)"
	}
	if _, err := db.ExecContext(ctx, q, latest); err != nil {
		t.Fatalf("move schema: %v", err)
	}
	if _, err := db.ExecContext(ctx, "CALL DOLT_COMMIT('-Am', 'fixture: move schema')"); err != nil {
		t.Fatalf("commit: %v", err)
	}
}

func TestSchemaBehindNeedsConsent(t *testing.T) {
	dir := newWorkspace(t)
	moveSchema(t, dir, -1)
	e := NewEngine()

	open := call(t, e, map[string]any{"op": "open", "beads_dir": dir})
	if open.Error == nil || open.Error.Code != CodeSchemaBehind {
		t.Fatalf("open on an older schema: %+v", open.Error)
	}
	if open.Error.BinaryVersion != schema.LatestVersion() || open.Error.DBVersion >= open.Error.BinaryVersion {
		t.Fatalf("versions: db %d binary %d", open.Error.DBVersion, open.Error.BinaryVersion)
	}
	// still behind: nothing migrated by the failed open
	if again := call(t, e, map[string]any{"op": "open", "beads_dir": dir}); again.Error == nil || again.Error.Code != CodeSchemaBehind {
		t.Fatalf("open migrated without consent: %+v", again.Error)
	}

	mig := call(t, e, map[string]any{"op": "migrate", "beads_dir": dir})
	if mig.Error != nil || !mig.Changed {
		t.Fatalf("migrate: %+v changed=%v", mig.Error, mig.Changed)
	}
	if after := call(t, e, map[string]any{"op": "open", "beads_dir": dir}); after.Error != nil {
		t.Fatalf("open after migrate: %+v", after.Error)
	}
	if again := call(t, e, map[string]any{"op": "migrate", "beads_dir": dir}); again.Error != nil || again.Changed {
		t.Fatalf("second migrate should be a no-op: %+v %v", again.Error, again.Changed)
	}
}

func TestSchemaAheadIsNeverTouched(t *testing.T) {
	dir := newWorkspace(t)
	moveSchema(t, dir, +1)
	e := NewEngine()
	open := call(t, e, map[string]any{"op": "open", "beads_dir": dir})
	if open.Error == nil || open.Error.Code != CodeSchemaAhead {
		t.Fatalf("open on a newer schema: %+v", open.Error)
	}
	if open.Error.DBVersion <= open.Error.BinaryVersion {
		t.Fatalf("versions: db %d binary %d", open.Error.DBVersion, open.Error.BinaryVersion)
	}
	if mig := call(t, e, map[string]any{"op": "migrate", "beads_dir": dir}); mig.Error == nil || mig.Error.Code != CodeSchemaAhead {
		t.Fatalf("migrate must refuse a newer schema: %+v", mig.Error)
	}
}
