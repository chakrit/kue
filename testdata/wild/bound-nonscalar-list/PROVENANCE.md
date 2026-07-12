# bound-nonscalar-list

- **Source:** BOUND-OPERAND-CLASSIFY, from the 2026-07-12 two-phase audit
  (PA-BOUND-GROUND). A soundness regression introduced by the PATTERN-BOUND-OPERAND
  slice `a8e37e2`.
- **Defect:** `classifyScalarOperand` mapped a ground list/struct operand to the same
  `.defer` class as a genuinely-incomplete operand, so `evalBoundOp` FABRICATED a
  residual `<[1, 2]` and `kue export` reported "incomplete value" instead of the type
  error. A ground list can never refine into an ordered scalar; treating it as
  incomplete is unsound.
- **Spec basis:** CUE grammar — `rel_op UnaryExpr`; a comparator bound (`< <= > >=`)
  applies only to an ordered type (number, string, bytes). A resolved list is not an
  ordered scalar, so `<[1, 2]` is a type error (⊥), not an incomplete value.
- **cue:** v0.16.1 — hard error: `cannot use [1,2] (value of type list) as number in
  argument to <`. kue renders the terser `_|_` verdict ("conflicting values
  (bottom)"); the bottom verdict is what is pinned, not cue's exact text.
- **Fix:** split `ScalarOperandClass.defer` into `.incomplete` (retain) and
  `.nonScalar` (list/listTail/embeddedList/struct → ⊥ in bound/regex/unary-arith).
