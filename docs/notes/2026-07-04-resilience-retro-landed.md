# Breadcrumb: 2026-07-04 — resilience/retro pass landed

Supersedes `2026-07-04-phase-b-audit-complete.md` as the live front. That note's ranked
"Next step" queue is UNCHANGED and still authoritative — this was an out-of-band
process-hardening slice (no plan item, no code change), so resume from there.

## What landed

Resilience/retrospective pass over the 2026-07-03/04 session's OPERATIONAL failures
(docs-only; `./scripts/check.sh` GREEN, exit 0).

- **`failure-modes.md`** — 2 new + 2 extended:
  - NEW: subagent stalls babysitting a long foreground build → orchestrator runs it as a
    `run_in_background` job, never delegates.
  - NEW: invasive change to a foundational type (`Field.quoted`, `f128600`) polluted derived
    `BEq` (`{x:1}!={"x":1}`), canary missed it → mandatory two-phase audit after reshaping an
    equality-derived type; keep provenance bits inert.
  - EXTENDED (parallel commit collision): facet (b) — bare `git commit` sweeps a peer's staged
    change (`b5425fb`) → ALWAYS `git commit -F msg -- <files>`.
  - EXTENDED (handoff misdiagnosis): the three 2026-07-04 red-herring pins (L5-1, L5-2,
    module-import "spec says X") → treat any inherited pin as a hypothesis; reproduce + bisect.
- **`slice-loop.md`** subagent-prompt conventions — 2 new standing bullets: explicit-pathspec
  commit (never bare); long builds are the orchestrator's `run_in_background` job.

## Next step

Resume the ranked queue in `2026-07-04-phase-b-audit-complete.md` — top item is
**AUDIT-STRUCT-EQ half (1), the `evalEq` slice (plan 0b)**. Two-phase audit for the current
batch is complete; run 2–3 implementation slices before the next audit.
