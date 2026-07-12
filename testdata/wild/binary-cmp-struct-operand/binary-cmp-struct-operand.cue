package repro

// Ordered comparison with a ground STRUCT operand (either side) is a type error.
// A struct can never refine into an ordered scalar, so `{a: 1} > 3` is ⊥, not an
// incomplete residual. cue v0.16.1: "invalid operands {a:1} and 3 to '>' (type
// struct and int)". kue previously retained `{a: 1} > 3` via the
// `evalPrimitiveOrdering` catch-all. Spec-correct verdict: ⊥.
x: {a: 1} > 3
