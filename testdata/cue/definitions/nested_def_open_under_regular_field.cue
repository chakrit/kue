a: {
	#Inner: {x: int, ...}
}
out: a.#Inner & {x: 1, extra: 2}
