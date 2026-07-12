package repro

// QUARANTINED (.known-red) — captured residual of DEF-FLATTEN-CLOSEDNESS-DISJ-REF, not
// yet fixed. A CLOSED def whose disjunction has a NESTED disjunction arm:
// `#X: {a:1} & ({b:2} | ({c:3} | {e:5}))`. The nested `.disj` arm is not
// `isUnionableDefValue`, so `isClosableDisj` fails and `#X` stays OPEN; `#X & {g:9}` then
// leaks. cue v0.16.1 flattens the nested disjunction to `{b:2}|{c:3}|{e:5}`, closes each
// arm to `{a}∪arm`, and bottoms `g` in every arm ⇒ bottom. kue currently reports
// `ambiguous` (a distinct disjunction-resolution issue entangled here). Needs the nested
// disjunction flattened before the closability test.
#X: {a: 1} & ({b: 2} | ({c: 3} | {e: 5}))
y: #X & {g: 9}
