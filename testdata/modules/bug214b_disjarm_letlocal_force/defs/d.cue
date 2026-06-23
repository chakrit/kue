package defs

import "example.com/parts"

// Host declares `kind` as a SIBLING and embeds `parts.#Use` — the disjunction is two embed
// levels down (#Use → #Mixin). The cross-package force must carry `kind` through the chain.
#LS: {
	kind: "ListenerSet"
	parts.#Use
}
