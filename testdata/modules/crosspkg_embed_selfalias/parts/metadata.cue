package parts

// A self-referential cross-package definition embedded into a use-site def. Its only fields are
// HIDDEN (`#kind`, `#norm`), so the embed contributes no regular output — it widens the def's
// closed label set and provides hidden bindings the host self-references.
#Metadata: {
	#kind: string
	#norm: #kind
}
