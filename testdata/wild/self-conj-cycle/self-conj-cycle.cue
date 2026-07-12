package repro

// A field declared multiply, where ONE declaration self-references inside a
// conjunction (`x: x & int` alongside `x: 1`), must resolve the self-reference
// as top (`_`) per CUE's reference-cycle rule: `x & int` becomes `_ & int` =
// `int`, unified with the sibling `1` = `1`. cue v0.16.1 yields `{x: 1}`.
// kue FABRICATES `_|_` (conflicting values) — a wrong-value bug: the self-ref
// inside the multi-conjunct field is not being collapsed to top the way the
// single-declaration form (`x: x & int` alone ⇒ `int`) already is.
// Spec-adjudicated value: {"x": 1}.
x: 1
x: x & int
