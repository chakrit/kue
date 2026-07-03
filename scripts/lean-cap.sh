# shellcheck shell=bash
# Cap Lean/Lake CPU use. LEAN_NUM_THREADS bounds Lean's elaboration thread pool AND is
# Lake's default job count, so exporting it before a build keeps `lake build` from
# saturating an interactive machine. Defaults to half the host's cores; children of a
# script that sources this inherit it. Override for a dedicated build box, e.g.
# `LEAN_NUM_THREADS=8 ./scripts/check.sh`. Sourced (not executed) by the gate scripts.
if [ -z "${LEAN_NUM_THREADS:-}" ]; then
  _kue_ncpu="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
  LEAN_NUM_THREADS=$(( (_kue_ncpu + 1) / 2 ))
  [ "${LEAN_NUM_THREADS}" -lt 1 ] && LEAN_NUM_THREADS=1
  export LEAN_NUM_THREADS
  unset _kue_ncpu
fi
