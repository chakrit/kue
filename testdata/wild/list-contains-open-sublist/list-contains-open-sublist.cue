package repro

// `list.Contains` compares each element against the needle under CUE's STRUCTURAL equality.
// Two facets, both spec-adjudicated (cue is a fallible reference here):
//
//   1. Open-tail stripping (cue AND spec agree). The `...` marker is stripped recursively — at
//      every nesting depth, through structs — before comparing, so `[1,2,...]` reads equal to
//      `[1,2]` as an element OR as the needle. kue formerly used raw structural `BEq`, which
//      distinguishes `.listTail` from `.list` and missed the open-tail-vs-prefix match
//      (`shallow`/`needle`/`deep` returned false, cue true).
//
//   2. Numeric leaves compare BY VALUE with int→float conversion (`intVsFloat` is TRUE). The
//      CUE spec defines `==` recursively over list/struct elements and mandates int→float
//      conversion for numeric comparison, so `[1]` IS contained by `[[1.0]]`. cue v0.16.1
//      returns false here (the STRUCT-EQ-LEAF-TYPESENSE cue bug, ruled spec-wrong 2026-07-04);
//      kue is spec-correct and consistent with its scalar `1 == 1.0` (also true). See
//      cue-divergences.md.
//
// Fixed by the single value-based, open-tail-stripping `structuralEq` (LIST-ELEM-EQ slice).
import "list"

shallow:    list.Contains([[1, 2, ...]], [1, 2])
needle:     list.Contains([[1, 2]], [1, 2, ...])
deep:       list.Contains([[[1, ...]]], [[1]])
intVsFloat: list.Contains([[1]], [1.0])
