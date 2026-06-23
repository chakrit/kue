package main

import "example.com/defs"

// bare value drains the comprehension; list-wrapped surfaces an undrained residual as a bottom.
t: defs.#LS & {#issuer: "le"}
wrapped: [t]
