# RESUME HERE — argocd deprioritized, design-first; AFK mode added (2026-06-20)

Newest START-HERE; supersedes all prior breadcrumbs as the live pointer. Authoritative live
roadmap: [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (owns the ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities + non-spec roadmap).

## What this session did

1. **Durable-docs cleanup** (committed `da05059`, pushed): plan.md 2741→411, audit.md
   1519→507, notes/ 110→3, +2 ADRs (distribution, language). History → implementation-log
   + git; the log itself left intact (it's the verification archive).
2. **argocd reframed — it was never a goal.** Per chakrit: argocd was a manufactured
   sub-goal; it was only ever an instance of "does real infra compile," which is itself a
   STRESS TEST of the real goal (correct CUE semantics, cleanly-evolving design). The
   6-layer narrowing chase (Bug#1 → … → Bug2-5) was the tail wagging the dog.
   - **Now durable** so it can't recur: plan.md Working Principles gained "Real-app
     compilation is a stress test, not the goal"; audit.md's re-rank principle now ranks by
     spec-correctness + clean design (argocd/Bug2-5 PARKED, never promoted).
   - The backlog was already design-first; the ranked head was tidied (DONE Bug2-3/Bug2-4
     dropped to Audit history; **D#2a now leads**).
3. **AFK mode folded into project CLAUDE.md** (from the `ace-afk` skill): an unattended
   "nightshift" envelope — no global mutation, no outward-facing actions, **commit but DON'T
   push** (overrides the attended commit/push grant), log blockers to `.afk.log` instead of
   waiting, loop until out of unblocked work / budget.

## RESOLVED (was the open question in the prior breadcrumb)

**argocd priority** — answered: **deprioritize.** Not a must-do; do not grind Bug2-5.
Rank by design-correctness. No longer an open call awaiting the user.

## IMMEDIATE NEXT STEPS (design-first; the loop can just `Keep going`)

1. **D#2a — DONE (2026-06-20).** Structural-cycle DETECTION landed. NOTE: the designed
   force-stack lever was WRONG as built (instrumentation: `#L` hits `forceClosureWithConjunct`
   once, the unroll is on the `.refId` re-eval path with FRESH frame ids each level, so no
   force-triple identity can fire). Redesigned by first principles: a `structStack : List Value`
   on the `.refId` path detects struct-body RE-ENTRANCY (the body `Value` is the stable
   identity). Detects def + regular + mutual cycles, preserves `x: x` → `_`, no false-positive
   on finite-deep or list-tail recursion; cert-manager content-identical. 8 pins + 2 `refs/`
   fixtures. See implementation-log 2026-06-20.
2. **D#2b — NOW LEADS** (terminating-disjunct, slice 2 of 2). `#List | *null` must take the
   `*null` arm once the cyclic `#List` arm bottoms. The cyclic arm ALREADY carries
   `.structuralCycle` (D#2a verified: `#List | *null` eval shows the cyclic arm `_|_`); D#2b =
   confirm `liveAlternatives`/`resolveDisjDefault?` PRUNE that bottom arm and collapse `tail` to
   `null` (oracle #2: cue `tail: null`, Kue currently keeps `{…} | *null`). ⚠ Check the A#6
   `containsBottom` fuel cap (100, `Lattice.lean`) does not hide a deep `.structuralCycle` bottom
   from `liveAlternatives`; raise/special-case if it does. ⚠ The D#2 design section's root-cause
   in `spec-conformance-audit.md` is marked SUPERSEDED — the terminating-disjunct subsection
   itself is still valid (it doesn't depend on the force-path premise).
3. Then the ranked tail in `spec-conformance-audit.md § Consolidated fix backlog`: **RX-2a**
   (`\D\W\S` in char-class) · MED tail (D#1b/c, D#3, SC-3, BI-1/2, F-3) · **SC-4** (LOW,
   spec-check first) · the 4 spec-gap ratifications · **A#6** · **DRY-1** (let-walker
   consolidation).
4. Plan-only roadmap (plan.md Live Backlog, NOT in audit.md): `truncate-primitive` (HIGH —
   soundness hardening) · Regex/EvalOps module extractions · test/fixture-org pass ·
   field-order #3 · A2-x/A2-y loader corners · B3/B5 incompleteness. NOTE: plan-side
   **A-EN3** and audit-side **DRY-1** look like the same let-walker consolidation —
   reconcile when picked.

**argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path. It resolves
as the general semantics mature; do not chase it with app-specific narrowing.

## CANONICAL PATHS (ground-truth — a prior auditor got confused; do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` and
  `.../cert-manager.cue` (cert-manager is fully correct; argocd parked).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on
  `main` when attended). **Spec is authority; `cue` is a fallible cross-check, never the
  gate.** Correctness-over-performance. **Unattended/AFK → commit, don't push** (CLAUDE.md).
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2–3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Loose end (low priority): compat-assumptions.md "Composition note (infra docker-config)"
  (~L503–510) may be stale — `_auths` hidden-field refs + `[string]:` label patterns now
  likely resolve; needs a targeted end-to-end check on `secret.cue` before trusting.
