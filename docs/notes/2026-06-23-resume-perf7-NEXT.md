# RESUME — Bug2-14b/c LANDED; argocd EXPORTS (drop-in #2); next = perf #7 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug214b-NEXT.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) (Bug2-14b/c
RESOLVED entry). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — audit counter = 2. TWO-PHASE AUDIT DUE after this batch.

Two code slices landed since the last two-phase audit closed (Bug2-14 plain-embed
`e404b21` + Bug2-14b/c this slice) → audit counter = 2 → **a two-phase audit is DUE**
(per `slice-loop.md`: A code-quality then B architecture, sequential — do NOT invoke
`/ace-audit`). Run it before or alongside the next forward slice.

On resume: verify HEAD == upstream (tree clean, pushed `main -> main`).

## THE MILESTONE — argocd EXPORTS, content-identical (2nd prod9 real-app drop-in)

`kue export apps/argocd.cue` → **CONTENT-IDENTICAL to cue** (jq -S diff = 0, 37230 bytes
both, ~53s wall). argocd is now a content-identical drop-in alongside cert-manager
(~12.6s). This is a NOTABLE-milestone alpha — flag a fresh `scripts/release.sh` cut for
the user's greenlight (attended: push waits for a human).

## What landed this slice (Bug2-14b + Bug2-14c)

The last TWO on-path argocd blockers — the `#Mixin` structural-disjunction let-local
(`_patch.kind`) now receives the host's `kind` narrowing on the cross-package force path.

- **Bug2-14b — wrong-frame disjunction-deep gate.** `embedBodyEmbedsDisjDeep` was gated
  against the OUTER fold `env`, but a closure body's own embed-refs (`.refId depth:=1`) are
  relative to the def frame the force PUSHES (the Bug2-11 wrong-frame hazard — trace showed
  `#Mixin` resolving to the string `"ListenerSet"`). Fixed by a `bodyForceFrameEnv
  (capturedEnv body) := (0, body-statics) :: capturedEnv` helper at all THREE gate sites.
  The design's predicted "disjunction-arm distribution" lever was FALSIFIED by trace (third
  slice running where the design lever was wrong — resolve the seam EMPIRICALLY).
- **Bug2-14c — cross-conjunct regular narrowing in the multi-closure `.conj` fold.** The
  real `defaults.#ListenerSet = defs.#ListenerSet & parts.#UseCertManager & {…}` is a
  MULTI-CLOSURE conjunction where `kind` is in one closure and the disjunction+`_patch` in
  another; the `.conj` fold forced each closure independently so `kind` never reached
  `_patch.kind`. Fixed by a TWO-PASS fold splicing a sibling closure's regular fields into a
  disjunction-bearing closure.
- **Soundness:** force-path == inline == cue; arm selection correct (struct arm wins,
  list/error prune); incomplete-guard (abstract `kind`) DEFERS as `incomplete` (not
  force-drain — cue picks the `error` arm, recorded in `cue-spec-gaps.md`); real conflict
  BOTTOMS; cert-manager content-identical (jq -S = 0).
- **Tests:** 2 module fixtures (`testdata/modules/bug214{b,c}_*`) + 3 `native_decide` pins
  (`Bug2xTests` `bug214b_disj_arm_{drains,incomplete_guard_defers,conflict_bottoms}`) +
  tripwire anchor. Build clean (112 jobs), fixtures + shellcheck green.

## Next leader — perf #7 (UN-GATED; argocd's last on-path correctness blocker cleared)

`kue export apps/argocd.cue` exports content-correct in ~53s — the wall is now a PURE perf
concern (no correctness divergence). The heavy `argo` sub-package dominates. Profile it:
the cache-hash digest already collapsed cert-manager's O(N²) (119s → ~30.6s); apply the
same lens (cache-key cost, frame-id churn, force-cache hit rate over the Bug2-14c two-pass
fold) to the `argo` sub-package. See `plan.md` perf item #5/#7.

## Release state

`v0.1.0-alpha.20260622` was the last cut. A fresh alpha is NOW a NOTABLE milestone (argocd
exports content-identical — 2nd real-app drop-in) — flag it for the user's greenlight.
CI/Actions banned; release = local `scripts/release.sh` + `release-linux.sh`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. kue binary: `.lake/build/bin/kue`. `kue export <dir>` for a package (NOT
  `kue export` bare — that reads stdin); `-e field` selects a dotted path (bracket-string
  selectors do NOT parse — use a scratch field). The argocd faithful self-contained repro
  (REAL `prodigy9.co/defs@v0.3.19` from cache) is reconstructable at `/tmp/argols`.
- prod9 (`/Users/chakrit/Documents/prod9/infra`) + cue caches READ-ONLY. NO `git
  checkout`/`restore`/`reset --hard` on the main tree. argocd oracle = `kue export
  apps/argocd.cue` from the infra root.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
