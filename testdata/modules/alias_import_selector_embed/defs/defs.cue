package defs

import "example.com/parts"

// `#A` EMBEDS the import selector (`{parts.#M}`, a structComp) rather than aliasing it directly.
// The deferral must follow the embedding too, so `defs.#A & {#name: …}` resolves identically.
#A: {parts.#M}
