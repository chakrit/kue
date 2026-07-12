package repro

// A regex-match bound (`=~`) requires a STRING operand. A ground list operand is a
// type error, NOT an incomplete value. cue v0.16.1 hard-errors; kue previously
// fabricated a residual `=~[1]` reported as "incomplete value" (soundness regression,
// slice a8e37e2). Spec-correct verdict: ⊥.
x: =~[1]
