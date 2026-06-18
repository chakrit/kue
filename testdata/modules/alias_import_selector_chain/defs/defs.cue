package defs

import "example.com/parts"

// Two-level alias: `#A` aliases the import selector, `#B` aliases `#A`. The deferral must follow
// the chain `#B → #A → parts.#M`, so `defs.#B & {#name: …}` defers through both hops.
#A: parts.#M
#B: #A
