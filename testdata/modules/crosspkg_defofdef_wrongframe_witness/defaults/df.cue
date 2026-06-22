package defaults

import "example.com/defs"

// A SAME-NAMED local binding with a DIFFERENT value. If the def-of-def's narrowing-delivery
// spliced `defs.#ListenerSet`'s body into THIS (use-site) frame, `zone` would mis-resolve to
// "EU". The fix must keep each conjunct in its OWN package frame: `zone` stays "US".
_region: "EU"

#ListenerSet: defs.#ListenerSet & {
	#gateway_name: "nginx"
}
