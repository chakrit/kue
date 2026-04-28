import Kue.Eval
import Kue.Resolve

namespace Kue

theorem resolve_same_struct_reference_to_binding_id :
    (resolveStructRefs
      (.struct [("#A", .definition, .kind .int), ("x", .regular, .ref "#A")] true)
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .refId ⟨0⟩)] true) = true := by
  native_decide

theorem resolve_reference_uses_first_matching_binding :
    (resolveStructRefs
      (.struct [("same", .definition, .kind .int), ("same", .regular, .kind .string), ("x", .regular, .ref "same")] true)
      == .struct [("same", .definition, .kind .int), ("same", .regular, .kind .string), ("x", .regular, .refId ⟨0⟩)] true) = true := by
  native_decide

theorem resolve_missing_reference_keeps_label_reference :
    (resolveStructRefs
      (.struct [("x", .regular, .ref "#Missing")] true)
      == .struct [("x", .regular, .ref "#Missing")] true) = true := by
  native_decide

theorem eval_after_resolve_reference_to_definition :
    (evalStructRefs
      (resolveStructRefs
        (.struct [("#A", .definition, .kind .int), ("x", .regular, .ref "#A")] true))
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .kind .int)] true) = true := by
  native_decide

end Kue
