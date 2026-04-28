import Kue.Order

namespace Kue

theorem top_subsumes_primitive :
    subsumes .top (.prim (.int 1)) = true := by
  native_decide

theorem kind_subsumes_matching_primitive :
    subsumes (.kind .int) (.prim (.int 1)) = true := by
  native_decide

theorem kind_does_not_subsume_other_primitive :
    subsumes (.kind .int) (.prim (.string "x")) = false := by
  native_decide

theorem primitive_subsumes_identical_primitive :
    subsumes (.prim (.int 1)) (.prim (.int 1)) = true := by
  native_decide

theorem primitive_does_not_subsume_distinct_primitive :
    subsumes (.prim (.int 1)) (.prim (.int 2)) = false := by
  native_decide

theorem value_subsumes_bottom :
    subsumes (.kind .int) .bottom = true := by
  native_decide

theorem disjunction_subsumes_matching_alternative :
    subsumes
      (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))])
      (.prim (.string "b"))
      = true := by
  native_decide

theorem closed_struct_subsumes_matching_struct :
    subsumes
      (.struct [("a", .regular, .kind .int)] false)
      (.struct [("a", .regular, .prim (.int 1))] false)
      = true := by
  native_decide

theorem closed_struct_rejects_extra_field :
    subsumes
      (.struct [("a", .regular, .kind .int)] false)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      = false := by
  native_decide

theorem open_struct_accepts_extra_field :
    subsumes
      (.struct [("a", .regular, .kind .int)] true)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      = true := by
  native_decide

end Kue
