package repro

// A CLOSED definition whose body unions its own struct literals THROUGH a PARENTHESIZED nested
// `.conj` (`#X: {a:1} & ({b:2} & {d:4})`). The field set is fixed to {a,b,d} — `&`-grouping is
// associative, so this closes exactly as the flat `#X: {a:1} & {b:2} & {d:4}` does. A use-site
// `#X & {z:9}` adds an undeclared `z`, rejected by the closed struct → bottom.
//
// cue v0.16.1 ⇒ bottom (`y.z: field not allowed`). Spec-adjudicated verdict: bottom — a definition
// is closed to its declared field set regardless of `&`-grouping. See PROVENANCE.md.
#X: {a: 1} & ({b: 2} & {d: 4})
y: #X & {z: 9}
