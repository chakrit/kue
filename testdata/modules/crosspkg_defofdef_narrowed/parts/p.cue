package parts

// A self-referential cross-package def: `metadata.name` reads the hidden `#name`, so the
// use-site narrowing must reach this embedded body or `name` freezes at `string`.
#Meta: Self={
	#name: string
	metadata: name: Self.#name
}
