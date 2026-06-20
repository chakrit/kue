# RESUME HERE — D#2 COMPLETE; RX-2a leads (2026-06-20)

Newest START-HERE; supersedes all prior breadcrumbs as the live pointer. Authoritative live
roadmap: [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (owns the ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities + non-spec roadmap).

**Latest (2026-06-20):** D#2b landed → **D#2 (structural cycles) COMPLETE** (detection +
terminating-disjunct). `#List | *null` → `tail: null` (cue-byte-identical). The fix was a single
`normalizeEvaluatedDisj` change (apply `liveAlternatives` on the has-default branch); the A#6 fuel
cap was NOT implicated. SC-3's dedup half folded in. **RX-2a now leads** — see IMMEDIATE NEXT STEPS.
⚠ **Audit-due check:** D#2a + D#2b are 2 landed slices since the last two-phase audit — a
Phase-A/Phase-B audit is DUE before or right after the next slice (per `slice-loop.md` cadence).

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

1. **D#2 — COMPLETE (2026-06-20).** Both halves landed: D#2a (structural-cycle DETECTION,
   struct-body re-entrancy `structStack` on the `.refId` path) + D#2b (terminating-disjunct).
   D#2b re-diagnosis vs the plan: VALUE resolution was ALREADY correct after D#2a (`export` →
   `tail: null` via the existing `resolveDisjDefault?`); the A#6 fuel cap was NEVER implicated
   (detection at depth ~2 ⇒ shallow bottom — A#6 stays standalone). The gap was the EVAL value
   path (`normalizeEvaluatedDisj` emitting defaulted disjunctions RAW, the SC-3 root). Fix:
   apply `liveAlternatives` (prune-bottom/dedup) on its has-default branch, WITHOUT collapsing
   the default into the value (collapse is unsound — `b: a & 2` needs the live non-default arm;
   cue's display-collapse is a projection, not a value rewrite). Folds in **SC-3's dedup**
   (`*1|*1|2` → `*1 | 2`); SC-3's residual is only cue's display-collapse, which Kue
   deliberately rejects (recorded spec-gap). 8 pins + 3 `export/` fixtures; cert-manager
   content-identical. See implementation-log 2026-06-20.
2. **RX-2a — NOW LEADS** (MED — `\D`/`\W`/`\S` INSIDE a `[…]` char class, the lone regex-corpus
   divergence). Needs class-level set-complement folding in `parseClassEscape` (`Kue/Regex.lean`)
   — the current `.error` arms become real folds (fold the negated perl ranges into the class, or
   carry per-class negation of a sub-set). RE2 feature; current behavior is an honest stub, not
   silent-wrong. Serialize with any other regex-module edit to avoid worktree contention.
3. Then the ranked tail in `spec-conformance-audit.md § Consolidated fix backlog`: MED tail
   (D#1b/c, D#3, SC-3 display-residual, BI-1/2, F-3) · **SC-4** (LOW, spec-check first) · the 4
   spec-gap ratifications · **A#6** (standalone, NOT folded into D#2 — confirmed) · **DRY-1**
   (let-walker consolidation).
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
