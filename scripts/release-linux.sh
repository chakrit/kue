#!/usr/bin/env bash
# Build and publish Kue's Linux release assets. Companion to release.sh, which
# ships the macOS arm64 asset; this ships the two Linux targets.
#
# There is no turnkey Lean cross-compile (lake/leanc emit C and link the host's
# Lean runtime), so each Linux binary is built NATIVELY-IN-CONTAINER from
# Dockerfile.linux-build: a Linux image with elan + the repo's pinned toolchain,
# then `lake build kue`. On a macOS arm64 host, linux/arm64 builds native (fast)
# and linux/amd64 builds under QEMU emulation (correct but slow).
#
# For each target it builds the image, extracts kue, shasums it, and uploads the
# asset to the v<version> GitHub Release with --clobber (idempotent re-runs).
# It does NOT create the tag/release or touch the Homebrew formula — release.sh
# owns those; this assumes the release already exists.
#
#   Usage: scripts/release-linux.sh <version>     # e.g. ...sh 0.1.0-alpha.20260622
#   Env:   KUE_LINUX_TARGETS="amd64 arm64"        # subset to build (default: both)
set -euo pipefail

VERSION="${1:?usage: scripts/release-linux.sh <version>   (e.g. scripts/release-linux.sh 0.1.0-alpha.20260622)}"
TAG="v${VERSION}"
REPO="chakrit/kue"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${REPO_ROOT}/dist"
TOOLCHAIN="$(cat "${REPO_ROOT}/lean-toolchain")"
TARGETS="${KUE_LINUX_TARGETS:-amd64 arm64}"

step() { printf '\n==> %s\n' "$1"; }
die()  { printf 'release-linux: %s\n' "$1" >&2; exit 1; }

# Map a Docker arch (the buildx --platform suffix) to the Rust-style asset name
# used for the released file, matching the macOS asset's naming scheme.
asset_name() {
  case "$1" in
    amd64) echo "kue-x86_64-unknown-linux-gnu" ;;
    arm64) echo "kue-aarch64-unknown-linux-gnu" ;;
    *) die "unknown target arch: $1" ;;
  esac
}

command -v docker >/dev/null || die "docker not found on PATH"
docker buildx version >/dev/null 2>&1 || die "docker buildx unavailable (needed for --platform builds)"
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
  || die "release $TAG not found on $REPO — cut it with release.sh first"

mkdir -p "$DIST"

for arch in $TARGETS; do
  asset="$(asset_name "$arch")"
  image="kue-linux-build:${arch}"
  platform="linux/${arch}"

  step "Building $asset ($platform, toolchain $TOOLCHAIN)"
  # --load brings the image into the local docker engine so we can extract from
  # it. QEMU (linux/amd64 on an arm64 host) is slow but correct.
  docker buildx build \
    --platform "$platform" \
    --build-arg "LEAN_TOOLCHAIN=${TOOLCHAIN}" \
    --file "${REPO_ROOT}/Dockerfile.linux-build" \
    --tag "$image" \
    --load \
    "$REPO_ROOT"

  step "Extracting binary from $image"
  # Run a throwaway container, copy the binary out, then drop the container.
  cid="$(docker create --platform "$platform" "$image")"
  trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
  docker cp "${cid}:/src/.lake/build/bin/kue" "${DIST}/${asset}"
  docker rm -f "$cid" >/dev/null
  trap - EXIT
  [ -x "${DIST}/${asset}" ] || die "extracted asset ${DIST}/${asset} is not present/executable"

  step "Smoke-testing $asset in $platform container"
  # Run the extracted binary under the matching platform to confirm it executes
  # (the build-time RUN already smoke-tested inside the image; this re-confirms
  # the extracted artifact end-to-end).
  out="$(printf 'x: int & 1\n' \
    | docker run --rm -i --platform "$platform" \
        -v "${DIST}/${asset}:/kue:ro" "$image" /kue eval)"
  [ "$out" = "x: 1" ] || die "smoke test failed for $asset: expected 'x: 1', got '$out'"
  printf 'smoke-test ok: kue eval -> %s\n' "$out"

  sha="$(shasum -a 256 "${DIST}/${asset}" | awk '{print $1}')"
  printf 'sha256(%s): %s\n' "$asset" "$sha"

  step "Uploading $asset to release $TAG"
  gh release upload "$TAG" "${DIST}/${asset}" --repo "$REPO" --clobber

  step "Done with $asset"
done

step "All requested Linux targets published to $TAG"
