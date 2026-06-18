package main

import "example.com/lib"

// Use site narrows `#name`/`#suffix` THROUGH the struct-embedding-a-list operand `{ [...]; ... }`.
// The def's trailing list embed reads `Self.#components.{repo,app}`, which read `Self.#name` /
// `Self.#suffix` — all must resolve to the use-site values, not the def defaults.
out: lib.#ListDef & {
	[...]
	#name:   "web"
	#suffix: "-prod"
}
