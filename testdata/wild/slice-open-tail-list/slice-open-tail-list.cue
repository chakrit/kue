package repro

// Slicing an open-tail list `[a,b,c,...]`. kue defines `len([1,2,3,...]) = 3`
// (the concrete prefix), so every length-dependent value operation must be
// consistent: the slice bounds validate against the prefix length and the result
// is the closed sub-list of the prefix. The `...` open marker affects only
// unification/closedness, never a value-level read. kue previously leaked a
// non-CUE residual `slice([1,2,3,...],1,2)` (dispatch matched only `.list`, not
// the open-tail carrier), failing export as an incomplete value. Spec-silent on
// open-list value ops; resolved by consistency with the committed `len` semantics
// (and cue-compat, which agrees): [1,2,3,...][1:3] = [2, 3].
x: [1, 2, 3, ...][1:3]
