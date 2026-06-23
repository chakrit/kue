# RESUME — plan-hygiene DONE; argocd content-identical drop-in #2 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-perf7-profiled-optimized.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) (NEXT LEADER block + Live Backlog).
Per-slice history: [`../reference/implementation-log.md`](../reference/implementation-log.md).
Perf detail: [`../guides/kue-performance.md`](../guides/kue-performance.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## State — audit counter = 2. A two-phase audit is DUE after the NEXT slice.

perf #7 (first sound optimizations) = slice 1; this plan-hygiene pass = slice 2 (counter 0 → 1
→ 2). Run **one more forward slice, then the two-phase audit** (counter hits 3). On resume:
verify HEAD == upstream (tree clean, pushed `main -> main`).

## What landed this slice — plan-hygiene (DOCS-ONLY)

Distilled the accreted design record back to a clean restore point after the Bug2-5..2-14c
chain + ~7 audit rounds + perf #7:
- **`plan.md` 1121 → 710 lines** — shed the Bug2-x blow-by-blow + ~7 closed audit-round HEALTHY
  verdicts (collapsed to one history summary keeping the whole-graph invariants + the
  `Eval.DefDeferral` carve-trigger); kept North Star, Working Principles, Standing Capabilities
  (UPDATED), the ranked OPEN backlog, ALL durable rulings, Pointers.
- **`spec-conformance-audit.md` 1236 → 607 lines** — Bug2-5..2-14c family RESOLVED (compressed
  to a per-fix one-liner + log pointer); dropped the Live-slice mechanism blocks + Bug2-x DESIGN
  NOTES; re-ranked the genuinely-open backlog.
- **`www/index.html` refreshed** — argocd flipped to Done (drop-in #2); perf #7 is the live
  frontier; current wall-times; footer 2026-06-23 / release 20260622.
- No live backlog item or durable ruling dropped; all internal doc links verified resolving;
  `lake build` + `check-fixtures.sh` re-confirmed green (docs-only, build unaffected).

## Live state

- **TWO content-identical prod9 drop-ins:** cert-manager **~11.7s**, argocd **~50.3s** (both jq
  -S diff = 0 vs `cue`, modulo field-order #3). The Bug2-5..2-14c argocd narrowing/close-once
  chain is CLOSED — argocd byte-matches cue, no on-path layer hides behind a sound drain.
- **perf #7 safe wins SHIPPED** (2026-06-23): `selfEvaluatingLeaf?` fast path + saturated-only
  `satCache` insert (~53.4s → ~50.3s argocd, ~12.6s → ~11.7s cert-manager; both value-identical,
  zero fixture drift).
- Everything spec-conformance-HIGH is DONE; BI-2 family COMPLETE (math.Pow/Sqrt full real
  domain, exact decimal); EvalOps carved.

## NEXT LEADER — perf #7 frame-sharing (PROOF-FIRST, GATED — STOP-if-unprovable)

The dominant residual is a **~175× re-eval factor** — `evalCalls=832338` core evals over only
`distinctShapes=4763` distinct subtrees, because the SAME subtree is re-evaluated under ~175
distinct frame envs and the cache keys on `env.ids` (FRAME-ID DIVERGENCE; `evalCacheHits=0`, the
fuel-keyed `cache` is dead — all re-served from `satCache`). The designed fix — collapse
structurally-identical def bodies forced under different resource scopes to one frame id (hitting
the env-keyed satCache), OR content-address def-body closures independent of the capturing frame
— **touches the SOUNDNESS CORE of frame identity (`FrameKey`/`ForceKey`) and needs a
no-false-share proof.** A frame-sharing widening that could alias-corrupt a value is a Violation:
profile + design + **STOP** beats an unsound ship. The `FrameKey` soundness note (`Eval.lean`
~1403) is the proof-obligation template. NOT foldable into a quick slice — a dedicated gated one.

Below perf #7: **SC-4** (LOW spec-gap-first) · **Bug2-12** (cycle-closedness leak, spec-check
first) · **missing-field-selection** (LOW) · the **item-6 LOW tail** in `plan.md`
(`module-file-scoped-imports`, parser strictness, `release-linux.sh` dirty-tree guard, A2-x/y,
B2-A1/A2 — none soundness-bearing).

## RELEASE FLAG (orchestrator, user-gated) — STILL PENDING

A fresh alpha **`v0.1.0-alpha.20260623`** is a NOTABLE-milestone release (argocd drop-in #2, now
~50.3s) the orchestrator should cut WITH THE USER'S GREENLIGHT. Mechanism: `scripts/release.sh
v0.1.0-alpha.20260623` (local only; CI/Actions banned; push waits for a human). Do NOT cut
autonomously. Last cut was `v0.1.0-alpha.20260622`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check, never
  the gate. kue binary: `.lake/build/bin/kue`. argocd oracle = `kue export apps/argocd.cue` from
  the prod9 infra root (`/Users/chakrit/Documents/prod9/infra`, READ-ONLY).
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (`--` line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
