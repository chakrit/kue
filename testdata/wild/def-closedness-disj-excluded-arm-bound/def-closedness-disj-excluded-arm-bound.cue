package repro

// A CLOSED definition whose body unions its own struct literal THROUGH a
// disjunction carrying a BOUND arm (`#X: {a:1} & ({z:9} | >5)`). The `>5` arm
// dies against the def's own `{a:1}` struct literal (struct vs number ⇒ bottom)
// EXACTLY like a scalar arm, so it contributes an empty combination; the
// surviving `{z:9}` arm closes to the fixed field set `{a,z}`. A use-site
// `#X & {w:7}` adds an undeclared `w`, which the closed struct arm rejects and
// the bound arm has already dropped → the disjunction is empty → bottom.
// cue v0.16.1 ⇒ `y.w: field not allowed`. Spec-adjudicated verdict: bottom.
#X: {a: 1} & ({z: 9} | >5)
y: #X & {w: 7}
