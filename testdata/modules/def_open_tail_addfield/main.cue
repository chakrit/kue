package main

import "example.com/lib"

// The use site ADDS `added` (undeclared by the def) past the def-level `...`. The open def
// admits it; cue exports all four fields. Pre-fix this bottomed (the `...` was dropped and the
// def silently closed). The closed sibling rejecting `added` is pinned in EvalTests.
out: lib.#OpenEmbed & {port: 8080, added: "extra"}
