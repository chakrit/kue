package repro

// A pattern-constraint bound whose operand is a REFERENCE (not a literal):
// `[=~_re]` matches field names against the regex bound to `_re`. CUE's grammar
// allows any UnaryExpr as a bound operand (`rel_op UnaryExpr`), so `=~_re`,
// `>k`, `<len(x)` are all legal. kue's parser accepts ONLY literal operands
// (`parseBoundValue` wants a numeric literal; the `=~` arm wants a quoted
// string), so `=~_re` fails to parse: "expected string literal".
//
// Spec-correct behavior: `abc` matches `^a` and is thus constrained to `int`
// (satisfied by `1`); `xyz` does not match the pattern and stays unconstrained.
//
//   kue: parse error: expected string literal
//   cue: {"out":{"abc":1,"xyz":9}}   (v0.16.1)
_re: "^a"
out: {[=~_re]: int, abc: 1, xyz: 9}
