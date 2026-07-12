package repro

// DEF-FLATTEN-CLOSEDNESS-DISJ-REF guard: a CLOSED def whose disjunction has a def-REF arm
// (`#Base`, not a plain struct literal): `#X: {a:1} & ({z:9} | #Base)`. The `#Base` arm
// composes as `{a:1} & #Base` — `a` is not in `#Base`'s closed allowed-set, so that arm
// bottoms; the `{z:9}` arm closes to `{a:1,z:9}`, which rejects `b`,`extra`. Both arms
// bottom. cue v0.16.1 ⇒ `3 errors in empty disjunction` (bottom). The distribution emits
// the ref arm as an OPEN-compose `.conj [{a:1}, #Base]` (the ref governs closedness), so
// `#X` does not flatten OPEN and leak `{a,z,b,extra}`.
#Base: {b: 2}
#X: {a: 1} & ({z: 9} | #Base)
y: #X & {b: 2, extra: 7}
