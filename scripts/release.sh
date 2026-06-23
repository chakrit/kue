#!/usr/bin/env bash
# Cut a Kue release locally. No CI, no GitHub Actions — this script IS the
# release pipeline. Run it from a clean checkout on macOS arm64.
#
# It builds the self-contained `kue` binary, publishes it as a GitHub Release
# asset on the `v<version>` tag, then patches and pushes the Homebrew tap
# formula so `brew install chakrit/tap/kue` serves the new version.
#
#   Usage: scripts/release.sh <version>          # e.g. scripts/release.sh 0.1.0
#   Env:   KUE_TAP_DIR=<path>                     # chakrit/homebrew-tap clone
#                                                 # (default: ../homebrew-tap)
#
# Lean 4 / lake static-links the Lean runtime; on macOS the binary's only
# dynamic deps are /usr/lib system libraries, so the arm64 asset installs
# directly. We build for the host only — the formula is arm64-macOS-only.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version>   (e.g. scripts/release.sh 0.1.0)}"
TAG="v${VERSION}"
TARGET="aarch64-apple-darwin"
ASSET="kue-${TARGET}"
REPO="chakrit/kue"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_DIR="${KUE_TAP_DIR:-"$(dirname "$REPO_ROOT")/homebrew-tap"}"
FORMULA="${TAP_DIR}/Formula/kue.rb"

# shellcheck source=scripts/patch-formula-block.sh
. "$(dirname "${BASH_SOURCE[0]}")/patch-formula-block.sh"

step() { printf '\n==> %s\n' "$1"; }
die()  { printf 'release: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ] \
  || die "must run on macOS arm64 (the formula ships an arm64 asset); host is $(uname -s)/$(uname -m)"
[ -f "$FORMULA" ] || die "tap formula not found at $FORMULA (set KUE_TAP_DIR)"
[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] \
  || die "working tree dirty — commit or stash before releasing"

step "Building kue (lake build)"
( cd "$REPO_ROOT" && lake build kue )
BIN="$REPO_ROOT/.lake/build/bin/kue"
[ -x "$BIN" ] || die "expected binary at $BIN after build"

step "Staging asset $ASSET"
DIST="$REPO_ROOT/dist"
mkdir -p "$DIST"
cp "$BIN" "$DIST/$ASSET"
SHA="$(shasum -a 256 "$DIST/$ASSET" | awk '{print $1}')"
printf 'sha256: %s\n' "$SHA"

step "Ensuring tag $TAG"
if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "tag $TAG already exists"
else
  git -C "$REPO_ROOT" tag -a "$TAG" -m "Kue $TAG"
fi
git -C "$REPO_ROOT" push gh "$TAG"

step "Publishing GitHub release $TAG"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DIST/$ASSET" --repo "$REPO" --clobber
else
  gh release create "$TAG" --repo "$REPO" --title "Kue $TAG" \
    --generate-notes "$DIST/$ASSET"
fi

step "Patching tap formula $FORMULA"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
# The formula is per-platform blocks; release.sh owns `version` + the macOS
# on_arm block. Patch by asset name so we never touch the Linux blocks (those
# belong to release-linux.sh).
patch_formula_version "$FORMULA" "$VERSION"
patch_formula_block "$FORMULA" "$ASSET" "$URL" "$SHA"

step "Pushing tap"
git -C "$TAP_DIR" pull --ff-only
git -C "$TAP_DIR" add Formula/kue.rb
git -C "$TAP_DIR" commit -m "kue ${VERSION}"
git -C "$TAP_DIR" push

step "Done — install with: brew install chakrit/tap/kue"
