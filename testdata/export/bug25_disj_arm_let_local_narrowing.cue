// Bug2-5: a co-embedding sibling def's static field (`kind`) must narrow a let-local
// (`_patch.kind`) buried inside a TRANSITIVELY-embedded mixin whose body is a disjunction
// (`listShape | structShape | error`). The narrowing crosses TWO embed levels (`#Outer`
// embeds `#Mid`, `#Mid` embeds `#Mixin`) and lands on the disjunction-arm path, so the
// force-path `injectLetLocalNarrowings` never sees it. cue emits `meta: "yes"`; kue
// pre-fix bottomed (the `if kind == add.#kind` guard never fired against the un-narrowed
// `kind: string`). The faithful argocd `#ListenerSet` shape, minimized.
#Mixin: Self={
	#additions: [string]: {#kind: string, #patch: _}
	let _patch = {
		kind: string
		for _, add in Self.#additions {
			if kind == add.#kind {add.#patch}
		}
		...
	}
	let listShape = {#components: [string]: _patch, [...]}
	let structShape = {_patch, ...}
	listShape | structShape | error("#Mixin: target must have #components or kind: string")
	...
}

#Mid: {
	#Mixin
	#additions: cert_ls: {#kind: "ListenerSet", #patch: {meta: "yes"}}
}

#Outer: {
	#Mid
	kind: "ListenerSet"
}

out: #Outer
