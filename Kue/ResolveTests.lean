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

theorem resolve_reference_inside_list :
    (resolveStructRefs
      (.struct [("#A", .definition, .kind .int), ("x", .regular, .list [.ref "#A"])] true)
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .list [.refId ⟨0⟩])] true) = true := by
  native_decide

theorem eval_resolved_reference_inside_list :
    (evalStructRefs
      (resolveStructRefs
        (.struct [("#A", .definition, .kind .int), ("x", .regular, .list [.ref "#A"])] true))
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .list [.kind .int])] true) = true := by
  native_decide

theorem resolve_reference_inside_conjunction :
    (resolveStructRefs
      (.struct [("#A", .definition, .kind .int), ("x", .regular, .conj [.ref "#A", .intGe 0])] true)
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .conj [.refId ⟨0⟩, .intGe 0])] true) = true := by
  native_decide

theorem resolve_reference_inside_disjunction :
    (resolveStructRefs
      (.struct [("#A", .definition, .kind .int), ("x", .regular, .disj [(.regular, .ref "#A"), (.regular, .kind .string)])] true)
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .disj [(.regular, .refId ⟨0⟩), (.regular, .kind .string)])] true) = true := by
  native_decide

theorem resolve_reference_inside_struct_tail :
    (resolveStructRefs
      (.structTail [("#A", .definition, .kind .int)] (.ref "#A"))
      == .structTail [("#A", .definition, .kind .int)] (.refId ⟨0⟩)) = true := by
  native_decide

theorem resolve_reference_inside_struct_pattern :
    (resolveStructRefs
      (.structPattern [("#A", .definition, .kind .int)] (.ref "#A"))
      == .structPattern [("#A", .definition, .kind .int)] (.refId ⟨0⟩)) = true := by
  native_decide

end Kue
