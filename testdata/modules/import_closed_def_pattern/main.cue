package main

import "example.com/lib"

// `xfoo` matches the def's `^x` pattern, so the closed def ADMITS it.
out: lib.#Pat & {port: 1, xfoo: "ok"}
