package main

import "example.com/lib"

// `extra` is added past the def-level `...`; an OPEN def admits it. cue exports both fields.
out: lib.#Open & {port: 8080, extra: "ok"}
