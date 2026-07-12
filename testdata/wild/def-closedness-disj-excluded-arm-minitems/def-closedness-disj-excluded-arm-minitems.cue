package repro

import "list"

// As the -bound sibling, but the non-struct disjunction arm is a list-length
// validator (`#X: {a:1} & ({z:9} | list.MinItems(2))`). The `list.MinItems(2)` arm
// is a `.lengthConstraint` of kind `.items` — it dies against the def's own `{a:1}`
// struct literal (struct vs list ⇒ bottom), contributing an empty combination; the
// `{z:9}` arm closes to `{a,z}`. A use-site `#X & {z:9,w:7}` adds an undeclared `w`
// → both arms bottom → bottom.
// cue v0.16.1 ⇒ `y.w: field not allowed`. Spec-adjudicated verdict: bottom.
#X: {a: 1} & ({z: 9} | list.MinItems(2))
y: #X & {z: 9, w: 7}
