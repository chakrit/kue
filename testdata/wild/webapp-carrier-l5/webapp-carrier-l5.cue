#Mixin: {
	{kind: string, ...} | error("nope")
	...
}

#Ctl: Self={
	#name: string
	kind:  string
	spec: foo: Self.#name
	...
}

out: #Ctl & {
	#Mixin
	#name: "x"
	kind:  "StatefulSet"
}
