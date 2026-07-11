# uniqueitems-abstract-elements  (list.UniqueItems × abstract-then-concrete elements)

- **Source:** reproduced 2026-07-11 from the Phase-A audit of STDLIB-VALIDATORS (`5d9b65c`);
  HIGH-2 soundness finding.
- **CUE construct at fault:** `[int,int] & list.UniqueItems` later narrowed by `[1,2]`.
- **Direction: SOUNDNESS / SILENTLY-WRONG (fabricated bottom).** kue's `hasStructuralDup` saw
  `int == int` and eager-bottomed at meet, killing an arm that concretizes to the perfectly-unique
  `[1,2]`. Spec-correct: two abstract elements are not a duplicate; retain and re-check on
  concretization.
- **Root cause (kue):** `hasStructuralDup` fired on any `eqUpToFieldOrder` pair, including abstract
  ones — conflating "structurally equal now" with "definitely a duplicate".
- **Fix:** `hasGroundDup` requires both elements GROUND (`Value.isGround`) before bottoming;
  abstract coincidences retain (`Kue/Lattice.lean`, `Kue/Value.lean`). Applied at both the meet
  callsite (`applyUniqueItems`) and the manifest callsite (`finalizeLengthConj`).
- **Spec basis:** `[int,int] & [1,2]` = `[1,2]`, which satisfies UniqueItems; the constraint is
  incomplete until the elements are ground. `cue` v0.16.1 → `{"x":[1,2]}` (correct). The pinned
  `.expected` is that JSON.
