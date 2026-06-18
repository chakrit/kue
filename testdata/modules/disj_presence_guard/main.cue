package main

import "example.com/lib"

// `#ns` defaults to "argocd"; the embed's `if Self.#ns != _|_` guard must fire (a default
// disjunction is present) and emit `metadata.namespace: "argocd"`.
out: lib.#Repo & {#name: "web-repo"}
