package repro

// `list.Concat` destructures each element AS a sublist and concatenates them. An
// open-tail sublist `[1,2,...]` presents its concrete prefix `[1,2]` to that read,
// consistent with `len([1,2,...]) = 3` and the top-level open-list rule (LIST-OPS-PROBE)
// — the `...` marker governs only unification/closedness, never a value read. kue
// previously matched only `.list` when collecting sublists, so a `.listTail` element
// fell through to `none` and Concat leaked bottom. The normalization must reach the
// NESTED sublist, not just the top-level operand. An inner open-tail one level deeper
// (`[1,[2,...]]`) is preserved as an element (Concat flattens exactly one level); its
// `...` is stripped by the value read on export.
import "list"

basic:     list.Concat([[1, 2, ...], [3, 4]])
bothOpen:  list.Concat([[1, 2, ...], [3, 4], ...])
deepInner: list.Concat([[1, [2, ...]], [3]])
