package repro

// As the -bound sibling, but the non-struct disjunction arm is a `!=` negation
// (`#X: {a:1} & ({z:9} | !=5)`). The `!=5` arm is number-kinded and dies against
// the def's own `{a:1}` struct literal (struct vs number ⇒ bottom), contributing
// an empty combination; the `{z:9}` arm closes to `{a,z}`. A use-site
// `#X & {z:9,w:7}` adds an undeclared `w` → both arms bottom → bottom.
// cue v0.16.1 ⇒ `y.w: field not allowed`. Spec-adjudicated verdict: bottom.
#X: {a: 1} & ({z: 9} | !=5)
y: #X & {z: 9, w: 7}
