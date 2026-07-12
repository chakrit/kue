# binary-cmp-struct-operand

- **Source:** BINARY-CMP-OPERAND, from the 2026-07-12 two-phase audit — sibling of
  BOUND-OPERAND-CLASSIFY. Exercises the non-scalar operand on the LEFT / a struct
  (the list twin covers the right side / a list).
- **Defect:** identical to binary-cmp-list-operand — `evalPrimitiveOrdering`'s
  catch-all retained `{a: 1} > 3` as an incomplete residual instead of ⊥.
- **Spec basis:** ordered comparison requires ordered-scalar operands; a resolved
  struct is a type error, not incomplete.
- **cue:** v0.16.1 — `invalid operands {a:1} and 3 to '>' (type struct and int)`.
  kue pins the `_|_` verdict.
- **Fix:** see binary-cmp-list-operand — `.nonScalar` operand ⇒ ⊥ in
  `evalPrimitiveOrdering`.
