package repro

// A `list.*` package function applied to an open-tail list operates on the
// concrete prefix, consistent with `len([1,2,3,...]) = 3`. The `.listTail`
// carrier previously fell through every `list.*` arm (they destructure `.list`
// only), leaking a residual `list.Reverse([1,2,3,...])` that failed export.
import "list"

rev: list.Reverse([1, 2, 3, ...])
sum: list.Sum([1, 2, 3, ...])
drop: list.Drop([1, 2, 3, ...], 1)
