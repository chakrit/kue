package repro

// BOTH-DIRECTION guard for DEF-FLATTEN-CLOSEDNESS-DISJ: closing the disjunction
// arms must NOT reject a legitimately-declared field. `#X & {b:2}` selects the
// `{a,b}` arm — closed to exactly its own labels — which admits `b`; the `{a,c}`
// arm rejects `b` and drops out, so the disjunction resolves to `{a:1,b:2}`.
// cue v0.16.1 ⇒ `{a:1,b:2}`. The fix must both reject the extra field (sibling
// fixture) AND resolve to this concrete value here.
#X: {a: 1} & ({b: 2} | {c: 3})
y: #X & {b: 2}
