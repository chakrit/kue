// An incomplete operand keeps arithmetic deferred (a residual), never a premature type
// error — even when the OTHER operand is a concrete list. The operation may still become
// valid once the incomplete side resolves to a number; deciding it as bottom now would be
// unsound (cue holds `[1] + x` while `x: int`, erroring only after `x` concretizes).
abstract: int
listDefer: abstract + [1]
numDefer: abstract * 2

// Once the abstract operand resolves to a concrete number, the arithmetic computes.
resolved: int
resolved: 5
sum:      resolved + 3
