package main

import l "list"

// Aliased stdlib CONSTANTS must resolve identically to their unaliased form. The parser
// resolves `list.Ascending`/`Descending` inline off the LITERAL head, so an aliased import
// (`import l "list"`) keys `stdlibPackageValue? "l" …` to nothing and `l.Ascending` survives
// as a deferred selector — `Sort` then bottoms. The post-parse alias canonicalization
// re-resolves the aliased head to the comparator struct. This pins the fix end-to-end through
// the module loader (file load + import binding).
out: {
	asc: l.Sort([3, 1, 2], l.Ascending)
	desc: l.Sort([3, 1, 2], l.Descending)
}
