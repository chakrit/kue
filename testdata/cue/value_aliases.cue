#Secret: Self={
	#name: "tls"
	data:  Self.#name
}

aliased: X={
	greeting: "hi"
	echo:     X.greeting
}

nestedSelf: Self={
	port: 8080
	inner: lo: Self.port
}
