package defs

import "example.com/parts"

// The terminal cross-package def, embedding `parts.#Meta` and carrying a sibling default
// disjunction (`#passthrough_hosts`). Selected indirectly through `defaults.#ListenerSet`.
#ListenerSet: {
	parts.#Meta
	#gateway_name: string
	#passthrough_hosts: [...string] | *[]
	kind: "ListenerSet"
}
