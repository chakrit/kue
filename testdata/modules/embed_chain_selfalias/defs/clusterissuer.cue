package defs

import "example.com/parts"

// Outermost level (slice E), mirroring the real `#ClusterIssuer` PLAINLY embedding
// `parts.#Metadata` (which plainly embeds `attr.#Metadata`). The use-site narrows `#name` at
// THIS level; the narrowing must propagate down two plain-embed levels so the innermost `name`
// and the middle `mname` both resolve. Regular output fields (`apiVersion`) stay this def's own
// — they are NOT spliced into the embeds (only hidden `#name` is).
#ClusterIssuer: Self={
	parts.#Metadata
	#name:      string
	apiVersion: "cert-manager.io/v1"
	kind:       Self.#name
}
