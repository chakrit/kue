# uniqueitems-abstract-incomplete  (list.UniqueItems × abstract elements, standalone)

- **Source:** reproduced 2026-07-11 from the Phase-A audit of STDLIB-VALIDATORS (`5d9b65c`);
  HIGH-2 soundness finding (standalone form).
- **CUE construct at fault:** `[int,int] & list.UniqueItems` (no concretization).
- **Direction: SOUNDNESS / SILENTLY-WRONG (fabricated bottom).** kue eager-bottomed on `int==int`;
  spec-correct is INCOMPLETE (the abstract ints are unmeasured, so uniqueness is undecided).
- **Root cause / fix (kue):** same as `uniqueitems-abstract-elements` — `hasGroundDup` ground guard.
- **Spec basis + `cue` divergence:** two abstract elements cannot be adjudicated as a duplicate; the
  value is incomplete. `cue` v0.16.1 is INTERNALLY INCONSISTENT here: `cue eval` retains it
  (`list.UniqueItems & [int, int]`, correct) but `cue export` fabricates a bottom
  (`does not satisfy list.UniqueItems: equal values at position 0 and 1`) — the same unsound eager
  check this fix removes. kue follows the spec (incomplete) and the `cue export` bug is recorded in
  `cue-divergences.md`. The pinned `.expected.err` (`incomplete value`) is the spec-adjudicated
  verdict.
