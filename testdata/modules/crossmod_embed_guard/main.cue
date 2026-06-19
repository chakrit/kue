package main

import "example.com/mix"

// Narrow `kind` at the use site; the embedded `#Inner`'s comprehension guard `kind == add.#kind`
// must see the narrowed value and emit `meta.annotations.issuer`.
out: mix.#Outer & {kind: "ListenerSet"}
