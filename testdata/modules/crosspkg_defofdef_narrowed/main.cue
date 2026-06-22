package main

import "example.com/defaults"

t: defaults.#ListenerSet & {
	#name: "argocd-ls"
	#passthrough_hosts: ["argo.prodigy9.co"]
}
