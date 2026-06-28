package repro

// A list-embedding carrier ({hidden decls, [list embed]}) met with a
// `let`-delivered list-shaped value. A `let` is pure substitution, so this must
// behave identically to the inline meet. cue collapses the carrier to its list
// and meets the lists. kue routed the let-delivered operand to meetCore's
// `.embeddedList _ _ _, _ => .bottom` (Lattice.lean:519) instead of the
// struct-embeds-list collapse arms — spurious "conflicting values".

f: {let ls = [...], {#name: "web", [1, 2]} & ls}
e: {let ls = {#k: string, [...]}, [1, 2] & ls}
f2: {let ls = {#k: string, [...]}, {#name: "web", [1, 2]} & ls}
