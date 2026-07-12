# let-cycle-through-field-top

- **Source:** LET-CYCLE-ERROR (2026-07-12).
- **Guard:** A cycle touching a FIELD (`let a = x; x: a`) truncates to top, NOT a let
  load error. cue v0.16.1 ⇒ `x: incomplete value _`; kue matches (`incomplete value: _`).
- **Spec basis:** the pure-`let` cycle error fires only when the WHOLE cycle sits on
  `letBinding` slots; a field on the cycle keeps the field-self-reference top rule.
