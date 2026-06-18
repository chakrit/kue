package attr

// Innermost level of the 3-level embed chain (slice E), mirroring the real
// `attr.#Metadata`. A `Self=` self-ref def whose only regular output (`name`) reads a
// hidden field the OUTER use-site narrows through the chain. The chain composes three
// captured frames; this is the deepest.
#Metadata: Self={
	#name: string
	name:  Self.#name
}
