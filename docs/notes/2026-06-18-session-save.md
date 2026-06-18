# RESUME HERE — session save (ace-save, 2026-06-18)

Deliberate save point. Newest START-HERE; supersedes all prior breadcrumbs as the pointer.
Tree clean, pushed to `gh:main` (HEAD `e4c9f3a`). For the FULL detail of the latest work +
the read-only bisect/probe recipe, see the companion breadcrumb
[`2026-06-18-argocd-packs-argo-chain-landed.md`](2026-06-18-argocd-packs-argo-chain-landed.md).
Live roadmap: [`../spec/plan.md`](../spec/plan.md) (lean + current, authoritative).

User note on this save: *"seems agents crashed or something?"* — see **Agent crash** below.
Short answer: one transient crash earlier, fully recovered; nothing lost; tree clean.

## Where Kue stands (real-app)

- **argocd: LAST CORRECTNESS GAP CLOSED** (link 5 `packs.#Argo`, a 4-sub-fix chain —
  `8ce2462`/`6436d08`/`14994e6`/`7898cff`). Every component is content-identical to cue.
  Full `kue export apps/argocd.cue` still bottoms — but that's the **PERF WALL** (fuel
  exhaustion under combined load, ~5×71s `packs.#Argo`), NOT a correctness "link 6". cue
  does the full app in 0.03s.
- **cert-manager: content-identical to cue, but slow** (~92–160s across probes; perf-bound;
  the link-3/4 two-pass change regressed it from ~31s and the cheap Pass-2 fix did NOT
  reclaim it — the dominant cost is frame-id divergence, item 7).
- So correctness for both probed prod9 apps is **DONE**; the remaining real-app gap is PERF.

## Immediate next steps (in order)

1. **Two-phase audit — PENDING, run FIRST (before more code).** Covers the un-audited batch
   since the last audit: the `def-open-tail-closedness` `hasTail` change (NEW `.structComp`
   field threaded through 42 sites — exhaustiveness/open-closed correctness), the Pass-2
   selective re-eval, and the argocd link-5 4-sub-fix chain. Phase A (code-quality) then
   Phase B (architecture — overdue; especially the frame/`structComp` machinery, best
   audited right before the frame-id perf work). Procedure: `docs/guides/slice-loop.md`, NOT
   `/ace-audit`.
2. **Plan item 7 — per-eval-cost / canonical frame identity (THE perf frontier).** Reclaims
   cert-manager AND unblocks full argocd (correct-but-fuel-exhausted at scale). Lever:
   structurally-identical frame re-pushes get fresh ids → memo misses → exponential
   divergence → fuel exhaustion. Same fields + same parent id-stack → reuse id.
   Soundness-critical + audit-heavy ("independently-built frames never falsely share"):
   design sub-spike first, byte-identical fixtures, STOP-and-report if soundness can't be
   guaranteed (per `docs/decisions/2026-06-18-correctness-over-performance.md`).
3. Remaining backlog (`plan.md`): truncate-primitive #2, Regex/EvalOps #3/#4, test-org #5,
   field-ordering #6, borderline #8 + the deferred no-default-disj-self-embed shape (see the
   companion breadcrumb's "KNOWN latent shape").

## Agent crash (the user's note)

One transient failure this session, **RECOVERED**: an audit subagent died on an API
"Overloaded" error mid-run, losing its *uncommitted* work; I re-ran it → succeeded
(`fc25a71`/`faf38b7`). That incident prompted the new **resilience pass** + the
**commit-at-checkpoints** guard — now a standing duty in `slice-loop.md` and logged in
[`../reference/failure-modes.md`](../reference/failure-modes.md). Separately, a *stale
duplicate* notification from an already-completed fix agent LOOKED like a crash but wasn't.
The link-5 agent did NOT crash — it completed the full chain. Net: nothing lost, tree clean
+ pushed at `e4c9f3a`.

## Standing context (durable, do not relearn)

- Autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on
  `main`, no branch). **Correctness over performance** (decision doc).
- Orchestrator = thin re-spawner; one subagent per slice; audits every 2–3 slices (A then
  B); periodic test-org / plan-hygiene / **resilience** passes (`slice-loop.md`). Subagents
  **commit at checkpoints**, not only at the end.
- prod9 + cue cache READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard`
  on the main tree. `git commit -F /tmp/msg` (the bash filter mangles piped/heredoc input).
- Human-scannable status page: `docs/www/index.html` (note: currently lags the plan — shows
  argocd "blocked on link 3"; refresh on the next plan-hygiene pass).
