package app

// Bug2-4 (the argocd `defs/parts.#Mixin` export blocker): the shape that bottomed
// `kue export apps/argocd.cue`. `#Mixin` buries a comprehension inside `let _patch`, and the
// regular sibling the guard reads (`kind`) is DECLARED INSIDE that same let (`kind: string`) —
// not at the def frame. The guard's `kind` resolves to `_patch`'s OWN frame, where it is also
// declared, so no def-frame index names it: the host narrowing (`kind: "ListenerSet"`) spliced
// at the def frame lands as a SIBLING the guard never reads, the comprehension fires against
// `string`, and the matched patch drops. The fix surfaces the let-local label
// (`letPromotedReadLabels`) and MEETS the host narrowing into the let-local before the
// comprehension expands (`injectLetLocalNarrowings`) — matching cue's lazy promote-then-narrow.
// Tested WITH the structural `listShape | structShape | error` disjunction (the real Mixin),
// so it exercises the Bug2-4 fix on top of the Gap-2b structural prune.
#Mixin: Self={
	#additions: [string]: {#kind: string, #patch: _}

	let _patch = {
		kind: string
		for _, add in Self.#additions {
			if kind == add.#kind {add.#patch}
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

	listShape | structShape | error("#Mixin: target must have #components or kind")
	...
}

// The host is a DEF embedding `#Mixin` (the `defaults.#ListenerSet` shape: a def composing the
// mixin, then narrowed at the use site) — the closure-force splice path the fix targets.
#Use: {
	#Mixin
	#additions: cert_ls: {#kind: "ListenerSet", #patch: {meta: "yes"}}
}

// Struct-shape host narrows `kind` → the matched patch (`meta: "yes"`) surfaces.
outMatched: #Use & {kind: "ListenerSet"}

// Guard FALSE (host `kind` mismatches): the body must NOT fire — no over-fire.
outDropped: #Use & {kind: "Other"}
