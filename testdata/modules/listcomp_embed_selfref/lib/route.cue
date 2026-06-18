package lib

// A def that embeds a self-referential def (`#Hosts`, whose guard produces `#hosts` from a
// use-site-narrowed `#host`) and then iterates that embedded field in a LIST comprehension
// (`[for h in Self.#hosts {…}]`). The list-comprehension source `Self.#hosts` must trigger the
// embedding-`Self` two-pass exactly as a plain `Self.#hosts` selection does; before the fix the
// `.listComprehension` source was invisible to `refsSelfEmbeddedLabel`, so the comprehension
// iterated the un-narrowed (empty) `#hosts` and dropped every element (argocd `#ListenerSet`
// `spec.listeners` / `#TLSRoute` family).
#Hosts: {
	#host?: string
	#hosts: [...string]
	if #host != _|_ {
		#hosts: [#host]
	}
}

#Route: Self={
	#Hosts
	spec: {
		listeners: [
			for h in Self.#hosts {
				hostname: h
			},
		]
	}
}
