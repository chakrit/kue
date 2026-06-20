import Kue.Tests.EvalTestHelpers

/-! # `list.Sort` / `list.SortStable` pins (BI-2)

Carved out of `EvalTests.lean` (test-org pass). The comparator is a `{x, y, less}` struct
evaluated per pair; `list.Ascending`/`list.Descending` are the predefined comparator values.
End-to-end (parse → resolve → eval), since the sort is driven from the eval layer (the pure
`Builtin` layer cannot evaluate the comparator). Each `.expected` is cue v0.16.1-cross-checked. -/

namespace Kue

theorem eval_list_sort_ascending :
    evalSourceMatches "import \"list\"\nout: list.Sort([3, 1, 2], list.Ascending)\n" "out: [1, 2, 3]"
      = true := by
  native_decide

theorem eval_list_sort_descending :
    evalSourceMatches "import \"list\"\nout: list.Sort([1, 3, 2], list.Descending)\n" "out: [3, 2, 1]"
      = true := by
  native_decide

theorem eval_list_sort_already_sorted :
    evalSourceMatches "import \"list\"\nout: list.Sort([1, 2, 3], list.Ascending)\n" "out: [1, 2, 3]"
      = true := by
  native_decide

theorem eval_list_sort_empty :
    evalSourceMatches "import \"list\"\nout: list.Sort([], list.Ascending)\n" "out: []"
      = true := by
  native_decide

theorem eval_list_sort_single :
    evalSourceMatches "import \"list\"\nout: list.Sort([5], list.Ascending)\n" "out: [5]"
      = true := by
  native_decide

theorem eval_list_sort_duplicates :
    evalSourceMatches "import \"list\"\nout: list.Sort([3, 1, 2, 1, 3], list.Ascending)\n"
        "out: [1, 1, 2, 3, 3]"
      = true := by
  native_decide

theorem eval_list_sort_strings :
    evalSourceMatches
        "import \"list\"\nout: list.Sort([\"banana\", \"apple\", \"cherry\"], list.Ascending)\n"
        "out: [\"apple\", \"banana\", \"cherry\"]"
      = true := by
  native_decide

-- An inline comparator (no `list.Ascending`): the `{x, y, less}` struct works directly.
theorem eval_list_sort_inline_comparator :
    evalSourceMatches "import \"list\"\nout: list.Sort([3, 1, 2], {x: _, y: _, less: x < y})\n"
        "out: [1, 2, 3]"
      = true := by
  native_decide

-- A comparator over a sub-field of struct elements.
theorem eval_list_sort_by_field :
    evalSourceMatches
        "import \"list\"\nout: list.Sort([{k: 3}, {k: 1}, {k: 2}], {x: {k: _}, y: {k: _}, less: x.k < y.k})\n"
        "out: [{k: 1}, {k: 2}, {k: 3}]"
      = true := by
  native_decide

-- SortStable STABILITY: equal-key elements keep their input order (`a` before `b` before `d`,
-- all key 1). A discriminating fixture — an unstable sort could reorder the ties.
theorem eval_list_sort_stable_keeps_tie_order :
    evalSourceMatches
        ("import \"list\"\n"
          ++ "out: list.SortStable("
          ++ "[{k: 1, v: \"a\"}, {k: 1, v: \"b\"}, {k: 0, v: \"c\"}, {k: 1, v: \"d\"}], "
          ++ "{x: {k: _}, y: {k: _}, less: x.k < y.k})\n")
        ("out: [{k: 0, v: \"c\"}, {k: 1, v: \"a\"}, {k: 1, v: \"b\"}, {k: 1, v: \"d\"}]")
      = true := by
  native_decide

-- An incomparable comparator (`<` on structs) is a cue error; Kue bottoms, not a bogus order.
theorem eval_list_sort_incomparable_bottoms :
    evalSourceMatches "import \"list\"\nout: list.Sort([{a: 1}, {a: 2}], list.Ascending)\n" "out: _|_"
      = true := by
  native_decide

-- A concrete non-list first argument is a cue type error (`cannot use 5 as list`); Kue bottoms.
theorem eval_list_sort_non_list_bottoms :
    evalSourceMatches "import \"list\"\nout: list.Sort(5, list.Ascending)\n" "out: _|_"
      = true := by
  native_decide

-- The predefined comparator VALUES resolve as structs (used standalone, not only inside Sort).
theorem eval_list_ascending_is_comparator_struct :
    evalSourceMatches "import \"list\"\nout: list.Ascending\n"
        "out: {T: number | string, x: number | string, y: number | string, less: number | string < number | string}"
      = true := by
  native_decide

end Kue
