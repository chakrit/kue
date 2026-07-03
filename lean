#!/usr/bin/env bash
# Repo Lean wrapper — invoke Lean via ./lean, never bare `lean`, for the same CPU cap as
# ./lake (LEAN_NUM_THREADS + nice). Builds go through ./lake; this covers direct `lean`
# use. Resolves the real lean via `elan which` to avoid recursing through a repo-root PATH.
set -euo pipefail
: "${LEAN_NUM_THREADS:=2}"
export LEAN_NUM_THREADS
real_lean="$(elan which lean 2>/dev/null || true)"
[ -n "${real_lean}" ] || real_lean="lean"
exec nice -n 19 "${real_lean}" "$@"
