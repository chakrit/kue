package repro

// A CLOSED definition whose body unions its own struct literal across MULTIPLE
// closable disjunction conjuncts (`#X: {a:1} & (*{b:2}|{c:3}) & (*{d:4}|{e:5})`)
// has a fixed field set PER cross-product combination: {a,b,d}, {a,b,e},
// {a,c,d}, {a,c,e}. A use-site `#X & {f:6}` adds an undeclared `f`, which every
// combination rejects → the disjunction is empty → bottom. Before the
// cross-product distribution the multiple disjunctions flattened OPEN and the
// defaults collapsed to one arm, SILENTLY exporting `{a,b,d,f}`.
// cue v0.16.1 ⇒ `y.f: field not allowed`. Spec-adjudicated verdict: bottom.
#X: {a: 1} & (*{b: 2} | {c: 3}) & (*{d: 4} | {e: 5})
y: #X & {f: 6}
