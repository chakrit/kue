package repro

// A CLOSED definition whose body UNIONS its own struct literals (`#X: {a:1} & {b:3}`)
// has a fixed field set `{a,b}` — exactly like the single-decl `#X: {a:1, b:3}`. A
// use-site `#X & {c:4}` adds an undeclared `c`, which the closed field set rejects.
// cue v0.16.1 ⇒ `#X.c: field not allowed`. Spec-adjudicated verdict: bottom.
#X: {a: 1} & {b: 3}
y: #X & {c: 4}
