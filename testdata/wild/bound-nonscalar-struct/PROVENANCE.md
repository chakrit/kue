# bound-nonscalar-struct

- **Source:** BOUND-OPERAND-CLASSIFY, from the 2026-07-12 two-phase audit
  (PA-BOUND-GROUND). Soundness regression from PATTERN-BOUND-OPERAND slice `a8e37e2`.
- **Defect:** a ground struct operand classified as `.defer` (incomplete) rather than a
  type error, so `evalBoundOp` fabricated a residual `<{a: 1}` reported as "incomplete
  value" instead of ⊥.
- **Spec basis:** CUE grammar — `rel_op UnaryExpr`; a comparator bound applies only to
  an ordered scalar. A resolved struct is not ordered, so `<{a: 1}` is a type error.
- **cue:** v0.16.1 — hard error (`cannot use {a:1} (value of type struct) as number in
  argument to <`). kue pins the terser bottom verdict.
- **Fix:** `.struct` joins the `.nonScalar` bucket; `evalBoundOp` ⊥s it.
