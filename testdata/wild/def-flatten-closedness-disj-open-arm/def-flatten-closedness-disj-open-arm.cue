package repro

// MUST-NOT-OVER-CLOSE guard for DEF-FLATTEN-CLOSEDNESS-DISJ: a disjunction arm that
// carries an explicit `...` tail stays OPEN through the distribution — the fix closes
// each arm only to its own declared field set UNION the `...`-openness, so an arm with
// `...` admits extras. `#X & {b:2, d:4}` selects the open `{b, ...}` arm (admits `d`);
// the closed `{a,c}` arm rejects `b` and drops out.
// cue v0.16.1 ⇒ `{a:1, b:2, d:4}`. The fix must reject extras on CLOSED arms yet keep
// an explicit-`...` arm open.
#X: {a: 1} & ({b: 2, ...} | {c: 3})
y: #X & {b: 2, d: 4}
