package main

import "example.com/defs"

// 3-level PLAIN-embed chain (slice E), the real `#ClusterIssuer → parts.#Metadata →
// attr.#Metadata` shape: each level plainly embeds the next (no explicit `& {#name: …}`
// wiring), so the hidden `#name` flows IMPLICITLY through the shared frame. The use-site
// narrows `#name: "keel"` at the OUTER level; it must propagate down two embed levels so the
// innermost `name`, the middle `mname`, and the outer `kind` all resolve to "keel" — while the
// outer's own regular `apiVersion` stays its own (not spliced into the embeds).
out: defs.#ClusterIssuer & {#name: "keel"}
