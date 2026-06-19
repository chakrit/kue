package app

// Gap-2 (Bug2-2) + the shapeD repro: a discriminated disjunction whose arms are LET
// bindings (`structShape | listShape | error`, each `let`-bound to a struct declaring the
// regular discriminator `shape`), wrapping a comprehension buried under `let _patch`. The
// def `#MixinD` is embedded one layer down (`#UseD: {#MixinD}`), then narrowed at the use
// site with `shape:"struct"`. cue selects the struct arm and emits the matched `#patch`
// (`meta:"yes"`); before the fix Kue BOTTOMED — `embedDisjArmDeclLabels` follows the
// `.refId` arms into their `let` slots to discover the arm-declared discriminator `shape`,
// splices the host's narrowed `shape` into `#MixinD` so its force-time disjunction prunes
// the dead `listShape`/`error` arms exactly as a direct `#MixinD & {shape:"struct"}` does.
#MixinD: Self={
	#additions: [string]: {#kind: string, #patch: _}
	kind:  string
	shape: string
	let _patch = {
		for _, add in Self.#additions {
			if kind == add.#kind {add.#patch}
		}
	}
	let listShape = {shape: "list", items: [_patch]}
	let structShape = {shape: "struct", _patch}
	structShape | listShape | error("no shape")
	...
}

#UseD: {
	#MixinD
	#additions: cert_ls: {#kind: "ListenerSet", #patch: {meta: "yes"}}
}

outMatch: #UseD & {kind: "ListenerSet", shape: "struct"}
outNoMatch: #UseD & {kind: "Other", shape: "struct"}
