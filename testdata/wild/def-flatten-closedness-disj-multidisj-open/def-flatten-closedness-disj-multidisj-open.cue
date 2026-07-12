package repro

// Both-direction guard: a `...`-tailed arm inside the cross-product must keep its
// combination OPEN, so an undeclared field on the selected combination is admitted, not
// force-closed. `#X: {a:1} & (*{b:2, ...}|{c:3}) & (*{d:4}|{e:5})` — the default
// combination is `{a,b,...,d}`, open via the `b` arm's tail. `#X & {f:6}` admits `f`.
// Guards the over-close direction the cross-product must not trip. cue v0.16.1 ⇒
// `{a:1, b:2, d:4, f:6}`.
#X: {a: 1} & (*{b: 2, ...} | {c: 3}) & (*{d: 4} | {e: 5})
y: #X & {f: 6}
