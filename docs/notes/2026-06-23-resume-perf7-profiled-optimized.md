# RESUME — perf #7 PROFILED + first sound optimization LANDED (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-audit-CLOSED-perf7-leader.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) (NEXT LEADER block). Per-slice
history: [`../reference/implementation-log.md`](../reference/implementation-log.md) (perf #7
slice, appended). Perf detail: [`../guides/kue-performance.md`](../guides/kue-performance.md)
(argocd-EXPORTS block + perf-#7 PROFILED+OPTIMIZED note).

## State — audit counter = 1. perf #7 first slice LANDED.

One forward slice landed since the last two-phase audit (counter 0 → 1). Run **1–2 more
forward slices, then the next two-phase audit** (counter hits 2–3). On resume: verify HEAD ==
upstream (tree clean, pushed `main -> main`).

## What landed this slice — perf #7 (profile + two sound optimizations)

`kue export apps/argocd.cue` **~53.4s → ~50.3s user** · cert-manager **~12.6s → ~11.7s** ·
BOTH jq -S diff = 0 vs cue (51178 / 1448 bytes) · full `native_decide` suite +
`check-fixtures.sh` green · ZERO fixture drift.

**The profile (the bankable finding):** the ~53s wall is a **~175× RE-EVALUATION factor** —
`evalCalls=832338` core evals but only `distinctShapes=4763` distinct value subtrees, because
the SAME subtree is re-evaluated under ~175 distinct frame envs and the cache keys on
`env.ids` (FRAME-ID DIVERGENCE). NOT fuel (DIGEST_DEPTH 1 vs 3 flat), NOT an O(N²) hash
collapse (item-7 hash is well-tuned), NOT output-driven. `evalCacheHits=0` (the fuel-keyed
`cache` never hits — all re-served from the fuel-free `satCache`). Tag histogram: `.prim`
+`.kind` ≈ 37% are env-INDEPENDENT constants re-keyed per env.

**Two sound optimizations (Kue/Eval.lean):** (1) `selfEvaluatingLeaf?` fast path — return
env-independent leaves directly, skip the `valueDigest`-hashed satCache/cache probe+insert;
(2) saturated-only `satCache` insert — saturated results live only in the fuel-free
`satCache`, never the (provably dead) fuel-keyed `cache`. Both value-identical by construction
+ empirically (canaries jq-S=0). The 5 `evalStructRefsCalls` perf pins shifted to new lower
counts (metric move; value pins unchanged).

## NEXT LEADER — perf #7 CONTINUED: share env-DEPENDENT evals across frames (RANKED #1)

The dominant ~50s residual is the ~175× re-eval of env-DEPENDENT shapes (structs/refs/
conjunctions forced under divergent frames) — the leaf bypass does NOT touch it. The designed
fix: collapse structurally-identical def bodies forced under different resource scopes to one
frame id (so they hit the env-keyed `satCache`), OR content-address def-body closures
independent of the capturing frame. **This touches the soundness core of frame identity
(`FrameKey`/`ForceKey` proxy argument) — a DEDICATED GATED slice needing a no-false-share
proof, not a quick change.** Correctness-over-perf is ABSOLUTE: a frame-sharing widening that
could alias-corrupt a value is a Violation; profile + design + STOP beats an unsound ship. The
existing `FrameKey` soundness note (Eval.lean ~1403) is the template for the proof obligation.

Below perf #7 in rank: the **item-6 LOW tail** (`module-file-scoped-imports`/
`release-linux.sh` consistency, LOW), then a **plan-hygiene pass** (distill Bug2-5..2-14c
history → log + git; normalize ~95-col wrapping back to 90).

## RELEASE FLAG (orchestrator, user-gated) — STILL PENDING

A fresh alpha `v0.1.0-alpha.20260623` is a NOTABLE-milestone release (argocd drop-in #2, now
~50s) the orchestrator should cut WITH THE USER'S GREENLIGHT. Mechanism: `scripts/release.sh
v0.1.0-alpha.20260623` (local only; CI/Actions banned; push waits for a human). Do NOT cut
autonomously. Last cut was `v0.1.0-alpha.20260622`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check, never
  the gate. kue binary: `.lake/build/bin/kue`. argocd oracle = `kue export apps/argocd.cue`
  from the prod9 infra root (`/Users/chakrit/Documents/prod9/infra`, READ-ONLY).
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
