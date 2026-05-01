import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

theorem format_closed_list :
    formatValue (.list [.prim (.int 1), .prim (.string "x")]) = "[1, \"x\"]" := by
  native_decide

theorem format_open_list_tail :
    formatValue (.listTail [.kind .int] (.kind .string)) = "[int, ...string]" := by
  native_decide

theorem meet_lists_elementwise :
    meet
      (.list [.kind .int, .kind .string])
      (.list [.prim (.int 1), .prim (.string "x")])
      = .list [.prim (.int 1), .prim (.string "x")] := by
  rfl

theorem meet_lists_preserves_element_bottom :
    meet
      (.list [.kind .int])
      (.list [.prim (.string "x")])
      = .list [.bottomWith [.kindConflict .int .string]] := by
  rfl

theorem meet_lists_different_lengths_bottom :
    meet
      (.list [.kind .int])
      (.list [.prim (.int 1), .prim (.int 2)])
      = .bottom := by
  rfl

theorem meet_open_list_tail_with_longer_closed_list :
    meet
      (.listTail [.kind .int] (.kind .string))
      (.list [.prim (.int 1), .prim (.string "x"), .prim (.string "y")])
      = .list [.prim (.int 1), .prim (.string "x"), .prim (.string "y")] := by
  rfl

theorem meet_open_list_tail_preserves_extra_bottom :
    meet
      (.listTail [.kind .int] (.kind .string))
      (.list [.prim (.int 1), .prim (.int 2)])
      = .list [.prim (.int 1), .bottomWith [.kindConflict .string .int]] := by
  rfl

theorem meet_struct_field_open_list_tail_with_longer_closed_list :
    meet
      (.struct [("x", .regular, .listTail [.kind .int] (.kind .string))] true)
      (.struct [("x", .regular, .list [.prim (.int 1), .prim (.string "x")])] true)
      = .struct [("x", .regular, .list [.prim (.int 1), .prim (.string "x")])] true := by
  rfl

theorem meet_struct_field_open_list_tail_preserves_extra_bottom :
    meet
      (.struct [("x", .regular, .listTail [.kind .int] (.kind .string))] true)
      (.struct [("x", .regular, .list [.prim (.int 1), .prim (.int 2)])] true)
      = .struct [("x", .regular, .list [.prim (.int 1), .bottomWith [.kindConflict .string .int]])] true := by
  rfl

theorem meet_struct_field_closed_list_uses_list_meet :
    meet
      (.struct [("x", .regular, .list [.kind .int, .kind .string])] true)
      (.struct [("x", .regular, .list [.prim (.int 1), .prim (.string "x")])] true)
      = .struct [("x", .regular, .list [.prim (.int 1), .prim (.string "x")])] true := by
  rfl

theorem meet_list_item_disjunction_distributes :
    meet
      (.list [.disj [(.regular, .kind .int), (.regular, .kind .string)]])
      (.list [.prim (.int 1)])
      = .list [.prim (.int 1)] := by
  rfl

theorem meet_open_list_tail_rejects_short_closed_list :
    meet
      (.listTail [.kind .int, .kind .string] (.kind .bool))
      (.list [.prim (.int 1)])
      = .bottom := by
  rfl

theorem list_subsumes_matching_items :
    subsumes
      (.list [.kind .int, .kind .string])
      (.list [.prim (.int 1), .prim (.string "x")])
      = true := by
  native_decide

theorem list_rejects_different_length :
    subsumes
      (.list [.kind .int])
      (.list [.prim (.int 1), .prim (.int 2)])
      = false := by
  native_decide

theorem open_list_tail_subsumes_matching_extra_items :
    subsumes
      (.listTail [.kind .int] (.kind .string))
      (.list [.prim (.int 1), .prim (.string "x"), .prim (.string "y")])
      = true := by
  native_decide

theorem open_list_tail_rejects_conflicting_extra_item :
    subsumes
      (.listTail [.kind .int] (.kind .string))
      (.list [.prim (.int 1), .prim (.int 2)])
      = false := by
  native_decide

end Kue
