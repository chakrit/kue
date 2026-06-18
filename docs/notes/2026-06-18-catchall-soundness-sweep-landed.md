# RESUME HERE — catch-all soundness sweep landed (2026-06-18)

Newest START-HERE; supersedes all prior breadcrumbs as the pointer (incl.
`2026-06-18-session-save.md`). Tree clean, pushed to `gh:main` (HEAD `a7b2724`).
Live roadmap: [`../spec/plan.md`](../spec/plan.md) (authoritative). Full slice detail:
[`../reference/implementation-log.md`](../reference/implementation-log.md) entry
"catch-all soundness hardening sweep (A1 + B1 + Normalize)".

## What just landed

Audit fix-slices **A1 + B1 are DONE**, plus a graph-wide sweep that found and fixed a
THIRD unsound catch-all of the same class. All three were a catch-all over `Value`
silently swallowing compound constructors a recursive function must descend into.

- **A1 + B1 (`80df01e`).** `Eval.lean`: `selfReferencedLabels`/`refsSelfEmbeddedLabel`
  gained `builtinCall`/`embeddedList`/`structPattern`/`structPatterns` arms (a
  `len(Self.#x)` embedded read is now visible to the Pass-2 gate + selection → no stale
  value); `remapConjRefs` gained `.structComp`/`.comprehension`/`.listComprehension`/
  `.embeddedList`/`.dynamicField` arms (+ new `remapConjClauses` helper) so a conjunct's
  `.refId`s rebase correctly across a field-reindexing merge. `closure` stays in both
  catch-alls (captured-env coordinate space — must NOT remap). Pins in EvalTests.
- **Sweep → `Normalize.lean` (`a7b2724`).** Both `normalizeDefinitionValueWithFuel` and
  `normalizeDefinitionsWithFuel` swallowed `.list`/`.comprehension`/`.embeddedList`/…
  (and `.structComp` for the spine walker), so a nested `#Def` directly under a def-field
  list/comprehension was never closed. Added recursing arms (closing normalizer for
  def-body struct literals — CUE closes those, verified). Pins in NormalizeTests.
- **Defensible catch-alls** (swept, left, noted in plan): `resolveValueWithFuel:145`,
  `evalValueCoreWithFuel:2181` (pre-cleared), `meetWithFuel` (exhaustive `meetCore`),
  `subsumesWithFuel`, `selectEvaluatedField`/`lookupField?`/`closeValue`, `Format`/`Manifest`.

Verify: `lake build` 86 jobs green; `fixture pairs ok` (zero byte-drift); no shell changed.

## Immediate next steps (in order)

1. **B6 (NEW, MEDIUM — soundness, surfaced by this sweep).** The Normalize fix closes nested
   defs that normalize REACHES, but the headline closedness hole stays OPEN: (a)
   `normalizeFieldWithFuel` descends ONLY definition fields, so a nested `#Def` under a
   REGULAR field (`a: {#Inner: {…}}` → `a.#Inner & {extra}`) is never normalized — inside a
   def body CUE closes regular-field struct values too; (b) even once normalize closes a
   nested def, the eager nested-selector path does not ENFORCE it (`import-eager-closedness`
   family, item 8). Both oracle-confirmed reachable vs cue 0.16.1. Needs a design-spike: the
   shared `normalizeFieldWithFuel` conflates two contexts (closing-in-def-body vs
   spine-walk) — split it; route the eager selector path through closedness enforcement.
   Behavior change with def-open-tail regression risk → own slice, NOT a quick fix. See plan
   B6.
2. **Two-phase audit is DUE** — A1+B1+Normalize are 1 landed slice; combined with the prior
   un-audited batch (def-open-tail `hasTail`, Pass-2 selective re-eval, argocd link-5 chain
   — see `2026-06-18-session-save.md` step 1) this is past the 2–3-slice mark. Run Phase A
   then Phase B per `docs/guides/slice-loop.md` (NOT `/ace-audit`). Phase B should weigh the
   B6 split + the B2 struct-constructor unification together (both touch normalize/struct
   machinery).
3. **Then the correctness/perf frontier**: A2 (hidden-field deep bottom), A3 (`classifyDefinedness
   .disj` smart-`mkDisj`), B2 (headline 5-struct unification — design-spike), and plan item 7
   (canonical frame identity — THE perf wall reclaiming cert-manager + full argocd).

## Standing context (durable, do not relearn)

- Autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on
  `main`, no branch). **Correctness over performance** (decision doc) — a latent wrong value
  is a Violation; STOP-and-report if soundness can't be guaranteed for a sub-fix (this slice
  did exactly that for B6 rather than ship a risky `normalizeFieldWithFuel` change).
- Orchestrator = thin re-spawner; one subagent per slice; audits every 2–3 slices (A then
  B); subagents commit at checkpoints, not only at the end.
- prod9 + cue cache READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
  `git commit -F /tmp/msg` (the bash filter mangles piped/heredoc input). Oracle:
  `/Users/chakrit/go/bin/cue` (0.16.1).
- `kue eval` does NOT take `-e`; use `kue export -e <path>` to select a field.
- Status page `docs/www/index.html` lags the plan — refresh on the next plan-hygiene pass.
