package defaults

import "example.com/defs"

// The def-OF-def indirection (Bug2-11): a cross-package def whose BODY refs ANOTHER
// cross-package selector. Use-site narrowing of `defaults.#ListenerSet` must reach
// `defs.#ListenerSet`'s embedded `parts.#Meta` — across two package boundaries.
#ListenerSet: defs.#ListenerSet & {
	#gateway_name: "nginx"
}
