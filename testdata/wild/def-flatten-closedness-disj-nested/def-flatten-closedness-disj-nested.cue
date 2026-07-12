package repro

// DEF-FLATTEN-CLOSEDNESS-DISJ-REF guard: a CLOSED def whose disjunction has a NESTED
// disjunction arm: `#X: {a:1} & ({b:2} | ({c:3} | {e:5}))`. Disjunction is associative, so
// the nested arm flattens to `{b:2}|{c:3}|{e:5}`; each arm closes to `{a}∪arm`, and an
// undeclared `g` bottoms every arm. cue v0.16.1 ⇒ bottom. Before flattening the nested arm
// the def stayed OPEN and reported `ambiguous` (both inner arms survived the open meet);
// `flattenNestedDisjArms` now splices the nested arms before the cross-product close.
#X: {a: 1} & ({b: 2} | ({c: 3} | {e: 5}))
y: #X & {g: 9}
