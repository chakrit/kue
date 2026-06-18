import Kue.Manifest

namespace Kue

theorem manifest_primitive :
    manifest (.prim (.int 1)) = .ok (.prim (.int 1)) := by
  rfl

theorem manifest_concrete_list :
    manifest (.list [.prim (.int 1), .prim (.string "x")])
      = .ok (.list [.prim (.int 1), .prim (.string "x")]) := by
  rfl

theorem manifest_open_list_drops_tail :
    manifest (.listTail [.prim (.int 1)] .top)
      = .ok (.list [.prim (.int 1)]) := by
  rfl

theorem manifest_empty_open_list :
    manifest (.listTail [] .top)
      = .ok (.list []) := by
  rfl

theorem manifest_open_list_typed_tail_drops_tail :
    manifest (.listTail [.prim (.int 1), .prim (.int 2)] (.kind .int))
      = .ok (.list [.prim (.int 1), .prim (.int 2)]) := by
  rfl

theorem manifest_open_list_string_tail_keeps_prefix :
    manifest (.listTail [.prim (.int 1)] (.kind .string))
      = .ok (.list [.prim (.int 1)]) := by
  rfl

theorem manifest_open_list_non_concrete_prefix_incomplete :
    manifest (.listTail [.kind .int] .top)
      = .error (.incomplete (.kind .int)) := by
  rfl

theorem manifest_open_list_nested_in_struct :
    manifest (.struct [⟨"xs", .regular, .listTail [.prim (.int 1)] .top⟩] .regularOpen none [])
      = .ok (.struct [("xs", .list [.prim (.int 1)])]) := by
  rfl

theorem manifest_concrete_struct :
    manifest (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = .ok (.struct [("a", .prim (.int 1)), ("b", .prim (.string "x"))]) := by
  rfl

theorem manifest_string_pattern_struct_outputs_regular_fields :
    manifest (.struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [((.kind .string), (.kind .int))])
      = .ok (.struct [("a", .prim (.int 1))]) := by
  rfl

theorem manifest_filters_non_output_fields :
    manifest
      (.struct [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"b", .optional, .prim (.int 2)⟩,
          ⟨"_c", .hidden, .prim (.int 3)⟩,
          ⟨"#D", .definition, .kind .int⟩
        ] .regularOpen none [])
      = .ok (.struct [("a", .prim (.int 1))]) := by
  rfl

theorem manifest_incomplete_regular_field_fails :
    manifest (.struct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
      = .error (.incomplete (.kind .int)) := by
  rfl

theorem manifest_unsatisfied_required_field_fails :
    manifest (.struct [⟨"a", .required, .prim (.int 1)⟩] .regularOpen none [])
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
    (manifest (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))])
      == .error (.ambiguous [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))])) = true := by
  native_decide

theorem manifest_selects_single_default :
    (manifest (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
      == .ok (.prim (.string "prod"))) = true := by
  native_decide

theorem manifest_selects_struct_field_default :
    (manifest
      (.struct [⟨"mode", .regular, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
      == .ok (.struct [("mode", .prim (.string "prod"))])) = true := by
  native_decide

theorem manifest_selects_list_item_default :
    (manifest
      (.list [.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]])
      == .ok (.list [.prim (.string "prod")])) = true := by
  native_decide

theorem manifest_default_override_after_regular_unification :
    manifest
      (meet
        (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
        (.prim (.string "dev")))
      = .ok (.prim (.string "dev")) := by
  rfl

theorem manifest_ignores_absent_optional_default :
    manifest
      (.struct [⟨"mode", .optional, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
      = .ok (.struct []) := by
  rfl

theorem manifest_selects_optional_default_when_regular_field_exists :
    (manifest
      (meet
        (.struct [⟨"mode", .optional, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
        (.struct [⟨"mode", .regular, .top⟩] .regularOpen none []))
      == .ok (.struct [("mode", .prim (.string "prod"))])) = true := by
  native_decide

theorem manifest_unsatisfied_required_default_fails :
    manifest
      (.struct [⟨"mode", .required, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
      = .error (.incomplete (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])) := by
  rfl

theorem manifest_selects_required_default_when_regular_field_exists :
    (manifest
      (meet
        (.struct [⟨"mode", .required, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
        (.struct [⟨"mode", .regular, .top⟩] .regularOpen none []))
      == .ok (.struct [("mode", .prim (.string "prod"))])) = true := by
  native_decide

end Kue
