# RESUME — two-phase audit CLOSED (Phase A + B HEALTHY); counter = 0; next = per-eval-cost perf frontier (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug212-mutual-resolved.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).
Served status page: [`../../www/index.html`](../../www/index.html).

## State — audit counter = 0. Two-phase audit CLOSED, batch `32643f5..2bbdb05`.

**Both phases HEALTHY** over the Bug2-12b + Bug2-12-mutual + cycle-detector-edge-pins batch:

- **Phase A (code-quality) — HEALTHY** (`2bbdb05`). The new
  `defSlotInClosedCycle`/`defConjRefSlots` cycle detector verified SOUND (terminating,
  `propext`-only, over-fire ruled out, under-fire ruled out at depth 4 + entry-from-member,
  D#2 coexists). Bug2-12b re-confirmed. 6 coverage pins added. Canaries jq-S=0
  (cert-manager 11.4s, argocd 50.5s).
- **Phase B (architecture/refactor) — HEALTHY** (this audit, light confirm-and-close).
  Module graph ACYCLIC + layered, unchanged: the cycle-detector helpers
  (`defConjRefSlots` `Eval.lean:1615`, `defSlotInClosedCycle` `:1635`) sit in a neutral
  upper region above `flattenConjDefRef`, NOT in the def-deferral tier (`:2245+`) nor the
  unsplittable core-force `mutual` (`:3004–4229`); reuse the `mergeDefinitionDecls`
  primitive (`:385`); add NO cross-module edge. **`Eval.lean` = 4282 lines** (+167 since
  4115, all upper-helper) — under the ~4500 `Eval.DefDeferral` carve watch (HELD; trigger
  not met). Tech-debt sweep clean (only `\uXXXX` doc-comment "XXX" hits). NO new
  duplication — three-gate close reuses `mergeDefinitionDecls`, already ruled
  SHARED-PRIMITIVE-DISTINCT-SEAMS. Test-health OK: `Bug2xTests` 1235, `TwoPassTests` 1493,
  `EvalTests` 1641 — all under the ~2000 silent-failure watch, no org due.

**HEADLINE recorded — multi-ref CYCLIC perf repro.** A closed mutual cycle conjoining ≥2
back-referencing defs (`#A: #B & #C & {a}`, `#B: #A & {b}`, `#C: #A & {c}`) reproduces the
per-eval-cost / flatten-fan-out wall in 3 lines: `kue export` **>40s** vs a single-ref
cycle of any depth **~0.12s** (both correct when finished). PREDATES the cycle detector
(verified `32643f5` worktree — same family as the cert-manager/argocd per-eval churn, NOT
introduced by Bug2-12-mutual). `cue` v0.16.1 cheaply REJECTS it (the Bug2-12-mutual
over-rejection divergence) so the oracle is no profiling aid. **NOT a soundness/termination
defect** — record-only, a small fast repro for the next perf slice. Landed in
`kue-performance.md` § Known limitations (Multi-ref CYCLIC defs) + cross-ref'd from
`plan.md` perf item #5. Commit: this audit-close commit on `main`.

Release `v0.1.0-alpha.20260623` is CUT; the Homebrew formula is live-correct across 3
platforms (host arm64 + Linux x86_64/arm64, `14fb23e` block-aware patch).

## NEXT — pick the next leader (resolve by philosophy; none soundness-bearing)

Spec-conformance-HIGH fully DONE. The whole Bug2-12 family (self-rec + 2-12b + MUTUAL)
RESOLVED. perf-#7 frame-sharing WON'T-FIX (~0.05% ceiling, unsound where non-empty).
Ranked candidates:

1. **per-eval-cost / flatten-fan-out perf frontier** (the live lever) — lower the per-eval
   CONSTANT / eval COUNT over the genuinely-large distinct population. NOW with the small
   multi-ref-cyclic repro (3 lines, >40s) — profile that instead of the 50s argocd. NOT
   cross-env sharing (closed). Detail: `kue-performance.md`.
2. **SC-4** (LOW, spec-gap-first — nested hidden/let closedness on direct def-meet; cue
   internally inconsistent, spec-check FIRST, do not reflexively match cue).
3. **item-6 LOW tail** in `plan.md` (parser strictness `*(1|2)`/`__x`, A2-x/y, B2,
   `module-file-scoped-imports`, the concurrent-release tap-clone race — none
   soundness-bearing).

## Live state end
