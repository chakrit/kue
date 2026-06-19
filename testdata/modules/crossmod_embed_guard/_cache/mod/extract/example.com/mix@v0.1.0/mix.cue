package mix

// `#Inner` carries a comprehension whose guard reads its REGULAR sibling `kind`. `#Outer`
// embeds `#Inner` and supplies `#additions`; the consumer narrows `kind` at the use site. cue
// defers the guard until `kind` is concrete and emits the matched patch; Kue must splice the
// guarded regular sibling into the embed so the guard fires AFTER the use-site narrowing (else
// the comprehension drops the matched body silently).
#Inner: Self={
	#additions: [string]: {
		#kind:  string
		#patch: _
	}

	kind: string
	for _, add in Self.#additions {
		if kind == add.#kind {
			add.#patch
		}
	}
	...
}

#Outer: {
	#Inner
	#additions: cert_ls: {#kind: "ListenerSet", #patch: {meta: annotations: "issuer": "main"}}
}
