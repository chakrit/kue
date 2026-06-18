package attr

// The shared package imported by two sibling files of `parts`. Self-referential so an eager
// resolution would collapse `name` before a use-site narrows `#name`.
#Metadata: {
	#name: string
	name:  #name
}
