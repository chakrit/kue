import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

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
        (.struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] .regularOpen none []))
      == .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_missing_reference_bottom :
    (evalStructRefs
      (.struct [⟨"x", .regular, .ref "#Missing"⟩] .regularOpen none [])
      == .struct [⟨"x", .regular, .bottomWith [.unresolvedReference "#Missing"]⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_resolved_reference_by_binding_id :
    (evalStructRefs
      (.struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none [])
      == .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_static_field_selector :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"base", .regular, .struct [⟨"inner", .regular, .prim (.int 4)⟩] .regularOpen none []⟩,
            ⟨"x", .regular, .selector (.ref "base") "inner"⟩
          ] .regularOpen none []))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

theorem eval_static_list_index :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"xs", .regular, .list [.prim (.int 10), .prim (.int 20)]⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 1))⟩
          ] .regularOpen none []))
      = "xs: [10, 20]\nx: 20" := by
  native_decide

theorem eval_static_string_field_index :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"base", .regular, .struct [⟨"inner", .regular, .prim (.int 4)⟩] .regularOpen none []⟩,
            ⟨"x", .regular, .index (.ref "base") (.prim (.string "inner"))⟩
          ] .regularOpen none []))
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
        (.struct [
            ⟨"base", .regular, .prim (.string "v")⟩,
            ⟨"components", .regular,
              .struct [
                  ⟨"a", .regular, .struct [⟨"who", .regular, .ref "base"⟩] .regularOpen none []⟩,
                  ⟨"b", .regular, .struct [⟨"who", .regular, .ref "base"⟩] .regularOpen none []⟩
                ] .regularOpen none []⟩,
            ⟨"aWho", .regular, .selector (.selector (.ref "components") "a") "who"⟩,
            ⟨"bWho", .regular, .selector (.selector (.ref "components") "b") "who"⟩
          ] .regularOpen none []))
      = "base: \"v\"\ncomponents: {a: {who: \"v\"}, b: {who: \"v\"}}\naWho: \"v\"\nbWho: \"v\"" := by
  native_decide

-- A direct self-cycle selected twice: caching must not turn the bounded-cycle `⊤` into a
-- wrong value, and both selections must agree. `x: x & {p: 1}` resolves the cycle to its
-- constraint; `p1`/`p2` select the same field from the cyclic struct.
theorem eval_cycle_with_repeated_selection :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"x", .regular, .conj [.ref "x", .struct [⟨"p", .regular, .prim (.int 1)⟩] .regularOpen none []]⟩,
            ⟨"p1", .regular, .selector (.ref "x") "p"⟩,
            ⟨"p2", .regular, .selector (.ref "x") "p"⟩
          ] .regularOpen none []))
      = "x: {p: 1}\np1: 1\np2: 1" := by
  native_decide


/-! ### list-comprehension parse+eval pins (slice `list-comprehension-parse-eval`).

End-to-end behavioral pins over the full list-comprehension surface, each cue v0.16.1-exact (the
`.expected` strings are the oracle-checked outputs). Parsed-resolved-evaluated-formatted, so a
regression anywhere in the parser/resolver/eval chain trips them. Paired with the
fuel-truncation/saturation guards above (`sat_list_comprehension_*`). -/

-- for over a literal list, body uses the loop var.
theorem listcomp_for_basic :
    evalSourceMatches "out: [for x in [1, 2, 3] {x * 2}]\n" "out: [2, 4, 6]" = true := by
  native_decide

-- for-index form: `for i, x in list` binds the 0-based index.
theorem listcomp_for_index :
    evalSourceMatches "out: [for i, x in [10, 20, 30] {i*100 + x}]\n" "out: [10, 120, 230]"
      = true := by
  native_decide

-- for-k,v over a struct: iterates regular fields, binding key + value.
theorem listcomp_for_kv_struct :
    evalSourceMatches "out: [for k, v in {a: 1, b: 2} {v}]\n" "out: [1, 2]" = true := by
  native_decide

-- if guard mixed with a plain element: order preserved, false guard yields zero.
theorem listcomp_if_mixed :
    evalSourceMatches "out: [if true {1}, 2]\n" "out: [1, 2]" = true := by
  native_decide

theorem listcomp_if_false_zero :
    evalSourceMatches "out: [if false {42}]\n" "out: []" = true := by
  native_decide

-- for + if clause chain: the guard filters the iteration.
theorem listcomp_for_if_chain :
    evalSourceMatches "l: [1, 2, 3]\nout: [for x in l if x > 1 {x}]\n"
        "l: [1, 2, 3]\nout: [2, 3]" = true := by
  native_decide

-- nested for: the outer var is in scope for the inner; flattened in iteration order.
theorem listcomp_nested_for :
    evalSourceMatches "xs: [1, 2]\nys: [10, 20]\nout: [for x in xs for y in ys {x + y}]\n"
        "xs: [1, 2]\nys: [10, 20]\nout: [11, 21, 12, 22]" = true := by
  native_decide

-- mixed plain elements + comprehension: source order is preserved through the flatten.
theorem listcomp_mixed_order :
    evalSourceMatches "xs: [5, 6]\nout: [1, for x in xs {x}, 2]\n"
        "xs: [5, 6]\nout: [1, 5, 6, 2]" = true := by
  native_decide

-- empty source yields the empty list (not bottom).
theorem listcomp_empty_source :
    evalSourceMatches "out: [for x in [] {x}]\n" "out: []" = true := by
  native_decide

-- multiple elements yielded per outer iteration (inner for produces >1 each).
theorem listcomp_multi_yield :
    evalSourceMatches "out: [for x in [1, 2] for y in [x, x*10] {y}]\n" "out: [1, 10, 2, 20]"
      = true := by
  native_decide

-- struct-valued body element (body has a field, so the element IS that struct).
theorem listcomp_struct_body :
    evalSourceMatches "out: [for x in [1, 2] {a: x}]\n" "out: [{a: 1}, {a: 2}]" = true := by
  native_decide

/-! ### scalar struct-embedding collapse pins (root prerequisite for list comprehensions).

A struct with no output field embedding a non-struct value IS that value (CUE: `{5}`→`5`). cue
v0.16.1-exact; collapse only when LOSSLESS (no output field). -/

-- bare scalar literal collapses; a ref-embedding collapses to the resolved scalar.
theorem scalar_embed_collapse_ref :
    evalSourceMatches "a: 7\nout: {a}\n" "a: 7\nout: 7" = true := by
  native_decide

-- a struct-embedding of a list element collapses each element (the `[{5},{6}]` shape).
theorem scalar_embed_collapse_in_list :
    evalSourceMatches "out: [{5}, {6}]\n" "out: [5, 6]" = true := by
  native_decide

-- an output field PLUS a scalar embedding conflicts (mismatched struct/scalar) — NOT collapsed.
theorem scalar_embed_with_output_field_conflicts :
    evalSourceMatches "out: {a: 1, 5}\n" "out: _|_" = true := by
  native_decide

-- two equal scalar embeddings unify to the scalar; the collapse is idempotent.
theorem scalar_embed_two_equal :
    evalSourceMatches "out: {5, 5}\n" "out: 5" = true := by
  native_decide

-- two distinct scalar embeddings conflict (`5 & 6`).
theorem scalar_embed_two_distinct_conflicts :
    evalSourceMatches "out: {5, 6}\n" "out: _|_" = true := by
  native_decide

/-! ### empty/decl-free struct ∩ scalar is a CONFLICT, not a collapse (audit #10 V1).

The `{5}`→`5` collapse lives in embed-eval (`meetEmbeddingsWithFuel`), where the host is KNOWN
to embed a scalar — NOT in `meet`, which cannot tell an empty struct `{}` from `{5}`'s residual
`.struct []`. A genuine struct ∩ scalar must conflict (cue v0.16.1: mismatched types). Before the
fix these all wrongly collapsed to the scalar. -/

-- empty struct meeting a scalar conflicts (was wrongly `5`). cue: mismatched types struct/int.
theorem empty_struct_meet_scalar_conflicts :
    evalSourceMatches "out: {} & 5\n" "out: _|_" = true := by
  native_decide

-- order-independent: scalar on the left conflicts too.
theorem scalar_meet_empty_struct_conflicts :
    evalSourceMatches "out: 5 & {}\n" "out: _|_" = true := by
  native_decide

-- empty struct ∩ string conflicts (the absorb bug was not int-specific).
theorem empty_struct_meet_string_conflicts :
    evalSourceMatches "out: {} & \"s\"\n" "out: _|_" = true := by
  native_decide

-- empty struct ∩ bool conflicts.
theorem empty_struct_meet_bool_conflicts :
    evalSourceMatches "out: true & {}\n" "out: _|_" = true := by
  native_decide

-- two field decls — `out:{}` then `out:5` — unify via meet and conflict (the broad basic shape).
theorem field_struct_then_scalar_conflicts :
    evalSourceMatches "out: {}\nout: 5\n" "out: _|_" = true := by
  native_decide

theorem eval_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3))⟩,
            ⟨"cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b"))⟩,
            ⟨"bytes", .regular, .binary .add (.prim (.bytes "ab")) (.prim (.bytes "cd"))⟩
          ] .regularOpen none []))
      = "sum: 3\ndiff: 2\ncat: \"ab\"\nbytes: 'abcd'" := by
  native_decide

theorem eval_float_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"floatSum", .regular, .binary .add (.prim (.float "1.5")) (.prim (.float "2.25"))⟩,
            ⟨"intFloat", .regular, .binary .add (.prim (.int 1)) (.prim (.float "2.5"))⟩,
            ⟨"floatSub", .regular, .binary .sub (.prim (.float "5.5")) (.prim (.int 2))⟩,
            ⟨"exp", .regular, .binary .add (.prim (.float "1e+3")) (.prim (.int 2))⟩,
            ⟨"small", .regular, .binary .add (.prim (.float "0.1")) (.prim (.float "0.2"))⟩
          ] .regularOpen none []))
      = "floatSum: 3.75\nintFloat: 3.5\nfloatSub: 3.5\nexp: 1002.0\nsmall: 0.3" := by
  native_decide

theorem eval_multiplication_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"mul", .regular, .binary .mul (.prim (.int 3)) (.prim (.int 4))⟩,
            ⟨
              "precedence",
              .regular,
              .binary .add (.prim (.int 1)) (.binary .mul (.prim (.int 2)) (.prim (.int 3)))
            ⟩
          ] .regularOpen none []))
      = "mul: 12\nprecedence: 7" := by
  native_decide

theorem eval_division_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"div", .regular, .binary .div (.prim (.int 5)) (.prim (.int 2))⟩,
            ⟨"whole", .regular, .binary .div (.prim (.int 6)) (.prim (.int 3))⟩,
            ⟨"third", .regular, .binary .div (.prim (.int 1)) (.prim (.int 3))⟩,
            ⟨"negative", .regular, .binary .div (.prim (.int (-5))) (.prim (.int 2))⟩
          ] .regularOpen none []))
      = "div: 2.5\nwhole: 2.0\nthird: 0.3333333333333333333333333333333333\nnegative: -2.5" := by
  native_decide

theorem eval_division_by_zero_bottom :
    evalBinary .div (.prim (.int 1)) (.prim (.int 0)) = .bottomWith [.divisionByZero] := by
  rfl

theorem eval_integer_keyword_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"divValue", .regular, .binary .intDiv (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"modValue", .regular, .binary .intMod (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"quoValue", .regular, .binary .intQuo (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"remValue", .regular, .binary .intRem (.prim (.int (-7))) (.prim (.int 3))⟩
          ] .regularOpen none []))
      = "divValue: -3\nmodValue: 2\nquoValue: -2\nremValue: -1" := by
  native_decide

theorem eval_integer_keyword_incomplete_keeps_infix :
    formatValue (evalBinary .intDiv (.kind .int) (.prim (.int 3))) = "int div 3" := by
  native_decide

theorem eval_equality_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"same", .regular, .binary .eq (.prim (.int 1)) (.prim (.int 1))⟩,
            ⟨"diff", .regular, .binary .ne (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"text", .regular, .binary .eq (.prim (.string "a")) (.prim (.string "b"))⟩
          ] .regularOpen none []))
      = "same: true\ndiff: true\ntext: false" := by
  native_decide

theorem eval_ordering_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"lt", .regular, .binary .lt (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"le", .regular, .binary .le (.prim (.int 2)) (.prim (.int 2))⟩,
            ⟨"gt", .regular, .binary .gt (.prim (.int 3)) (.prim (.int 2))⟩,
            ⟨"ge", .regular, .binary .ge (.prim (.int 3)) (.prim (.int 4))⟩,
            ⟨"slt", .regular, .binary .lt (.prim (.string "a")) (.prim (.string "b"))⟩
          ] .regularOpen none []))
      = "lt: true\nle: true\ngt: true\nge: false\nslt: true" := by
  native_decide

theorem eval_numeric_comparison_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"lt", .regular, .binary .lt (.prim (.float "1.5")) (.prim (.int 2))⟩,
            ⟨"le", .regular, .binary .le (.prim (.float "1.5")) (.prim (.float "1.50"))⟩,
            ⟨"gt", .regular, .binary .gt (.prim (.float "1e+3")) (.prim (.float "999.9"))⟩,
            ⟨"ge", .regular, .binary .ge (.prim (.float "1.0")) (.prim (.int 1))⟩,
            ⟨"eq", .regular, .binary .eq (.prim (.int 1)) (.prim (.float "1.0"))⟩,
            ⟨"ne", .regular, .binary .ne (.prim (.int 1)) (.prim (.float "1.0"))⟩
          ] .regularOpen none []))
      = "lt: true\nle: true\ngt: true\nge: true\neq: true\nne: false" := by
  native_decide

theorem eval_logical_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"andFalse", .regular, .binary .boolAnd (.prim (.bool true)) (.prim (.bool false))⟩,
            ⟨"orTrue", .regular, .binary .boolOr (.prim (.bool false)) (.prim (.bool true))⟩,
            ⟨
              "andCmp",
              .regular,
              .binary .boolAnd
                (.binary .lt (.prim (.int 1)) (.prim (.int 2)))
                (.binary .gt (.prim (.int 3)) (.prim (.int 2)))
            ⟩
          ] .regularOpen none []))
      = "andFalse: false\norTrue: true\nandCmp: true" := by
  native_decide

theorem eval_logical_not_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"notFalse", .regular, .unary .boolNot (.prim (.bool false))⟩,
            ⟨"notCmp", .regular, .unary .boolNot (.binary .lt (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"double", .regular, .unary .boolNot (.unary .boolNot (.prim (.bool true)))⟩
          ] .regularOpen none []))
      = "notFalse: true\nnotCmp: false\ndouble: true" := by
  native_decide

theorem eval_unary_numeric_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"negGroup", .regular, .unary .numNeg (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"posGroup", .regular, .unary .numPos (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"negFloat", .regular, .unary .numNeg (.prim (.float "1.5"))⟩
          ] .regularOpen none []))
      = "negGroup: -3\nposGroup: 3\nnegFloat: -1.5" := by
  native_decide

theorem eval_regex_match_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"match", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "^a"))⟩,
            ⟨"miss", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "z"))⟩,
            ⟨"notMatch", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "z"))⟩
          ] .regularOpen none []))
      = "match: true\nmiss: false\nnotMatch: true" := by
  native_decide

theorem eval_list_index_out_of_range_bottom :
    (evalStructRefs
      (resolveStructRefs
        (.struct [
            ⟨"xs", .regular, .list [.prim (.int 10)]⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 2))⟩
          ] .regularOpen none []))
      == .struct [
          ⟨"xs", .regular, .list [.prim (.int 10)]⟩,
          ⟨"x", .regular, .bottomWith [.indexOutOfRange 2 1]⟩
        ] .regularOpen none []) = true := by
  native_decide

theorem eval_missing_binding_id_bottom :
    (evalStructRefs
      (.struct [⟨"x", .regular, .refId ⟨0, 2⟩⟩] .regularOpen none [])
      == .struct [⟨"x", .regular, .bottomWith [.unresolvedBinding ⟨0, 2⟩]⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_binding_id_not_label_lookup :
    (evalStructRefs
      (.struct [⟨"#same", .definition, .kind .int⟩, ⟨"same", .regular, .kind .string⟩, ⟨"x", .regular, .refId ⟨0, 1⟩⟩] .regularOpen none [])
      == .struct [⟨"#same", .definition, .kind .int⟩, ⟨"same", .regular, .kind .string⟩, ⟨"x", .regular, .kind .string⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_direct_self_reference :
    (resolveStructRefs
      (.struct [⟨"x", .regular, .ref "x"⟩] .regularOpen none [])
      == .struct [⟨"x", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_direct_self_reference_as_top :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .ref "x"⟩] .regularOpen none []))
      == .struct [⟨"x", .regular, .top⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_mutual_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .ref "y"⟩, ⟨"y", .regular, .ref "x"⟩] .regularOpen none []))
      == .struct [⟨"x", .regular, .top⟩, ⟨"y", .regular, .top⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_three_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs
        (.struct [
            ⟨"x", .regular, .ref "y"⟩,
            ⟨"y", .regular, .ref "z"⟩,
            ⟨"z", .regular, .ref "x"⟩
          ] .regularOpen none []))
      == .struct [⟨"x", .regular, .top⟩, ⟨"y", .regular, .top⟩, ⟨"z", .regular, .top⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_direct_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .conj [.ref "x", .boundConstraint (intDecimal 0) .ge .number]⟩] .regularOpen none []))
      == .struct [⟨"x", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_mutual_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs
        (.struct [
            ⟨"a", .regular, .conj [.ref "b", .boundConstraint (intDecimal 0) .ge .number]⟩,
            ⟨"b", .regular, .ref "a"⟩
          ] .regularOpen none []))
      == .struct [⟨"a", .regular, .boundConstraint (intDecimal 0) .ge .number⟩, ⟨"b", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_non_cycle_reference_still_uses_target_value :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .kind .int⟩, ⟨"y", .regular, .ref "x"⟩] .regularOpen none []))
      == .struct [⟨"x", .regular, .kind .int⟩, ⟨"y", .regular, .kind .int⟩] .regularOpen none []) = true := by
  native_decide

/-- A value alias (`Self={…}`) lowers to a `.thisStruct` let-binding; `Self.field`
    (a selector on the binding) resolves as a same-struct sibling reference. Pins the
    eval-level `thisStruct` mechanism directly. -/
theorem eval_value_alias_self_reference :
    (evalStructRefs
      (resolveStructRefs
        (.struct [
            ⟨"Self", .letBinding, .thisStruct⟩,
            ⟨"x", .regular, .prim (.int 5)⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x"⟩
          ] .regularOpen none []))
      == .struct [
          ⟨"Self", .letBinding, .thisStruct⟩,
          ⟨"x", .regular, .prim (.int 5)⟩,
          ⟨"y", .regular, .prim (.int 5)⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- A self-reference cycle through the alias is bounded to top, never diverging. -/
theorem eval_value_alias_cycle_bounds_to_top :
    (evalStructRefs
      (resolveStructRefs
        (.struct [
            ⟨"Self", .letBinding, .thisStruct⟩,
            ⟨"x", .regular, .selector (.ref "Self") "y"⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x"⟩
          ] .regularOpen none []))
      == .struct [
          ⟨"Self", .letBinding, .thisStruct⟩,
          ⟨"x", .regular, .top⟩,
          ⟨"y", .regular, .top⟩
        ] .regularOpen none []) = true := by
  native_decide

theorem eval_regular_disjunction_uses_join_normalization :
    (evalStructRefs
      (.struct [⟨"x", .regular, .disj [(.regular, .boundConstraint (intDecimal 5) .ge .number), (.regular, .boundConstraint (intDecimal 0) .ge .number)]⟩] .regularOpen none [])
      == .struct [⟨"x", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_regular_field_reference_to_hidden :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"_secret", .hidden, .prim (.string "x")⟩, ⟨"value", .regular, .ref "_secret"⟩] .regularOpen none []))
      == .struct [⟨"_secret", .hidden, .prim (.string "x")⟩, ⟨"value", .regular, .prim (.string "x")⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_reference_inside_struct_tail :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"#A", .definition, .kind .int⟩] .defOpenViaTail (some (.ref "#A")) []))
      == .struct [⟨"#A", .definition, .kind .int⟩] .defOpenViaTail (some (.kind .int)) []) = true := by
  native_decide

theorem eval_reference_inside_nested_struct :
    (evalStructRefs
      (resolveStructRefs
        (.struct [⟨"x", .regular, .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] .regularOpen none []⟩] .regularOpen none []))
      == .struct [⟨"x", .regular, .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] .regularOpen none []⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_reference_inside_struct_pattern :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"#A", .definition, .kind .int⟩] .regularOpen none [((.kind .string), (.ref "#A"))]))
      == .struct [⟨"#A", .definition, .kind .int⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem eval_struct_pattern_constrains_own_regular_field :
    (evalStructRefs
      (.struct [⟨"a", .regular, .prim (.string "bad")⟩] .regularOpen none [((.kind .string), (.kind .int))])
      == .struct [⟨"a", .regular, .bottomWith [.fieldConstraint "a"]⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem string_kind_pattern_types_matching_field :
    (meet
      (.struct [] .regularOpen none [((.kind .string), (.kind .int))])
      (.struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      == .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem string_kind_pattern_rejects_type_mismatch :
    containsBottom
      (meet
        (.struct [] .regularOpen none [((.kind .string), (.kind .int))])
        (.struct [⟨"a", .regular, .prim (.string "x")⟩] .regularOpen none [])) = true := by
  native_decide

theorem eval_len_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (.struct [⟨"x", .regular, .prim (.string "abc")⟩, ⟨"y", .regular, .builtinCall "len" [.ref "x"]⟩] .regularOpen none []))
      == .struct [⟨"x", .regular, .prim (.string "abc")⟩, ⟨"y", .regular, .prim (.int 3)⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_integer_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (.struct [
            ⟨"n", .regular, .prim (.int (-7))⟩,
            ⟨"q", .regular, .builtinCall "div" [.ref "n", .prim (.int 3)]⟩
          ] .regularOpen none []))
      == .struct [⟨"n", .regular, .prim (.int (-7))⟩, ⟨"q", .regular, .prim (.int (-3))⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_incomplete_builtin_call_remains_call :
    (evalStructRefs (.struct [⟨"x", .regular, .builtinCall "len" [.kind .string]⟩] .regularOpen none [])
      == .struct [⟨"x", .regular, .builtinCall "len" [.kind .string]⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_comprehension_for_keyed_over_struct :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [
            .comprehension
              [.forIn (some "k") "v" (.struct [⟨"x", .regular, .prim (.int 1)⟩] .regularOpen none [])]
              (.struct [⟨"key", .regular, .ref "k"⟩, ⟨"val", .regular, .ref "v"⟩] .regularOpen none [])
          ]
          true false))
      == .struct [⟨"key", .regular, .prim (.string "x")⟩, ⟨"val", .regular, .prim (.int 1)⟩] .regularOpen none [])
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
              (.struct [⟨"only", .regular, .ref "v"⟩] .regularOpen none [])
          ]
          true false))
      == .struct [⟨"only", .regular, .prim (.int 42)⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_comprehension_if_true_admits :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [.comprehension [.guard (.prim (.bool true))] (.struct [⟨"flag", .regular, .prim (.bool true)⟩] .regularOpen none [])]
          true false))
      == .struct [⟨"flag", .regular, .prim (.bool true)⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_comprehension_if_false_drops :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [.comprehension [.guard (.prim (.bool false))] (.struct [⟨"hidden", .regular, .prim (.int 1)⟩] .regularOpen none [])]
          true false))
      == .struct [] .regularOpen none []) = true := by
  native_decide

theorem eval_comprehension_body_sees_sibling_field :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          [⟨"base", .regular, .prim (.int 7)⟩]
          [.comprehension [.guard (.prim (.bool true))] (.struct [⟨"copy", .regular, .ref "base"⟩] .regularOpen none [])]
          true false))
      == .struct [⟨"base", .regular, .prim (.int 7)⟩, ⟨"copy", .regular, .prim (.int 7)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem eval_comprehension_for_source_sees_sibling_field :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          [⟨"k", .regular, .prim (.int 3)⟩]
          [.comprehension [.forIn none "v" (.list [.ref "k"])] (.struct [⟨"g", .regular, .ref "v"⟩] .regularOpen none [])]
          true false))
      == .struct [⟨"k", .regular, .prim (.int 3)⟩, ⟨"g", .regular, .prim (.int 3)⟩] .regularOpen none [])
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

/-- Slice F1. A unary op RESOLVES its disjunction operand to the default first, then applies
    the scalar op — it does NOT distribute. `!(bool | *false)` resolves to `false`, then
    `!false = true`. (Old slice-C behavior `bool | *true` was wrong: CUE forces the operand
    concrete; `!(bool | *false)` → `true`, oracle-verified.) -/
theorem distribute_not_over_default_disj :
    (distributeUnary .boolNot (.disj [(.default, .prim (.bool false)), (.regular, .kind .bool)])
      == .prim (.bool true)) = true := by
  native_decide

/-- Slice F1. `(int | *1) + 1` resolves the operand to `1`, then `1 + 1 = 2` — NOT
    `int+1 | *2`. CUE forces arithmetic operands concrete (`(int | *1) + 1 → 2`,
    oracle-verified), never a cross-product. -/
theorem distribute_add_over_default_disj :
    (distributeBinary .add (.disj [(.default, .prim (.int 1)), (.regular, .kind .int)]) (.prim (.int 1))
      == .prim (.int 2)) = true := by
  native_decide

/-- Slice C. The negated real-app guard shape: `x: bool | *false; if !x { y: 1 }`. The `!`
    distributes over the default disjunction and the guard collapses the default to `true`,
    so the body admits. cue-exact (`{x: false, out: {y: 1}}`). -/
theorem eval_comprehension_guard_negated_default_disj_admits :
    (evalStructRefs
      (resolveStructRefs
        (.struct [⟨"x", .regular, .disj [(.default, .prim (.bool false)), (.regular, .kind .bool)]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.unary .boolNot (.ref "x"))]
                 (.struct [⟨"y", .regular, .prim (.int 1)⟩] .regularOpen none [])]
               true false⟩] .regularOpen none []))
      == .struct [⟨"x", .regular, .disj [(.default, .prim (.bool false)), (.regular, .kind .bool)]⟩,
         ⟨"out", .regular, .struct [⟨"y", .regular, .prim (.int 1)⟩] .regularOpen none []⟩] .regularOpen none []) = true := by
  native_decide

/-- Slice C. The direct guard shape `if x` with `x: bool | *true` admits (default `true`). -/
theorem eval_comprehension_guard_direct_default_disj_admits :
    (evalStructRefs
      (resolveStructRefs
        (.struct [⟨"x", .regular, .disj [(.default, .prim (.bool true)), (.regular, .kind .bool)]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.ref "x")]
                 (.struct [⟨"y", .regular, .prim (.int 1)⟩] .regularOpen none [])]
               true false⟩] .regularOpen none []))
      == .struct [⟨"x", .regular, .disj [(.default, .prim (.bool true)), (.regular, .kind .bool)]⟩,
         ⟨"out", .regular, .struct [⟨"y", .regular, .prim (.int 1)⟩] .regularOpen none []⟩] .regularOpen none []) = true := by
  native_decide

/-- Slice C (over-resolution guard). A NON-default disjunction in a guard must STAY
    unsatisfied — only marked defaults collapse. `if x` with `x: bool` (no default) drops
    the body, matching cue's `incomplete value bool`. -/
theorem eval_comprehension_guard_non_default_disj_drops :
    (evalStructRefs
      (resolveStructRefs
        (.struct [⟨"x", .regular,
             .disj [(.regular, .prim (.bool true)), (.regular, .prim (.bool false))]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.ref "x")]
                 (.struct [⟨"y", .regular, .prim (.int 1)⟩] .regularOpen none [])]
               true false⟩] .regularOpen none []))
      == .struct [⟨"x", .regular,
           .disj [(.regular, .prim (.bool true)), (.regular, .prim (.bool false))]⟩,
         ⟨"out", .regular, .struct [] .regularOpen none []⟩] .regularOpen none []) = true := by
  native_decide

/-! ### Slice F1 — default-mark algebra (audit #3 Violation)

    Three coupled facets, oracle-verified against `cue` v0.16.1:
    (1) unification ANDs default sets across the cross product (was OR);
    (2) `flattenAlternatives` honors two-level default precedence (a default-marked outer
        arm selects the inner disjunction's own default structure);
    (3) equal defaults dedup before the unique-default test.
    Arithmetic/comparison/unary ops resolve each operand to its default FIRST (no
    distribution / cross-product). -/

/-- F1 facet 1, the cross-product where `combineMark` lives. Unification ANDs the default
    sets: `(1|*2) & (1|2|3)` → the no-`*` right operand contributes its whole set as
    defaults, so only `*2 & 2` survives as a default → resolves to `2`. -/
theorem f1_unify_cross_and_marks_resolves :
    (resolveDisjDefault?
      (match meet
          (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
          (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2)), (.regular, .prim (.int 3))]) with
        | .disj alts => alts
        | _ => [])
      == some (.prim (.int 2))) = true := by
  native_decide

/-- F1 facet 1, NEGATIVE: two distinct defaults survive the cross → ambiguous (no resolve).
    `(*1|2) & (1|*2)` crosses to live `1|2` with no surviving default (`*1&1` regular,
    `2&*2` regular) → stays the disjunction `1 | 2`. -/
theorem f1_unify_cross_two_survivors_ambiguous :
    (meet
      (.disj [(.default, .prim (.int 1)), (.regular, .prim (.int 2))])
      (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
      == .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]) = true := by
  native_decide

/-- F1. `combineMark` is AND: a result alternative is default iff BOTH inputs were. -/
theorem f1_combine_mark_is_and :
    (combineMark .default .default == .default
      && combineMark .default .regular == .regular
      && combineMark .regular .default == .regular
      && combineMark .regular .regular == .regular) = true := by
  native_decide

/-- F1 facet 3, equal-default dedup. `*1 | *1 | 2` → the two equal defaults collapse to one,
    so a unique default remains → resolves to `1`. The headline dedup case. -/
theorem f1_equal_defaults_dedup_resolves :
    (resolveDisjDefault?
      [(.default, .prim (.int 1)), (.default, .prim (.int 1)), (.regular, .prim (.int 2))]
      == some (.prim (.int 1))) = true := by
  native_decide

/-- F1 facet 3, NEGATIVE: DISTINCT defaults stay ambiguous (no spurious dedup). -/
theorem f1_distinct_defaults_stay_ambiguous :
    (resolveDisjDefault? [(.default, .prim (.int 1)), (.default, .prim (.int 2))]
      == none) = true := by
  native_decide

/-- F1 facet 2, two-level default precedence. `*d | 5` with `d : 1 | 2` (no inner default):
    the outer default selects `d`'s disjunction, promoting its own arms to defaults (no
    inner `*` → both `1` and `2` become defaults), while the regular outer `5` stays
    regular. The flatten thus carries the inner default structure rather than blanket- or
    OR-marking — the OLD bug produced `*1 | 2 | 5`. -/
theorem f1_nested_default_flatten_carries_inner :
    (liveAlternatives
      [(.default, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == [(.default, .prim (.int 1)), (.default, .prim (.int 2)), (.regular, .prim (.int 5))]) = true := by
  native_decide

/-- F1 facet 2, precedence at resolve. With the `*d | 5` flatten above, the two carried
    defaults `1`, `2` are DISTINCT → `resolveDisjDefault?` shadows the regular `5` and stays
    ambiguous (matches cue `incomplete value 1 | 2`), neither resolving to `1` nor keeping
    `5`. -/
theorem f1_nested_default_flatten_resolve_ambiguous :
    (resolveDisjDefault?
      [(.default, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == none) = true := by
  native_decide

/-- F1 facet 2. `*d | 5` with `d : *1 | 2` (inner default `*1`): only the inner default
    carries → unique default `1` → resolves to `1` (matches cue). -/
theorem f1_nested_inner_default_resolves :
    (resolveDisjDefault?
      [(.default, .disj [(.default, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == some (.prim (.int 1))) = true := by
  native_decide

/-- F1 facet 2, NEGATIVE: a REGULAR outer arm does NOT contribute its inner disjunction to
    the default set. `d | *5` with `d : 1 | 2` → `d`'s arms stay regular (shed), the lone
    default `5` wins → resolves to `5`. -/
theorem f1_nested_regular_outer_sheds :
    (resolveDisjDefault?
      [(.regular, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.default, .prim (.int 5))]
      == some (.prim (.int 5))) = true := by
  native_decide

/-- F1, arithmetic resolve-first. `(1|*2) + (10|*20)` resolves each operand to its default
    (`2`, `20`) then adds → `22`. The headline arithmetic case; NOT a mark cross-product. -/
theorem f1_arithmetic_resolves_operands_first :
    (distributeBinary .add
      (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
      (.disj [(.regular, .prim (.int 10)), (.default, .prim (.int 20))])
      == .prim (.int 22)) = true := by
  native_decide

/-- F1, arithmetic NEGATIVE: a no-default operand does NOT resolve, so the op stays a stuck
    node — `(1|2) + 10` keeps the unevaluated `(1|2) + 10`, matching cue's "unresolved
    disjunction" (manifest reports incomplete), never an over-resolution. -/
theorem f1_arithmetic_no_default_stays_stuck :
    (distributeBinary .add
      (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))])
      (.prim (.int 10))
      == .binary .add (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]) (.prim (.int 10)))
      = true := by
  native_decide

/-- F1, a non-default disjunction stays a non-default disjunction through resolve — no arm
    becomes a default and it does not collapse (`1 | 2` stays ambiguous). -/
theorem f1_non_default_disj_stays_non_default :
    (resolveDisjDefault? [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]
      == none) = true := by
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
      (.struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      == .struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none []) = true := by
  native_decide

/-- A duplicate-label conflict bottoms both the label and any sibling referencing it:
    `{a: 1, b: a, a: 2}` -> `a` and `b` both bottom. -/
theorem eval_in_struct_sibling_conflict :
    (resolveAndEval
      (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 2)⟩] .regularOpen none [])
      == .struct [
          ⟨"a", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)]⟩,
          ⟨"b", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)]⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- Canonicalization is visible through nested sub-structs: `c.e` references the outer `a`,
    seeing the merged `int & 1 = 1`. -/
theorem eval_nested_sibling_merge :
    (resolveAndEval
      (.struct [
          ⟨"a", .regular, .kind .int⟩,
          ⟨"c", .regular, .struct [⟨"e", .regular, .ref "a"⟩] .regularOpen none []⟩,
          ⟨"a", .regular, .prim (.int 1)⟩
        ] .regularOpen none [])
      == .struct [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"c", .regular, .struct [⟨"e", .regular, .prim (.int 1)⟩] .regularOpen none []⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- A self-referential merged slot must not loop: `{a: a, a: 1}` canonicalizes to
    `.conj [a, 1]` at slot 0; the self-ref hits the `slotVisited` -> `.top` guard, so the
    meet collapses to `1` rather than diverging. -/
theorem eval_merged_self_ref_cycle :
    (resolveAndEval
      (.struct [⟨"a", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      == .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []) = true := by
  native_decide

/-- 2c.2: struct conjunction through a referenced binding. `d & {a: 1}` merges the conjuncts'
    declarations into one frame before evaluating bodies, so `d.b: a` sees the narrowed `a`
    and `y.b` resolves to `1` (not `int`). -/
theorem eval_meet_lazy_sibling_ref :
    (resolveAndEval
      (.struct [
          ⟨"d", .regular, .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] .regularOpen none []⟩,
          ⟨"y", .regular, .conj [.ref "d", .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []]⟩
        ] .regularOpen none [])
      == .struct [
          ⟨"d", .regular, .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .kind .int⟩] .regularOpen none []⟩,
          ⟨"y", .regular,
            .struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none []⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- 2c.2: literal struct conjunction (no reference operand). `{a: int, b: a} & {a: 1}` → `b: 1`
    via the merged frame. -/
theorem eval_meet_lazy_literal :
    (resolveAndEval
      (.struct [
          ⟨"x", .regular,
            .conj
              [
                .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] .regularOpen none [],
                .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []
              ]⟩
        ] .regularOpen none [])
      == .struct [
          ⟨"x", .regular,
            .struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none []⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- 2c.2: a chained sibling reference within one conjunct, narrowed across the meet —
    `{a: int, b: a, c: b} & {a: 1}` resolves `a`, `b`, `c` all to `1`. -/
theorem eval_meet_lazy_chain :
    (resolveAndEval
      (.struct [
          ⟨"x", .regular,
            .conj
              [
                .struct [
                    ⟨"a", .regular, .kind .int⟩,
                    ⟨"b", .regular, .ref "a"⟩,
                    ⟨"c", .regular, .ref "b"⟩
                  ] .regularOpen none [],
                .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []
              ]⟩
        ] .regularOpen none [])
      == .struct [
          ⟨"x", .regular,
            .struct [
                ⟨"a", .regular, .prim (.int 1)⟩,
                ⟨"b", .regular, .prim (.int 1)⟩,
                ⟨"c", .regular, .prim (.int 1)⟩
              ] .regularOpen none []⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- 2c.2: nested sub-struct visibility through a *definition* meet. `out.val` references the
    hidden `#x`; `#D & {#x: "hi"}` narrows `#x` and the nested `out.val` resolves to `"hi"`. -/
theorem eval_meet_lazy_hidden_def :
    (resolveAndEval
      (.struct [
          ⟨"#D", .definition,
            .struct [
                ⟨"#x", .definition, .kind .string⟩,
                ⟨"out", .regular, .struct [⟨"val", .regular, .ref "#x"⟩] .regularOpen none []⟩
              ] .regularOpen none []⟩,
          ⟨"y", .regular, .conj [.ref "#D", .struct [⟨"#x", .definition, .prim (.string "hi")⟩] .regularOpen none []]⟩
        ] .regularOpen none [])
      == .struct [
          ⟨"#D", .definition,
            .struct [
                ⟨"#x", .definition, .kind .string⟩,
                ⟨"out", .regular, .struct [⟨"val", .regular, .kind .string⟩] .regularOpen none []⟩
              ] .defClosed none []⟩,
          ⟨"y", .regular,
            .struct [
                ⟨"#x", .definition, .prim (.string "hi")⟩,
                ⟨"out", .regular, .struct [⟨"val", .regular, .prim (.string "hi")⟩] .regularOpen none []⟩
              ] .defClosed none []⟩
        ] .regularOpen none []) = true := by
  native_decide

/-! ### B2.2 must-fix item 3 — `applyEvaluatedStructN` pattern path (end-to-end, live).

With production emitting the unified `.struct`, an evaluated pattern-struct now flows through
`applyEvaluatedStructN`'s pattern arm (`meet (mkStruct [] op none patterns) (mkStruct fields
…)`), which applies each `[pattern]: constraint` to the matching evaluated fields. These pin
that arm against cue v0.16.1: a matching field is constrained (`xy` matches `=~"x"`, so
`string & "hi" = "hi"`; a conflicting constraint bottoms it), a non-matching field is left
untouched (`z`). cue elides the residual `[=~"x"]: c` pattern in `eval` output but APPLIES it;
Kue keeps the pattern visible (a formatting divergence, recorded) — the field VALUES agree
exactly with cue (`xy: "hi"`/`xy: _|_`, `z: 1`). -/
theorem eval_pattern_struct_applies_to_matching_field :
    evalSourceMatches
        "out: {[=~\"x\"]: string, xy: \"hi\", z: 1}\n"
        "out: {xy: \"hi\", z: 1, [=~\"x\"]: string}"
      = true := by
  native_decide

theorem eval_pattern_struct_constraint_conflict_bottoms_field :
    evalSourceMatches
        "out: {[=~\"x\"]: int, xy: \"str\"}\n"
        "out: {xy: _|_, [=~\"x\"]: int}"
      = true := by
  native_decide

/-! ### B6 — definition-body closedness enforced through a regular field (gap 1).

A closed `#Def` nested under a REGULAR field reaches the use-site meet still closed, so an
undeclared field is rejected. Pre-B6 `normalizeFieldWithFuel` left a regular field's value
unwalked, so the nested def stayed open and admitted the extra. Oracle: cue v0.16.1 reports
`out.extra: field not allowed` for the closed form and admits `extra` when the def is opened via
`...`. The eager-selector form (`x.#Inner`, gap 2) is the SAME root cause — once normalize closes
the def, the eager selector returns the closed body and the existing meet enforces it. -/
theorem eval_closed_def_under_regular_field_rejects_extra :
    evalSourceMatches
        "a: {\n\t#Inner: {x: int}\n}\nout: a.#Inner & {x: 1, extra: 2}\n"
        "a: {#Inner: {x: int}}\nout: {x: 1, extra: _|_}"
      = true := by
  native_decide

theorem eval_eager_selector_closed_def_rejects_extra :
    evalSourceMatches
        "x: {#Inner: {y: int}}\nout: x.#Inner & {y: 1, extra: 3}\n"
        "x: {#Inner: {y: int}}\nout: {y: 1, extra: _|_}"
      = true := by
  native_decide

theorem eval_open_def_under_regular_field_admits_extra :
    evalSourceMatches
        "a: {\n\t#Inner: {x: int, ...}\n}\nout: a.#Inner & {x: 1, extra: 2}\n"
        "a: {#Inner: {x: int, ...}}\nout: {x: 1, extra: 2, ...}"
      = true := by
  native_decide


end Kue
