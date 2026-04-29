import Kue.Manifest

namespace Kue

theorem manifest_primitive :
    manifest (.prim (.int 1)) = .ok (.prim (.int 1)) := by
  rfl

theorem manifest_concrete_list :
    manifest (.list [.prim (.int 1), .prim (.string "x")])
      = .ok (.list [.prim (.int 1), .prim (.string "x")]) := by
  rfl

theorem manifest_concrete_struct :
    manifest (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      = .ok (.struct [("a", .prim (.int 1)), ("b", .prim (.string "x"))]) := by
  rfl

theorem manifest_filters_non_output_fields :
    manifest
      (.struct
        [
          ("a", .regular, .prim (.int 1)),
          ("b", .optional, .prim (.int 2)),
          ("_c", .hidden, .prim (.int 3)),
          ("#D", .definition, .kind .int)
        ]
        true)
      = .ok (.struct [("a", .prim (.int 1))]) := by
  rfl

theorem manifest_incomplete_regular_field_fails :
    manifest (.struct [("a", .regular, .kind .int)] true)
      = .error (.incomplete (.kind .int)) := by
  rfl

theorem manifest_unsatisfied_required_field_fails :
    manifest (.struct [("a", .required, .prim (.int 1))] true)
      = .error (.incomplete (.prim (.int 1))) := by
  rfl

theorem manifest_kind_incomplete :
    manifest (.kind .int) = .error (.incomplete (.kind .int)) := by
  rfl

theorem manifest_top_incomplete :
    manifest .top = .error (.incomplete .top) := by
  rfl

theorem manifest_bottom_contradiction :
    manifest .bottom = .error .contradiction := by
  rfl

theorem manifest_ambiguous_disjunction :
    manifest (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))])
      = .error (.ambiguous [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))]) := by
  rfl

theorem manifest_selects_single_default :
    manifest (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
      = .ok (.prim (.string "prod")) := by
  rfl

theorem manifest_selects_struct_field_default :
    manifest
      (.struct
        [("mode", .regular, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])]
        true)
      = .ok (.struct [("mode", .prim (.string "prod"))]) := by
  rfl

theorem manifest_selects_list_item_default :
    manifest
      (.list [.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]])
      = .ok (.list [.prim (.string "prod")]) := by
  rfl

theorem manifest_default_override_after_regular_unification :
    manifest
      (meet
        (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
        (.prim (.string "dev")))
      = .ok (.prim (.string "dev")) := by
  rfl

end Kue
