package defs

// The kind-declaring closure. In the conjunction `defs.#ListenerSet & parts.#UseCertManager`
// this closure owns `kind` while the OTHER closure owns the disjunction+let-local.
#ListenerSet: {
	apiVersion: "gateway.networking.k8s.io/v1"
	kind:       "ListenerSet"
	...
}
