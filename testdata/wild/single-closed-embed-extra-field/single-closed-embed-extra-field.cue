package repro

// A single closed definition EMBEDDED in a plain struct — no disjunction at
// all. Embedding a definition closes the host struct (spec: a struct with an
// embedded definition is closed), so #M & {p: 1, r: 9} must reject the
// undeclared `r` → bottom. cue: "out.r: field not allowed"; kue renders the
// bottom as "conflicting values (bottom)". The carrier is a HIDDEN def (#M) so
// the observed export result is `out`'s value, not the carrier's own (inherent)
// incompleteness — see PROVENANCE.md.
#A: {p: int}
#M: {#A}
out: #M & {p: 1, r: 9}
