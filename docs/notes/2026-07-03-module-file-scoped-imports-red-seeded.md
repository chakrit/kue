# Breadcrumb — 2026-07-03: module-file-scoped-imports RED-SEEDED (fix pending attended)

## State
- Divergence CONFIRMED vs spec + `cue` v0.16.1 (NOT a red herring). Kue merges sibling files'
  imports into one shared package frame; CUE scopes them per-file. Three faces (collision,
  shadow-leak, sibling-not-visible) — all Kue-wrong. Details: implementation-log entry
  "module-file-scoped-imports — RED SEED + gate infra"; plan.md item-6 Open bullet.
- Committed this slice: 2 `.known-red` module fixtures + 1 green over-scope guard; module-gate
  `.known-red` quarantine (`check_module_subpaths`). `./scripts/check.sh` GREEN, canary clean.
- Core fix NOT landed (AFK envelope — core resolve/eval surgery, attended-only).

## Next step (attended)
Implement the fix per the `.afk.log` blocker #5 design (unique per-file importBinding labels +
scope-aware ref-rewrite preserving import sharing). Then delete the two `.known-red` markers so
the gate enforces the seeds, and add the face-3 (reference-not-found) error case.

## Do NOT
- Re-investigate whether the divergence is real — it is (spec + cue confirmed, seeds red).
- Substitute the package VALUE at each ref site (perf trap) — rewrite to a shared unique-label
  binding instead.
