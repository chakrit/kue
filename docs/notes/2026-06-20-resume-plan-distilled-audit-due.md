# RESUME HERE — plan distilled (hygiene pass); TWO-PHASE AUDIT DUE next (Phase A → Phase B on BI-2 + F-3) (2026-06-20)

Live START-HERE pointer; supersedes all prior breadcrumbs. Authoritative live roadmap:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (owns the ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities + non-spec roadmap, just distilled).

**Latest (2026-06-20):** plan-hygiene pass landed. `plan.md` distilled 721 → ~280 lines — shed
the entire "Audit & design history" archive (pure pointers duplicating the implementation-log),
the completed fix-slice diagnoses (D#2a/b, RX-2a, D#1b/c, D#3, BI-2, F-3, AD2-2-done), and the
verbose embedded prose; kept North Star + Working Principles (spec-is-authority,
correctness-over-perf, real-app-is-a-stress-test), standing capabilities, and every OPEN backlog
item terse. Deleted the confirmed-stale AD3-1 / item-3 Regex-extraction / B5-regex-bullet text
(`Kue/Regex.lean` is a verified true leaf). `docs/www/index.html` refreshed (was stale at
2026-06-19): RX-1/D#2/Gap-2b/SC-2/F-2/F-3/D#3/BI-2 all moved to "Landed", argocd reframed
Gap-2b→Bug2-5-parked, fix-backlog cards rewritten to the current open set, footer redated.
Docs-only — build (100 jobs) / fixtures (`fixture pairs ok`) / shellcheck all green, untouched.

**Audit state — AUDIT DUE.** BI-2 (slice 1) + F-3 (slice 2) + this plan-hygiene pass (slice 3)
since the last two-phase audit (Phase A `7ee15d8` + Phase B `457a165`). **The two-phase audit is
now DUE — run it NEXT, before any new feature slice.** It scopes the CODE slices **BI-2 + F-3**
(this docs-only hygiene pass itself is NOT audited). Run sequentially: **Phase A (code-quality on
BI-2 + F-3) → Phase B (architecture / whole module graph)**. Both edit `plan.md`/the audit doc —
parallel collides; run A then B. Follow [`../guides/slice-loop.md`](../guides/slice-loop.md); do
NOT invoke `/ace-audit`.

**Phase-B rulings to carry forward (do not re-litigate):** the walker/normalizer dedups are FOUR
distinct mechanisms, NOT one — **AD4-1** (`EvalM` comprehension clause-drivers → one
`expandClauseChain` over a generic `ClauseOutcome β`), **A-EN3** (pure structural `Value` folds →
`foldValueWithDepth`), **DRY-1** (let-slot fixpoint walkers → `walkFollowedLets`), **AD2-1** (the
two disjunction normalizers, lattice/eval layer boundary). Sequence **AD4-1 → A-EN3+DRY-1
(locality batch) → AD2-1**, all post-argocd, gated behind correctness. AD4-1 MUST preserve+pin the
VERIFIED-CORRECT list-arm bottom-non-propagation asymmetry (`[for x in [1] {x & "s"}]` → `[_|_]` ≠
`_|_` is correct CUE list semantics). AD2-1 is FILE-not-inline (flips two named theorem pins + the
SC-3 display contract). The bottom-payload newtype (**AD3-4**) is RULED OUT (over-engineering).

## IMMEDIATE NEXT STEPS (the loop can just `Keep going`)

1. **Run the two-phase audit NOW** (it is DUE — BI-2=slice1, F-3=slice2, hygiene=slice3). Phase A
   on the BI-2 + F-3 diff (the code batch), then Phase B on the whole module graph. Fold findings
   into `plan.md`/the audit doc as fix-slices; apply only LOW-RISK fixes inline (re-verify +
   commit). Counter resets after Phase B lands.
2. **Then the next-batch leader = the remaining MED / hardening tail**, in order:
   - **BI-1** — Unicode case-fold for `strings.ToUpper/ToLower` (ASCII-only today → wrong on
     non-ASCII). ⚠ **DATA-APPROACH SPIKE FIRST, do NOT slice blind**: full Unicode case-mapping
     likely needs a generated case-folding TABLE = a data dependency / possible network fetch.
     Decide vendored-checked-in-table vs scoped-coverage BEFORE any code; if a builtin would
     require fetching external data into the repo, STOP and flag (envelope boundary).
   - **BI-2-residual** — `math.Sqrt` (IEEE-754 float64 + `NaN`/`Infinity` + Go sci-notation
     formatting Kue lacks) and `math.Pow` neg/fractional exponent + `Pow(0,neg)=Infinity` (apd
     34-sig-digit decimal Pow + Infinity model). Needs a Float/decimal-numeric-methods design
     fork. Kue bottoms today (honest "not computed", never wrong). Lower priority; no app needs it.
   - **Test/fixture-org pass** — DUE (plan item #3): `EvalTests.lean` re-grew to ~1505 lines →
     carve `ComprehensionTests`/`GuardTests`; sub-group `testdata/cue/{definitions,comprehensions}`.
     Run within 1-2 cycles, before `EvalTests` crosses ~1800; does NOT preempt the feature tail.
   - **The walker-dedup family** (AD4-1 → A-EN3+DRY-1 → AD2-1) per the rulings above — post-argocd.
3. **Then the ranked tail** in `spec-conformance-audit.md § Consolidated fix backlog`: **SC-3**
   display-residual (LOW/spec-gap), **SC-4** (spec-check FIRST — cue is internally inconsistent),
   **SC-1b** (closed×closed-pattern), **A#6** (`containsBottom` fuel cap, STANDALONE — D#2 confirmed
   NOT implicated by structural cycles), the 4 spec-gap ratifications. Plan-only roadmap:
   **truncate-primitive** (HIGH soundness hardening), **EvalOps** extraction, **field-order #3**,
   the B3/B5/A2-x/A2-y LOW corners.

**argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path. Resolves as the
general semantics mature; do not chase it with app-specific narrowing.

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
