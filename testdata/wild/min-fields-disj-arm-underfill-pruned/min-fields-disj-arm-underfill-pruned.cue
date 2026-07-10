package repro

import "struct"

// A retained `struct.MinFields` residual inside a disjunction arm must be finalized when
// the disjunction resolves at manifestation. Arm `{a:1}` meets `MinFields(2)` to the
// retained residual `.conj [{a:1}, fieldCountConstraint min 2]` (the deferral is sound —
// a later conjunct could still accrete the missing field). With NO further conjunct, at
// manifest the arm is genuinely under-count → bottom → pruned, leaving the sole live arm
// `{a:1,b:2}`. Historically the retained-min arm survived liveness (it holds no present
// bottom), so both arms stayed live → a spurious "ambiguous" error.
// Spec-adjudicated to `{a:1,b:2}`; cue v0.16.1 agrees.
x: struct.MinFields(2) & ({a: 1} | {a: 1, b: 2})
