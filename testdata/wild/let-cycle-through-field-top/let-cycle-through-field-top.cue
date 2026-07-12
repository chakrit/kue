package repro

// A reference cycle that PASSES THROUGH a field: x (field) -> a (let) -> x.
// Because a FIELD sits on the cycle, cue truncates to top (`incomplete value _`)
// rather than raising the pure-let load error. Guards that the let-vs-field
// distinction does NOT over-correct a field-anchored cycle into an error.
let a = x
x: a
