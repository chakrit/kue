package main

import "example.com/lib"

// `if #port > 0` fires (8080 > 0) → enabled/bound; the `for` over two names emits two fields.
out: lib.#M & {#port: 8080, #names: ["a", "b"]}
