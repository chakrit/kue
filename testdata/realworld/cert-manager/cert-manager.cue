// Self-contained, sanitized port of a real cert-manager ClusterIssuer app.
// Inlines the private-module definition chain (attr.#Metadata -> parts.#Metadata ->
// #ClusterIssuer) so it evaluates with no imports, no registry, no external dependency.
// All infra-identifying values are replaced with structure-preserving placeholders; the
// CUE evaluation shape is unchanged.

#AttrMetadata: {
	#name: string
	#ns?:  string
	#labels?: [string]:      string
	#annotations?: [string]: string

	_
}

#Metadata: Self={
	#AttrMetadata

	metadata: {
		name: Self.#name
		if Self.#ns != _|_ {
			namespace: Self.#ns
		}
		if Self.#labels != _|_ {
			if len(Self.#labels) > 0 {
				labels: Self.#labels
			}
		}
		if Self.#annotations != _|_ {
			if len(Self.#annotations) > 0 {
				annotations: Self.#annotations
			}
		}
		...
	}
}

#ClusterIssuer: Self={
	#Metadata

	#email:   string
	#staging: bool | *false

	#gateway_name: string
	#gateway_ns:   string

	apiVersion: "cert-manager.io/v1"
	kind:       "ClusterIssuer"

	spec: acme: {
		email: Self.#email
		if Self.#staging {
			server: "https://acme-staging-v02.api.letsencrypt.org/directory"
		}
		if !Self.#staging {
			server: "https://acme-v02.api.letsencrypt.org/directory"
		}
		privateKeySecretRef: name: Self.#name + "-secret"
		solvers: [{
			http01: gatewayHTTPRoute: parentRefs: [{
				group:     "gateway.networking.k8s.io"
				kind:      "Gateway"
				name:      Self.#gateway_name
				namespace: Self.#gateway_ns
			}]
		}]
	}
}

#defaults: {
	#gateway_name: "example-gateway"
	#gateway_ns:   "example-ns"
}

"cert-manager": {
	let issuer = #ClusterIssuer & {
		#name:         "cluster-issuer-main"
		#email:        "ops@example.test"
		#gateway_name: #defaults.#gateway_name
		#gateway_ns:   #defaults.#gateway_ns
	}

	"cluster-issuer.yaml": [issuer]
}
