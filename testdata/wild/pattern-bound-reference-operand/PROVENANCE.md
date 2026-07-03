# pattern-bound-reference-operand

- **Source:** EVAL-CORE conformance probe (comprehensions + struct embedding/patterns),
  2026-07-04. Surfaced probing pattern constraints with a computed/reference key
  (`{[=~k]: int}`, `{[>k]: int}`).
- **Defect:** kue's parser accepts only LITERAL operands for bound/relational operators.
  `parseBoundValue` (Kue/Parse.lean) requires a numeric literal for `>`/`>=`/`<`/`<=`; the
  `=~`/`!~` arms call `parseQuotedString`, requiring a string literal; `!=` requires a
  `.prim`. A reference or any expression operand (`>k`, `=~_re`, `<len(x)`) fails to parse.
- **Spec basis:** CUE grammar — `UnaryExpr = PrimaryExpr | unary_op UnaryExpr`,
  `unary_op = "+" | "-" | "!" | "*" | rel_op`, `rel_op = "=~" | "!~" | "<" | "<=" | ">" |
  ">=" | "!="`. The operand of a relational/bound operator is an arbitrary `UnaryExpr`,
  not restricted to a literal. cue v0.16.1 accepts `=~_re`, `>k`, etc.
- **Impact:** correctness/completeness (not soundness) — kue REJECTS valid CUE that cue
  accepts. Manifests both bare (`x: >k`) and in pattern constraints (`{[=~_re]: int}`).
- **cue:** v0.16.1 — `{"out":{"abc":1,"xyz":9}}`.
- **Fix (deferred, soundness-core / broad):** the bound Value representation must carry an
  unresolved operand expression; the parser must parse a general `UnaryExpr` operand for
  every rel_op; the evaluator must evaluate the operand (deferring on incomplete) before
  applying the relation. Bounds are pervasive, so this is a parser+evaluator change
  red-seeded under AFK rather than forced. Filed in docs/spec/plan.md. Quarantined
  `.known-red` until fixed.
