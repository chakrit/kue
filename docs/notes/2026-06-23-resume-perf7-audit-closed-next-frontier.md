# RESUME — perf #7 safe-wins audit CLOSED (HEALTHY); audit counter = 0 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-perf7-frame-sharing-wontfix-audit-due.md`
(deleted). Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) (perf #5/#7 block +
Live Backlog). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Perf detail:
[`../guides/kue-performance.md`](../guides/kue-performance.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## State — audit counter = 0. Pick the next forward slice.

The single-pass code-quality audit of batch `50a0db3..14fb23e` is **CLOSED — HEALTHY**.
Counter reset to 0. No audit is due; resume forward motion. On resume: verify HEAD ==
upstream (tree clean, pushed `main -> main`).

## What landed this round — audit of the perf #7 safe-wins (`014faaf`) + docs/infra

Scoped single pass (deliberate, not the A+B split): the batch was thin — ONE Lean change
plus docs/release-infra — and the whole module graph was reassessed last round (acyclic,
layered, healthy; no new modules). Findings:

- **Perf #7 safe-wins (`014faaf`) — adversarially SOUND.** A cache fast-path bug =
  silent wrong values, so both legs were attacked:
  - **`selfEvaluatingLeaf?` = EXACTLY the env/fuel-independent identity set.** All 9
    constructors (`.prim/.kind/.top/.bottom/.bottomWith/.notPrim/.stringRegex/
    .boundConstraint/.thisStruct`) fall through the core's trailing `| _, value =>
    pure value` arm (reads no fuel/env/visited); none carries an unevaluated nested
    `Value`. The env-DEPENDENT catch-all members (`.embeddedList`, `.embeddedScalar`,
    `.listComprehension`) are conservatively EXCLUDED — omission keeps the sound slow
    path, the safe direction. **No false leaf.**
  - **Saturated-only `satCache` insert = provable dead-code elimination.** `SatKey =
    EvalKey ∖ {fuel}`; `satCache.get?` is checked FIRST (`Eval.lean:2979`) before
    `cache.get?` (`:2985`). A saturated result is fuel-insensitive, so it always serves
    from satCache at any fuel — the removed fuel-keyed `cache` insert was STRUCTURALLY
    unreachable (lookup order + key subsumption). `evalCacheHits=0` corroborates, is not
    the proof.
  - **Canaries:** argocd jq -S diff = 0 (51178 B, ~50.5s), cert-manager jq -S diff = 0
    (1448 B, ~12s). 5 `evalStructRefsCalls` metric pins moved to lower counts; value pins
    (`eval_deep_inline_value_correct`, `selpass_value_correct`) UNCHANGED + green. Full
    `native_decide` + `check-fixtures.sh` green. No new `partial`/`sorry`/axiom.
- **Plan-hygiene `014faaf..686f522` — NO-LOSS.** All 5 named live items present
  (per-eval-cost frontier, SC-4, Bug2-12, missing-field-selection, item-6 tail); 410+629
  removed lines are resolved-history with commit hashes intact, plus item-1 correctly
  rewritten (frame-sharing → WON'T-FIX, per-eval-cost survives as the live lever).
- **Release scripts — SOUND.** `patch-formula-block.sh` is block-aware (asset-name-keyed
  awk, quote-anchored), fail-loud (`exit 3` on missing/ambiguous block, no `mv` on
  failure), idempotent (in-place url+sha replace), disjoint block ownership (macOS vs
  Linux assets never overlap). Shellcheck clean. ONE LOW finding filed: the two scripts
  share ONE tap clone and each `pull/commit/push` it, so a CONCURRENT run races the git
  index/push — safe sequentially (the intended flow), would race in parallel. Not a
  correctness defect; doc-the-precondition / take-a-lock. Filed in `plan.md` item 6.
- **CLAUDE.md amendment (`8b51b83`)** reads coherently: extends the attended grant to
  auto-cut releases + "don't pause at milestones"; AFK envelope still no-push/no-release.

**Inline fix this round:** concurrent-release tap-clone race → LOW entry in `plan.md`
item 6. No soundness defect found, so no fix-slice filed.

## Live state

- **TWO content-identical prod9 drop-ins:** cert-manager **~12s**, argocd **~50–54s**
  (both jq -S diff = 0 vs `cue`, modulo field-order #3; bytes 1448 / 51178). Bug2-5..2-14c
  chain CLOSED. perf #7 safe-wins SHIPPED + AUDITED SOUND; frame-sharing leg WON'T-FIX.
- Everything spec-conformance-HIGH DONE; BI-2 family COMPLETE; EvalOps carved. Module
  graph ACYCLIC + layered. `Eval`+`Lattice` FULLY total.

## NEXT LEADER — pick one (none soundness-bearing, none block adoption)

perf #7 frame-sharing is CLOSED (WON'T-FIX). The live perf frontier is the per-eval
CONSTANT / eval COUNT over a genuinely-large distinct-eval population — a future
**per-eval-cost slice** (the principled perf lever now that fuel-multiplication + the
safe-wins are banked), OR the **item-6 LOW tail** in `plan.md`
(`module-file-scoped-imports`, parser strictness `*(1|2)`/`__x`, A2-x/y, B2-A1/A2,
`release-linux.sh` dirty-tree guard, the new concurrent-tap-race note, DRY
`selectEvaluatedField .disj`). Also open: **SC-4** (LOW, spec-gap-first) · **Bug2-12**
(cycle-closedness leak, spec-check first) · **missing-field-selection** (LOW).

Rank per the distilled plan: the per-eval-cost lever is the higher-leverage perf next
step; the item-6 tail is cheap-ready cleanup to bank first. Resolve by philosophy and
drive — do not pause to ask "what next".

## RELEASE STATUS

`v0.1.0-alpha.20260623` is **CUT** (GH release Latest, 2026-06-23) and the Homebrew
formula is **live-correct on all 3 platforms** (macOS arm64, linux x86_64, linux arm64).
Do NOT re-cut. Next alpha: ~daily cadence via `scripts/release.sh` +
`scripts/release-linux.sh` (local only; CI/Actions banned; push/release attended-only).

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push/release on `main`
  (attended). Don't pause at milestones.
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue`) a fallible cross-check, never the
  gate. kue binary: `.lake/build/bin/kue`. argocd/cert-manager oracles from the prod9
  infra root (`/Users/chakrit/Documents/prod9/infra`, READ-ONLY): `apps/argocd.cue`,
  `apps/cert-manager.cue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main
  tree.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (`--` line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
