# wide-struct-nested  (manifest — field-count fuel cliff, nested variant)

- **Source:** the nested twin of `wide-struct-export` (same 2026-07-11 audit HIGH). A struct
  nested one level (`{ outer: { r0: 0, … } }`) failed at a LOWER inner field count than the
  flat case — inner cliff at index 96, two below the flat 98. That two-field offset is the
  mechanism's fingerprint: the enclosing `outer` struct spends two extra fuel units (the
  `.struct` arm's descent + one field-list step) before the inner walk begins, so the inner
  budget starts two lower. Confirms the fuel is consumed by nesting depth AND preceding
  siblings, exactly as the per-sibling decrement predicts.
- **CUE construct at fault:** `{ outer: { r0: 0, …, r104: 104 } }` — 105 inner fields, past
  the old nested-96 cliff.
- **Direction: UNDER-ACCEPT.**
- **Root cause (kue):** same as `wide-struct-export` — per-sibling fuel decrement in
  `manifestFieldsWithFuel` (`Kue/Manifest.lean`), fixed by threading fuel undecremented across
  siblings.
- **Spec basis:** byte-identical to `cue export --out json` v0.16.1.
