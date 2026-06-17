#D: {
	#x?: string
	_y?: int
}
provided: #D & {
	#x: "hi"
	_y: 7
}
selected: provided.#x
hidden:   provided._y
