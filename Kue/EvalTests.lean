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
      (resolveStructRefs
        (.struct [("#A", .definition, .kind .int), ("x", .regular, .ref "#A")] true))
      == .struct [("#A", .definition, .kind .int), ("x", .regular, .kind .int)] true) = true := by
  native_decide

theorem eval_missing_reference_bottom :
    (evalStructRefs
      (.struct [("x", .regular, .ref "#Missing")] true)
      == .struct [("x", .regular, .bottomWith [.unresolvedReference "#Missing"])] true) = true := by
  native_decide

theorem eval_resolved_reference_by_binding_id :
    (evalStructRefs
      (.struct [("#A", .definition, .kind .int), ("x", .regular, .refId ⟨0, 0⟩)] true)
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

-- Memoization regression pins. Evaluation now shares computed-once results via a
-- frame-id-keyed cache; these prove the cache is behavior-preserving on the shapes it
-- targets — repeated selection into a shared sub-struct, and a cycle reached through such
-- repeated selection (the cache must not let a mid-cycle partial leak as a wrong cached
-- value; cycle detection via `visited` must still fire identically).

theorem eval_shared_repeated_selection :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("base", .regular, .prim (.string "v")),
            ("components", .regular,
              .struct
                [
                  ("a", .regular, .struct [("who", .regular, .ref "base")] true),
                  ("b", .regular, .struct [("who", .regular, .ref "base")] true)
                ]
                true),
            ("aWho", .regular, .selector (.selector (.ref "components") "a") "who"),
            ("bWho", .regular, .selector (.selector (.ref "components") "b") "who")
          ]
          true))
      = "base: \"v\"\ncomponents: {a: {who: \"v\"}, b: {who: \"v\"}}\naWho: \"v\"\nbWho: \"v\"" := by
  native_decide

-- A direct self-cycle selected twice: caching must not turn the bounded-cycle `⊤` into a
-- wrong value, and both selections must agree. `x: x & {p: 1}` resolves the cycle to its
-- constraint; `p1`/`p2` select the same field from the cyclic struct.
theorem eval_cycle_with_repeated_selection :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("x", .regular, .conj [.ref "x", .struct [("p", .regular, .prim (.int 1))] true]),
            ("p1", .regular, .selector (.ref "x") "p"),
            ("p2", .regular, .selector (.ref "x") "p")
          ]
          true))
      = "x: {p: 1}\np1: 1\np2: 1" := by
  native_decide

theorem eval_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2))),
            ("diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3))),
            ("cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b"))),
            ("bytes", .regular, .binary .add (.prim (.bytes "ab")) (.prim (.bytes "cd")))
          ]
          true))
      = "sum: 3\ndiff: 2\ncat: \"ab\"\nbytes: 'abcd'" := by
  native_decide

theorem eval_float_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("floatSum", .regular, .binary .add (.prim (.float "1.5")) (.prim (.float "2.25"))),
            ("intFloat", .regular, .binary .add (.prim (.int 1)) (.prim (.float "2.5"))),
            ("floatSub", .regular, .binary .sub (.prim (.float "5.5")) (.prim (.int 2))),
            ("exp", .regular, .binary .add (.prim (.float "1e+3")) (.prim (.int 2))),
            ("small", .regular, .binary .add (.prim (.float "0.1")) (.prim (.float "0.2")))
          ]
          true))
      = "floatSum: 3.75\nintFloat: 3.5\nfloatSub: 3.5\nexp: 1002.0\nsmall: 0.3" := by
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

theorem eval_integer_keyword_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("divValue", .regular, .binary .intDiv (.prim (.int (-7))) (.prim (.int 3))),
            ("modValue", .regular, .binary .intMod (.prim (.int (-7))) (.prim (.int 3))),
            ("quoValue", .regular, .binary .intQuo (.prim (.int (-7))) (.prim (.int 3))),
            ("remValue", .regular, .binary .intRem (.prim (.int (-7))) (.prim (.int 3)))
          ]
          true))
      = "divValue: -3\nmodValue: 2\nquoValue: -2\nremValue: -1" := by
  native_decide

theorem eval_integer_keyword_incomplete_keeps_infix :
    formatValue (evalBinary .intDiv (.kind .int) (.prim (.int 3))) = "int div 3" := by
  native_decide

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

theorem eval_numeric_comparison_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("lt", .regular, .binary .lt (.prim (.float "1.5")) (.prim (.int 2))),
            ("le", .regular, .binary .le (.prim (.float "1.5")) (.prim (.float "1.50"))),
            ("gt", .regular, .binary .gt (.prim (.float "1e+3")) (.prim (.float "999.9"))),
            ("ge", .regular, .binary .ge (.prim (.float "1.0")) (.prim (.int 1))),
            ("eq", .regular, .binary .eq (.prim (.int 1)) (.prim (.float "1.0"))),
            ("ne", .regular, .binary .ne (.prim (.int 1)) (.prim (.float "1.0")))
          ]
          true))
      = "lt: true\nle: true\ngt: true\nge: true\neq: true\nne: false" := by
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

theorem eval_unary_numeric_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("negGroup", .regular, .unary .numNeg (.binary .add (.prim (.int 1)) (.prim (.int 2)))),
            ("posGroup", .regular, .unary .numPos (.binary .add (.prim (.int 1)) (.prim (.int 2)))),
            ("negFloat", .regular, .unary .numNeg (.prim (.float "1.5")))
          ]
          true))
      = "negGroup: -3\nposGroup: 3\nnegFloat: -1.5" := by
  native_decide

theorem eval_regex_match_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("match", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "^a"))),
            ("miss", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "z"))),
            ("notMatch", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "z")))
          ]
          true))
      = "match: true\nmiss: false\nnotMatch: true" := by
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
      (.struct [("x", .regular, .refId ⟨0, 2⟩)] true)
      == .struct [("x", .regular, .bottomWith [.unresolvedBinding ⟨0, 2⟩])] true) = true := by
  native_decide

theorem eval_binding_id_not_label_lookup :
    (evalStructRefs
      (.struct [("#same", .definition, .kind .int), ("same", .regular, .kind .string), ("x", .regular, .refId ⟨0, 1⟩)] true)
      == .struct [("#same", .definition, .kind .int), ("same", .regular, .kind .string), ("x", .regular, .kind .string)] true) = true := by
  native_decide

theorem resolve_direct_self_reference :
    (resolveStructRefs
      (.struct [("x", .regular, .ref "x")] true)
      == .struct [("x", .regular, .refId ⟨0, 0⟩)] true) = true := by
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
      (resolveStructRefs (.struct [("x", .regular, .conj [.ref "x", .boundConstraint 0 .ge])] true))
      == .struct [("x", .regular, .boundConstraint 0 .ge)] true) = true := by
  native_decide

theorem eval_mutual_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ("a", .regular, .conj [.ref "b", .boundConstraint 0 .ge]),
            ("b", .regular, .ref "a")
          ]
          true))
      == .struct [("a", .regular, .boundConstraint 0 .ge), ("b", .regular, .boundConstraint 0 .ge)] true) = true := by
  native_decide

theorem eval_non_cycle_reference_still_uses_target_value :
    (evalStructRefs
      (resolveStructRefs (.struct [("x", .regular, .kind .int), ("y", .regular, .ref "x")] true))
      == .struct [("x", .regular, .kind .int), ("y", .regular, .kind .int)] true) = true := by
  native_decide

/-- A value alias (`Self={…}`) lowers to a `.thisStruct` let-binding; `Self.field`
    (a selector on the binding) resolves as a same-struct sibling reference. Pins the
    eval-level `thisStruct` mechanism directly. -/
theorem eval_value_alias_self_reference :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ("Self", .letBinding, .thisStruct),
            ("x", .regular, .prim (.int 5)),
            ("y", .regular, .selector (.ref "Self") "x")
          ]
          true))
      == .struct
        [
          ("Self", .letBinding, .thisStruct),
          ("x", .regular, .prim (.int 5)),
          ("y", .regular, .prim (.int 5))
        ]
        true) = true := by
  native_decide

/-- A self-reference cycle through the alias is bounded to top, never diverging. -/
theorem eval_value_alias_cycle_bounds_to_top :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ("Self", .letBinding, .thisStruct),
            ("x", .regular, .selector (.ref "Self") "y"),
            ("y", .regular, .selector (.ref "Self") "x")
          ]
          true))
      == .struct
        [
          ("Self", .letBinding, .thisStruct),
          ("x", .regular, .top),
          ("y", .regular, .top)
        ]
        true) = true := by
  native_decide

theorem eval_regular_disjunction_uses_join_normalization :
    (evalStructRefs
      (.struct [("x", .regular, .disj [(.regular, .boundConstraint 5 .ge), (.regular, .boundConstraint 0 .ge)])] true)
      == .struct [("x", .regular, .boundConstraint 0 .ge)] true) = true := by
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

theorem string_kind_pattern_types_matching_field :
    (meet
      (.structPattern [] (.kind .string) (.kind .int) true)
      (.struct [("a", .regular, .prim (.int 1))] true)
      == .structPattern [("a", .regular, .prim (.int 1))] (.kind .string) (.kind .int) true) = true := by
  native_decide

theorem string_kind_pattern_rejects_type_mismatch :
    containsBottom
      (meet
        (.structPattern [] (.kind .string) (.kind .int) true)
        (.struct [("a", .regular, .prim (.string "x"))] true)) = true := by
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

theorem eval_comprehension_for_keyed_over_struct :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [
            .comprehension
              [.forIn (some "k") "v" (.struct [("x", .regular, .prim (.int 1))] true)]
              (.struct [("key", .regular, .ref "k"), ("val", .regular, .ref "v")] true)
          ]
          true))
      == .struct [("key", .regular, .prim (.string "x")), ("val", .regular, .prim (.int 1))] true)
      = true := by
  native_decide

theorem eval_comprehension_for_over_list :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [
            .comprehension
              [.forIn none "v" (.list [.prim (.int 42)])]
              (.struct [("only", .regular, .ref "v")] true)
          ]
          true))
      == .struct [("only", .regular, .prim (.int 42))] true) = true := by
  native_decide

theorem eval_comprehension_if_true_admits :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [.comprehension [.guard (.prim (.bool true))] (.struct [("flag", .regular, .prim (.bool true))] true)]
          true))
      == .struct [("flag", .regular, .prim (.bool true))] true) = true := by
  native_decide

theorem eval_comprehension_if_false_drops :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [.comprehension [.guard (.prim (.bool false))] (.struct [("hidden", .regular, .prim (.int 1))] true)]
          true))
      == .struct [] true) = true := by
  native_decide

theorem eval_comprehension_body_sees_sibling_field :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          [("base", .regular, .prim (.int 7))]
          [.comprehension [.guard (.prim (.bool true))] (.struct [("copy", .regular, .ref "base")] true)]
          true))
      == .struct [("base", .regular, .prim (.int 7)), ("copy", .regular, .prim (.int 7))] true)
      = true := by
  native_decide

theorem eval_comprehension_for_source_sees_sibling_field :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          [("k", .regular, .prim (.int 3))]
          [.comprehension [.forIn none "v" (.list [.ref "k"])] (.struct [("g", .regular, .ref "v")] true)]
          true))
      == .struct [("k", .regular, .prim (.int 3)), ("g", .regular, .prim (.int 3))] true)
      = true := by
  native_decide

/-- Was a deferred-bottom pin; float×float now evaluates exactly through the decimal
    layer. Scales add and CUE preserves the summed scale verbatim: `1.5 * 2.0 = 3.00`
    (oracle-confirmed, cue v0.16.1), no trailing-zero trim. -/
theorem eval_mul_two_floats :
    evalMul (.prim (.float "1.5")) (.prim (.float "2.0")) = .prim (.float "3.00") := by
  rfl

/-- Was a deferred-bottom pin; float÷float now evaluates through the decimal layer.
    `/` always yields a float; `3.0 / 2.0 = 1.5` terminates cleanly (oracle-confirmed,
    cue v0.16.1). -/
theorem eval_div_two_floats :
    (evalDiv (.prim (.float "3.0")) (.prim (.float "2.0")) == .prim (.float "1.5")) = true := by
  native_decide

/-- Multiplication preserves the full summed scale: `1.0 * 1.0 = 1.00`. -/
theorem eval_mul_scale_preserved :
    (evalMul (.prim (.float "1.0")) (.prim (.float "1.0")) == .prim (.float "1.00")) = true := by
  native_decide

/-- Mixed int×float promotes to float; int contributes scale 0. -/
theorem eval_mul_int_float :
    (evalMul (.prim (.int 2)) (.prim (.float "1.5")) == .prim (.float "3.0")) = true := by
  native_decide

/-- float×int likewise. -/
theorem eval_mul_float_int :
    (evalMul (.prim (.float "1.5")) (.prim (.int 2)) == .prim (.float "3.0")) = true := by
  native_decide

/-- Negative operand carries through multiplication. -/
theorem eval_mul_negative :
    (evalMul (.prim (.float "-1.5")) (.prim (.float "2.0")) == .prim (.float "-3.00")) = true := by
  native_decide

/-- int×int stays int (no float promotion). -/
theorem eval_mul_int_int :
    evalMul (.prim (.int 3)) (.prim (.int 4)) = .prim (.int 12) := by
  rfl

/-- Terminating division renders without padding. -/
theorem eval_div_terminating :
    (evalDiv (.prim (.float "1.0")) (.prim (.float "4.0")) == .prim (.float "0.25")) = true := by
  native_decide

/-- Clean division still yields a float, never an int: `4.0 / 2.0 = 2.0`. -/
theorem eval_div_clean_is_float :
    (evalDiv (.prim (.float "4.0")) (.prim (.float "2.0")) == .prim (.float "2.0")) = true := by
  native_decide

/-- Mixed float÷int promotes; `3.0 / 2 = 1.5`. -/
theorem eval_div_float_int :
    (evalDiv (.prim (.float "3.0")) (.prim (.int 2)) == .prim (.float "1.5")) = true := by
  native_decide

/-- Mixed int÷float promotes; `2 / 4.0 = 0.5`. -/
theorem eval_div_int_float :
    (evalDiv (.prim (.int 2)) (.prim (.float "4.0")) == .prim (.float "0.5")) = true := by
  native_decide

/-- Negative division carries the sign. -/
theorem eval_div_negative :
    (evalDiv (.prim (.float "-1.0")) (.prim (.float "4.0")) == .prim (.float "-0.25")) = true := by
  native_decide

/-- Float division by zero is bottom with divisionByZero provenance. -/
theorem eval_div_float_by_zero :
    (evalDiv (.prim (.float "1.0")) (.prim (.float "0.0")) == .bottomWith [.divisionByZero]) = true := by
  native_decide

/-- int÷int now routes through the same decimal divider and yields a float: `6 / 2 = 3.0`. -/
theorem eval_div_int_int_is_float :
    (evalDiv (.prim (.int 6)) (.prim (.int 2)) == .prim (.float "3.0")) = true := by
  native_decide

/-- Repeating-decimal division renders at 34 significant digits, round-half-up.
    `2.0 / 3.0 = 0.666…667` (34 sig digits). This is the apd-context subset that is
    now reachable; see compat-assumptions for the rounding-tie boundary. -/
theorem eval_div_repeating :
    (evalDiv (.prim (.float "2.0")) (.prim (.float "3.0"))
      == .prim (.float "0.6666666666666666666666666666666667")) = true := by
  native_decide

/-- Repeating division with an integer part rounds at 34 sig digits, not 34 frac
    digits: `10.0 / 3.0 = 3.33…3` (33 frac digits). Pins the significant-digit rule
    that the prior fixed-fraction int divider got wrong for quotients ≥ 1. -/
theorem eval_div_repeating_int_part :
    (evalDiv (.prim (.float "10.0")) (.prim (.float "3.0"))
      == .prim (.float "3.333333333333333333333333333333333")) = true := by
  native_decide

/-- Rounding carries past 9s: `100.0 / 7.0 = 14.28…29`, last digit rounded up. -/
theorem eval_div_repeating_round_up :
    (evalDiv (.prim (.float "100.0")) (.prim (.float "7.0"))
      == .prim (.float "14.28571428571428571428571428571429")) = true := by
  native_decide

/-- High-fuel pin: a full-34-significant-digit repeating quotient with no leading
    zeros. `1.0 / 7.0 = 0.142857…429` emits the maximum significant digits plus the
    guard, so the `divisionDigitsFuel` ceiling must not be exhausted before the
    over-budget exit. Reduces under `native_decide` ⇒ the bound is sufficient. -/
theorem eval_div_repeating_full_sig :
    (evalDiv (.prim (.float "1.0")) (.prim (.float "7.0"))
      == .prim (.float "0.1428571428571428571428571428571429")) = true := by
  native_decide

/-- High-fuel pin exercising the leading-zero slack in the fuel bound: `1.0 / 700.0
    = 0.001428…429` has two leading fractional zeros (non-emitting iterations) on
    top of the 34 significant digits, so it leans on the `+ <den digit count>` term
    of `divisionDigitsFuel`. -/
theorem eval_div_repeating_leading_zeros :
    (evalDiv (.prim (.float "1.0")) (.prim (.float "700.0"))
      == .prim (.float "0.001428571428571428571428571428571429")) = true := by
  native_decide

/-- Slice 2c.1: an in-struct sibling reference (`b: a`) sees the FULLY-MERGED value of a
    duplicated label, not the first conjunct. `{a: int, b: a, a: 1}` canonicalizes the two
    `a` slots into `.conj [int, 1]` at slot 0, so `b` evaluates to `1`, and the duplicate
    collapses to a single `a` field. -/
theorem eval_in_struct_sibling_merge :
    (resolveAndEval
      (.struct
        [("a", .regular, .kind .int), ("b", .regular, .ref "a"), ("a", .regular, .prim (.int 1))]
        true)
      == .struct
        [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 1))]
        true) = true := by
  native_decide

/-- A duplicate-label conflict bottoms both the label and any sibling referencing it:
    `{a: 1, b: a, a: 2}` -> `a` and `b` both bottom. -/
theorem eval_in_struct_sibling_conflict :
    (resolveAndEval
      (.struct
        [("a", .regular, .prim (.int 1)), ("b", .regular, .ref "a"), ("a", .regular, .prim (.int 2))]
        true)
      == .struct
        [
          ("a", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)]),
          ("b", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)])
        ]
        true) = true := by
  native_decide

/-- Canonicalization is visible through nested sub-structs: `c.e` references the outer `a`,
    seeing the merged `int & 1 = 1`. -/
theorem eval_nested_sibling_merge :
    (resolveAndEval
      (.struct
        [
          ("a", .regular, .kind .int),
          ("c", .regular, .struct [("e", .regular, .ref "a")] true),
          ("a", .regular, .prim (.int 1))
        ]
        true)
      == .struct
        [
          ("a", .regular, .prim (.int 1)),
          ("c", .regular, .struct [("e", .regular, .prim (.int 1))] true)
        ]
        true) = true := by
  native_decide

/-- A self-referential merged slot must not loop: `{a: a, a: 1}` canonicalizes to
    `.conj [a, 1]` at slot 0; the self-ref hits the `slotVisited` -> `.top` guard, so the
    meet collapses to `1` rather than diverging. -/
theorem eval_merged_self_ref_cycle :
    (resolveAndEval
      (.struct [("a", .regular, .ref "a"), ("a", .regular, .prim (.int 1))] true)
      == .struct [("a", .regular, .prim (.int 1))] true) = true := by
  native_decide

/-- 2c.2: struct conjunction through a referenced binding. `d & {a: 1}` merges the conjuncts'
    declarations into one frame before evaluating bodies, so `d.b: a` sees the narrowed `a`
    and `y.b` resolves to `1` (not `int`). -/
theorem eval_meet_lazy_sibling_ref :
    (resolveAndEval
      (.struct
        [
          ("d", .regular, .struct [("a", .regular, .kind .int), ("b", .regular, .ref "a")] true),
          ("y", .regular, .conj [.ref "d", .struct [("a", .regular, .prim (.int 1))] true])
        ]
        true)
      == .struct
        [
          ("d", .regular, .struct [("a", .regular, .kind .int), ("b", .regular, .kind .int)] true),
          ("y", .regular,
            .struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 1))] true)
        ]
        true) = true := by
  native_decide

/-- 2c.2: literal struct conjunction (no reference operand). `{a: int, b: a} & {a: 1}` → `b: 1`
    via the merged frame. -/
theorem eval_meet_lazy_literal :
    (resolveAndEval
      (.struct
        [
          ("x", .regular,
            .conj
              [
                .struct [("a", .regular, .kind .int), ("b", .regular, .ref "a")] true,
                .struct [("a", .regular, .prim (.int 1))] true
              ])
        ]
        true)
      == .struct
        [
          ("x", .regular,
            .struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 1))] true)
        ]
        true) = true := by
  native_decide

/-- 2c.2: a chained sibling reference within one conjunct, narrowed across the meet —
    `{a: int, b: a, c: b} & {a: 1}` resolves `a`, `b`, `c` all to `1`. -/
theorem eval_meet_lazy_chain :
    (resolveAndEval
      (.struct
        [
          ("x", .regular,
            .conj
              [
                .struct
                  [
                    ("a", .regular, .kind .int),
                    ("b", .regular, .ref "a"),
                    ("c", .regular, .ref "b")
                  ]
                  true,
                .struct [("a", .regular, .prim (.int 1))] true
              ])
        ]
        true)
      == .struct
        [
          ("x", .regular,
            .struct
              [
                ("a", .regular, .prim (.int 1)),
                ("b", .regular, .prim (.int 1)),
                ("c", .regular, .prim (.int 1))
              ]
              true)
        ]
        true) = true := by
  native_decide

/-- 2c.2: nested sub-struct visibility through a *definition* meet. `out.val` references the
    hidden `#x`; `#D & {#x: "hi"}` narrows `#x` and the nested `out.val` resolves to `"hi"`. -/
theorem eval_meet_lazy_hidden_def :
    (resolveAndEval
      (.struct
        [
          ("#D", .definition,
            .struct
              [
                ("#x", .definition, .kind .string),
                ("out", .regular, .struct [("val", .regular, .ref "#x")] true)
              ]
              true),
          ("y", .regular, .conj [.ref "#D", .struct [("#x", .definition, .prim (.string "hi"))] true])
        ]
        true)
      == .struct
        [
          ("#D", .definition,
            .struct
              [
                ("#x", .definition, .kind .string),
                ("out", .regular, .struct [("val", .regular, .kind .string)] true)
              ]
              false),
          ("y", .regular,
            .struct
              [
                ("#x", .definition, .prim (.string "hi")),
                ("out", .regular, .struct [("val", .regular, .prim (.string "hi"))] true)
              ]
              false)
        ]
        true) = true := by
  native_decide

end Kue
