# shellcheck shell=bash
# Cap Lean/Lake CPU so builds never starve an interactive machine. Sourced (not executed)
# by the gate scripts; slices source it before an ad-hoc `lake build` (see slice-loop.md).
# Two permanent levers:
#   1. LEAN_NUM_THREADS bounds Lean's elaboration thread pool AND Lake's build-job count.
#      Defaults to 2. Override upward on a dedicated build box: `LEAN_NUM_THREADS=8 ...`.
#   2. a `lake` wrapper runs the real binary under `nice`, so build workers always yield
#      to foreground work regardless of how many cores they touch.
: "${LEAN_NUM_THREADS:=2}"
export LEAN_NUM_THREADS

# Wrap `lake` so every build in a sourcing script is low-priority. `command` reaches the
# real binary past this function; `nice -n 19` is the lowest user-settable priority.
lake() { nice -n 19 command lake "$@"; }
