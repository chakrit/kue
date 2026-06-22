package defs

import "example.com/parts"

// Frame witness: `_region` is a package-LOCAL binding. `#ListenerSet.zone` reads it, so the
// def body's internal ref MUST resolve against defs' own frame.
_region: "US"

#ListenerSet: {
	parts.#Meta
	#gateway_name: string
	zone:          _region
	kind:          "ListenerSet"
}
