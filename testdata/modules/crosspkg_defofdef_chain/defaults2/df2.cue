package defaults2

import "example.com/defaults"

// A THIRD level of def-of-def indirection — the narrowing must thread through two
// `&`-composed cross-package selectors before reaching the embedded self-ref.
#ListenerSet: defaults.#ListenerSet & {
	#passthrough_hosts: ["base.example.com"]
}
