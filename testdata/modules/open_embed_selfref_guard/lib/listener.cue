package lib

// An OPEN cross-package definition (`...` at the def level) that ALSO embeds a self-referential
// def AND reads a use-site-narrowed hidden field through `Self` from a NESTED struct. The
// def-level `...` previously made the parser split the body into `.conj [.structComp(embeds),
// .structTail(fields, tail)]`: the `Self.#gw` self-ref landed in the structTail arm, which never
// saw the embedded `#Hosts`-supplied fields, so the use-site narrowing collapsed to `.bottom`
// (the argocd `defs.#ListenerSet` blocker — `parts.#Metadata` embedded + a def-level `...`).
#Hosts: {
	#host?: string
	#hosts: [...string]
	if #host != _|_ {
		#hosts: [#host]
	}
}

#ListenerSet: Self={
	#Hosts
	#gateway_name: string
	spec: {
		parentRef: name: Self.#gateway_name
		hosts: Self.#hosts
	}
	...
}
