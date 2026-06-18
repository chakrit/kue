package main

// F2 site 2 — the NON-definition lazy-merge case: a comprehension struct met with a use-site
// narrowing. The `if x > 0` guard must fire AFTER the meet lands `x: 5`, so `y` appears — the same
// comprehension-loss class as the forced-def site, on the regular-struct path. `_M` is hidden (not
// output); only `out` manifests. Before F2 `_M` evaluated eagerly (guard dropped against `x: int`)
// then met → `{x: 5}`.
_M: {x: int, if x > 0 {y: x}}
out: _M & {x: 5}
