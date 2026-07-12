package repro

import "list"

// `runSort` (`Kue/Eval.lean`) matched ONLY `.list items`, so `list.Sort`/`SortStable` on a
// `.embeddedList` (`{[3,1,2], _y: 9}`) or `.listTail` (`[3,1,2, ...int]`) operand fell to the
// non-list branch and DEFERRED ("incomplete value") instead of sorting — the 5th carrier-miss,
// this one on the effectful `EvalM` path (`evalListBuiltin`'s `openListOperand` normalization
// never reached it). A struct-embedded / open-tail list IS the list `[3,1,2]` (the hidden `_y`
// and the `...` tail govern only unification/closedness, never a value read), so Sort is
// prefix-based: cue v0.16.1 agrees, sorting the concrete prefix to `[1,2,3]`. Spec-adjudicated.
// Fix routes `runSort` through `listItems?` (all three carriers descend by construction).
// Regression: plain `.list` Sort still sorts. Provenance: 2026-07-13 Phase A audit.

embedded:       list.Sort({[3, 1, 2], _y: 9}, list.Ascending)
embeddedStable: list.SortStable({[3, 1, 2], _y: 9}, list.Ascending)
openTail:       list.Sort([3, 1, 2, ...int], list.Ascending)
plainList:      list.Sort([3, 1, 2], list.Ascending)
