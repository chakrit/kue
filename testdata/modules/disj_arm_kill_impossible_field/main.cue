package main

import "example.com/lib"

// Supplying `#user` kills the `_#GitHubApp` arm (its `#user?: _|_`) so `_#PAT` wins; `Self.#user`
// resolves to the use-site value in the surviving arm's `stringData`.
out: lib.#Repo & {#user: "me-token"}
