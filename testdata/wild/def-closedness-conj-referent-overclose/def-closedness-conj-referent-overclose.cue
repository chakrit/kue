package repro

// A definition whose body is a CONJUNCTION reaching NON-def struct referents
// (`#X: a0 & b0`, both plain structs) must close ONCE over the UNION of their
// fields — exactly as the direct `#X: {a:1} & {b:2}` does. The 68c4879 `underDef`
// indirection-close path follows and closes EACH referent SEPARATELY, producing
// two independent closedClauses (`{a}` AND `{b}`); a use-site meet (`& {a:1}`) then
// requires every field in BOTH allowed-sets, so a legitimately-declared field is
// rejected — an OVER-REJECTION (kue bottoms `y.b`, valid under cue).
//
// The bug bites only at a use-site meet: `y: #X` alone resolves correctly
// (`{a:1,b:2}`); `y: #X & {a:1}` bottoms `b`. A mixed ref+literal conj
// (`#X: a0 & {b:2}`) and a `.selector`-to-disjunction referent
// (`#X: w.inner`, `w.inner: {a:1}|{b:2}`, which bottoms the whole value) are the
// same root — separate-closing instead of union-close-once.
//
// Contrast (correct): the DIRECT literal conj `#X: {a:1} & {b:2}` closes once over
// `{a,b}` (Bug2-12b union-then-close-once) and admits both fields.
//
// Spec-adjudicated verdict: `#X`'s allowed set is the UNION `{a,b}`; `y` is
// `{a:1, b:2}`.
a0: {a: 1}
b0: {b: 2}
#X: a0 & b0
y: #X & {a: 1}
