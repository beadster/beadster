#!/bin/bash
# BeadsFFI: beads' own Go code, called in-process from the sandboxed app.
# The package is built INSIDE a pinned beads checkout because the read-only embedded open
# lives in beads' internal packages.
#
#   bash macos/BeadsFFI/build.sh test      # bd built from the pin + go test
#   bash macos/BeadsFFI/build.sh archive   # the c-archive + header (P2 wraps it as an xcframework)
set -euo pipefail
BEADS_TAG="v1.3.1"
BEADS_COMMIT="c1c4b642ac1c08d8c828007a1c2f96e47e43ef7c"
HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="${BEADSTER_CACHE:-$HOME/.cache/beadster}"
SRC="$CACHE/beads-${BEADS_TAG#v}"
OUT="$CACHE/out"

if [ ! -d "$SRC" ]; then
  git clone -q --depth 1 --branch "$BEADS_TAG" https://github.com/gastownhall/beads "$SRC"
fi
got="$(git -C "$SRC" rev-parse HEAD)"
[ "$got" = "$BEADS_COMMIT" ] || { echo "beads checkout is $got, expected $BEADS_COMMIT"; exit 1; }

rm -rf "$SRC/beadsffi" && cp -R "$HERE/beadsffi" "$SRC/beadsffi"
mkdir -p "$OUT"
# gms_pure_go: no ICU, as beads' own release builds (.goreleaser.yml)
export CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 MACOSX_DEPLOYMENT_TARGET=27.0 GOFLAGS=-tags=gms_pure_go

case "${1:-test}" in
  test)
    (cd "$SRC" && go build -o "$OUT/bd" ./cmd/bd)
    (cd "$SRC" && BD="$OUT/bd" go test -count=1 ./beadsffi/)
    ;;
  archive)
    (cd "$SRC" && go build -trimpath -buildmode=c-archive -o "$OUT/libbeadsffi.a" ./beadsffi/)
    ls -la "$OUT/libbeadsffi.a" "$OUT/libbeadsffi.h"
    ;;
  *) echo "usage: build.sh test|archive"; exit 2 ;;
esac
