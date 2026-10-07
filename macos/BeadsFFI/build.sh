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
    # the c-archive, its header and a module map, wrapped as BeadsFFI.xcframework in build/
    # (build/ is gitignored and marked ignored for Dropbox: the archive is ~100 MB)
    (cd "$SRC" && go build -trimpath -buildmode=c-archive -o "$OUT/libbeadsffi.a" ./beadsffi/)
    rm -rf "$OUT/headers" && mkdir -p "$OUT/headers"
    cp "$OUT/libbeadsffi.h" "$OUT/headers/"
    printf 'module BeadsFFI {\n  header "libbeadsffi.h"\n  link "resolv"\n  export *\n}\n' > "$OUT/headers/module.modulemap"
    mkdir -p "$HERE/build"
    xattr -w com.dropbox.ignored 1 "$HERE/build" 2>/dev/null || true
    rm -rf "$HERE/build/BeadsFFI.xcframework"
    xcodebuild -create-xcframework -library "$OUT/libbeadsffi.a" -headers "$OUT/headers" \
      -output "$HERE/build/BeadsFFI.xcframework" >/dev/null
    shasum -a 256 "$OUT/libbeadsffi.a" | tee "$HERE/build/libbeadsffi.sha256"
    du -sh "$OUT/libbeadsffi.a" "$HERE/build/BeadsFFI.xcframework"
    ;;
  *) echo "usage: build.sh test|archive"; exit 2 ;;
esac
