package parts

import "example.com/attr"

// Middle level (slice E): a `Self=` def that PLAINLY embeds the innermost `attr.#Metadata`
// (no explicit `& {#name: …}` wiring — the hidden `#name` flows IMPLICITLY through the shared
// frame, exactly as the real `parts.#Metadata` embeds `attr.#Metadata`). The embed is itself a
// cross-package self-ref closure, so forcing must recurse: the use-site narrowing propagates
// down by splicing only the hidden/definition fields into each embed.
#Metadata: Self={
	attr.#Metadata
	mname: Self.#name
}
