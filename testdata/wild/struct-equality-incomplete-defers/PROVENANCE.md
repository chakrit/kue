# struct-equality-incomplete-defers

**Source:** captured 2026-07-04 alongside AUDIT-STRUCT-EQ half-1 (concrete struct/list `==`) as
the over-eager guard that fix must not trip.

**Adjudication (spec-correct):** CUE holds `==` INCOMPLETE unless BOTH operands are fully
concrete. Here `b: _x` with `_x: int` is abstract, so `({a:1, b:_x}) == ({a:2, b:_x})` stays
incomplete — even though `a` already differs (`1` vs `2`). An incomplete operand defers the whole
comparison; it does NOT short-circuit to `false`. cue v0.16.1: `invalid left-hand value to '=='
(type struct): b: incomplete value int`.

**Guard:** the concrete-equality fast path (`structEqConcrete?` in `Kue/EvalOps.lean`) must run a
FULL-concreteness check on both operands FIRST and DEFER (`.binary .eq` residual, exported as
`incomplete value`) when either is non-concrete — never fold an abstract `==` to a bool. This
fixture stays RED-if-regressed: if the guard ever turns eager, kue would export `false` and the
`.expected.err` (`incomplete value`) match fails.
