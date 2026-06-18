package defs

import "example.com/parts"

// Real-app shape (slice A): a value-alias def EMBEDDING a cross-package self-ref def. The embed
// makes the body a `.structComp`; the closure producer/force must splice the use-site narrowing
// into the static fields AND meet-fold the embedded `parts.#Metadata` closure so the hidden
// `#norm` (= `#kind`) resolves. The single regular output `spec` references the narrowed hidden
// fields — one output field, so byte-order parity (#3) does not bite.
#Def: {
	parts.#Metadata
	#x:   string
	spec: #x
}
