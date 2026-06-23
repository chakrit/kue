# RESUME — perf #7 frame-sharing WON'T-FIX; two-phase audit DUE (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-plan-hygiene-argocd-milestone.md`
(deleted). Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) (perf #7 block +
Live Backlog). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Perf detail:
[`../guides/kue-performance.md`](../guides/kue-performance.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## State — audit counter = 3. A two-phase audit is DUE NOW (before the next forward slice)

perf #7 safe-wins = slice 1; plan-hygiene = slice 2; perf #7 frame-sharing measurement =
slice 3 (counter hit 3). **Next action is the two-phase audit**, per
[`../guides/slice-loop.md`](../guides/slice-loop.md) — sequential (A) code-quality then
(B) architecture/refactor/cleanup. Do NOT invoke `/ace-audit`; spawn the audit subagents
per the guide. On resume: verify HEAD == upstream (tree clean, pushed `main -> main`).

## What landed this slice — perf #7 frame-sharing: DESIGNED-AND-DEFERRED → WON'T-FIX

The proof-first GATED slice for perf #7's residual (~175× env-DEPENDENT re-eval).
**Nothing shipped — and that is the correct outcome, backed by hard measurement, not a
deferred-proof punt.**

- **The no-false-share invariant (established first):** two def-body forces are
  share-equivalent iff their captured envs agree on everything the body can OBSERVE (the
  reachable captured bindings up to the body's free-var depth-reach). Merging frames that
  disagree on an observable binding = false share = silent wrong value = Violation.
  `env.ids` is already a SOUND content-proxy (`FrameKey = (parentIds, fields)`); the ~175×
  is id-DIVERGENCE of *shape*-similar but *content*-distinct envs.
- **Measured the win ceiling before touching the soundness core** with a zero-risk
  content-addressed SHADOW of `satCache` (keyed on FULL env CONTENTS via structural `BEq`,
  never read by the result path) counting how many core evals a content-addressed env key
  would COLLAPSE:

  | app          | core evals | content-collapsible | ceiling |
  |--------------|-----------:|--------------------:|--------:|
  | cert-manager |    317,788 |                 144 |  0.045% |
  | argocd       |    486,773 |                 288 |  0.059% |

- **Verdict: WON'T-FIX.** The ~175× re-eval is REAL but NOT content-redundant:
  `distinctShapes≈4763` measured SHAPE similarity (digest-depth 8); the cache correctly
  keys on CONTENT. The ~175 frame envs carry ~175 GENUINELY-DIFFERENT observable bindings
  (distinct resource fields + use-site narrowings) — distinct evaluations, not
  id-divergence of identical content. Collapsing them is a FALSE SHARE → wrong value, which
  is why the ceiling is ~0%. No sound frame-sharing widening can reclaim the factor; it is
  the irreducible cost of distinct content. Proof obligation moot (share empirically empty
  AND unsound where non-empty).
- Instrument fully REVERTED; tree clean; `lake build` + `check-fixtures.sh` green; both
  canaries jq -S = 0 (unchanged from baseline). Docs updated: `plan.md`,
  `kue-performance.md`, `implementation-log.md`.

## Live state

- **TWO content-identical prod9 drop-ins:** cert-manager **~12s**, argocd **~50–54s** (both
  jq -S diff = 0 vs `cue`, modulo field-order #3; bytes 1448 / 51178). Bug2-5..2-14c chain
  CLOSED.
- **perf #7:** the two safe wins SHIPPED earlier (`selfEvaluatingLeaf?` fast path +
  saturated-only `satCache` insert). The frame-sharing leg is now **CLOSED as won't-fix**
  (this slice). The per-eval-cost frontier (residual ~50s) is a genuinely-large
  distinct-eval population, NOT cross-env-shareable.
- Everything spec-conformance-HIGH DONE; BI-2 family COMPLETE; EvalOps carved.

## NEXT LEADER — none active in the perf lane

perf #7 frame-sharing is CLOSED. After the DUE two-phase audit, the live frontier is the
per-eval CONSTANT / eval COUNT (a future per-eval-cost slice, or the user-controllable
flatten/shorten lever — NOT cross-env sharing). Remaining ranked backlog (none
soundness-bearing, none block adoption):

- **SC-4** (LOW, spec-gap-first) · **Bug2-12** (cycle-closedness leak, spec-check first) ·
  **missing-field-selection** (LOW) · the **item-6 LOW tail** in `plan.md`
  (`module-file-scoped-imports`, parser strictness, `release-linux.sh` dirty-tree guard,
  A2-x/y, B2-A1/A2).

Fold audit findings into the plan as fix-slices; pick the next leader after the audit.

## RELEASE FLAG (orchestrator, user-gated)

A parallel agent (SEPARATE worktree) is finalizing **`v0.1.0-alpha.20260623`** (Linux
assets + formula) — the argocd-drop-in-#2 milestone release. Mechanism: `scripts/release.sh
v0.1.0-alpha.20260623` (local only; CI/Actions banned; push waits for a human). Do NOT cut
autonomously, and do NOT touch `scripts/**` (owned by that agent). Last cut:
`v0.1.0-alpha.20260622`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue`) a fallible cross-check, never the
  gate. kue binary: `.lake/build/bin/kue`. argocd/cert-manager oracles from the prod9
  infra root (`/Users/chakrit/Documents/prod9/infra`, READ-ONLY): `apps/argocd.cue`,
  `apps/cert-manager.cue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main
  tree.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (`--` line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
