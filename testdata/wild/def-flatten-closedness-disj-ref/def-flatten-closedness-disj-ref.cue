package repro

// QUARANTINED (.known-red) — captured residual of DEF-FLATTEN-CLOSEDNESS-DISJ-REF, not
// yet fixed. A CLOSED def whose disjunction has a def-REF arm (`#Base`, not a plain
// struct literal): `#X: {a:1} & ({z:9} | #Base)`. The `#Base` arm resolves to a CLOSED
// `{a:1,b:2}` (a-not-allowed under #Base's closedness → that arm bottoms), and the `{z:9}`
// arm closes to `{a:1,z:9}`; `#X & {b:2, extra:7}` bottoms both. cue v0.16.1 ⇒
// `3 errors in empty disjunction` (bottom). kue currently exports `{a,z,b,extra}` — the
// `.refId` arm fails `isClosableDisj`, so the whole `#X` stays OPEN and leaks.
// Needs per-arm RESOLUTION (resolve the ref to its closed field set) before the
// closability test — a representation change scoped out of the multi-disjunction slice.
#Base: {b: 2}
#X: {a: 1} & ({z: 9} | #Base)
y: #X & {b: 2, extra: 7}
