package parts

// Bug2-14c: the #Mixin structural disjunction, used through a MULTI-CLOSURE conjunction. The
// host's regular `kind` lives in a SIBLING closure (defs.#ListenerSet), not in this closure —
// so the multi-closure force fold must carry it across the conjunct boundary into `_patch.kind`.
#Mixin: Self={
	#additions: [string]: {
		#kind:  string
		#patch: _
	}
	let _patch = {
		kind: string
		for _, add in Self.#additions {
			if kind == add.#kind {
				add.#patch
			}
		}
		...
	}
	let listShape = {
		#components: [string]: _patch
		[...]
	}
	let structShape = {
		_patch
		...
	}
	listShape | structShape | error("#Mixin: target must have #components or kind: string")
	...
}

// #UseCertManager embeds #Mixin and adds the kind-scoped patch — but does NOT declare `kind`.
#UseCertManager: Self={
	#Mixin
	#cluster_issuer: string | *"main"
	#additions: cert_ls: {#kind: "ListenerSet", #patch: {metadata: annotations: "ci": Self.#cluster_issuer}}
}
