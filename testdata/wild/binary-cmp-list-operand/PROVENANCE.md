# binary-cmp-list-operand

- **Source:** BINARY-CMP-OPERAND, from the 2026-07-12 two-phase audit — the flagged
  sibling of BOUND-OPERAND-CLASSIFY (same soundness class, different code path:
  `evalPrimitiveOrdering` rather than `evalBoundOp`).
- **Defect:** `evalPrimitiveOrdering`'s catch-all (`| _, _ => .binary op left right`)
  RETAINED any operand pair that was not two comparable prims — including a ground
  list/struct operand that can never refine into an ordered scalar. `1 < [1, 2]`
  fabricated the residual `1 < [1, 2]` and reported it as an incomplete value,
  masking the type error (a soundness gap: an ill-typed operation accepted as
  incomplete instead of ⊥).
- **Spec basis:** CUE ordered comparison (`< <= > >=`) is defined only over operands
  of the same ordered type (number, string, bytes). A resolved list is not an ordered
  scalar, so `1 < [1, 2]` is a type error (⊥), not an incomplete value.
- **cue:** v0.16.1 — hard error: `invalid operands 1 and [1,2] to '<' (type int and
  list)`. kue renders the terser `_|_` verdict ("conflicting values (bottom)"); the
  bottom verdict is pinned, not cue's exact text.
- **Fix:** `evalPrimitiveOrdering` splits its catch-all — `.incomplete` on either side
  RETAINS (may refine to a scalar), `.nonScalar` on either side (with a non-incomplete
  other operand) ⇒ ⊥.
