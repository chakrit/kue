package defs

import "example.com/parts"

// Frame witness, leaf level: `_region` is package-LOCAL. `zone` reads it, so a wrong-frame
// splice into the use-site would mis-resolve it. The open `...` lets the middle/top conjuncts
// ADD their own fields (isolating frame resolution from closedness).
_region: "US"

#ListenerSet: {
	parts.#Meta
	#gateway_name: string
	zone:          _region
	kind:          "ListenerSet"
	...
}
