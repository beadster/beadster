#!/bin/bash
# Fixture projects made by bd itself (the pinned build from build.sh test), each with the
# answers bd --json gives for it. BeadsKit's tests (K7) read both and compare field by field.
#
#   bash macos/BeadsFFI/fixtures.sh            # all fixtures into ~/.cache/beadster/fixtures
#
# Each fixture: <name>/.beads (the project) and <name>/expected/*.json (bd's answers).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="${BEADSTER_CACHE:-$HOME/.cache/beadster}"
BD="$CACHE/out/bd"
FIX="$CACHE/fixtures"
[ -x "$BD" ] || { echo "no bd at $BD: run build.sh test first"; exit 1; }
REAL_HOME="$HOME"
before="$(ls -A "$REAL_HOME/.beads" 2>/dev/null | sort | tr '\n' ' ')"
# bd keeps usage metrics under the user's home and sends them: off, and HOME away from the real one
export DO_NOT_TRACK=1 BD_DISABLE_METRICS=1 BD_DISABLE_EVENT_FLUSH=1 HOME="$FIX"

rm -rf "$FIX" && mkdir -p "$FIX"
"$BD" version | grep -q "1.3.1" || { echo "bd is not 1.3.1"; exit 1; }
export BD_JSON_ENVELOPE=0 BEADS_ACTOR=fixture GIT_CONFIG_NOSYSTEM=1

# new <name>: an initialized project. BEADS_DIR pins every bd call to it: without it bd walks
# up from the folder and lands in ~/.beads (it did on 2026-10-07 and wrote a project there).
# HOME inside the fixture keeps bd's per-user files out of the real home.
new() {
  DIR="$FIX/$1"; mkdir -p "$DIR/expected"; export HOME="$DIR" BEADS_DIR="$DIR/.beads"
  (cd "$DIR" && "$BD" init --prefix "$2" --quiet >/dev/null)
}
b() { (cd "$DIR" && "$BD" "$@"); }
id() { b create "$@" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'; }
expect() {
  b list --all --limit 0 --json > "$DIR/expected/list-all.json"
  b ready --limit 0 --json > "$DIR/expected/ready.json"
  b export --all -o "$DIR/expected/export.jsonl" >/dev/null
}
show() { b show "$1" --json --include-comments --include-dependents > "$DIR/expected/show-$1.json"; }

# empty: init and nothing else
new empty em; expect

# one: a single bead with every text field
new one on
X=$(id "The only bead" -d "A description." --design "A design." --acceptance "It works." -p 1 -t feature -a anton)
expect; show "$X"

# links: every dependency type, labels, comments, closed and deleted
new links ln
EPIC=$(id "Sync 2.0" -t epic -p 1)
A=$(id "Conflicts lose a paragraph" -t bug -p 0)
B=$(id "Conflict banner copy" -p 2 --deps "blocked-by:$A")
C=$(id "Merge by block id" -p 2)
D=$(id "Found while fixing" -p 3 --deps "discovered-from:$A")
b dep add "$A" "$EPIC" --type parent-child >/dev/null
b dep add "$B" "$EPIC" --type parent-child >/dev/null
b dep relate "$C" "$D" >/dev/null
b label add "$A" sync,data-loss >/dev/null
b comments add "$A" "Repro: two devices, offline edits." >/dev/null
b close "$C" -r "done" >/dev/null
GONE=$(id "Deleted bead" -p 4)
b delete "$GONE" --force >/dev/null
expect; for i in "$EPIC" "$A" "$B" "$C"; do show "$i"; done

# gates: a human gate holding a bead, a timer gate
new gates gt
W=$(id "Deploy to production" -p 1)
b gate create --type=human --blocks "$W" --reason "Approve the deploy" >/dev/null
T=$(id "Ship after review" -p 2)
b gate create --type=timer --blocks "$T" --timeout 2h >/dev/null
expect; show "$W"

# workflow: a molecule poured from beads' own example formula
new workflow wf
mkdir -p "$DIR/.beads/formulas"
cp "$CACHE/beads-1.3.1/examples/formulas/quick-check.formula.toml" "$DIR/.beads/formulas/"
b mol pour quick-check >/dev/null
expect

# memories
new memories mm
b remember "Never run wrangler deploy; use npm run deploy." --key deploy-rule >/dev/null
b remember "History lives in .wander inside the vault." --key vault-history >/dev/null
b memories --json > "$DIR/expected/memories.json"
expect

# claims: one bead claimed by an agent
new claims cl
K=$(id "Branch mode" -p 1)
(cd "$DIR" && BEADS_ACTOR=claude-1 "$BD" update "$K" --claim >/dev/null)
id "Unclaimed" -p 2 >/dev/null
expect; show "$K"

# many: 2,000 beads imported in one go (speed checks, Q3)
new many mn
python3 - "$DIR/import.jsonl" <<'PY'
import json, sys
types = ["task", "bug", "feature", "chore"]
with open(sys.argv[1], "w") as f:
    for i in range(2000):
        f.write(json.dumps({"id": f"mn-{i:04x}", "title": f"Generated bead {i}", "status": "closed" if i % 5 == 0 else "open",
                            "priority": i % 5, "issue_type": types[i % 4],
                            "created_at": "2026-10-01T10:00:00Z", "updated_at": "2026-10-01T10:00:00Z",
                            **({"closed_at": "2026-10-02T10:00:00Z"} if i % 5 == 0 else {})}) + "\n")
PY
b import "$DIR/import.jsonl" >/dev/null
rm "$DIR/import.jsonl"
expect

after="$(ls -A "$REAL_HOME/.beads" 2>/dev/null | sort | tr '\n' ' ')"
[ "$before" = "$after" ] || { echo "FAIL: ~/.beads changed: $before -> $after"; exit 1; }
echo "fixtures in $FIX:"
for d in "$FIX"/*/; do
  n=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$d/expected/list-all.json")
  printf '  %-10s %5s beads  %s\n' "$(basename "$d")" "$n" "$(du -sh "$d/.beads" | cut -f1)"
done
