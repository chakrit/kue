import Kue.Eval
import Kue.Resolve

namespace Kue

theorem resolve_same_struct_reference_to_binding_id :
    (resolveStructRefs
      (.struct [("#A", .definition, .kind .int), ("x", .regular, .ref "#A")] true)
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .refId ⟨0, 0⟩)] true) = true := by
  native_decide

theorem resolve_reference_uses_first_matching_binding :
    (resolveStructRefs
      (.struct [("same", .definition, .kind .int), ("same", .regular, .kind .string), ("x", .regular, .ref "same")] true)
      == .struct [("same", .definition, .kind .int), ("same", .regular, .kind .string), ("x", .regular, .refId ⟨0, 0⟩)] true) = true := by
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
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .list [.refId ⟨0, 0⟩])] true) = true := by
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
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .conj [.refId ⟨0, 0⟩, .intGe 0])] true) = true := by
  native_decide

theorem resolve_reference_inside_disjunction :
    (resolveStructRefs
      (.struct [("#A", .definition, .kind .int), ("x", .regular, .disj [(.regular, .ref "#A"), (.regular, .kind .string)])] true)
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .disj [(.regular, .refId ⟨0, 0⟩), (.regular, .kind .string)])] true) = true := by
  native_decide

theorem resolve_reference_inside_struct_tail :
    (resolveStructRefs
      (.structTail [("#A", .definition, .kind .int)] (.ref "#A"))
      == .structTail [("#A", .definition, .kind .int)] (.refId ⟨0, 0⟩)) = true := by
  native_decide

theorem resolve_reference_inside_struct_pattern :
    (resolveStructRefs
      (.structPattern [("#A", .definition, .kind .int)] (.kind .string) (.ref "#A") true)
      == .structPattern [("#A", .definition, .kind .int)] (.kind .string) (.refId ⟨0, 0⟩) true) = true := by
  native_decide

theorem resolve_inner_reference_to_outer_field :
    (resolveStructRefs
      (.struct [("a", .regular, .kind .int),
                ("b", .regular, .struct [("c", .regular, .ref "a")] true)] true)
      == .struct [("a", .regular, .kind .int),
                  ("b", .regular, .struct [("c", .regular, .refId ⟨1, 0⟩)] true)] true) = true := by
  native_decide

theorem resolve_inner_reference_prefers_nearest_scope :
    (resolveStructRefs
      (.struct [("a", .regular, .kind .int),
                ("b", .regular, .struct [("a", .regular, .kind .string), ("c", .regular, .ref "a")] true)] true)
      == .struct [("a", .regular, .kind .int),
                  ("b", .regular, .struct [("a", .regular, .kind .string), ("c", .regular, .refId ⟨0, 0⟩)] true)] true) = true := by
  native_decide

theorem eval_inner_reference_to_outer_field :
    (evalStructRefs
      (resolveStructRefs
        (.struct [("a", .regular, .prim (.int 1)),
                  ("b", .regular, .struct [("c", .regular, .ref "a")] true)] true))
      == .struct [("a", .regular, .prim (.int 1)),
                  ("b", .regular, .struct [("c", .regular, .prim (.int 1))] true)] true) = true := by
  native_decide

end Kue
