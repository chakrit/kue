package repro

// The three list carriers — `.list`, `.listTail`, `.embeddedList` — all mean "a list."
// `listItems?` (`Kue/Value.lean`) reads items from all three; the value-level list surface in
// `Kue/Builtin.lean` routes every carrier destructure through it, so a struct that embeds a list
// plus non-regular decls (`{[1,2], _x: 9}`, an `.embeddedList`) is a list value everywhere cue
// treats it as one.
//
//   concat/flatten1/depthFull — nested-sublist destructure (`listConcat`, `listFlattenFuel`,
//                               full-flatten fuel) reads the embedded carrier's elements.
//   lenEmbed                  — `len` of an embedded-list is its element count.
//   sumEmbed/reverseEmbed     — a `list.*` operand that is an embedded-list normalizes to its
//                               concrete-prefix list (`openListOperand`).
//
// Expected values are spec-adjudicated (a struct-embedded list IS the list `[1,2]`); cue v0.16.1
// AGREES on all cases, so NO divergence — a straight kue soundness gap.
// Provenance: 2026-07-13 Phase A/B audit, carrier-enumeration completeness.
import "list"

concat:       list.Concat([{[1, 2], _x: 9}, [3]])
flatten1:     list.FlattenN([{[1, 2], _x: 9}, [3]], 1)
depthFull:    list.FlattenN([[{[1, 2], _x: 9}]], -1)
lenEmbed:     len({[1, 2, 3], _x: 9})
sumEmbed:     list.Sum({[1, 2, 3], _x: 9})
reverseEmbed: list.Reverse({[1, 2], _x: 9})
