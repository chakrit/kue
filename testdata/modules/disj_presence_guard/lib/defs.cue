package lib

// The `parts.#Metadata` shape (argocd link 5, sub-fix 4): an embed whose presence guard tests a
// host field that carries a DEFAULT disjunction (`#ns: *"argocd" | string`). `#ns != _|_` must be
// `true` (the field IS present), so the guard fires and `metadata.namespace` is emitted with the
// default. Pre-fix the presence test classified a `.disj` as incomplete, dropping `namespace`.
#Meta: Self={
	#name: string
	#ns?:  string
	metadata: {
		name: Self.#name
		if Self.#ns != _|_ {
			namespace: Self.#ns
		}
	}
}

#Repo: {
	#Meta
	#ns:  *"argocd" | string
	kind: "Secret"
}
