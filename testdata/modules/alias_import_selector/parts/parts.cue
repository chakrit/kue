package parts

// A self-referential cross-package definition: the regular `name` reads the hidden `#name`,
// so an eager resolution collapses it to `string` before a use-site narrows `#name`.
#M: {
	#name: string
	name:  #name
}
