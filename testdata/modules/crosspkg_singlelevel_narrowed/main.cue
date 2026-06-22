package main

import "example.com/defs"

// Control for Bug2-11: a SINGLE-level cross-package selector narrows correctly already.
// The def-of-def fixture differs ONLY by the `defaults` indirection — isolating it as the cause.
t: defs.#ListenerSet & {
	#name:         "argocd-ls"
	#gateway_name: "nginx"
	#passthrough_hosts: ["argo.prodigy9.co"]
}
