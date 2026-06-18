#S: Self={
	#name: string
	(*{#type: "Opaque"} | {#type: "tls"})
	type: Self.#type
}
out: (#S & {#name: "s"}).type
