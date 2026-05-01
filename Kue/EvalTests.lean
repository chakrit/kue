import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve

namespace Kue

theorem format_unresolved_ref :
    formatValue (.ref "#A") = "#A" := by
  native_decide

theorem manifest_unresolved_ref_incomplete :
    manifest (.ref "#A") = .error (.incomplete (.ref "#A")) := by
  rfl

theorem eval_regular_field_reference_to_definition :
    (evalStructRefs
      (.struct [("#A", .definition, .kind .int), ("x", .regular, .ref "#A")] true)
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .kind .int)] true) = true := by
  native_decide

theorem eval_missing_reference_bottom :
    (evalStructRefs
      (.struct [("x", .regular, .ref "#Missing")] true)
      == .struct [("x", .regular, .bottomWith [.unresolvedReference "#Missing"])] true) = true := by
  native_decide

theorem eval_resolved_reference_by_binding_id :
    (evalStructRefs
      (.struct [("#A", .definition, .kind .int), ("x", .regular, .refId ⟨0⟩)] true)
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .kind .int)] true) = true := by
  native_decide

theorem eval_missing_binding_id_bottom :
    (evalStructRefs
      (.struct [("x", .regular, .refId ⟨2⟩)] true)
      == .struct [("x", .regular, .bottomWith [.unresolvedBinding ⟨2⟩])] true) = true := by
  native_decide

theorem eval_binding_id_not_label_lookup :
    (evalStructRefs
      (.struct [("same", .definition, .kind .int), ("same", .regular, .kind .string), ("x", .regular, .refId ⟨1⟩)] true)
      == .struct [("same", .definition, .kind .int), ("same", .regular, .kind .string), ("x", .regular, .kind .string)] true) = true := by
  native_decide

theorem resolve_direct_self_reference :
    (resolveStructRefs
      (.struct [("x", .regular, .ref "x")] true)
      == .struct [("x", .regular, .refId ⟨0⟩)] true) = true := by
  native_decide

theorem eval_direct_self_reference_as_top :
    (evalStructRefs
      (resolveStructRefs (.struct [("x", .regular, .ref "x")] true))
      == .struct [("x", .regular, .top)] true) = true := by
  native_decide

theorem eval_mutual_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs (.struct [("x", .regular, .ref "y"), ("y", .regular, .ref "x")] true))
      == .struct [("x", .regular, .top), ("y", .regular, .top)] true) = true := by
  native_decide

theorem eval_three_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ("x", .regular, .ref "y"),
            ("y", .regular, .ref "z"),
            ("z", .regular, .ref "x")
          ]
          true))
      == .struct [("x", .regular, .top), ("y", .regular, .top), ("z", .regular, .top)] true) = true := by
  native_decide

theorem eval_non_cycle_reference_still_uses_target_value :
    (evalStructRefs
      (resolveStructRefs (.struct [("x", .regular, .kind .int), ("y", .regular, .ref "x")] true))
      == .struct [("x", .regular, .kind .int), ("y", .regular, .kind .int)] true) = true := by
  native_decide

theorem eval_regular_field_reference_to_hidden :
    (evalStructRefs
      (resolveStructRefs (.struct [("_secret", .hidden, .prim (.string "x")), ("value", .regular, .ref "_secret")] true))
      == .struct [("_secret", .hidden, .prim (.string "x")), ("value", .regular, .prim (.string "x"))] true) = true := by
  native_decide

theorem eval_reference_inside_struct_tail :
    (evalStructRefs
      (resolveStructRefs (.structTail [("#A", .definition, .kind .int)] (.ref "#A")))
      == .structTail [("#A", .definition, .kind .int)] (.kind .int)) = true := by
  native_decide

theorem eval_reference_inside_struct_pattern :
    (evalStructRefs
      (resolveStructRefs (.structPattern [("#A", .definition, .kind .int)] (.kind .string) (.ref "#A")))
      == .structPattern [("#A", .definition, .kind .int)] (.kind .string) (.kind .int)) = true := by
  native_decide

end Kue
