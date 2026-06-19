package app

// A-EN1 (rides Bug2-1): the let-buried comprehension's `for` SOURCE — not a guard — is
// the def's REGULAR sibling `items`, narrowed at the use site. The same detection gap:
// the let-ref `_expanded` is a `.refId` leaf, so the `for _, it in items` read of the
// regular `items` is invisible until the analysis follows the let into its value. cue
// expands the comprehension once `items` is concrete; before the fix Kue dropped the keys.
#Mixin: {
	items: [...string]
	let _expanded = {
		for _, it in items {
			"\(it)": {present: true}
		}
	}
	_expanded
	...
}
#Use: {
	#Mixin
}
out: #Use & {items: ["a", "b"]}
