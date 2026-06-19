package app

// Gap-1 (Bug2-1): a comprehension guard buried under ONE `let` reads the def's REGULAR
// sibling `kind`, narrowed at the use site. The let-ref `_patch` is a `.refId` leaf; the
// read-label analysis must follow it into the let value to discover `kind` and splice it
// so the guard sees the narrowed value (cue defers the comprehension until `kind` is
// concrete, then emits the matched `#patch`). Before the fix Kue dropped `meta`.
#Mixin: Self={
	#additions: [string]: {#kind: string, #patch: _}
	kind: string
	let _patch = {
		for _, add in Self.#additions {
			if kind == add.#kind {add.#patch}
		}
	}
	_patch
	...
}
#Use: {
	#Mixin
	#additions: cert_ls: {#kind: "ListenerSet", #patch: {meta: "yes"}}
}
outMatch: #Use & {kind: "ListenerSet"}
outNoMatch: #Use & {kind: "Other"}
