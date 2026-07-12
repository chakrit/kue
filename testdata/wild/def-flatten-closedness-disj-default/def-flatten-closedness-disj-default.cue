package repro

// SILENT-LEAK guard for DEF-FLATTEN-CLOSEDNESS-DISJ: with a DEFAULT arm (`*{b:2}`)
// the disjunction collapses to one concrete arm, so the under-close does not merely
// surface as an ambiguity error — pre-fix kue SILENTLY exported `{a:1,b:2,d:4}`,
// leaking the undeclared `d` past a closed definition. Both closed arms reject the
// undeclared `d` → both bottom → bottom.
// cue v0.16.1 ⇒ `y.d: field not allowed`. Spec verdict: bottom.
#X: {a: 1} & (*{b: 2} | {c: 3})
y: #X & {d: 4}
