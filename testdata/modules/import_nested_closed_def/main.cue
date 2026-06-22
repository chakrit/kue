package main

import "example.com/lib"

// `inner` carries `{a: 1}` — `a` is declared by the nested closed `#Inner`, so the closed
// def ADMITS it. cue exports `{inner: {a: 1}}`. An extra field at `inner` would be rejected
// (closedness propagates through the nested def selection).
out: lib.#Outer & {inner: {a: 1}}
