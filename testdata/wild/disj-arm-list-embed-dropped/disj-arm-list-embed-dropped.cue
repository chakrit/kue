package repro

// Unification distributes over disjunction: x & (a|b) = (x&a)|(x&b), and a
// disjunction is bottom only if ALL arms are bottom. A struct that embeds a
// disjunction with a list-shaped arm must KEEP that arm when the host is a
// list-carrier (an embedding host is transparent to the list arm). kue's
// embed-fold (Eval.lean:3928) meets the host-struct against the opened list
// arm as a top-level struct-vs-list kind conflict → .bottom → normalizeDisj
// prunes the arm → spurious overall bottom where cue selects the list arm.

#Emit: {#name: string, [{x: #name}]}
#Mixin: {{[...]} | {kind: string}}
out: #Emit & #Mixin & {#name: "web", [...]}
