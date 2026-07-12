package repro

// `list.Concat`/`list.FlattenN` destructure each element as a sublist, but the destructure
// sites (`listConcat.collect`, `listFlattenFuel`, `listNestingDepth` in `Kue/Builtin.lean`)
// enumerate only the `.list` and `.listTail` list carriers — the THIRD list carrier,
// `.embeddedList` (a struct that embeds a list plus non-regular decls, e.g. `{[1,2], _x: 9}`),
// falls through. `listItems?`/`structuralEq` (`Kue/Value.lean`) already treat all three
// carriers as list-shaped, so this is a carrier-enumeration ASYMMETRY, the same defect class
// as LIST-OPS-NESTED-OPENTAIL one carrier over.
//
//   concat    — an embedded-list sublist bottoms `collect` (`| _ => none`) instead of splicing.
//   flatten1  — an embedded-list sublist is emitted UNFLATTENED (silent wrong value).
//   depthFull — `listNestingDepth` scores an embedded-list nested carrier as depth 0, undersizing
//               the full-flatten fuel so the inner list is never descended.
//
// Expected values are spec-adjudicated (a struct-embedded list IS the list `[1,2]`); cue v0.16.1
// AGREES on all three, so NO divergence — a straight kue soundness gap.
import "list"

concat:    list.Concat([{[1, 2], _x: 9}, [3]])
flatten1:  list.FlattenN([{[1, 2], _x: 9}, [3]], 1)
depthFull: list.FlattenN([[{[1, 2], _x: 9}]], -1)
