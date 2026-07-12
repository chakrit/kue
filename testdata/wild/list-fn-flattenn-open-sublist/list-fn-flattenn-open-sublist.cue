package repro

// `list.FlattenN` descends into nested sublists, splicing their elements. An open-tail
// sublist `[1,2,...]` presents its concrete prefix to that descent, consistent with
// `len([1,2,...]) = 3` and the top-level open-list rule (LIST-OPS-PROBE). kue previously
// matched only `.list` when peeling a level, so an open-tail sublist was emitted UNFLATTENED
// (a SILENT WRONG value: `[[1,2],3]` instead of `[1,2,3]`), and the full-flatten depth
// (`FlattenN(_, -1)`) undercounted nesting through a `.listTail` carrier. The fix normalizes
// the `.listTail` prefix wherever the flatten descends AND where nesting depth is measured.
import "list"

one:      list.FlattenN([[1, 2, ...], [3]], 1)
deep:     list.FlattenN([[1, [2, ...]], 3], 2)
full:     list.FlattenN([[1, 2, ...], [3]], -1)
deepFull: list.FlattenN([[1, [2, ...]]], -1)
