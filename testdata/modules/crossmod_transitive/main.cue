package main

import "mid.example/lib"

out: lib.#Box & {
	tag: "outer"
	inner: {value: 7}
}
