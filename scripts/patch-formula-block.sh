#!/usr/bin/env bash
# Block-aware Homebrew-formula patcher, shared by release.sh and release-linux.sh.
#
# The tap formula (Formula/kue.rb) is structured as per-platform blocks:
#
#   on_macos { on_arm  { url ...; sha256 ... } }
#   on_linux { on_intel{ url ...; sha256 ... }
#              on_arm  { url ...; sha256 ... } }
#
# url/sha256 sit 6 spaces deep inside the blocks, so a flat top-level sed
# (`s|^  url ...|`) silently no-ops. We instead key on the asset *filename*,
# which appears in exactly one block's url line, and rewrite that block's url +
# the sha256 line that immediately follows it. Indentation-agnostic and scoped
# to one block, so the other platform blocks are never touched.
#
#   patch_formula_block <formula> <asset> <url> <sha256>
#
# Idempotent: re-running with the same url/sha is a no-op diff. Exits non-zero
# if the asset's block (url + following sha256) is not found, so a structural
# drift in the formula fails the release loudly instead of shipping stale shas.

# Replace the `url`/`sha256` pair of the block identified by $asset (the binary
# filename that the block's url ends with). Writes in place.
patch_formula_block() {
  local formula="$1" asset="$2" url="$3" sha="$4"
  local tmp; tmp="$(mktemp)"

  awk -v asset="$asset" -v url="$url" -v sha="$sha" '
    # A url line for the target block: ends in /<asset>". Capture leading
    # whitespace, rewrite the value, and arm the sha256 rewrite for the next
    # sha256 line.
    $1 == "url" && $0 ~ ("/" asset "\"[[:space:]]*$") {
      match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH)
      print indent "url \"" url "\""
      arm = 1
      url_hits++
      next
    }
    arm && $1 == "sha256" {
      match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH)
      print indent "sha256 \"" sha "\""
      arm = 0
      sha_hits++
      next
    }
    { print }
    END {
      if (url_hits != 1) { print "patch-formula: expected 1 url for " asset ", found " url_hits > "/dev/stderr"; exit 3 }
      if (sha_hits != 1) { print "patch-formula: expected 1 sha256 after " asset " url, found " sha_hits > "/dev/stderr"; exit 3 }
    }
  ' "$formula" > "$tmp" || { rm -f "$tmp"; return 1; }

  mv "$tmp" "$formula"
}

# Replace the top-level `version "..."` line. release.sh owns this.
patch_formula_version() {
  local formula="$1" version="$2" tmp; tmp="$(mktemp)"
  awk -v version="$version" '
    $1 == "version" {
      match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH)
      print indent "version \"" version "\""
      hits++
      next
    }
    { print }
    END { if (hits != 1) { print "patch-formula: expected 1 version line, found " hits > "/dev/stderr"; exit 3 } }
  ' "$formula" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$formula"
}
