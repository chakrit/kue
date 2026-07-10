# min-fields-disj-arm-underfill-pruned  (field-count validators × disjunction)

- **Source:** reproduced 2026-07-10 from the Phase-A code-quality audit (finding: a
  retained `struct.MinFields` residual inside a disjunction arm was never finalized when
  the disjunction collapsed; audit finding #2 flagged the paired test-strength gap — NO
  existing test exercised `fieldCountConstraint × disjunction`).
- **CUE construct at fault:** a field-count validator met with a disjunction whose arms
  differ in field count — `struct.MinFields(2) & ({a:1} | {a:1,b:2})`.
- **Direction: SOUNDNESS / OVER-REPORT** — kue reported "ambiguous value: multiple
  non-default disjuncts remain" where cue/spec resolve to the single satisfiable arm. The
  under-count arm `{a:1}` (1 field < min 2) should manifest bottom on its own and be
  pruned; instead it stayed live and shadowed the sole valid arm.
- **Root cause (kue):** `applyFieldCountConstraint` (`Kue/Lattice.lean`) soundly RETAINS an
  unsatisfied `min` as `.conj [struct, fieldCountConstraint …]` — the deferral is required
  for cross-conjunct accretion (`{a:1} & MinFields(2) & {b:2}` ⇒ ok). But the disjunction
  resolution path (`liveAlternatives` via `resolveDisjDefault?`) prunes only arms that hold
  a PRESENT `.bottom` (`containsBottom`); a retained-min conj holds none, so the violated
  arm survived. `manifest` finalized a TOP-LEVEL retained conj (`finalizeFieldCountConj`)
  but not one nested inside a disjunction arm.
- **Fix:** `manifestWithFuel`'s `.disj` arm maps each alternative through `finalizeDisjArm`
  (`Kue/Manifest.lean`), which runs `finalizeFieldCountConj` on conj arms — a violated bound
  collapses the arm to `.bottomWith`, which `liveAlternatives` then prunes. Manifest-only:
  meet-time `normalizeDisj` is untouched, so accretion (a later conjunct rescuing an
  under-count arm) still works.
- **Spec basis:** unification distributes over disjunction, so `MinFields(2)` applies per
  arm; an arm whose struct is final and under the min is bottom; a disjunction reduces to
  its live arms. `cue` v0.16.1 → `{"x":{"a":1,"b":2}}` and is correct (NOT a cue bug). The
  pinned `.expected` is that spec-adjudicated JSON.
