# RESUME — two-phase audit CLOSED; argocd-EXPORT MILESTONE; next = perf #7 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-perf7-NEXT.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) (NEXT LEADER block +
Resolved/ruled-out top entry). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Perf detail:
[`../guides/kue-performance.md`](../guides/kue-performance.md).

## State — audit counter = 0 (RESET). Two-phase audit CLOSED.

The two-phase audit over batch `673cec8`..`c942993` (Bug2-14 plain-embed + Bug2-14b/14c +
Phase-A coverage) is CLOSED: **Phase A HEALTHY** (`c942993`, milestone NOT at risk —
argocd EXPORTS content-identical, jq-S=0) + **Phase B HEALTHY** (this round). Counter
reset to 0 → run 2–3 forward slices before the next two-phase audit.

On resume: verify HEAD == upstream (tree clean, pushed `main -> main`).

## THE MILESTONE — argocd EXPORTS, content-identical (2nd prod9 real-app drop-in)

`kue export apps/argocd.cue` → **CONTENT-IDENTICAL to cue** (jq -S diff = 0, 51178 bytes
both, **~53s wall**). argocd is now a content-identical drop-in alongside cert-manager
(**~12.6s**, freshly re-measured this round — down from the stale ~30.5s). This is a
NOTABLE-milestone alpha.

**🚩 RELEASE FLAG (orchestrator, user-gated):** a fresh alpha `v0.1.0-alpha.20260623` is a
NOTABLE-milestone release (argocd drop-in #2) the orchestrator should cut WITH THE USER'S
GREENLIGHT. Mechanism: `scripts/release.sh v0.1.0-alpha.20260623` (local only;
CI/Actions banned; push waits for a human). Do NOT cut autonomously. Last cut was
`v0.1.0-alpha.20260622`.

## Phase B verdict (this round) — HEALTHY

- **Architecture HEALTHY.** Module graph re-checked WHOLE: ACYCLIC, strictly layered,
  UNCHANGED (`Builtin` no `Eval`/`EvalOps` edge; `EvalOps → {Builtin,Decimal,Regex}` no
  back-edge; `Decimal → Value`; `Lattice → {Value,Regex}`; `Runtime → Eval`). Cleanliness
  CLEAN (no `sorry`/`panic`/`.get!`/dead code/stale TODO; `partial def` only in
  Parse/Module). Test/fixture health HEALTHY (`TwoPassTests` 1493, `Bug2xTests` 862 — both
  under the 2000 silent-failure surface; bug214b/c module fixtures exercised by
  `check-fixtures.sh`). No test-org due.

- **inject-family DRY → RULED OUT (keep separate).** `injectEmbedSiblingNarrowings`
  (Bug2-14) vs `injectLetLocalNarrowings` (Bug2-4): the DRY-1 / `mergeFieldsWith` trap,
  NOT the `embedChainAny` shape. Decisive asymmetry — at a nested `let`, the embed walker
  DISPATCHES TO the let walker (`:1927`), while the let walker recurses into itself
  (`:1839`); a read-labels-only combinator would change the milestone splice's let-frame
  gating (soundness change to the code that landed argocd). Full basis: `plan.md`
  Resolved/ruled-out, dedicated inject-family entry.

- **perf-#7 → STILL REAL, target now PRECISE (the leader).** argocd ~53s vs `cue` 0.03s
  (~1700×). Profiled: the wall is a FLAT per-eval-constant in definition/import-closure
  setup — selecting ANY single field (even 484-byte `listener.yaml`) AND bare `kue eval`
  both cost the full 53s; NOT a subtree hot spot, NOT output-driven (largest field 4.5KB),
  NOT fuel-axis. Bug2-14 unblocked correctness, exposing the wall is fixed setup. The
  "heavy argo sub-package" framing was imprecise — target = the SETUP closure
  (`defs`+`defaults`+`apps/argo`), profiled with the item-7 lens (cache-key cost, frame-id
  churn, force-cache hit rate). Flat-per-field signature is the reproducer.

- **Eval.DefDeferral carve → HOLD, sharpened trigger.** Eval.lean 4115 (+126 over 3989 —
  Bug2-14b/c growth landed in the CORE force `mutual` block `:3707+`, the unsplittable
  region, NOT the def-deferral tier). Headroom 385; ~2-3 slices at the recent rate. Carve
  the def-deferral tier (`:2220–2828`, ~600 lines, `Eval.DefDeferral`) only when EITHER a
  def-deferral-tier slice pushes Eval.lean past ~4500, OR core-force growth crosses ~4400
  with the tier still intact (carve first to buy room). Semantic-module refactor —
  standalone slice, don't carve inline.

## Inline this round (`c942993`+1 docs commit) — all canary-verified jq-S=0

- `kue-performance.md`: (a) argocd block flipped "bottoms (correctness bug)" → "EXPORTS
  content-identical; chain CLOSED" + perf-#7 PROFILED note (flat 53s setup constant);
  (b) cert-manager currency RE-RECONCILED ~30.5s → ~12.6s (live; 2.4× drop over
  Bug2-6..2-14).
- `plan.md`: NEXT LEADER perf-#7 reassessment; inject-family DRY ruling; new Phase-B audit
  entry; Eval.DefDeferral HOLD math.

## Next leader — perf #7 (RANKED #1)

perf-#7 is the highest-value remaining work: the ~1700× argocd gap is a real cliff with a
now-precise target (definition/import-closure SETUP per-eval constant, flat-per-field
reproducer). Below it, in rank: the **item-6 LOW tail**
(`module-file-scoped-imports`/`release-linux.sh` consistency, LOW), then a **plan-hygiene
pass** (the plan has accreted hugely across Bug2-5..2-14c; distill history → log + git,
also normalize the ~95-col wrapping back to 90). **Correctness-over-perf:** any perf
slice needs byte-identical fixtures + a soundness argument; never trade a wrong value for
speed.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. kue binary: `.lake/build/bin/kue`. `kue export <dir>` for a package; `-e
  field` selects a dotted path (bracket-string selectors do NOT parse — use a scratch
  field). argocd oracle = `kue export apps/argocd.cue` from the prod9 infra root
  (`/Users/chakrit/Documents/prod9/infra`, READ-ONLY).
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main
  tree.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
