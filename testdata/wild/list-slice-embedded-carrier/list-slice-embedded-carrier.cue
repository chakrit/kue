package repro

// The slice-syntax desugar `x[lo:hi]` (`evalCoreBuiltin`, `Kue/Builtin.lean`) hand-enumerated
// `.list` + `.listTail` and MISSED `.embeddedList` — a struct embedding a list plus non-regular
// decls (`{[1,2,3], _y: 9}`). `len`/index on the same value already routed through `listItems?`,
// so slice was the lone carrier-miss outlier: `({[1,2,3], _y: 9})[0:2]` deferred as an
// `incomplete value` residual instead of slicing the embedded list's concrete prefix.
//
// A struct-embedded list IS the list `[1,2,3]` (the hidden `_y` governs only unification, never
// a value read), so slicing is prefix-based: `[0:2]` = `[1,2]`, `[1:]` = `[2,3]`, `[:]` = the
// whole prefix. Spec-adjudicated.
//
// cue v0.16.1 DIVERGES (buggy): it bleeds the hidden `_y: 9` into the slice, so `[0:2]` = `[9,1]`
// (see docs/spec/cue-divergences.md). kue follows the spec: the hidden field is not a list
// element. Provenance: 2026-07-13 Phase A audit, list-carrier-enumeration completeness.

interior: ({[1, 2, 3], _y: 9})[0:2]
openLow:  ({[1, 2, 3], _y: 9})[1:]
openHigh: ({[1, 2, 3], _y: 9})[:2]
whole:    ({[1, 2, 3], _y: 9})[:]
tail:     ({[1, 2, 3, ...], _y: 9})[0:2]
