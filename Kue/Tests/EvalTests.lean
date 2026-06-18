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
        (.struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] true))
      == .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] true) = true := by
  native_decide

theorem eval_missing_reference_bottom :
    (evalStructRefs
      (.struct [⟨"x", .regular, .ref "#Missing"⟩] true)
      == .struct [⟨"x", .regular, .bottomWith [.unresolvedReference "#Missing"]⟩] true) = true := by
  native_decide

theorem eval_resolved_reference_by_binding_id :
    (evalStructRefs
      (.struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .refId ⟨0, 0⟩⟩] true)
      == .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] true) = true := by
  native_decide

theorem eval_static_field_selector :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"base", .regular, .struct [⟨"inner", .regular, .prim (.int 4)⟩] true⟩,
            ⟨"x", .regular, .selector (.ref "base") "inner"⟩
          ]
          true))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

theorem eval_static_list_index :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"xs", .regular, .list [.prim (.int 10), .prim (.int 20)]⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 1))⟩
          ]
          true))
      = "xs: [10, 20]\nx: 20" := by
  native_decide

theorem eval_static_string_field_index :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"base", .regular, .struct [⟨"inner", .regular, .prim (.int 4)⟩] true⟩,
            ⟨"x", .regular, .index (.ref "base") (.prim (.string "inner"))⟩
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
            ⟨"base", .regular, .prim (.string "v")⟩,
            ⟨"components", .regular,
              .struct
                [
                  ⟨"a", .regular, .struct [⟨"who", .regular, .ref "base"⟩] true⟩,
                  ⟨"b", .regular, .struct [⟨"who", .regular, .ref "base"⟩] true⟩
                ]
                true⟩,
            ⟨"aWho", .regular, .selector (.selector (.ref "components") "a") "who"⟩,
            ⟨"bWho", .regular, .selector (.selector (.ref "components") "b") "who"⟩
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
            ⟨"x", .regular, .conj [.ref "x", .struct [⟨"p", .regular, .prim (.int 1)⟩] true]⟩,
            ⟨"p1", .regular, .selector (.ref "x") "p"⟩,
            ⟨"p2", .regular, .selector (.ref "x") "p"⟩
          ]
          true))
      = "x: {p: 1}\np1: 1\np2: 1" := by
  native_decide

theorem eval_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3))⟩,
            ⟨"cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b"))⟩,
            ⟨"bytes", .regular, .binary .add (.prim (.bytes "ab")) (.prim (.bytes "cd"))⟩
          ]
          true))
      = "sum: 3\ndiff: 2\ncat: \"ab\"\nbytes: 'abcd'" := by
  native_decide

theorem eval_float_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"floatSum", .regular, .binary .add (.prim (.float "1.5")) (.prim (.float "2.25"))⟩,
            ⟨"intFloat", .regular, .binary .add (.prim (.int 1)) (.prim (.float "2.5"))⟩,
            ⟨"floatSub", .regular, .binary .sub (.prim (.float "5.5")) (.prim (.int 2))⟩,
            ⟨"exp", .regular, .binary .add (.prim (.float "1e+3")) (.prim (.int 2))⟩,
            ⟨"small", .regular, .binary .add (.prim (.float "0.1")) (.prim (.float "0.2"))⟩
          ]
          true))
      = "floatSum: 3.75\nintFloat: 3.5\nfloatSub: 3.5\nexp: 1002.0\nsmall: 0.3" := by
  native_decide

theorem eval_multiplication_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"mul", .regular, .binary .mul (.prim (.int 3)) (.prim (.int 4))⟩,
            ⟨
              "precedence",
              .regular,
              .binary .add (.prim (.int 1)) (.binary .mul (.prim (.int 2)) (.prim (.int 3)))
            ⟩
          ]
          true))
      = "mul: 12\nprecedence: 7" := by
  native_decide

theorem eval_division_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"div", .regular, .binary .div (.prim (.int 5)) (.prim (.int 2))⟩,
            ⟨"whole", .regular, .binary .div (.prim (.int 6)) (.prim (.int 3))⟩,
            ⟨"third", .regular, .binary .div (.prim (.int 1)) (.prim (.int 3))⟩,
            ⟨"negative", .regular, .binary .div (.prim (.int (-5))) (.prim (.int 2))⟩
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
            ⟨"divValue", .regular, .binary .intDiv (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"modValue", .regular, .binary .intMod (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"quoValue", .regular, .binary .intQuo (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"remValue", .regular, .binary .intRem (.prim (.int (-7))) (.prim (.int 3))⟩
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
            ⟨"same", .regular, .binary .eq (.prim (.int 1)) (.prim (.int 1))⟩,
            ⟨"diff", .regular, .binary .ne (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"text", .regular, .binary .eq (.prim (.string "a")) (.prim (.string "b"))⟩
          ]
          true))
      = "same: true\ndiff: true\ntext: false" := by
  native_decide

theorem eval_ordering_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"lt", .regular, .binary .lt (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"le", .regular, .binary .le (.prim (.int 2)) (.prim (.int 2))⟩,
            ⟨"gt", .regular, .binary .gt (.prim (.int 3)) (.prim (.int 2))⟩,
            ⟨"ge", .regular, .binary .ge (.prim (.int 3)) (.prim (.int 4))⟩,
            ⟨"slt", .regular, .binary .lt (.prim (.string "a")) (.prim (.string "b"))⟩
          ]
          true))
      = "lt: true\nle: true\ngt: true\nge: false\nslt: true" := by
  native_decide

theorem eval_numeric_comparison_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"lt", .regular, .binary .lt (.prim (.float "1.5")) (.prim (.int 2))⟩,
            ⟨"le", .regular, .binary .le (.prim (.float "1.5")) (.prim (.float "1.50"))⟩,
            ⟨"gt", .regular, .binary .gt (.prim (.float "1e+3")) (.prim (.float "999.9"))⟩,
            ⟨"ge", .regular, .binary .ge (.prim (.float "1.0")) (.prim (.int 1))⟩,
            ⟨"eq", .regular, .binary .eq (.prim (.int 1)) (.prim (.float "1.0"))⟩,
            ⟨"ne", .regular, .binary .ne (.prim (.int 1)) (.prim (.float "1.0"))⟩
          ]
          true))
      = "lt: true\nle: true\ngt: true\nge: true\neq: true\nne: false" := by
  native_decide

theorem eval_logical_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"andFalse", .regular, .binary .boolAnd (.prim (.bool true)) (.prim (.bool false))⟩,
            ⟨"orTrue", .regular, .binary .boolOr (.prim (.bool false)) (.prim (.bool true))⟩,
            ⟨
              "andCmp",
              .regular,
              .binary .boolAnd
                (.binary .lt (.prim (.int 1)) (.prim (.int 2)))
                (.binary .gt (.prim (.int 3)) (.prim (.int 2)))
            ⟩
          ]
          true))
      = "andFalse: false\norTrue: true\nandCmp: true" := by
  native_decide

theorem eval_logical_not_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"notFalse", .regular, .unary .boolNot (.prim (.bool false))⟩,
            ⟨"notCmp", .regular, .unary .boolNot (.binary .lt (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"double", .regular, .unary .boolNot (.unary .boolNot (.prim (.bool true)))⟩
          ]
          true))
      = "notFalse: true\nnotCmp: false\ndouble: true" := by
  native_decide

theorem eval_unary_numeric_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"negGroup", .regular, .unary .numNeg (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"posGroup", .regular, .unary .numPos (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"negFloat", .regular, .unary .numNeg (.prim (.float "1.5"))⟩
          ]
          true))
      = "negGroup: -3\nposGroup: 3\nnegFloat: -1.5" := by
  native_decide

theorem eval_regex_match_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"match", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "^a"))⟩,
            ⟨"miss", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "z"))⟩,
            ⟨"notMatch", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "z"))⟩
          ]
          true))
      = "match: true\nmiss: false\nnotMatch: true" := by
  native_decide

theorem eval_list_index_out_of_range_bottom :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"xs", .regular, .list [.prim (.int 10)]⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 2))⟩
          ]
          true))
      == .struct
        [
          ⟨"xs", .regular, .list [.prim (.int 10)]⟩,
          ⟨"x", .regular, .bottomWith [.indexOutOfRange 2 1]⟩
        ]
        true) = true := by
  native_decide

theorem eval_missing_binding_id_bottom :
    (evalStructRefs
      (.struct [⟨"x", .regular, .refId ⟨0, 2⟩⟩] true)
      == .struct [⟨"x", .regular, .bottomWith [.unresolvedBinding ⟨0, 2⟩]⟩] true) = true := by
  native_decide

theorem eval_binding_id_not_label_lookup :
    (evalStructRefs
      (.struct [⟨"#same", .definition, .kind .int⟩, ⟨"same", .regular, .kind .string⟩, ⟨"x", .regular, .refId ⟨0, 1⟩⟩] true)
      == .struct [⟨"#same", .definition, .kind .int⟩, ⟨"same", .regular, .kind .string⟩, ⟨"x", .regular, .kind .string⟩] true) = true := by
  native_decide

theorem resolve_direct_self_reference :
    (resolveStructRefs
      (.struct [⟨"x", .regular, .ref "x"⟩] true)
      == .struct [⟨"x", .regular, .refId ⟨0, 0⟩⟩] true) = true := by
  native_decide

theorem eval_direct_self_reference_as_top :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .ref "x"⟩] true))
      == .struct [⟨"x", .regular, .top⟩] true) = true := by
  native_decide

theorem eval_mutual_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .ref "y"⟩, ⟨"y", .regular, .ref "x"⟩] true))
      == .struct [⟨"x", .regular, .top⟩, ⟨"y", .regular, .top⟩] true) = true := by
  native_decide

theorem eval_three_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"x", .regular, .ref "y"⟩,
            ⟨"y", .regular, .ref "z"⟩,
            ⟨"z", .regular, .ref "x"⟩
          ]
          true))
      == .struct [⟨"x", .regular, .top⟩, ⟨"y", .regular, .top⟩, ⟨"z", .regular, .top⟩] true) = true := by
  native_decide

theorem eval_direct_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .conj [.ref "x", .boundConstraint (intDecimal 0) .ge .number]⟩] true))
      == .struct [⟨"x", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] true) = true := by
  native_decide

theorem eval_mutual_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"a", .regular, .conj [.ref "b", .boundConstraint (intDecimal 0) .ge .number]⟩,
            ⟨"b", .regular, .ref "a"⟩
          ]
          true))
      == .struct [⟨"a", .regular, .boundConstraint (intDecimal 0) .ge .number⟩, ⟨"b", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] true) = true := by
  native_decide

theorem eval_non_cycle_reference_still_uses_target_value :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .kind .int⟩, ⟨"y", .regular, .ref "x"⟩] true))
      == .struct [⟨"x", .regular, .kind .int⟩, ⟨"y", .regular, .kind .int⟩] true) = true := by
  native_decide

/-- A value alias (`Self={…}`) lowers to a `.thisStruct` let-binding; `Self.field`
    (a selector on the binding) resolves as a same-struct sibling reference. Pins the
    eval-level `thisStruct` mechanism directly. -/
theorem eval_value_alias_self_reference :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"Self", .letBinding, .thisStruct⟩,
            ⟨"x", .regular, .prim (.int 5)⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x"⟩
          ]
          true))
      == .struct
        [
          ⟨"Self", .letBinding, .thisStruct⟩,
          ⟨"x", .regular, .prim (.int 5)⟩,
          ⟨"y", .regular, .prim (.int 5)⟩
        ]
        true) = true := by
  native_decide

/-- A self-reference cycle through the alias is bounded to top, never diverging. -/
theorem eval_value_alias_cycle_bounds_to_top :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"Self", .letBinding, .thisStruct⟩,
            ⟨"x", .regular, .selector (.ref "Self") "y"⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x"⟩
          ]
          true))
      == .struct
        [
          ⟨"Self", .letBinding, .thisStruct⟩,
          ⟨"x", .regular, .top⟩,
          ⟨"y", .regular, .top⟩
        ]
        true) = true := by
  native_decide

theorem eval_regular_disjunction_uses_join_normalization :
    (evalStructRefs
      (.struct [⟨"x", .regular, .disj [(.regular, .boundConstraint (intDecimal 5) .ge .number), (.regular, .boundConstraint (intDecimal 0) .ge .number)]⟩] true)
      == .struct [⟨"x", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] true) = true := by
  native_decide

theorem eval_regular_field_reference_to_hidden :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"_secret", .hidden, .prim (.string "x")⟩, ⟨"value", .regular, .ref "_secret"⟩] true))
      == .struct [⟨"_secret", .hidden, .prim (.string "x")⟩, ⟨"value", .regular, .prim (.string "x")⟩] true) = true := by
  native_decide

theorem eval_reference_inside_struct_tail :
    (evalStructRefs
      (resolveStructRefs (.structTail [⟨"#A", .definition, .kind .int⟩] (.ref "#A")))
      == .structTail [⟨"#A", .definition, .kind .int⟩] (.kind .int)) = true := by
  native_decide

theorem eval_reference_inside_nested_struct :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [⟨"x", .regular, .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] true⟩]
          true))
      == .struct
        [⟨"x", .regular, .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] true⟩]
        true) = true := by
  native_decide

theorem eval_reference_inside_struct_pattern :
    (evalStructRefs
      (resolveStructRefs (.structPattern [⟨"#A", .definition, .kind .int⟩] (.kind .string) (.ref "#A") true))
      == .structPattern [⟨"#A", .definition, .kind .int⟩] (.kind .string) (.kind .int) true) = true := by
  native_decide

theorem eval_struct_pattern_constrains_own_regular_field :
    (evalStructRefs
      (.structPattern [⟨"a", .regular, .prim (.string "bad")⟩] (.kind .string) (.kind .int) true)
      == .structPattern
        [⟨"a", .regular, .bottomWith [.fieldConstraint "a"]⟩]
        (.kind .string)
        (.kind .int)
        true) = true := by
  native_decide

theorem string_kind_pattern_types_matching_field :
    (meet
      (.structPattern [] (.kind .string) (.kind .int) true)
      (.struct [⟨"a", .regular, .prim (.int 1)⟩] true)
      == .structPattern [⟨"a", .regular, .prim (.int 1)⟩] (.kind .string) (.kind .int) true) = true := by
  native_decide

theorem string_kind_pattern_rejects_type_mismatch :
    containsBottom
      (meet
        (.structPattern [] (.kind .string) (.kind .int) true)
        (.struct [⟨"a", .regular, .prim (.string "x")⟩] true)) = true := by
  native_decide

theorem eval_len_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (.struct [⟨"x", .regular, .prim (.string "abc")⟩, ⟨"y", .regular, .builtinCall "len" [.ref "x"]⟩] true))
      == .struct [⟨"x", .regular, .prim (.string "abc")⟩, ⟨"y", .regular, .prim (.int 3)⟩] true) = true := by
  native_decide

theorem eval_integer_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"n", .regular, .prim (.int (-7))⟩,
            ⟨"q", .regular, .builtinCall "div" [.ref "n", .prim (.int 3)]⟩
          ]
          true))
      == .struct [⟨"n", .regular, .prim (.int (-7))⟩, ⟨"q", .regular, .prim (.int (-3))⟩] true) = true := by
  native_decide

theorem eval_incomplete_builtin_call_remains_call :
    (evalStructRefs (.struct [⟨"x", .regular, .builtinCall "len" [.kind .string]⟩] true)
      == .struct [⟨"x", .regular, .builtinCall "len" [.kind .string]⟩] true) = true := by
  native_decide

theorem eval_comprehension_for_keyed_over_struct :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [
            .comprehension
              [.forIn (some "k") "v" (.struct [⟨"x", .regular, .prim (.int 1)⟩] true)]
              (.struct [⟨"key", .regular, .ref "k"⟩, ⟨"val", .regular, .ref "v"⟩] true)
          ]
          true))
      == .struct [⟨"key", .regular, .prim (.string "x")⟩, ⟨"val", .regular, .prim (.int 1)⟩] true)
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
              (.struct [⟨"only", .regular, .ref "v"⟩] true)
          ]
          true))
      == .struct [⟨"only", .regular, .prim (.int 42)⟩] true) = true := by
  native_decide

theorem eval_comprehension_if_true_admits :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [.comprehension [.guard (.prim (.bool true))] (.struct [⟨"flag", .regular, .prim (.bool true)⟩] true)]
          true))
      == .struct [⟨"flag", .regular, .prim (.bool true)⟩] true) = true := by
  native_decide

theorem eval_comprehension_if_false_drops :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [.comprehension [.guard (.prim (.bool false))] (.struct [⟨"hidden", .regular, .prim (.int 1)⟩] true)]
          true))
      == .struct [] true) = true := by
  native_decide

theorem eval_comprehension_body_sees_sibling_field :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          [⟨"base", .regular, .prim (.int 7)⟩]
          [.comprehension [.guard (.prim (.bool true))] (.struct [⟨"copy", .regular, .ref "base"⟩] true)]
          true))
      == .struct [⟨"base", .regular, .prim (.int 7)⟩, ⟨"copy", .regular, .prim (.int 7)⟩] true)
      = true := by
  native_decide

theorem eval_comprehension_for_source_sees_sibling_field :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          [⟨"k", .regular, .prim (.int 3)⟩]
          [.comprehension [.forIn none "v" (.list [.ref "k"])] (.struct [⟨"g", .regular, .ref "v"⟩] true)]
          true))
      == .struct [⟨"k", .regular, .prim (.int 3)⟩, ⟨"g", .regular, .prim (.int 3)⟩] true)
      = true := by
  native_decide

/-- Slice C (`closure-default-in-guard`). A marked-default disjunction collapses to its
    default in a concrete context; a non-default disjunction does not. These pin
    `resolveDisjDefault?` directly. -/
theorem resolve_default_disj_picks_marked_default :
    (resolveDisjDefault? [(.default, .prim (.bool false)), (.regular, .kind .bool)]
      == some (.prim (.bool false))) = true := by
  native_decide

theorem resolve_default_disj_non_default_stays_unresolved :
    (resolveDisjDefault? [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]
      == none) = true := by
  native_decide

theorem resolve_default_disj_multiple_defaults_stays_unresolved :
    (resolveDisjDefault? [(.default, .prim (.int 1)), (.default, .prim (.int 2)), (.regular, .kind .int)]
      == none) = true := by
  native_decide

/-- Slice C. Operations distribute over a disjunction preserving marks: `!(bool | *false)`
    becomes `!bool | *!false` = `bool | *true`, whose default collapses to `true`. -/
theorem distribute_not_over_default_disj :
    (distributeUnary .boolNot (.disj [(.default, .prim (.bool false)), (.regular, .kind .bool)])
      == .disj [(.default, .prim (.bool true)), (.regular, .unary .boolNot (.kind .bool))]) = true := by
  native_decide

/-- Slice C. `(int | *1) + 1` distributes to `int+1 | *(1+1)` = `int+1 | *2`; the regular
    branch is a stuck addition over `int`, the default is the concrete `2`. -/
theorem distribute_add_over_default_disj :
    (distributeBinary .add (.disj [(.default, .prim (.int 1)), (.regular, .kind .int)]) (.prim (.int 1))
      == .disj [(.default, .prim (.int 2)), (.regular, .binary .add (.kind .int) (.prim (.int 1)))]) = true := by
  native_decide

/-- Slice C. The negated real-app guard shape: `x: bool | *false; if !x { y: 1 }`. The `!`
    distributes over the default disjunction and the guard collapses the default to `true`,
    so the body admits. cue-exact (`{x: false, out: {y: 1}}`). -/
theorem eval_comprehension_guard_negated_default_disj_admits :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [⟨"x", .regular, .disj [(.default, .prim (.bool false)), (.regular, .kind .bool)]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.unary .boolNot (.ref "x"))]
                 (.struct [⟨"y", .regular, .prim (.int 1)⟩] true)]
               true⟩]
          true))
      == .struct
        [⟨"x", .regular, .disj [(.default, .prim (.bool false)), (.regular, .kind .bool)]⟩,
         ⟨"out", .regular, .struct [⟨"y", .regular, .prim (.int 1)⟩] true⟩]
        true) = true := by
  native_decide

/-- Slice C. The direct guard shape `if x` with `x: bool | *true` admits (default `true`). -/
theorem eval_comprehension_guard_direct_default_disj_admits :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [⟨"x", .regular, .disj [(.default, .prim (.bool true)), (.regular, .kind .bool)]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.ref "x")]
                 (.struct [⟨"y", .regular, .prim (.int 1)⟩] true)]
               true⟩]
          true))
      == .struct
        [⟨"x", .regular, .disj [(.default, .prim (.bool true)), (.regular, .kind .bool)]⟩,
         ⟨"out", .regular, .struct [⟨"y", .regular, .prim (.int 1)⟩] true⟩]
        true) = true := by
  native_decide

/-- Slice C (over-resolution guard). A NON-default disjunction in a guard must STAY
    unsatisfied — only marked defaults collapse. `if x` with `x: bool` (no default) drops
    the body, matching cue's `incomplete value bool`. -/
theorem eval_comprehension_guard_non_default_disj_drops :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [⟨"x", .regular,
             .disj [(.regular, .prim (.bool true)), (.regular, .prim (.bool false))]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.ref "x")]
                 (.struct [⟨"y", .regular, .prim (.int 1)⟩] true)]
               true⟩]
          true))
      == .struct
        [⟨"x", .regular,
           .disj [(.regular, .prim (.bool true)), (.regular, .prim (.bool false))]⟩,
         ⟨"out", .regular, .struct [] true⟩]
        true) = true := by
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
        [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 1)⟩]
        true)
      == .struct
        [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩]
        true) = true := by
  native_decide

/-- A duplicate-label conflict bottoms both the label and any sibling referencing it:
    `{a: 1, b: a, a: 2}` -> `a` and `b` both bottom. -/
theorem eval_in_struct_sibling_conflict :
    (resolveAndEval
      (.struct
        [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 2)⟩]
        true)
      == .struct
        [
          ⟨"a", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)]⟩,
          ⟨"b", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)]⟩
        ]
        true) = true := by
  native_decide

/-- Canonicalization is visible through nested sub-structs: `c.e` references the outer `a`,
    seeing the merged `int & 1 = 1`. -/
theorem eval_nested_sibling_merge :
    (resolveAndEval
      (.struct
        [
          ⟨"a", .regular, .kind .int⟩,
          ⟨"c", .regular, .struct [⟨"e", .regular, .ref "a"⟩] true⟩,
          ⟨"a", .regular, .prim (.int 1)⟩
        ]
        true)
      == .struct
        [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"c", .regular, .struct [⟨"e", .regular, .prim (.int 1)⟩] true⟩
        ]
        true) = true := by
  native_decide

/-- A self-referential merged slot must not loop: `{a: a, a: 1}` canonicalizes to
    `.conj [a, 1]` at slot 0; the self-ref hits the `slotVisited` -> `.top` guard, so the
    meet collapses to `1` rather than diverging. -/
theorem eval_merged_self_ref_cycle :
    (resolveAndEval
      (.struct [⟨"a", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 1)⟩] true)
      == .struct [⟨"a", .regular, .prim (.int 1)⟩] true) = true := by
  native_decide

/-- 2c.2: struct conjunction through a referenced binding. `d & {a: 1}` merges the conjuncts'
    declarations into one frame before evaluating bodies, so `d.b: a` sees the narrowed `a`
    and `y.b` resolves to `1` (not `int`). -/
theorem eval_meet_lazy_sibling_ref :
    (resolveAndEval
      (.struct
        [
          ⟨"d", .regular, .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] true⟩,
          ⟨"y", .regular, .conj [.ref "d", .struct [⟨"a", .regular, .prim (.int 1)⟩] true]⟩
        ]
        true)
      == .struct
        [
          ⟨"d", .regular, .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .kind .int⟩] true⟩,
          ⟨"y", .regular,
            .struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩] true⟩
        ]
        true) = true := by
  native_decide

/-- 2c.2: literal struct conjunction (no reference operand). `{a: int, b: a} & {a: 1}` → `b: 1`
    via the merged frame. -/
theorem eval_meet_lazy_literal :
    (resolveAndEval
      (.struct
        [
          ⟨"x", .regular,
            .conj
              [
                .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] true,
                .struct [⟨"a", .regular, .prim (.int 1)⟩] true
              ]⟩
        ]
        true)
      == .struct
        [
          ⟨"x", .regular,
            .struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩] true⟩
        ]
        true) = true := by
  native_decide

/-- 2c.2: a chained sibling reference within one conjunct, narrowed across the meet —
    `{a: int, b: a, c: b} & {a: 1}` resolves `a`, `b`, `c` all to `1`. -/
theorem eval_meet_lazy_chain :
    (resolveAndEval
      (.struct
        [
          ⟨"x", .regular,
            .conj
              [
                .struct
                  [
                    ⟨"a", .regular, .kind .int⟩,
                    ⟨"b", .regular, .ref "a"⟩,
                    ⟨"c", .regular, .ref "b"⟩
                  ]
                  true,
                .struct [⟨"a", .regular, .prim (.int 1)⟩] true
              ]⟩
        ]
        true)
      == .struct
        [
          ⟨"x", .regular,
            .struct
              [
                ⟨"a", .regular, .prim (.int 1)⟩,
                ⟨"b", .regular, .prim (.int 1)⟩,
                ⟨"c", .regular, .prim (.int 1)⟩
              ]
              true⟩
        ]
        true) = true := by
  native_decide

/-- 2c.2: nested sub-struct visibility through a *definition* meet. `out.val` references the
    hidden `#x`; `#D & {#x: "hi"}` narrows `#x` and the nested `out.val` resolves to `"hi"`. -/
theorem eval_meet_lazy_hidden_def :
    (resolveAndEval
      (.struct
        [
          ⟨"#D", .definition,
            .struct
              [
                ⟨"#x", .definition, .kind .string⟩,
                ⟨"out", .regular, .struct [⟨"val", .regular, .ref "#x"⟩] true⟩
              ]
              true⟩,
          ⟨"y", .regular, .conj [.ref "#D", .struct [⟨"#x", .definition, .prim (.string "hi")⟩] true]⟩
        ]
        true)
      == .struct
        [
          ⟨"#D", .definition,
            .struct
              [
                ⟨"#x", .definition, .kind .string⟩,
                ⟨"out", .regular, .struct [⟨"val", .regular, .kind .string⟩] true⟩
              ]
              false⟩,
          ⟨"y", .regular,
            .struct
              [
                ⟨"#x", .definition, .prim (.string "hi")⟩,
                ⟨"out", .regular, .struct [⟨"val", .regular, .prim (.string "hi")⟩] true⟩
              ]
              false⟩
        ]
        true) = true := by
  native_decide

/-! ## `Value.closure` constructor — slice 1 (closure-ctor) round-trip pins

The constructor is inert (no producer yet); these theorems lock its identity so the later
producer/meet slices can't silently corrupt hashing or comparison. -/

/-- A closure `BEq`-compares equal to itself (derived `BEq` extends to the new arm). -/
theorem closure_beq_self :
    ((Value.closure [(0, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name"))
      == (Value.closure [(0, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name")))
      = true := by
  native_decide

/-- A different captured env makes two closures compare unequal — the captured ids carry
    the "independently-built frames never falsely share" invariant into `BEq`. -/
theorem closure_beq_distinct_env :
    ((Value.closure [(0, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name"))
      == (Value.closure [(1, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name")))
      = false := by
  native_decide

/-- A different body makes two closures compare unequal. -/
theorem closure_beq_distinct_body :
    ((Value.closure [(0, [])] (.ref "a")) == (Value.closure [(0, [])] (.ref "b")))
      = false := by
  native_decide

/-- The closure tag is its own bucket in the memo hash (no collision with other arms). -/
theorem closure_valueTag :
    valueTag (.closure [(0, [])] .top) = 29 := by
  native_decide

/-! ### slice 2 (closure-eval) — forcing the deferred body under its captured env

The eval arm forces `body` against `capturedEnv` (lexical scope), discarding the call-site
env/visited. No producer yet ⇒ these run on hand-built `.closure` literals, but they pin the
semantic anchor slices 3-4 target. -/

/-- Forcing a closure evaluates its body under the captured env: a depth-0 ref into the
    captured frame resolves to that frame's binding, proving the body sees `capturedEnv`. -/
theorem closure_eval_forces_captured_binding :
    (runEval (evalValueWithFuel evalFuel [] []
        (.closure [(7, [⟨"x", .regular, .prim (.int 42)⟩])] (.refId ⟨0, 0⟩)))
      == .prim (.int 42)) = true := by
  native_decide

/-- A closure with an empty captured env forces a body that needs no scope to a literal. -/
theorem closure_eval_empty_captured_env :
    (runEval (evalValueWithFuel evalFuel [] []
        (.closure [] (.prim (.int 1))))
      == .prim (.int 1)) = true := by
  native_decide

/-- A closure whose body is itself a closure forces through both layers (nested force):
    the inner closure carries its own captured frame, resolved when the outer body forces. -/
theorem closure_eval_nested_closure :
    (runEval (evalValueWithFuel evalFuel [] []
        (.closure []
          (.closure [(9, [⟨"y", .regular, .prim (.string "inner")⟩])] (.refId ⟨0, 0⟩))))
      == .prim (.string "inner")) = true := by
  native_decide

/-- Lexical, not dynamic, scope: the call-site env binds slot 0 to one value, the captured
    env binds it to another. The closure resolves against the captured env — its definition
    site — so the call-site binding (which would win under dynamic scope) is ignored. -/
theorem closure_eval_lexical_not_dynamic :
    (runEval (evalValueWithFuel evalFuel
        [(3, [⟨"x", .regular, .prim (.string "callsite")⟩])] []
        (.closure [(7, [⟨"x", .regular, .prim (.string "captured")⟩])] (.refId ⟨0, 0⟩)))
      == .prim (.string "captured")) = true := by
  native_decide

/-- Fuel exhaustion degrades like every other arm — at `fuel = 0` the closure passes
    through unevaluated rather than crashing or looping. -/
theorem closure_eval_fuel_exhaustion :
    (runEval (evalValueWithFuel 0 []
        [] (.closure [(7, [⟨"x", .regular, .prim (.int 42)⟩])] (.refId ⟨0, 0⟩)))
      == .closure [(7, [⟨"x", .regular, .prim (.int 42)⟩])] (.refId ⟨0, 0⟩)) = true := by
  native_decide

/-- Inert manifest: an unforced closure is non-concrete (incomplete). -/
theorem closure_manifest_incomplete :
    manifest (.closure [(0, [])] (.prim (.int 1)))
      = .error (.incomplete (.closure [(0, [])] (.prim (.int 1)))) := by
  rfl

/-- Inert meet: a closure does not unify with anything yet (slice 4 changes this). -/
theorem closure_meet_bottom :
    (meet (.closure [(0, [])] .top) (.struct [] true) == .bottom) = true := by
  native_decide

/-! ### slice 3 (closure-producer) — the import-selector arm emits a closure

White-box pins: closures are not user-visible until slice 4, so these assert the producer
CONSTRUCTS the right `.closure` (full id-stack captured, unevaluated def body) at the
trigger site, and — critically — that the shapes which currently resolve correctly do NOT
become closures. `runEval` starts `nextFrameId := 0`, so the producer's first `pushFrame`
captures frame id `0`. -/

/-- The collapse shape: a package struct `parts` holding a definition `#M` whose body
    self-references a sibling (`out: #name`, `refId ⟨0,0⟩`). Selecting `parts.#M` defers to a
    `.closure` whose captured env is `pushFrame pkgFields env` (id 0 on the use-site frame 7)
    and whose body is the UNEVALUATED `#M` struct — NOT the eager, collapsed selection. The
    body is normalized-CLOSED (`open_ := false`) at capture: an imported def body is never
    normalized at load time, so the producer closes it so a forced cross-package def enforces
    its closedness against use-site fields (slice 4 EC5). -/
theorem closure_producer_emits_on_selfref_def :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"parts", .hidden,
          .struct [⟨"#M", .definition,
            .struct [⟨"#name", .definition, .kind .string⟩,
                     ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true⟩] true⟩])] []
        (.selector (.refId ⟨0, 0⟩) "#M"))
      == .closure
          [(0, [⟨"#M", .definition,
            .struct [⟨"#name", .definition, .kind .string⟩,
                     ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true⟩]),
           (7, [⟨"parts", .hidden,
            .struct [⟨"#M", .definition,
              .struct [⟨"#name", .definition, .kind .string⟩,
                       ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true⟩] true⟩])]
          (.struct [⟨"#name", .definition, .kind .string⟩,
                    ⟨"out", .regular, .refId ⟨0, 0⟩⟩] false)) = true := by
  native_decide

/-- NON-REGRESSION: a definition WITHOUT a sibling self-reference (`#Widget` = flat
    `{name: string, size: int}`) stays on the eager path — selecting it yields the evaluated
    field, NOT a closure. This is every committed `pkg.#Def & {…}` fixture's shape; the gate
    must leave it untouched so slice 3 is byte-identical on all of them. -/
theorem closure_producer_skips_selfref_free_def :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"defs", .hidden,
          .struct [⟨"#Widget", .definition,
            .struct [⟨"name", .regular, .kind .string⟩,
                     ⟨"size", .regular, .kind .int⟩] true⟩] true⟩])] []
        (.selector (.refId ⟨0, 0⟩) "#Widget"))
      == .struct [⟨"name", .regular, .kind .string⟩,
                  ⟨"size", .regular, .kind .int⟩] true) = true := by
  native_decide

/-- NON-REGRESSION: a NON-definition field (regular, not `#`) with a sibling self-ref is NOT
    a definition selection, so it stays eager — only `#`-definitions defer. -/
theorem closure_producer_skips_non_definition :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"pkg", .hidden,
          .struct [⟨"r", .regular,
            .struct [⟨"a", .regular, .prim (.int 1)⟩,
                     ⟨"b", .regular, .refId ⟨0, 0⟩⟩] true⟩] true⟩])] []
        (.selector (.refId ⟨0, 0⟩) "r"))
      == .struct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"b", .regular, .prim (.int 1)⟩] true) = true := by
  native_decide

/-- FULL ID-STACK capture: the producer captures the ENTIRE env, not just the package frame.
    A depth-2 use-site env (inner frame 5, outer frame 7) retains BOTH outer frames beneath
    the freshly-pushed package frame (id 0) in `capturedEnv` — so a def body's depth>0
    cross-package embeds still walk the import chain when the closure is forced. -/
theorem closure_producer_captures_full_id_stack :
    (runEval (evalValueWithFuel evalFuel
        [(5, [⟨"parts", .hidden,
          .struct [⟨"#M", .definition,
            .struct [⟨"out", .regular, .refId ⟨0, 0⟩⟩,
                     ⟨"x", .regular, .prim (.int 1)⟩] true⟩] true⟩]),
         (7, [⟨"outer", .regular, .prim (.int 9)⟩])] []
        (.selector (.refId ⟨0, 0⟩) "#M"))
      == .closure
          [(0, [⟨"#M", .definition,
            .struct [⟨"out", .regular, .refId ⟨0, 0⟩⟩,
                     ⟨"x", .regular, .prim (.int 1)⟩] true⟩]),
           (5, [⟨"parts", .hidden,
            .struct [⟨"#M", .definition,
              .struct [⟨"out", .regular, .refId ⟨0, 0⟩⟩,
                       ⟨"x", .regular, .prim (.int 1)⟩] true⟩] true⟩]),
           (7, [⟨"outer", .regular, .prim (.int 9)⟩])]
          (.struct [⟨"out", .regular, .refId ⟨0, 0⟩⟩,
                    ⟨"x", .regular, .prim (.int 1)⟩] false)) = true := by
  native_decide

/-- DEPTH-MATCHED self-ref detection (slice A): a `refId ⟨0,0⟩` nested inside a `.struct` field
    is depth-0 relative to that NESTED frame, NOT the def body — `hasSelfRefAtDepth` descends to
    depth 1 there, so `⟨0,0⟩` (`d == 0 ≠ 1`) is the nested frame's own sibling, not the def's. So
    a def whose only inner ref sits in a nested struct and points at THAT frame is not a def
    self-ref and stays eager. Pins the boundary that keeps the gate from over-firing. -/
theorem closure_producer_nested_struct_ref_not_sibling :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"nested", .regular,
                    .struct [⟨"inner", .regular, .refId ⟨0, 0⟩⟩] true⟩] true)) = false := by
  native_decide

/-- And the positive companion: a direct sibling ref IS detected. -/
theorem closure_producer_direct_sibling_ref_detected :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#name", .definition, .kind .string⟩,
                  ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true)) = true := by
  native_decide

/-- DEEP self-ref (slice A — the real-app shape): a hidden field read from a NESTED struct
    (`spec: acme: email: #email`, where `#email` is a top-level def field referenced from 3
    frames deep → `refId ⟨3, _⟩`) IS a def self-ref. `hasSelfRefAtDepth` descends `spec`(1),
    `acme`(2), then matches `refId ⟨2, 0⟩` at depth 2 — `d == depth` lands on the def frame. This
    is exactly the shape `#ClusterIssuer`/`#Secret` use that slice 4's depth-0-only gate missed. -/
theorem closure_producer_deep_nested_self_ref_detected :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#email", .definition, .kind .string⟩,
                  ⟨"spec", .regular,
                    .struct [⟨"acme", .regular,
                      .struct [⟨"email", .regular, .refId ⟨2, 0⟩⟩] true⟩] true⟩] true)) = true := by
  native_decide

/-- DEEP self-ref in a comprehension GUARD (slice A): `if Self.#staging` inside a nested struct
    references the def's `#staging` from the guard condition, which `hasSelfRefAtDepth` scans at
    the comprehension's own depth. A `refId ⟨1, 0⟩` in a guard one struct deep matches depth 1. -/
theorem closure_producer_comprehension_guard_self_ref_detected :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#staging", .definition, .kind .bool⟩,
                  ⟨"spec", .regular,
                    .structComp [] [.comprehension [.guard (.refId ⟨1, 0⟩)]
                      (.struct [⟨"server", .regular, .prim (.string "x")⟩] true)] true⟩] true)) = true := by
  native_decide

/-! ### slice 4 (closure-meet) — splice the use-site struct into the forced def body

THE unlock: `defs.#M & {#name: "keel"}` where `#M = {#name: string, out: #name}` is an
imported self-referential definition. The `.conj` fallback evaluates `defs.#M` to a closure
(slice 3) and `{#name: "keel"}` to a struct; instead of the inert `meet` (→ `.bottom`), the
closure is forced with the use-site spliced in as an extra conjunct, so `out`'s `#name` ref
sees the narrowed `"keel"` instead of collapsing to `string`. The env mirrors the producer
tests (package binding at frame 7); `runEval` allocates the closure's pushed frame ids. -/

private def pkgEnvWith (defBody : Value) : Env :=
  [(7, [⟨"parts", .hidden, .struct [⟨"#M", .definition, defBody⟩] true⟩])]

private def selfRefM : Value :=
  .struct [⟨"#name", .definition, .kind .string⟩, ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true

/-- THE unlock pinned: forcing `parts.#M & {#name: "keel"}` yields `out: "keel"` (the hidden
    `#name` and the spliced narrowing resolve), NOT the slice-3 `.bottom`. Body is closed
    (`open_ := false`) because `#M` is a definition. -/
theorem closure_meet_splices_use_site :
    (runEval (evalValueWithFuel evalFuel (pkgEnvWith selfRefM) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] true]))
      == .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                  ⟨"out", .regular, .prim (.string "keel")⟩] false) = true := by
  native_decide

/-- CONFLICT → bottom: the use-site narrows `#name` to a value the def's own `#name` rejects
    (def `#name: "fixed"`, use-site `#name: "keel"`). The splice unifies the two `#name`
    conjuncts → a primitive conflict, which propagates through `#name`'s spliced slot AND
    `out`'s ref to it as a field-local `.bottomWith`; export then rejects the struct. -/
theorem closure_meet_conflict_is_bottom :
    (runEval (evalValueWithFuel evalFuel
        (pkgEnvWith (.struct [⟨"#name", .definition, .prim (.string "fixed")⟩,
                              ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true)) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] true]))
      == .struct
          [⟨"#name", .definition,
            .bottomWith [.primitiveConflict (.string "fixed") (.string "keel")]⟩,
           ⟨"out", .regular,
            .bottomWith [.primitiveConflict (.string "fixed") (.string "keel")]⟩] false) = true := by
  native_decide

/-- EMPTY use-site: `parts.#M & {}` == `parts.#M` — splicing zero use fields leaves the def
    body unchanged (here `#name` stays `string`, so `out` is `string`). -/
theorem closure_meet_empty_use_site :
    (runEval (evalValueWithFuel evalFuel (pkgEnvWith selfRefM) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M", .struct [] true]))
      == .struct [⟨"#name", .definition, .kind .string⟩,
                  ⟨"out", .regular, .kind .string⟩] false) = true := by
  native_decide

/-- SELF-REF captured frame TERMINATES (does not loop / exhaust fuel): a def field referencing
    itself directly (`loop: loop`, `refId ⟨0,1⟩` at its own slot) is caught by the ordinary
    `slotVisited` machinery on the pushed frame and resolves to `.top` rather than diverging.
    `out` still resolves to the spliced `#name`. -/
theorem closure_meet_self_ref_terminates :
    (runEval (evalValueWithFuel evalFuel
        (pkgEnvWith (.struct [⟨"#name", .definition, .kind .string⟩,
                              ⟨"loop", .regular, .refId ⟨0, 1⟩⟩,
                              ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true)) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] true]))
      == .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                  ⟨"loop", .regular, .top⟩,
                  ⟨"out", .regular, .prim (.string "keel")⟩] false) = true := by
  native_decide

/-- OPEN def body (`...` → `.structTail`): the use-site may add a field absent from the def,
    and it appears in the output; `out` still sees the narrowed `#name`. The forced body stays
    a `.structTail` (open). -/
theorem closure_meet_open_def_admits_extra :
    (runEval (evalValueWithFuel evalFuel
        (pkgEnvWith (.structTail [⟨"#name", .definition, .kind .string⟩,
                                  ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .top)) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                         ⟨"extra", .regular, .prim (.int 42)⟩] true]))
      == .structTail [⟨"#name", .definition, .prim (.string "keel")⟩,
                      ⟨"out", .regular, .prim (.string "keel")⟩,
                      ⟨"extra", .regular, .prim (.int 42)⟩] .top) = true := by
  native_decide

/-- The producer NOW also fires on an OPEN (`.structTail`) self-ref def body (slice 4 extends
    `defBodyHasSiblingSelfRef` to `.structTail`), so open imported defs defer too. -/
theorem closure_producer_detects_structtail_sibling :
    (defBodyHasSiblingSelfRef
        (.structTail [⟨"#name", .definition, .kind .string⟩,
                      ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .top)) = true := by
  native_decide

/-! ### slice A (closure-realapp-selfalias) — multi-operand fold + `.structComp` embed defs

Real prod9 apps use value-alias defs that EMBED cross-package defs
(`#Def: { parts.#Metadata; #x: string; spec: #x }`). The embed makes the def body a
`.structComp` (the parser routes embeddings into `structComp.comprehensions`), which slice 4's
gate/force/embedding-meet paths all dropped. Slice A: (A.1) gate fires on `.structComp` siblings,
(A.2) the force path splices use-operands into a `.structComp` body and meet-folds its
embeddings, (A.3) the `.conj` fold splices the SHARED use set into EVERY closure operand, (A.4)
an embedding/operand that evaluated to a `.closure` is force-spliced not plain-`meet`-ed. -/

/-- A.1 GATE: a `.structComp` def body (an embedding-bearing def) with a sibling self-ref in its
    static fields IS detected — slice 4's gate only matched `.struct`/`.structTail`, so an
    embed-def returned `false` and never deferred. -/
theorem closure_producer_detects_structcomp_sibling :
    (defBodyHasSiblingSelfRef
        (.structComp [⟨"#x", .definition, .kind .string⟩,
                      ⟨"spec", .regular, .refId ⟨0, 1⟩⟩]
                     [.struct [⟨"kind", .regular, .prim (.string "Service")⟩] true] true)) = true := by
  native_decide

/-- A.1 GATE companion: a `.structComp` whose self-ref lives in the EMBEDDING (not the static
    fields) is also detected — the gate scans comprehensions too. -/
theorem closure_producer_detects_structcomp_embedding_sibling :
    (defBodyHasSiblingSelfRef
        (.structComp [⟨"#x", .definition, .kind .string⟩]
                     [.refId ⟨0, 0⟩] true)) = true := by
  native_decide

/-- A.2 FORCE `.structComp`: `parts.#Def & {#x: "hello"}` where `#Def` embeds a literal struct
    `{kind: "Service"}` and has a self-ref `spec: #x`. The force splices `{#x:"hello"}` into the
    static fields BEFORE evaluating, so `spec` sees `"hello"`, AND meet-folds the embedding so
    `kind` appears. Was `incomplete value: string` (eager collapse) pre-slice-A. -/
private def embedDefBody : Value :=
  .structComp [⟨"#x", .definition, .kind .string⟩,
               ⟨"spec", .regular, .refId ⟨0, 0⟩⟩]
              [.struct [⟨"kind", .regular, .prim (.string "Service")⟩] true] true

theorem closure_meet_structcomp_embed_splices :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"defs", .hidden, .struct [⟨"#Def", .definition, embedDefBody⟩] true⟩])] []
        (.conj [.selector (.refId ⟨0, 0⟩) "#Def",
                .struct [⟨"#x", .definition, .prim (.string "hello")⟩] true]))
      == .struct [⟨"#x", .definition, .prim (.string "hello")⟩,
                  ⟨"spec", .regular, .prim (.string "hello")⟩,
                  ⟨"kind", .regular, .prim (.string "Service")⟩] false) = true := by
  native_decide

/-- A.3 MULTI-OPERAND FOLD: `#M & #N & {narrow}` — two self-ref imported defs met with one
    use-site struct narrowing BOTH. Slice 4 spliced only the first closure (`#M`); the second
    (`#N`) was forced UNSPLICED → `tag: #label` collapsed → `incomplete value: string`. The fold
    splices the shared use set into BOTH. `#M = {#name, out:#name}`, `#N = {#label, tag:#label}`,
    both open (`...`) so they admit each other's fields. -/
private def twoDefEnv : Env :=
  [(7, [⟨"defs", .hidden,
    .struct
      [⟨"#M", .definition,
        .structTail [⟨"#name", .definition, .kind .string⟩,
                     ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .top⟩,
       ⟨"#N", .definition,
        .structTail [⟨"#label", .definition, .kind .string⟩,
                     ⟨"tag", .regular, .refId ⟨0, 0⟩⟩] .top⟩] true⟩])]

theorem closure_meet_multi_operand_fold :
    (runEval (evalValueWithFuel evalFuel twoDefEnv []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .selector (.refId ⟨0, 0⟩) "#N",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                         ⟨"#label", .definition, .prim (.string "x")⟩] true]))
      == .structTail [⟨"#name", .definition, .prim (.string "keel")⟩,
                      ⟨"out", .regular, .prim (.string "keel")⟩,
                      ⟨"#label", .definition, .prim (.string "x")⟩,
                      ⟨"tag", .regular, .prim (.string "x")⟩] .top) = true := by
  native_decide

/-- GENUINE CAPTURED-FRAME CYCLE termination (replaces the weak depth-0-slot
    `closure_meet_self_ref_terminates`): the closure's CAPTURED package frame contains a binding
    `#Self` that refs BACK into the def at depth 1 (`refId ⟨1, 0⟩` — out of the def's own frame,
    into the package frame, at `#Self`'s own slot → a capture-level self-loop). Forcing must
    terminate (→ `.top` for the cyclic slot) rather than diverge / exhaust fuel. -/
private def capturedCycleEnv : Env :=
  [(7, [⟨"pkg", .hidden,
    .struct
      [⟨"#Self", .definition, .refId ⟨0, 0⟩⟩,
       ⟨"#M", .definition,
        .struct [⟨"#name", .definition, .kind .string⟩,
                 ⟨"back", .regular, .refId ⟨1, 0⟩⟩,
                 ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true⟩] true⟩])]

theorem closure_meet_captured_frame_cycle_terminates :
    (runEval (evalValueWithFuel evalFuel capturedCycleEnv []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] true]))
      == .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                  ⟨"back", .regular, .top⟩,
                  ⟨"out", .regular, .prim (.string "keel")⟩] false) = true := by
  native_decide

end Kue
