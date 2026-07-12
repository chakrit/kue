package repro

import "list"

// As the -bound sibling, but the non-struct disjunction arm is a list-uniqueness
// validator (`#X: {a:1} & ({z:9} | list.UniqueItems)`). The `list.UniqueItems` arm
// dies against the def's own `{a:1}` struct literal (struct vs list ⇒ bottom),
// contributing an empty combination; the `{z:9}` arm closes to `{a,z}`. A use-site
// `#X & {z:9,w:7}` adds an undeclared `w` → both arms bottom → bottom.
// cue v0.16.1 ⇒ `y.w: field not allowed`. Spec-adjudicated verdict: bottom.
#X: {a: 1} & ({z: 9} | list.UniqueItems)
y: #X & {z: 9, w: 7}
