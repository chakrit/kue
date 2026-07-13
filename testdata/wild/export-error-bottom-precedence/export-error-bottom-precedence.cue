package repro

// Export error PRECEDENCE: when sibling EXPORTED top-level fields carry DIFFERENT error
// kinds — one INCOMPLETE (an unresolved disjunction) and one a hard CONTRADICTION
// (conflicting values) — cue reports the CONTRADICTION regardless of source order. kue's
// manifest walks fields in source order and surfaces the FIRST field's error
// (`manifestFieldsWithFuel` short-circuits on the first `.error`), so with the incomplete
// field declared first kue reports "ambiguous value" and MASKS the hard bottom.
//
// `foo` (plain/EXPORTED incomplete ambiguous disjunction) precedes `y` (a hard
// contradiction). A hidden `_foo` would be skipped from output and NOT mask — the masking
// needs an exported incomplete sibling.
//
// cue v0.16.1 ⇒ `y.x: conflicting values 2 and 1`. kue ⇒ "ambiguous value: multiple
// non-default disjuncts remain" (the source-first field), masking `y`'s bottom.
//
// Spec-adjudicated verdict: a definite contradiction OUTRANKS an incomplete sibling —
// export must surface the bottom. Expectation pinned to "conflicting values (bottom)".
foo: {a: 1} | {b: 2}
y: {x: 1} & {x: 2}
