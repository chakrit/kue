package defs

// A definition whose body self-references a sibling: `out` resolves to `#name`. Under the
// eager import-selector path this collapses (`out` becomes `string` before the use-site
// narrows `#name`); the closure-meet path (Value.closure slice 4) splices the use-site in
// first, so `out` sees the narrowed `#name`.
#M: {
	#name: string
	out:   #name
}
