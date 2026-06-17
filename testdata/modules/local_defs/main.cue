package main

import "example.com/defs"

widget: defs.#Widget & {
	name: "alpha"
	size: 3
}

gadget: defs.#Gadget & {
	label:  "beta"
	weight: 7
}
