package app

// Gap-1 (Bug2-1) nested variant: the comprehension is buried under TWO `let`s
// (`_patch` inside `structShape`). The read-label analysis must follow the let chain
// transitively (`structShape` -> `_patch` -> the comprehension reading `kind`) — the
// `closeDefFrameReadIndices` fixpoint with its visited-set cycle bound.
#Mixin: Self={
	#additions: [string]: {#kind: string, #patch: _}
	kind: string
	let _patch = {
		for _, add in Self.#additions {
			if kind == add.#kind {add.#patch}
		}
	}
	let structShape = {_patch}
	structShape
	...
}
#Use: {
	#Mixin
	#additions: cert_ls: {#kind: "ListenerSet", #patch: {meta: "yes"}}
}
outMatch: #Use & {kind: "ListenerSet"}
outNoMatch: #Use & {kind: "Other"}
