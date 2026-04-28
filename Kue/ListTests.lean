import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

theorem format_closed_list :
    formatValue (.list [.prim (.int 1), .prim (.string "x")]) = "[1, \"x\"]" := by
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

end Kue
