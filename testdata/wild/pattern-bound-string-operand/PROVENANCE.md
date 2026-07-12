# pattern-bound-string-operand

- **Source:** CORE-CONFORMANCE-PROBE (pattern constraints), 2026-07-12. Surfaced
  probing comparator-bound pattern labels with a non-numeric operand
  (`{[>"m"]: int}`, `x: <"m"`, `x: >='a'`).
- **Defect:** kue's parser accepts ONLY numeric literals after a comparator.
  `parseBoundValue` (`Kue/Parse.lean`) calls `parseNumberToken`, so a STRING or
  BYTES literal operand (`>"m"`, `<'m'`, `>="a"`) fails to parse: "expected number
  digits". Bare bounds (`x: <"m"`) and pattern-label bounds (`{[>"m"]: int}`) both
  fail.
- **Relationship:** SAME root cause as `pattern-bound-reference-operand` — the bound
  `Value` representation (`boundConstraint (bound : DecimalValue) …`) is numeric-only,
  so no comparator operand outside `DecimalValue` is representable. This is a DISTINCT
  facet: the operand here is a LITERAL string/bytes (fully known at parse time, no
  deferral), whereas the sibling fixture covers REFERENCE/expression operands.
- **Spec basis:** CUE grammar — `unary_op = … | rel_op`, `rel_op = "=~" | "!~" | "<" |
  "<=" | ">" | ">=" | "!="`, operand an arbitrary `UnaryExpr`. Bounds apply to any
  ORDERED type: numbers, strings (lexical, by code point), bytes. cue v0.16.1 accepts
  `>"m"` and applies it as a lexical bound.
- **Impact:** correctness/completeness (not soundness) — kue REJECTS valid CUE that
  cue accepts.
- **cue:** v0.16.1 — `{"out":{"apple":"keep","zebra":1}}`.
- **Fix (deferred, shares PATTERN-BOUND-REF-OPERAND's core change):** the bound `Value`
  repr must carry a non-numeric ordered operand (generalize `DecimalValue` to a `Prim`
  or an operand expression); meet/order/manifest must compare strings lexically and
  bytes by byte order; the parser must accept a general operand for every rel_op.
  Filed in `docs/spec/plan.md` under PATTERN-BOUND-REF-OPERAND. Quarantined `.known-red`.
