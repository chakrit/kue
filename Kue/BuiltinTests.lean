import Kue.Builtin
import Kue.Lattice

namespace Kue

theorem close_value_marks_struct_closed :
    closeValue (.struct [("a", .regular, .kind .int)] true)
      = .struct [("a", .regular, .kind .int)] false := by
  rfl

theorem close_value_rejects_extra_field_after_meet :
    meet
      (closeValue (.struct [("a", .regular, .kind .int)] true))
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true)
      =
        .struct
          [
            ("a", .regular, .prim (.int 1)),
            ("b", .regular, .bottomWith [.fieldNotAllowed "b"])
          ]
          false := by
  rfl

theorem close_value_is_shallow_for_nested_regular_structs :
    closeValue
      (.struct [("a", .regular, .struct [("b", .regular, .kind .int)] true)] true)
      = .struct [("a", .regular, .struct [("b", .regular, .kind .int)] true)] false := by
  rfl

end Kue
