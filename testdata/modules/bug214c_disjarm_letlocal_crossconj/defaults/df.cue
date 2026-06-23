package defaults

import (
	"example.com/defs"
	"example.com/parts"
)

// The multi-closure conjunction (the real argocd defaults.#ListenerSet shape): two separate def
// closures (`kind` in one, `#Mixin` disjunction in the other) plus a narrowing struct.
#ListenerSet: defs.#ListenerSet & parts.#UseCertManager & {
	#cluster_issuer: "cluster-issuer-main"
}
