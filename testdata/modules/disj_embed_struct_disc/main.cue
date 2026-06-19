package app

// Gap-2b (Bug2-3): a def `#M` embeds a STRUCTURAL disjunction — `listShape | structShape`
// discriminated by SHAPE (list-vs-struct), not a regular label. `listShape` is list-shaped
// (a hidden `#components` keyed map plus a `[...]` embedded list); `structShape` is a plain
// struct. When `#M` is embedded one layer down (`#U: {#M}`) and force-narrowed by a sibling
// regular OUTPUT field the arms lack (`#U & {meta: …}`), the host's regular fields reach the
// arms only as a sibling of the embedded disjunction, never met INTO the list arm as a value —
// so the sound `list & {regular fields} = ⊥` prune never fired and BOTH arms survived
// (ambiguous bottom). The fix splices the host's regular output fields into each structural
// arm so the meet primitive prunes the list arm (a list cannot carry `meta`) and selects the
// struct arm. The prune is the type-conflict meet, NOT a shape heuristic.
#M: {
	let listShape = {#components: [string]: {x: int}, [...]}
	let structShape = {meta: string, ...}
	listShape | structShape
	...
}

#U: {#M}

// Host narrows with a regular output field only `structShape` can carry → struct arm wins.
outStruct: #U & {meta: "yes", extra: "ok"}

// Direct narrowing (no embedding layer) of the same disjunction: struct arm wins identically.
outDirect: (#M) & {meta: "direct"}

// A host that matches NEITHER arm bottoms (real conflict): a list item shape conflict AND a
// struct field conflict — both arms die.
outBottom: (#U & {#components: notallowed: {x: "string-not-int"}, meta: 5}) | {fallback: "ok"}
