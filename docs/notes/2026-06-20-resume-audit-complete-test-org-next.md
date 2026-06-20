# RESUME HERE — two-phase audit COMPLETE; next-batch leader = TEST-ORG pass (2026-06-20)

Live START-HERE pointer; supersedes `2026-06-20-resume-plan-distilled-audit-due.md` (deleted).
Authoritative live roadmap: [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities + non-spec roadmap).

## Audit state — COMPLETE. Counter RESET to 0.

The two-phase audit ran and CLOSED, scoping the code slices **BI-2 `4c59989` + F-3 `a6dc012`**:

- **Phase A** (code-quality on BI-2 + F-3) — `3565525`. Verdict: load-bearing soundness CLEAN
  (eval-layer sort interception sound; `math.Pow` exact-domain sound); 2 LOW-risk F-3
  conformance tightenings applied inline; test strength GOOD. Escalated ONE question to Phase B.
- **Phase B** (architecture / whole module graph) — `28894ef`. Verdict: **architecture
  HEALTHY.** Layering clean + acyclic (`Builtin → {Lattice,Regex,Decimal,Base64,Json,Yaml}`, NO
  `Builtin → Eval`; the sort in `Eval` is correct BECAUSE of this). Resolved the escalated
  effectful-builtin question (BI-EFF, below). Perf-guide updated inline (Sort + Pow rows).

**Counter is 0 — the NEXT two-phase audit is due after 2–3 NEW slices** (the test-org pass below
counts as slice 1 of the next batch).

## Phase-B PRIMARY ruling — BI-EFF (effectful-builtin seam): SCOPED, TRIGGERED, not now

`list.Sort`/`SortStable` live as ONE shared inline `runSort` case in the `.builtinCall` arm of
`evalValueWithFuel` — the RIGHT layer (comparator needs `EvalM`; pure `Builtin` can't reach it),
and one logical case is below the abstraction threshold. **Do NOT abstract yet.** A full
name→`EvalM`-closure registry is REJECTED (less traceable than an exhaustive `match`; population
~3-4, not dozens). **TRIGGER:** at the SECOND effectful builtin — `list.IsSorted` (reuses
`sortWithComparator`'s `lt`) or a validator (`matchN`/`matchIf`/`list.MatchN`) — extract a named
`evalEffectfulBuiltin?` seam (mutual block) tried before the pure fallback, AS that slice's first
step. Forward-pointing seam comment already placed at the site. Filed as **BI-EFF** in
`plan.md`. (`struct.MaxFields`/`MinFields` are PURE → stay in `Builtin`.)

## Phase-B rulings to carry forward (do NOT re-litigate — confirmed intact this round)

- **Walker/normalizer dedups are FOUR distinct mechanisms**, sequenced **AD4-1 → A-EN3+DRY-1
  (locality batch) → AD2-1**, all post-argocd, gated behind correctness. AD4-1 MUST preserve+pin
  the VERIFIED-CORRECT list-arm bottom-non-propagation asymmetry (`[for x in [1] {x & "s"}]` →
  `[_|_]` ≠ `_|_` is correct CUE list semantics). AD2-1 is FILE-not-inline (flips two named
  theorem pins + the SC-3 display contract). **AD3-4** (bottom-payload newtype) RULED OUT.
- **EvalOps extraction** (plan item 2) stays the right first `Eval.lean` carve; the mutual block
  is large (3633 lines total) but cohesive — no second extraction justified beyond EvalOps yet.

## IMMEDIATE NEXT STEPS (the loop can just `Keep going`)

1. **NEXT-BATCH LEADER = the TEST-ORG pass** (plan item 3, DUE). Recommended AHEAD of BI-1 because:
   `EvalTests.lean` is now **1593 lines**, nearing the self-imposed ~1800 re-split ceiling; it is
   docs/test-only (envelope-safe), preempts nothing semantic; and BI-1 needs a data-approach
   SPIKE first anyway (so it can't start clean immediately). The slice: carve
   `ComprehensionTests`/`GuardTests` (and optionally a small `SortTests`) out of `EvalTests`;
   sub-group `testdata/cue/{definitions (100), comprehensions (54)}` into
   `comprehensions/{list,struct,let,guard}/`. Keep every `FixturePorts` entry + `testdata` pair in
   sync; build + fixtures must stay green. (`FixturePorts` 3049 lines is generated — leave whole.)
2. **Then BI-1** — Unicode case-fold for `strings.ToUpper/ToLower` (ASCII-only today → wrong on
   non-ASCII). ⚠ **DATA-APPROACH SPIKE FIRST, do NOT slice blind**: full Unicode case-mapping
   likely needs a generated case-folding TABLE = a data dependency / possible network fetch.
   Decide vendored-checked-in-table vs scoped-coverage BEFORE any code; if a builtin would require
   fetching external data into the repo, STOP and flag (envelope boundary).
3. **Then the MED / hardening tail:** **BI-2-residual** (`math.Sqrt` IEEE-754 + `NaN`/`Infinity`;
   `math.Pow` neg/fractional exponent — needs a Float/decimal-numeric design fork; Kue bottoms
   honestly today). **BI-EFF** fires only when its trigger (2nd effectful builtin) is hit.
4. **Then the ranked tail** in `spec-conformance-audit.md § Consolidated fix backlog`: **SC-3**
   display-residual, **SC-4** (spec-check FIRST), **SC-1b** (closed×closed-pattern), **A#6**
   (`containsBottom` fuel cap, STANDALONE), the 4 spec-gap ratifications. Plan-only roadmap:
   **truncate-primitive** (HIGH soundness hardening, item 1), **EvalOps** extraction (item 2),
   **field-order #3** (item 4), the B3/B5/A2-x/A2-y LOW corners.
5. **Walker-dedup family** (AD4-1 → A-EN3+DRY-1 → AD2-1) per the rulings above — post-argocd.

**argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path. Resolves as the
general semantics mature; do not chase it with app-specific narrowing.

## CANONICAL PATHS (ground-truth — a prior auditor got confused; do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` and
  `.../cert-manager.cue` (cert-manager is fully correct; argocd parked).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on
  `main` when attended). **Spec is authority; `cue` is a fallible cross-check, never the gate.**
  Correctness-over-performance. **Unattended/AFK → commit, don't push** (CLAUDE.md).
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2–3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag `cue-spec-gaps.md`;
  keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Loose end (low priority): compat-assumptions.md "Composition note (infra docker-config)"
  (~L503–510) may be stale — `_auths` hidden-field refs + `[string]:` label patterns now likely
  resolve; needs a targeted end-to-end check on `secret.cue` before trusting.
