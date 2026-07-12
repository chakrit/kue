package repro

// `list.Contains` compares each element against the needle. cue strips the open-tail
// `...` marker recursively (at every nesting depth, through structs) before comparing,
// so `[1,2,...]` reads equal to `[1,2]` as an element OR as the needle. It does NOT,
// however, unify numeric kinds inside a list: `[1]` is NOT contained by `[[1.0]]`
// (int ≠ float in element equality — distinct from the `1 == 1.0` operator).
//
// kue uses raw structural `BEq` for the element/needle comparison, which distinguishes
// `.listTail` from `.list` and so misses the open-tail-vs-prefix match — a SILENT WRONG
// value (`shallow`/`deep` return false, cue true). QUARANTINED (.known-red): the fix needs
// a recursive open-tail-stripping equality with STRICT prim comparison (so `strict` stays
// false) — a distinct mechanism from the destructure-site normalization used by
// Concat/FlattenN, and entangled with a separate `[1] == [1.0]` operator divergence.
// Filed as LIST-CONTAINS-OPENTAIL-EQ.
import "list"

shallow: list.Contains([[1, 2, ...]], [1, 2])
needle:  list.Contains([[1, 2]], [1, 2, ...])
deep:    list.Contains([[[1, ...]]], [[1]])
strict:  list.Contains([[1]], [1.0])
