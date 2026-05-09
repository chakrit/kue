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

theorem eval_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2))),
            ("diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3))),
            ("cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b")))
          ]
          true))
      = "sum: 3\ndiff: 2\ncat: \"ab\"" := by
  native_decide

theorem eval_multiplication_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("mul", .regular, .binary .mul (.prim (.int 3)) (.prim (.int 4))),
            (
              "precedence",
              .regular,
              .binary .add (.prim (.int 1)) (.binary .mul (.prim (.int 2)) (.prim (.int 3)))
            )
          ]
          true))
      = "mul: 12\nprecedence: 7" := by
  native_decide

theorem eval_division_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("div", .regular, .binary .div (.prim (.int 5)) (.prim (.int 2))),
            ("whole", .regular, .binary .div (.prim (.int 6)) (.prim (.int 3))),
            ("third", .regular, .binary .div (.prim (.int 1)) (.prim (.int 3))),
            ("negative", .regular, .binary .div (.prim (.int (-5))) (.prim (.int 2)))
          ]
          true))
      = "div: 2.5\nwhole: 2.0\nthird: 0.3333333333333333333333333333333333\nnegative: -2.5" := by
  native_decide

theorem eval_division_by_zero_bottom :
    evalBinary .div (.prim (.int 1)) (.prim (.int 0)) = .bottomWith [.divisionByZero] := by
  rfl

theorem eval_equality_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("same", .regular, .binary .eq (.prim (.int 1)) (.prim (.int 1))),
            ("diff", .regular, .binary .ne (.prim (.int 1)) (.prim (.int 2))),
            ("text", .regular, .binary .eq (.prim (.string "a")) (.prim (.string "b")))
          ]
          true))
      = "same: true\ndiff: true\ntext: false" := by
  native_decide

theorem eval_ordering_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("lt", .regular, .binary .lt (.prim (.int 1)) (.prim (.int 2))),
            ("le", .regular, .binary .le (.prim (.int 2)) (.prim (.int 2))),
            ("gt", .regular, .binary .gt (.prim (.int 3)) (.prim (.int 2))),
            ("ge", .regular, .binary .ge (.prim (.int 3)) (.prim (.int 4))),
            ("slt", .regular, .binary .lt (.prim (.string "a")) (.prim (.string "b")))
          ]
          true))
      = "lt: true\nle: true\ngt: true\nge: false\nslt: true" := by
  native_decide

theorem eval_logical_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("andFalse", .regular, .binary .boolAnd (.prim (.bool true)) (.prim (.bool false))),
            ("orTrue", .regular, .binary .boolOr (.prim (.bool false)) (.prim (.bool true))),
            (
              "andCmp",
              .regular,
              .binary .boolAnd
                (.binary .lt (.prim (.int 1)) (.prim (.int 2)))
                (.binary .gt (.prim (.int 3)) (.prim (.int 2)))
            )
          ]
          true))
      = "andFalse: false\norTrue: true\nandCmp: true" := by
  native_decide

theorem eval_logical_not_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("notFalse", .regular, .unary .boolNot (.prim (.bool false))),
            ("notCmp", .regular, .unary .boolNot (.binary .lt (.prim (.int 1)) (.prim (.int 2)))),
            ("double", .regular, .unary .boolNot (.unary .boolNot (.prim (.bool true))))
          ]
          true))
      = "notFalse: true\nnotCmp: false\ndouble: true" := by
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
