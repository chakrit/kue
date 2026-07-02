package repro

// A single closed definition EMBEDDED in a plain struct — no disjunction at
// all. Embedding a definition closes the host struct (spec: a struct with an
// embedded definition is closed), so M & {p: 1, r: 9} must reject the
// undeclared `r` → bottom. cue: "out.r: field not allowed". kue mishandles the
// embed-close path and reports "incomplete value: int" instead of the
// field-not-allowed bottom.
#A: {p: int}
M: {#A}
out: M & {p: 1, r: 9}
