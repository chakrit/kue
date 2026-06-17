package main

import (
	"strings"
	"mix.example/conf"
)

n: conf.#Name & {
	raw: "hello"
}
shout: strings.ToUpper(n.raw)
