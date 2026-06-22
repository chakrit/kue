package main

import "example.com/defaults2"

// Use-site narrowing threads through three def-of-def levels to the leaf self-ref
// (`metadata.name`), while each level's local `_region`/`_tier` resolves in its own frame.
t: defaults2.#ListenerSet & {
	#name: "argocd-ls"
}
