package defaults

import "example.com/defs"

// Frame witness, MIDDLE level: `_region` SHADOWS defs' (EU vs US), `_tier` is middle-local.
// `tier` reads the middle `_tier`; it must resolve here, not at the leaf or the use-site.
_region: "EU"
_tier:   "mid"

#ListenerSet: defs.#ListenerSet & {
	#gateway_name: "nginx"
	tier:          _tier
}
