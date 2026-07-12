# regex-list-operand

- **Source:** BOUND-OPERAND-CLASSIFY, from the 2026-07-12 two-phase audit
  (PA-BOUND-GROUND). Soundness regression from PATTERN-BOUND-OPERAND slice `a8e37e2`.
- **Defect:** a ground list operand classified as `.defer` (incomplete), so
  `evalRegexMatchOp` fabricated a residual `=~[1]` reported as "incomplete value"
  instead of ⊥.
- **Spec basis:** CUE grammar — `=~` requires a string operand. A resolved list is not a
  string, so `=~[1]` is a type error.
- **cue:** v0.16.1 — hard error. Note the sibling `=~5` micro-divergence: for a numeric
  operand kue already ⊥s (MORE spec-correct) while cue retains `=~5`; logged in
  `cue-divergences.md`. kue pins the terser bottom verdict here.
- **Fix:** `.list` joins the `.nonScalar` bucket; `evalRegexMatchOp` ⊥s it.
