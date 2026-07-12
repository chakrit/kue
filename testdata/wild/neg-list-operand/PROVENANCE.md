# neg-list-operand

- **Source:** BOUND-OPERAND-CLASSIFY, from the 2026-07-12 two-phase audit
  (PA-BOUND-GROUND). The pre-existing unary-arith twin of the bound soundness
  regression (slice `a8e37e2`).
- **Defect:** a ground list operand classified as `.defer` (incomplete), so `evalNumNeg`
  fabricated a residual `-[1, 2]` reported as "incomplete value" instead of ⊥.
- **Spec basis:** CUE grammar — unary `-` (and `+`) require a numeric operand. A resolved
  list is not numeric, so `-[1, 2]` is a type error.
- **cue:** v0.16.1 — hard error (`invalid operation -[1,2] (- list)`). kue pins the terser
  bottom verdict.
- **Fix:** `.list` joins the `.nonScalar` bucket; `evalNumNeg`/`evalNumPos` ⊥ it.
