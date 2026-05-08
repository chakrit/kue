import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime

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

theorem eval_static_field_selector :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("base", .regular, .struct [("inner", .regular, .prim (.int 4))] true),
            ("x", .regular, .selector (.ref "base") "inner")
          ]
          true))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

theorem eval_static_list_index :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("xs", .regular, .list [.prim (.int 10), .prim (.int 20)]),
            ("x", .regular, .index (.ref "xs") (.prim (.int 1)))
          ]
          true))
      = "xs: [10, 20]\nx: 20" := by
  native_decide

theorem eval_static_string_field_index :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("base", .regular, .struct [("inner", .regular, .prim (.int 4))] true),
            ("x", .regular, .index (.ref "base") (.prim (.string "inner")))
          ]
          true))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

theorem eval_list_index_out_of_range_bottom :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ("xs", .regular, .list [.prim (.int 10)]),
            ("x", .regular, .index (.ref "xs") (.prim (.int 2)))
          ]
          true))
      == .struct
        [
          ("xs", .regular, .list [.prim (.int 10)]),
          ("x", .regular, .bottomWith [.indexOutOfRange 2 1])
        ]
        true) = true := by
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

theorem eval_direct_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs (.struct [("x", .regular, .conj [.ref "x", .intGe 0])] true))
      == .struct [("x", .regular, .intGe 0)] true) = true := by
  native_decide

theorem eval_mutual_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ("a", .regular, .conj [.ref "b", .intGe 0]),
            ("b", .regular, .ref "a")
          ]
          true))
      == .struct [("a", .regular, .intGe 0), ("b", .regular, .intGe 0)] true) = true := by
  native_decide

theorem eval_non_cycle_reference_still_uses_target_value :
    (evalStructRefs
      (resolveStructRefs (.struct [("x", .regular, .kind .int), ("y", .regular, .ref "x")] true))
      == .struct [("x", .regular, .kind .int), ("y", .regular, .kind .int)] true) = true := by
  native_decide

theorem eval_regular_disjunction_uses_join_normalization :
    (evalStructRefs
      (.struct [("x", .regular, .disj [(.regular, .intGe 5), (.regular, .intGe 0)])] true)
      == .struct [("x", .regular, .intGe 0)] true) = true := by
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

theorem eval_reference_inside_nested_struct :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [("x", .regular, .struct [("#A", .definition, .kind .int), ("x", .regular, .ref "#A")] true)]
          true))
      == .struct
        [("x", .regular, .struct [("#A", .definition, .kind .int), ("x", .regular, .kind .int)] true)]
        true) = true := by
  native_decide

theorem eval_reference_inside_struct_pattern :
    (evalStructRefs
      (resolveStructRefs (.structPattern [("#A", .definition, .kind .int)] (.kind .string) (.ref "#A") true))
      == .structPattern [("#A", .definition, .kind .int)] (.kind .string) (.kind .int) true) = true := by
  native_decide

theorem eval_struct_pattern_constrains_own_regular_field :
    (evalStructRefs
      (.structPattern [("a", .regular, .prim (.string "bad"))] (.kind .string) (.kind .int) true)
      == .structPattern
        [("a", .regular, .bottomWith [.fieldConstraint "a"])]
        (.kind .string)
        (.kind .int)
        true) = true := by
  native_decide

theorem eval_len_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (.struct [("x", .regular, .prim (.string "abc")), ("y", .regular, .builtinCall "len" [.ref "x"])] true))
      == .struct [("x", .regular, .prim (.string "abc")), ("y", .regular, .prim (.int 3))] true) = true := by
  native_decide

theorem eval_integer_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ("n", .regular, .prim (.int (-7))),
            ("q", .regular, .builtinCall "div" [.ref "n", .prim (.int 3)])
          ]
          true))
      == .struct [("n", .regular, .prim (.int (-7))), ("q", .regular, .prim (.int (-3)))] true) = true := by
  native_decide

theorem eval_incomplete_builtin_call_remains_call :
    (evalStructRefs (.struct [("x", .regular, .builtinCall "len" [.kind .string])] true)
      == .struct [("x", .regular, .builtinCall "len" [.kind .string])] true) = true := by
  native_decide

end Kue
