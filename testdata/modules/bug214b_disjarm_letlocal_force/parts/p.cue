package parts

// Bug2-14b: a STRUCTURAL disjunction (`listShape | structShape | error`) embedding a `let
// _patch` whose `for … if kind == add.#kind` guard reads a host-narrowed sibling `kind`. On the
// cross-package FORCE path the host's narrowed `kind` must reach `_patch.kind` THROUGH the
// surviving disjunction arm, or the comprehension defers and `metadata.annotations` drops.
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

// One package embeds #Mixin AND adds the kind-scoped patch (single-closure embed chain).
#Use: Self={
	#Mixin
	#issuer: string | *"main"
	#additions: ls: {#kind: "ListenerSet", #patch: {metadata: annotations: issuer: Self.#issuer}}
}
