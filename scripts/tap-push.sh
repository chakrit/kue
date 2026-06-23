#!/usr/bin/env bash
# Race-safe Homebrew-tap update, shared by release.sh and release-linux.sh.
#
# Both scripts mutate the SAME tap clone (chakrit/homebrew-tap), each patching
# its own DISJOINT formula block (macOS vs the two Linux blocks). With auto-cut
# releases they may run concurrently, so a plain `pull --ff-only` + `push` races:
# whichever pushes second is rejected with no recovery.
#
# We serialize WITHOUT a lock (macOS ships no `flock`) via retry-on-reject with
# rebase. The caller passes a re-patch callback; on each attempt we sync to the
# remote tip, re-apply our patch on top, and push:
#
#   1. discard any local state and `reset --hard` to the freshly-fetched remote
#      tip — a clean base that already contains the sibling's latest block.
#   2. re-apply OUR patch via the callback — idempotent for our block (the
#      asset-suffixed url line survives version bumps, so re-patching finds and
#      rewrites the same block) and block-scoped (only our asset's block is
#      touched), so the sibling block we just fetched is preserved.
#   3. commit-if-changed, then push.
#
# On a push REJECT (a concurrent push landed between our fetch and push) we loop
# from step 1, up to TAP_PUSH_RETRIES times with a short backoff, then `die`.
# Re-fetching picks up the winner's commit; re-patching replays our block on top.
# This also absorbs transient push failures.
#
#   tap_push <tap_dir> <commit_msg> <repatch_fn>
#
# <repatch_fn> is a shell function (already defined by the caller) that re-applies
# the caller's formula patch(es) to "$tap_dir/Formula/kue.rb". It must be
# idempotent and block-scoped — it runs once per attempt, on a clean remote base.
#
# `reset --hard` here is scoped to the tap clone and only ever discards this
# script's own just-applied patch (the caller applies it via <repatch_fn>, which
# we immediately re-run); it never touches the kue repo working tree.
#
# Requires `step` and `die` to be defined by the sourcing script.

TAP_PUSH_RETRIES="${TAP_PUSH_RETRIES:-5}"
TAP_PUSH_BACKOFF="${TAP_PUSH_BACKOFF:-2}"

tap_push() {
  local tap_dir="$1" msg="$2" repatch_fn="$3"
  local attempt=1 branch remote upstream
  branch="$(git -C "$tap_dir" rev-parse --abbrev-ref HEAD)"
  [ -n "$branch" ] && [ "$branch" != "HEAD" ] \
    || die "tap clone is not on a branch (detached HEAD?) — cannot push"
  # Resolve the remote from the branch's upstream (the tap remote is `gh`, not
  # `origin`, per repo convention — never assume a name).
  upstream="$(git -C "$tap_dir" rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null)" \
    || die "tap branch $branch has no upstream — set one (git branch --set-upstream-to)"
  remote="${upstream%%/*}"

  while :; do
    git -C "$tap_dir" fetch --quiet "$remote" "$branch" \
      || die "tap fetch failed (attempt $attempt)"
    # Clean base at the remote tip — discards our local patch (re-applied below)
    # and any half-rebased state, and includes the sibling's latest block.
    git -C "$tap_dir" reset --hard --quiet "$remote/$branch" \
      || die "tap reset to $remote/$branch failed (attempt $attempt)"

    # Re-apply our patch — idempotent + block-scoped, so it never clobbers the
    # sibling block we just fetched.
    "$repatch_fn"

    git -C "$tap_dir" add Formula/kue.rb
    if git -C "$tap_dir" diff --cached --quiet; then
      echo "formula already up to date — nothing to commit"
      return 0
    fi
    git -C "$tap_dir" commit --quiet -m "$msg"

    if git -C "$tap_dir" push --quiet "$remote" "$branch"; then
      return 0
    fi

    # Push rejected (a concurrent push landed first) or transient failure: loop,
    # re-fetching the winner's commit and re-applying our block on top.
    if [ "$attempt" -ge "$TAP_PUSH_RETRIES" ]; then
      die "tap push failed after $TAP_PUSH_RETRIES attempts (concurrent contention or remote error)"
    fi
    echo "tap push rejected — retrying ($attempt/$TAP_PUSH_RETRIES) after ${TAP_PUSH_BACKOFF}s"
    sleep "$TAP_PUSH_BACKOFF"
    attempt=$((attempt + 1))
  done
}
