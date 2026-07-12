import Kue.Tests.EvalTestHelpers
import Kue.Tests.ParseTests

namespace Kue

-- List slicing `x[lo:hi]` (half-open, 0-based; bounds optional). Parses as a postfix form
-- alongside indexing `x[i]` and desugars to the core `slice` builtin — a language operator
-- distinct from the import-gated public `list.Slice`, so slicing needs no `import "list"`. It
-- inherits cue's bounds/negative/incomplete semantics. Oracle: cue v0.16.1.

-- Valid slices (CUE-syntax eval keeps the concrete sublist).
theorem slice_interior :
    evalSourceMatches "out: [1, 2, 3, 4][1:3]\n" "out: [2, 3]" = true := by native_decide

theorem slice_empty_equal_bounds :
    evalSourceMatches "out: [1, 2, 3, 4][2:2]\n" "out: []" = true := by native_decide

theorem slice_whole :
    evalSourceMatches "out: [1, 2, 3, 4][0:4]\n" "out: [1, 2, 3, 4]" = true := by native_decide

theorem slice_omitted_low :
    evalSourceMatches "out: [10, 20, 30, 40][:2]\n" "out: [10, 20]" = true := by native_decide

theorem slice_omitted_high :
    evalSourceMatches "out: [10, 20, 30, 40][1:]\n" "out: [20, 30, 40]" = true := by native_decide

theorem slice_both_omitted :
    evalSourceMatches "out: [7, 8, 9][:]\n" "out: [7, 8, 9]" = true := by native_decide

-- Single-index `x[i]` regression guard: the slice form must not disturb plain indexing.
theorem index_still_selects_element :
    evalSourceMatches "out: [1, 2, 3, 4][2]\n" "out: 3" = true := by native_decide

-- Bounds errors → bottom (cue: `index N out of range` / `cannot convert negative number to
-- uint64` / `invalid slice index: lo > hi`; all bottom on our side).
theorem slice_high_out_of_range_bottoms :
    exportJsonBottoms "out: [1, 2, 3, 4][1:10]\n" = true := by native_decide

theorem slice_negative_low_bottoms :
    exportJsonBottoms "out: [1, 2, 3, 4][-1:2]\n" = true := by native_decide

theorem slice_low_gt_high_bottoms :
    exportJsonBottoms "out: [1, 2, 3, 4][3:1]\n" = true := by native_decide

-- A string operand is NOT sliceable (cue: `cannot slice "hello" (type string)`) → bottom.
theorem slice_string_operand_bottoms :
    exportJsonBottoms "out: \"hello\"[1:3]\n" = true := by native_decide

-- An incomplete bound DEFERS (residual `slice`), not bottom — the guard that a non-concrete
-- index keeps the slice open for a later pass rather than erroring eagerly.
theorem slice_incomplete_index_defers :
    evalSourceMatches "x: int\nl: [1, 2, 3, 4]\nout: l[x:2]\n"
      "x: int\nl: [1, 2, 3, 4]\nout: slice([1, 2, 3, 4], int, 2)" = true := by
  native_decide

-- Open-tail list `[a,b,c,...]` slices like its concrete prefix (`len` = prefix count): the
-- `...` marker governs only closedness, never a value-level read. Result is the closed
-- sub-list; a high bound past the prefix is out of range → bottom.
theorem slice_open_tail_interior :
    evalSourceMatches "out: [1, 2, 3, ...][1:3]\n" "out: [2, 3]" = true := by native_decide

theorem slice_open_tail_omitted_high :
    evalSourceMatches "out: [1, 2, 3, ...][1:]\n" "out: [2, 3]" = true := by native_decide

theorem slice_open_tail_past_prefix_bottoms :
    exportJsonBottoms "out: [1, 2, 3, ...][1:5]\n" = true := by native_decide

-- Parser: every slice form parses, and a nested slice-then-index chains.
theorem slice_forms_parse :
    (parseSucceeds "out: [1, 2, 3, 4][1:3]\n"
      && parseSucceeds "out: [1, 2, 3, 4][:2]\n"
      && parseSucceeds "out: [1, 2, 3, 4][1:]\n"
      && parseSucceeds "out: [1, 2, 3, 4][:]\n"
      && parseSucceeds "out: [1, 2, 3, 4][1:3][0]\n") = true := by native_decide

-- COVERAGE TRIPWIRE (test-health): anchors the last theorem so a swallowed section fails
-- `#check` elaboration.
#check @slice_forms_parse

end Kue
