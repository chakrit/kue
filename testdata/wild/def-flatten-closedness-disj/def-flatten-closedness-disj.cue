package repro

// A CLOSED definition whose body UNIONS its own struct literals THROUGH a
// disjunction conjunct (`#X: {a:1} & ({b:2}|{c:3})`) has a fixed per-arm field
// set — `{a,b}` in one arm, `{a,c}` in the other — exactly like the embedded
// form `#X: {a:1, {b:2}|{c:3}}`. A use-site `#X & {d:4}` adds an undeclared `d`,
// which BOTH closed arms reject → the disjunction is empty → bottom.
// cue v0.16.1 ⇒ `y.d: field not allowed`. Spec-adjudicated verdict: bottom.
#X: {a: 1} & ({b: 2} | {c: 3})
y: #X & {d: 4}
