package repro

// A CLOSED definition whose body unions its own struct literal THROUGH a disjunction one of whose
// arms is a PARENTHESIZED nested `.conj`-of-struct-literals (`#X: {a:1} & (({b:2}&{d:4}) | {c:3})`).
// The `.conj` arm must distribute-and-close exactly as a plain struct arm does: the def denotes
// `{a,b,d} | {a,c}`, both closed. A use-site `#X & {z:9}` adds an undeclared `z`, rejected by BOTH
// closed arms → the disjunction is empty → bottom.
//
// LEAK (audit-caught, DEF-CLOSEDNESS-NESTED-CONJ-ARM 2026-07-13): `disjArmClass (.conj _)` was
// `.blocking`, so a `.conj` disjunction arm was NOT distributable → the whole disjunction stayed
// non-distributable → the def flattened OPEN and `z` leaked in BOTH arms (kue exported an ambiguous
// disjunction admitting `z`). The disjunction-face twin of the nested-conj conjunct leak; same root,
// same fix (`normalizeDefBodyConjunct` merges a pure-struct `.conj` arm before the gate).
//
// cue v0.16.1 ⇒ bottom (`z: field not allowed`). Spec-adjudicated verdict: bottom — a definition is
// closed to its declared field set per arm regardless of `&`-grouping inside an arm.
#X: {a: 1} & (({b: 2} & {d: 4}) | {c: 3})
y: #X & {z: 9}
