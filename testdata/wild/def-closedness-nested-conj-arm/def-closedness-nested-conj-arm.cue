package repro

// A PARENTHESIZED (nested) `.conj`-of-struct-literals conjunct in a closed definition
// (`#X: {a:1} & ({b:2} & {d:4})`). The def's field set is fixed to {a,b,d}, so a use-site
// `#X & {z:9}` adds an undeclared `z` and must be rejected — exactly as the flat, unparenthesized
// `#X: {a:1} & {b:2} & {d:4}` already is (that form closes correctly).
//
// LEAK (audit-caught, PHASEA milestone-reconfirmation 2026-07-13): the own-literal-union close
// (`flattenConjDefRef`) recognizes a conjunct as field-carrying only via `isUnionableDefValue`,
// which accepts `.struct`/`.structComp` but NOT a `.conj`. The parens keep `{b:2} & {d:4}` as a
// nested `.conj` (the flat chain is a single already-merged `.conj [{a:1},{b:2},{d:4}]`), so the
// `cs.all` gate fails, `ownLiteralUnion` is false, the def stays OPEN, and `z` leaks in.
// The disjunction-arm analog (`disjArmClass (.conj _) = .blocking`) is the same root: a `.conj`
// arm is not distributed, and it poisons its innocent struct-literal siblings' closedness too.
//
// cue v0.16.1 ⇒ bottom (`y.z: field not allowed`). Spec-adjudicated verdict: bottom — a
// definition is closed to its declared field set regardless of `&`-grouping.
#X: {a: 1} & ({b: 2} & {d: 4})
y: #X & {z: 9}
