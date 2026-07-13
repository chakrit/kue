package repro

// A definition whose body INDIRECTS (a bare ref/selector/index) to a DISJUNCTION
// of structs must close each arm — the value of a definition is closed however
// reached, and a disjunction of closed structs rejects a use-site extra in EVERY
// arm. cue v0.16.1 rejects `y` (empty disjunction: `y.b`/`y.z` field not allowed).
// kue LEAKS: the DEF-CLOSEDNESS-NONDEF-REFERENT (68c4879) indirection-close path
// follows a `.refId` referent but does NOT distribute the enclosing def's closedness
// across the referent's disjunction arms, so both arms inline OPEN and admit the
// extras — export then reports "ambiguous value: multiple non-default disjuncts
// remain" (both leaked arms survive) instead of an empty-disjunction bottom.
//
// Contrast: a DIRECT disjunction def body (`#X: {a:1} | {b:2}`) DOES close (both
// arms reject, empty disjunction ⇒ bottom). Only the INDIRECTION-to-disjunction
// (`#X: _foo`, `_foo: {a:1} | {b:2}`) leaks.
//
// The referent is HIDDEN (`_foo`) so this fixture isolates the CLOSEDNESS defect: a
// PLAIN `foo` is an exported top-level ambiguous disjunction whose own "ambiguous
// value" export error masks `y`'s bottom (kue reports the source-first field's
// error, cue prioritizes the hard bottom) — an ORTHOGONAL export-error-precedence
// divergence captured separately in `testdata/wild/export-error-bottom-precedence`.
//
// Spec-adjudicated verdict: closed per arm. `y` is an empty disjunction (bottom).
// Fixed kue emits the closed-disjunction-empty form "conflicting values (bottom)"
// (matching the direct `#X: {a:1}|{b:2}` face).
_foo: {a: 1} | {b: 2}
#X: _foo
y: #X & {b: 2, z: 9}
