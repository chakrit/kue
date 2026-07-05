# Breadcrumb: 2026-07-05 — AUDIT-STRUCT-EQ half-2 landed (order-independent dedup)

Supersedes `2026-07-04-audit-struct-eq-half1-landed.md` as the live front for STRUCT-EQ.

## What landed

**AUDIT-STRUCT-EQ half-2 (the deferred/attended half) — DONE. AUDIT-STRUCT-EQ fully CLOSED.**
`Kue/Lattice.lean` makes `dedupAlternatives` order-independent w.r.t. struct field order, so
`{a:1,b:2} | {b:2,a:1}` collapses to one arm (was `ambiguous value: multiple non-default
disjuncts remain`; cue collapses).

- **Canonical normal form, not ad-hoc compare** (philosophy: illegal-states-unrepresentable —
  order-independence BY CONSTRUCTION): `normalizeFieldOrder : Value → Value` sorts every
  struct-bearing constructor's member list by label (`sortFieldsByLabel`, stable mergeSort) with
  sub-values normalized recursively; LIST element order PRESERVED. `termination_by structural`,
  total. `eqUpToFieldOrder l r := normalizeFieldOrder l == normalizeFieldOrder r`.
- `dedupAlternatives` tests arms with `eqUpToFieldOrder` (NOT the global `BEq`) and keeps the
  INCOMING (earlier-in-list) arm's value → surviving arm displays FIRST-declared order,
  byte-for-byte with cue.
- **Global `Value` `BEq` UNTOUCHED** — cycle detection (`Eval.lean` `structStack.contains`) still
  relies on exact/order-sensitive equality; the coarser equality is confined to the dedup path
  (the Phase B architectural verdict's sanctioned route). No cycle-detection regression.

17 `native_decide` theorems (`LatticeTests` `structeq_*`): collapse cases (2-arm, three-field
perm, nested-inner, struct-in-list, empty, default-mark composition) + confinement
(`eqUpToFieldOrder` true while exact `==` false) + over-collapse guards (differing
value/label-set/openness/field-class, and LIST order stays significant). `structeq_disj_reorder`
export fixture (reordered/three-way/nested), kue == cue v0.16.1. RED reproduced first (positive
theorems failed under the pre-fix predicate), fix turns green. `./scripts/check.sh` GREEN;
cert-manager canary in-gate GREEN. Reordered-dedup divergence REMOVED from `cue-divergences.md`
(kue now agrees with cue and spec). Committed on `main`, NOT pushed.

## Next step (pick by rank)

1. **B3d-6b (NETWORK-GATED)** — `cue mod get/tidy` + requirement-graph fetch + `cue.sum` WRITE.
   Network-gated; skip if AFK/offline.
2. **ARCH-QUOTED-STRIP (MEDIUM)** — parse-only quoting; drop `Field.quoted` from the eval layer,
   delete the `stripFieldQuoting` walk (plan 0c).
3. **B2-A1** — thread `tail` through the patterns-present meet (lands with typed-ellipsis).
4. **PRIM-FLOAT-PARSED (LOW-MEDIUM)** — refine `Prim.float` to carry a `DecimalValue` alongside
   source text (plan 0e); couple with GDA-FLOAT-RENDER.
5. **GATE-KNOWNRED-DRY (LOW)** — share a `.known-red` decision helper across the two fixture gates.

Two-phase audit: STRUCT-EQ half-2 is the ~3rd slice since the last full audit (2026-07-04
Phase B) — a two-phase audit (code-quality then architecture) is due within ~1 slice.
