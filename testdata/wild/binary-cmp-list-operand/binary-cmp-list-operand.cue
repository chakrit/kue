package repro

// An ordered comparison (`<`, `<=`, `>`, `>=`) requires BOTH operands to be
// ordered scalars (number, string, bytes). A ground list operand is a type error,
// NOT an incomplete value: `[1, 2]` can never refine into an ordered scalar. cue
// v0.16.1 hard-errors ("invalid operands 1 and [1,2] to '<' (type int and list)");
// kue previously FABRICATED a residual `1 < [1, 2]` (the `evalPrimitiveOrdering`
// catch-all retained instead of rejecting the non-scalar), masking the type error.
// Spec-correct verdict: ⊥.
x: 1 < [1, 2]
