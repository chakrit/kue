package repro

// Both-direction guard for the cross-product distribution: selecting a NON-default
// combination must resolve to exactly that combination's closed field set, admitting
// its own declared fields. `#X: {a:1} & (*{b:2}|{c:3}) & (*{d:4}|{e:5})` unified with
// `{c:3, e:5}` picks the `{a,c,e}` combination; `c` and `e` are that combination's own
// declared fields, so they are ADMITTED, not rejected. Guards against over-closing a
// legitimately-selected arm. cue v0.16.1 ⇒ `{a:1, c:3, e:5}`.
#X: {a: 1} & (*{b: 2} | {c: 3}) & (*{d: 4} | {e: 5})
y: #X & {c: 3, e: 5}
