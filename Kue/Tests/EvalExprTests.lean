import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

theorem eval_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2)), false⟩,
            ⟨"diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3)), false⟩,
            ⟨"cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b")), false⟩,
            ⟨"bytes", .regular, .binary .add (.prim (.bytes (textBytes "ab"))) (.prim (.bytes (textBytes "cd"))), false⟩
          ] .regularOpen none []))
      = "sum: 3\ndiff: 2\ncat: \"ab\"\nbytes: 'abcd'" := by
  native_decide

theorem eval_float_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"floatSum", .regular, .binary .add (.prim (mkFloatText "1.5")) (.prim (mkFloatText "2.25")), false⟩,
            ⟨"intFloat", .regular, .binary .add (.prim (.int 1)) (.prim (mkFloatText "2.5")), false⟩,
            ⟨"floatSub", .regular, .binary .sub (.prim (mkFloatText "5.5")) (.prim (.int 2)), false⟩,
            ⟨"exp", .regular, .binary .add (.prim (mkFloatText "1e+3")) (.prim (.int 2)), false⟩,
            ⟨"small", .regular, .binary .add (.prim (mkFloatText "0.1")) (.prim (mkFloatText "0.2")), false⟩
          ] .regularOpen none []))
      = "floatSum: 3.75\nintFloat: 3.5\nfloatSub: 3.5\nexp: 1002.0\nsmall: 0.3" := by
  native_decide

theorem eval_multiplication_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"mul", .regular, .binary .mul (.prim (.int 3)) (.prim (.int 4)), false⟩,
            ⟨
              "precedence",
              .regular,
              .binary .add (.prim (.int 1)) (.binary .mul (.prim (.int 2)) (.prim (.int 3)))
            , false⟩
          ] .regularOpen none []))
      = "mul: 12\nprecedence: 7" := by
  native_decide

theorem eval_division_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"div", .regular, .binary .div (.prim (.int 5)) (.prim (.int 2)), false⟩,
            ⟨"whole", .regular, .binary .div (.prim (.int 6)) (.prim (.int 3)), false⟩,
            ⟨"third", .regular, .binary .div (.prim (.int 1)) (.prim (.int 3)), false⟩,
            ⟨"negative", .regular, .binary .div (.prim (.int (-5))) (.prim (.int 2)), false⟩
          ] .regularOpen none []))
      = "div: 2.5\nwhole: 2.0\nthird: 0.3333333333333333333333333333333333\nnegative: -2.5" := by
  native_decide

theorem eval_division_by_zero_bottom :
    evalBinary .div (.prim (.int 1)) (.prim (.int 0)) = .bottomWith [.divisionByZero] := by
  rfl

theorem eval_integer_keyword_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"divValue", .regular, .binary .intDiv (.prim (.int (-7))) (.prim (.int 3)), false⟩,
            ⟨"modValue", .regular, .binary .intMod (.prim (.int (-7))) (.prim (.int 3)), false⟩,
            ⟨"quoValue", .regular, .binary .intQuo (.prim (.int (-7))) (.prim (.int 3)), false⟩,
            ⟨"remValue", .regular, .binary .intRem (.prim (.int (-7))) (.prim (.int 3)), false⟩
          ] .regularOpen none []))
      = "divValue: -3\nmodValue: 2\nquoValue: -2\nremValue: -1" := by
  native_decide

theorem eval_integer_keyword_incomplete_keeps_infix :
    formatValue (evalBinary .intDiv (.kind .int) (.prim (.int 3))) = "int div 3" := by
  native_decide

theorem eval_equality_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"same", .regular, .binary .eq (.prim (.int 1)) (.prim (.int 1)), false⟩,
            ⟨"diff", .regular, .binary .ne (.prim (.int 1)) (.prim (.int 2)), false⟩,
            ⟨"text", .regular, .binary .eq (.prim (.string "a")) (.prim (.string "b")), false⟩
          ] .regularOpen none []))
      = "same: true\ndiff: true\ntext: false" := by
  native_decide

theorem eval_ordering_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"lt", .regular, .binary .lt (.prim (.int 1)) (.prim (.int 2)), false⟩,
            ⟨"le", .regular, .binary .le (.prim (.int 2)) (.prim (.int 2)), false⟩,
            ⟨"gt", .regular, .binary .gt (.prim (.int 3)) (.prim (.int 2)), false⟩,
            ⟨"ge", .regular, .binary .ge (.prim (.int 3)) (.prim (.int 4)), false⟩,
            ⟨"slt", .regular, .binary .lt (.prim (.string "a")) (.prim (.string "b")), false⟩
          ] .regularOpen none []))
      = "lt: true\nle: true\ngt: true\nge: false\nslt: true" := by
  native_decide

theorem eval_numeric_comparison_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"lt", .regular, .binary .lt (.prim (mkFloatText "1.5")) (.prim (.int 2)), false⟩,
            ⟨"le", .regular, .binary .le (.prim (mkFloatText "1.5")) (.prim (mkFloatText "1.50")), false⟩,
            ⟨"gt", .regular, .binary .gt (.prim (mkFloatText "1e+3")) (.prim (mkFloatText "999.9")), false⟩,
            ⟨"ge", .regular, .binary .ge (.prim (mkFloatText "1.0")) (.prim (.int 1)), false⟩,
            ⟨"eq", .regular, .binary .eq (.prim (.int 1)) (.prim (mkFloatText "1.0")), false⟩,
            ⟨"ne", .regular, .binary .ne (.prim (.int 1)) (.prim (mkFloatText "1.0")), false⟩
          ] .regularOpen none []))
      = "lt: true\nle: true\ngt: true\nge: true\neq: true\nne: false" := by
  native_decide

theorem eval_logical_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"andFalse", .regular, .binary .boolAnd (.prim (.bool true)) (.prim (.bool false)), false⟩,
            ⟨"orTrue", .regular, .binary .boolOr (.prim (.bool false)) (.prim (.bool true)), false⟩,
            ⟨
              "andCmp",
              .regular,
              .binary .boolAnd
                (.binary .lt (.prim (.int 1)) (.prim (.int 2)))
                (.binary .gt (.prim (.int 3)) (.prim (.int 2)))
            , false⟩
          ] .regularOpen none []))
      = "andFalse: false\norTrue: true\nandCmp: true" := by
  native_decide

theorem eval_logical_not_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"notFalse", .regular, .unary .boolNot (.prim (.bool false)), false⟩,
            ⟨"notCmp", .regular, .unary .boolNot (.binary .lt (.prim (.int 1)) (.prim (.int 2))), false⟩,
            ⟨"double", .regular, .unary .boolNot (.unary .boolNot (.prim (.bool true))), false⟩
          ] .regularOpen none []))
      = "notFalse: true\nnotCmp: false\ndouble: true" := by
  native_decide

theorem eval_unary_numeric_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"negGroup", .regular, .unary .numNeg (.binary .add (.prim (.int 1)) (.prim (.int 2))), false⟩,
            ⟨"posGroup", .regular, .unary .numPos (.binary .add (.prim (.int 1)) (.prim (.int 2))), false⟩,
            ⟨"negFloat", .regular, .unary .numNeg (.prim (mkFloatText "1.5")), false⟩
          ] .regularOpen none []))
      = "negGroup: -3\nposGroup: 3\nnegFloat: -1.5" := by
  native_decide

theorem eval_regex_match_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"match", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "^a")), false⟩,
            ⟨"miss", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "z")), false⟩,
            ⟨"notMatch", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "z")), false⟩
          ] .regularOpen none []))
      = "match: true\nmiss: false\nnotMatch: true" := by
  native_decide

theorem eval_list_index_out_of_range_bottom :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"xs", .regular, .list [.prim (.int 10)], false⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 2)), false⟩
          ] .regularOpen none []))
      == mkStruct [
          ⟨"xs", .regular, .list [.prim (.int 10)], false⟩,
          ⟨"x", .regular, .bottomWith [.indexOutOfRange 2 1], false⟩
        ] .regularOpen none []) = true := by
  native_decide

theorem eval_missing_binding_id_bottom :
    (evalStructRefs
      (mkStruct [⟨"x", .regular, .refId ⟨0, 2⟩, false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .bottomWith [.unresolvedBinding ⟨0, 2⟩], false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_binding_id_not_label_lookup :
    (evalStructRefs
      (mkStruct [⟨"#same", .definition, .kind .int, false⟩, ⟨"same", .regular, .kind .string, false⟩, ⟨"x", .regular, .refId ⟨0, 1⟩, false⟩] .regularOpen none [])
      == mkStruct [⟨"#same", .definition, .kind .int, false⟩, ⟨"same", .regular, .kind .string, false⟩, ⟨"x", .regular, .kind .string, false⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_direct_self_reference :
    (resolveStructRefs
      (mkStruct [⟨"x", .regular, .ref "x", false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .refId ⟨0, 0⟩, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_direct_self_reference_as_top :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .ref "x", false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .top, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_mutual_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .ref "y", false⟩, ⟨"y", .regular, .ref "x", false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .top, false⟩, ⟨"y", .regular, .top, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_three_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"x", .regular, .ref "y", false⟩,
            ⟨"y", .regular, .ref "z", false⟩,
            ⟨"z", .regular, .ref "x", false⟩
          ] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .top, false⟩, ⟨"y", .regular, .top, false⟩, ⟨"z", .regular, .top, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_direct_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .conj [.ref "x", .boundConstraint (.int 0 .number) .ge], false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .boundConstraint (.int 0 .number) .ge, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_mutual_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"a", .regular, .conj [.ref "b", .boundConstraint (.int 0 .number) .ge], false⟩,
            ⟨"b", .regular, .ref "a", false⟩
          ] .regularOpen none []))
      == mkStruct [⟨"a", .regular, .boundConstraint (.int 0 .number) .ge, false⟩, ⟨"b", .regular, .boundConstraint (.int 0 .number) .ge, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_non_cycle_reference_still_uses_target_value :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .kind .int, false⟩, ⟨"y", .regular, .ref "x", false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .kind .int, false⟩, ⟨"y", .regular, .kind .int, false⟩] .regularOpen none []) = true := by
  native_decide

-- A value alias (`Self={…}`) lowers to a `.thisStruct` let-binding; `Self.field`
-- (a selector on the binding) resolves as a same-struct sibling reference. Pins the
-- eval-level `thisStruct` mechanism directly.
theorem eval_value_alias_self_reference :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"Self", .letBinding, .thisStruct, false⟩,
            ⟨"x", .regular, .prim (.int 5), false⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x", false⟩
          ] .regularOpen none []))
      == mkStruct [
          ⟨"Self", .letBinding, .thisStruct, false⟩,
          ⟨"x", .regular, .prim (.int 5), false⟩,
          ⟨"y", .regular, .prim (.int 5), false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- A self-reference cycle through the alias is bounded to top, never diverging.
theorem eval_value_alias_cycle_bounds_to_top :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"Self", .letBinding, .thisStruct, false⟩,
            ⟨"x", .regular, .selector (.ref "Self") "y", false⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x", false⟩
          ] .regularOpen none []))
      == mkStruct [
          ⟨"Self", .letBinding, .thisStruct, false⟩,
          ⟨"x", .regular, .top, false⟩,
          ⟨"y", .regular, .top, false⟩
        ] .regularOpen none []) = true := by
  native_decide

theorem eval_regular_disjunction_uses_join_normalization :
    (evalStructRefs
      (mkStruct [⟨"x", .regular, .disj [(.regular, .boundConstraint (.int 5 .number) .ge), (.regular, .boundConstraint (.int 0 .number) .ge)], false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .boundConstraint (.int 0 .number) .ge, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_regular_field_reference_to_hidden :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"_secret", .hidden, .prim (.string "x"), false⟩, ⟨"value", .regular, .ref "_secret", false⟩] .regularOpen none []))
      == mkStruct [⟨"_secret", .hidden, .prim (.string "x"), false⟩, ⟨"value", .regular, .prim (.string "x"), false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_reference_inside_struct_tail :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"#A", .definition, .kind .int, false⟩] .defOpenViaTail (some (.ref "#A")) []))
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩] .defOpenViaTail (some (.kind .int)) []) = true := by
  native_decide

theorem eval_reference_inside_nested_struct :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"x", .regular, mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .ref "#A", false⟩] .regularOpen none [], false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .kind .int, false⟩] .regularOpen none [], false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_reference_inside_struct_pattern :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"#A", .definition, .kind .int, false⟩] .regularOpen none [((.kind .string), (.ref "#A"))]))
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem eval_struct_pattern_constrains_own_regular_field :
    (evalStructRefs
      (mkStruct [⟨"a", .regular, .prim (.string "bad"), false⟩] .regularOpen none [((.kind .string), (.kind .int))])
      == mkStruct [⟨"a", .regular, .bottomWith [.fieldConstraint "a"], false⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem string_kind_pattern_types_matching_field :
    (meet
      (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem string_kind_pattern_rejects_type_mismatch :
    containsBottom
      (meet
        (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
        (mkStruct [⟨"a", .regular, .prim (.string "x"), false⟩] .regularOpen none [])) = true := by
  native_decide

theorem eval_len_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"x", .regular, .prim (.string "abc"), false⟩, ⟨"y", .regular, .builtinCall "len" [.ref "x"], false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .prim (.string "abc"), false⟩, ⟨"y", .regular, .prim (.int 3), false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_integer_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"n", .regular, .prim (.int (-7)), false⟩,
            ⟨"q", .regular, .builtinCall "div" [.ref "n", .prim (.int 3)], false⟩
          ] .regularOpen none []))
      == mkStruct [⟨"n", .regular, .prim (.int (-7)), false⟩, ⟨"q", .regular, .prim (.int (-3)), false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_incomplete_builtin_call_remains_call :
    (evalStructRefs (mkStruct [⟨"x", .regular, .builtinCall "len" [.kind .string], false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .builtinCall "len" [.kind .string], false⟩] .regularOpen none []) = true := by
  native_decide

-- Slice C (`closure-default-in-guard`). A marked-default disjunction collapses to its
-- default in a concrete context; a non-default disjunction does not. These pin
-- `resolveDisjDefault?` directly.
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

-- Slice F1. A unary op RESOLVES its disjunction operand to the default first, then applies
-- the scalar op — it does NOT distribute. `!(bool | *false)` resolves to `false`, then
-- `!false = true`. (Old slice-C behavior `bool | *true` was wrong: CUE forces the operand
-- concrete; `!(bool | *false)` → `true`, oracle-verified.)
theorem distribute_not_over_default_disj :
    (distributeUnary .boolNot (.disj [(.default, .prim (.bool false)), (.regular, .kind .bool)])
      == .prim (.bool true)) = true := by
  native_decide

-- Slice F1. `(int | *1) + 1` resolves the operand to `1`, then `1 + 1 = 2` — NOT
-- `int+1 | *2`. CUE forces arithmetic operands concrete (`(int | *1) + 1 → 2`,
-- oracle-verified), never a cross-product.
theorem distribute_add_over_default_disj :
    (distributeBinary .add (.disj [(.default, .prim (.int 1)), (.regular, .kind .int)]) (.prim (.int 1))
      == .prim (.int 2)) = true := by
  native_decide

-- ### Slice F1 — default-mark algebra (audit #3 Violation)
--
-- Three coupled facets, oracle-verified against `cue` v0.16.1:
-- (1) unification ANDs default sets across the cross product (was OR);
-- (2) `flattenAlternatives` honors two-level default precedence (a default-marked outer
-- arm selects the inner disjunction's own default structure);
-- (3) equal defaults dedup before the unique-default test.
-- Arithmetic/comparison/unary ops resolve each operand to its default FIRST (no
-- distribution / cross-product).

-- F1 facet 1, the cross-product where `combineMark` lives. Unification ANDs the default
-- sets: `(1|*2) & (1|2|3)` → the no-`*` right operand contributes its whole set as
-- defaults, so only `*2 & 2` survives as a default → resolves to `2`.
theorem f1_unify_cross_and_marks_resolves :
    (resolveDisjDefault?
      (match meet
          (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
          (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2)), (.regular, .prim (.int 3))]) with
        | .disj alts => alts
        | _ => [])
      == some (.prim (.int 2))) = true := by
  native_decide

-- F1 facet 1, NEGATIVE: two distinct defaults survive the cross → ambiguous (no resolve).
-- `(*1|2) & (1|*2)` crosses to live `1|2` with no surviving default (`*1&1` regular,
-- `2&*2` regular) → stays the disjunction `1 | 2`.
theorem f1_unify_cross_two_survivors_ambiguous :
    (meet
      (.disj [(.default, .prim (.int 1)), (.regular, .prim (.int 2))])
      (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
      == .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]) = true := by
  native_decide

-- F1. `combineMark` is AND: a result alternative is default iff BOTH inputs were.
theorem f1_combine_mark_is_and :
    (combineMark .default .default == .default
      && combineMark .default .regular == .regular
      && combineMark .regular .default == .regular
      && combineMark .regular .regular == .regular) = true := by
  native_decide

-- F1 facet 3, equal-default dedup. `*1 | *1 | 2` → the two equal defaults collapse to one,
-- so a unique default remains → resolves to `1`. The headline dedup case.
theorem f1_equal_defaults_dedup_resolves :
    (resolveDisjDefault?
      [(.default, .prim (.int 1)), (.default, .prim (.int 1)), (.regular, .prim (.int 2))]
      == some (.prim (.int 1))) = true := by
  native_decide

-- F1 facet 3, NEGATIVE: DISTINCT defaults stay ambiguous (no spurious dedup).
theorem f1_distinct_defaults_stay_ambiguous :
    (resolveDisjDefault? [(.default, .prim (.int 1)), (.default, .prim (.int 2))]
      == none) = true := by
  native_decide

-- F1 facet 2, two-level default precedence. `*d | 5` with `d : 1 | 2` (no inner default):
-- the outer default selects `d`'s disjunction, promoting its own arms to defaults (no
-- inner `*` → both `1` and `2` become defaults), while the regular outer `5` stays
-- regular. The flatten thus carries the inner default structure rather than blanket- or
-- OR-marking — a blanket-OR-mark would wrongly produce `*1 | 2 | 5`.
theorem f1_nested_default_flatten_carries_inner :
    (liveAlternatives
      [(.default, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == [(.default, .prim (.int 1)), (.default, .prim (.int 2)), (.regular, .prim (.int 5))]) = true := by
  native_decide

-- F1 facet 2, precedence at resolve. With the `*d | 5` flatten above, the two carried
-- defaults `1`, `2` are DISTINCT → `resolveDisjDefault?` shadows the regular `5` and stays
-- ambiguous (matches cue `incomplete value 1 | 2`), neither resolving to `1` nor keeping
-- `5`.
theorem f1_nested_default_flatten_resolve_ambiguous :
    (resolveDisjDefault?
      [(.default, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == none) = true := by
  native_decide

-- F1 facet 2. `*d | 5` with `d : *1 | 2` (inner default `*1`): only the inner default
-- carries → unique default `1` → resolves to `1` (matches cue).
theorem f1_nested_inner_default_resolves :
    (resolveDisjDefault?
      [(.default, .disj [(.default, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == some (.prim (.int 1))) = true := by
  native_decide

-- F1 facet 2, NEGATIVE: a REGULAR outer arm does NOT contribute its inner disjunction to
-- the default set. `d | *5` with `d : 1 | 2` → `d`'s arms stay regular (shed), the lone
-- default `5` wins → resolves to `5`.
theorem f1_nested_regular_outer_sheds :
    (resolveDisjDefault?
      [(.regular, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.default, .prim (.int 5))]
      == some (.prim (.int 5))) = true := by
  native_decide

-- F1, arithmetic resolve-first. `(1|*2) + (10|*20)` resolves each operand to its default
-- (`2`, `20`) then adds → `22`. The headline arithmetic case; NOT a mark cross-product.
theorem f1_arithmetic_resolves_operands_first :
    (distributeBinary .add
      (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
      (.disj [(.regular, .prim (.int 10)), (.default, .prim (.int 20))])
      == .prim (.int 22)) = true := by
  native_decide

-- F1, arithmetic NEGATIVE: a no-default operand does NOT resolve, so the op stays a stuck
-- node — `(1|2) + 10` keeps the unevaluated `(1|2) + 10`, matching cue's "unresolved
-- disjunction" (manifest reports incomplete), never an over-resolution.
theorem f1_arithmetic_no_default_stays_stuck :
    (distributeBinary .add
      (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))])
      (.prim (.int 10))
      == .binary .add (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]) (.prim (.int 10)))
      = true := by
  native_decide

-- F1, a non-default disjunction stays a non-default disjunction through resolve — no arm
-- becomes a default and it does not collapse (`1 | 2` stays ambiguous).
theorem f1_non_default_disj_stays_non_default :
    (resolveDisjDefault? [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]
      == none) = true := by
  native_decide

-- ### Disjunction-meet conformance sweep (2026-07-04 AFK probe).
--
-- End-to-end pins (parse → eval → export) over disjunction×disjunction distribution,
-- bottom-elimination, and default preservation through meet. Every VALUE verdict below is
-- oracle-confirmed byte-identical to cue v0.16.1; the eval-DISPLAY divergences that remain are
-- the documented SC-3 keep-marked family (Kue shows `*` marks cue elides), never a value gap.

-- Distribution, single survivor: `(1|2) & (2|3)` crosses to the lone live arm `2`, which
-- resolves on export. cue: `{"x":2}`.
theorem disj_meet_distribute_single_survivor :
    exportJsonMatches "x: (1|2) & (2|3)\n" "{\n    \"x\": 2\n}\n" = true := by
  native_decide

-- Distribution, multiple survivors → ambiguous. `(1|2) & (2|3|1)` keeps `1|2` (no default),
-- so export fails ambiguous — matching cue's `incomplete value 1 | 2`.
theorem disj_meet_distribute_multi_survivor_ambiguous :
    exportJsonBottoms "x: (1|2) & (2|3|1)\n" = true := by
  native_decide

-- Bottom-elimination, empty intersection → the whole disjunction bottoms. `(1|2) & (3|4)` has
-- no surviving arm. cue: `2 errors in empty disjunction`.
theorem disj_meet_empty_intersection_bottoms :
    exportJsonBottoms "x: (1|2) & (3|4)\n" = true := by
  native_decide

-- All-default from a markerless×markerless meet. `(1|2) & (1|2)`: each markerless operand
-- contributes its whole set as defaults (`withDefaultConvention`), so the surviving arms are
-- BOTH default — default-set = full set → export ambiguous, matching cue's `incomplete 1 | 2`.
theorem disj_meet_markerless_pair_ambiguous :
    exportJsonBottoms "x: (1|2) & (1|2)\n" = true := by
  native_decide

-- SC-3 all-default DISPLAY sub-case: the same markerless×markerless meet renders in eval as
-- `*1 | *2` (both arms carry the vacuous full-set default) where cue elides to `1 | 2`. The
-- (value, default) semantics coincide (export identical, pinned above); only the marked-vs-
-- elided display differs — the SC-3 keep-marked family. Pins current Kue display as a guard.
theorem disj_meet_markerless_pair_eval_all_default_display :
    evalSourceMatches "x: (1|2) & (1|2)\n" "x: *1 | *2" = true := by
  native_decide

-- Default position-independent through meet: `(*1|2) & (2|*1)` — the surviving default `1` is
-- picked regardless of which operand or arm-position carries the mark. cue: `1`.
theorem disj_meet_default_position_independent :
    exportJsonMatches "x: (*1|2) & (2|*1)\n" "{\n    \"x\": 1\n}\n" = true := by
  native_decide

-- Struct-arm default preserved through a narrowing meet: `(*{a:1}|{a:2,b:3}) & {b:3}` narrows
-- BOTH arms with `{b:3}`; the marked arm stays the default → `{a:1,b:3}`. cue agrees.
theorem disj_meet_struct_default_preserved :
    exportJsonMatches "x: (*{a:1}|{a:2,b:3}) & {b:3}\n"
      "{\n    \"x\": {\n        \"a\": 1,\n        \"b\": 3\n    }\n}\n" = true := by
  native_decide

-- Bound narrows a disjunction to its in-range arms, no default introduced: `(1|2|3) & (>=2)`
-- keeps `2 | 3` (ambiguous). cue: `2 | 3`.
theorem disj_meet_bound_narrows_arms :
    evalSourceMatches "x: (1|2|3) & (>=2)\n" "x: 2 | 3" = true := by
  native_decide

-- COVERAGE TRIPWIRE (test-health). Anchors the LAST theorem of every section; a swallowed
-- section turns its anchor into an unknown identifier and `#check` fails to elaborate.
#check @eval_division_by_zero_bottom                         -- basic arithmetic expressions
#check @eval_binding_id_not_label_lookup                     -- keyword/eq/order/cmp/logical/unary/regex/index
#check @eval_value_alias_cycle_bounds_to_top                 -- reference cycles / value aliases
#check @eval_incomplete_builtin_call_remains_call            -- reference-resolved builtin calls
#check @resolve_default_disj_multiple_defaults_stays_unresolved  -- default-disjunction resolve
#check @distribute_add_over_default_disj                     -- op over default disjunction
#check @f1_non_default_disj_stays_non_default                -- F1 default-mark algebra
#check @disj_meet_bound_narrows_arms                         -- disjunction-meet sweep

end Kue
