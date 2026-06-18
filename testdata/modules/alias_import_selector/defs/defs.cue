package defs

import "example.com/parts"

// `#A` aliased DIRECTLY to the import selector `parts.#M` (no embed braces). Selecting/meeting
// through it (`defs.#A & {#name: …}`) must DEFER the import selector to a closure capturing the
// `parts` frame, so the use-site narrowing splices before `name: #name` collapses.
#A: parts.#M
