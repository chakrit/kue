package main

import "example.com/defs"

// Cross-package def-meet: the imported self-referential definition unified with a use-site
// struct that narrows the hidden `#name`. `out` must resolve to "keel" (matches `cue`).
t: defs.#M & {#name: "keel"}
