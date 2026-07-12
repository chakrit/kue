package repro

// A DIRECT `error(...)` disjunction arm in a closed definition
// (`#X: {a:1} & ({z:9} | error("x"))`). Met with the def's own `{a:1}` struct literal, the
// `error("x")` arm force-folds to bottom (the error dominates the meet, its message preserved),
// so it carries no allowed field; the `{z:9}` arm closes to `{a,z}`. The def is thus
// `{a,z}(closed) | error("x")`. A use-site `#X & {w:7}` adds an undeclared `w`: the `{a,z}` arm
// rejects it and the sole survivor is the `error("x")` arm, so the error surfaces.
// cue v0.16.1 ⇒ bottom with message `x` (force-folds the error). Spec-adjudicated verdict: bottom.
#X: {a: 1} & ({z: 9} | error("x"))
y: #X & {w: 7}
