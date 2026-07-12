package repro

// As the -bound sibling, but the non-struct disjunction arm is a LIST carrier
// (`#X: {a:1} & ({z:9} | [1,2])`). The `[1,2]` arm dies against the def's own
// `{a:1}` struct literal (struct vs list ⇒ bottom), contributing an empty
// combination; the `{z:9}` arm closes to `{a,z}`. A use-site `#X & {w:7}` adds
// an undeclared `w` → both arms bottom → the disjunction is empty → bottom.
// cue v0.16.1 ⇒ `y.w: field not allowed`. Spec-adjudicated verdict: bottom.
#X: {a: 1} & ({z: 9} | [1, 2])
y: #X & {w: 7}
