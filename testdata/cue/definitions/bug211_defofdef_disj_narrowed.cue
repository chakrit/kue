#Meta: Self={
	#name: string
	metadata: name: Self.#name
}
#Defs: {
	#Meta
	#gateway_name: string
	#passthrough_hosts: [...string] | *[]
	kind: "ListenerSet"
}
#Defaults: #Defs & {#gateway_name: "nginx"}
out: #Defaults & {#name: "x", #passthrough_hosts: ["a.example.com"]}
