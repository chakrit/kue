package repro

// A comparator bound (`<`, `<=`, `>`, `>=`) requires an ORDERED SCALAR operand
// (number, string, or bytes). A ground list operand is a type error, NOT an
// incomplete value: there is no future refinement that turns `[1, 2]` into an
// ordered scalar. cue v0.16.1 hard-errors ("cannot use [1,2] (type list) as
// number in bound"); kue previously FABRICATED a residual `<[1, 2]` and reported
// it as "incomplete value", masking the type error (soundness regression from the
// PATTERN-BOUND-OPERAND slice a8e37e2). Spec-correct verdict: ⊥.
x: <[1, 2]
