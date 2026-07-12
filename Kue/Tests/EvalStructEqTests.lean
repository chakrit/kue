import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

-- Slice 2c.1: an in-struct sibling reference (`b: a`) sees the FULLY-MERGED value of a
-- duplicated label, not the first conjunct. `{a: int, b: a, a: 1}` canonicalizes the two
-- `a` slots into `.conj [int, 1]` at slot 0, so `b` evaluates to `1`, and the duplicate
-- collapses to a single `a` field.
theorem eval_in_struct_sibling_merge :
    (resolveAndEval
      (mkStruct [⟨"a", .regular, .kind .int, false⟩, ⟨"b", .regular, .ref "a", false⟩, ⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 1), false⟩] .regularOpen none []) = true := by
  native_decide

-- A duplicate-label conflict bottoms both the label and any sibling referencing it:
-- `{a: 1, b: a, a: 2}` -> `a` and `b` both bottom.
theorem eval_in_struct_sibling_conflict :
    (resolveAndEval
      (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .ref "a", false⟩, ⟨"a", .regular, .prim (.int 2), false⟩] .regularOpen none [])
      == mkStruct [
          ⟨"a", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)], false⟩,
          ⟨"b", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- Canonicalization is visible through nested sub-structs: `c.e` references the outer `a`,
-- seeing the merged `int & 1 = 1`.
theorem eval_nested_sibling_merge :
    (resolveAndEval
      (mkStruct [
          ⟨"a", .regular, .kind .int, false⟩,
          ⟨"c", .regular, mkStruct [⟨"e", .regular, .ref "a", false⟩] .regularOpen none [], false⟩,
          ⟨"a", .regular, .prim (.int 1), false⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"a", .regular, .prim (.int 1), false⟩,
          ⟨"c", .regular, mkStruct [⟨"e", .regular, .prim (.int 1), false⟩] .regularOpen none [], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- A self-referential merged slot must not loop: `{a: a, a: 1}` canonicalizes to
-- `.conj [a, 1]` at slot 0; the self-ref hits the `slotVisited` -> `.top` guard, so the
-- meet collapses to `1` rather than diverging.
theorem eval_merged_self_ref_cycle :
    (resolveAndEval
      (mkStruct [⟨"a", .regular, .ref "a", false⟩, ⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none []) = true := by
  native_decide

-- 2c.2: struct conjunction through a referenced binding. `d & {a: 1}` merges the conjuncts'
-- declarations into one frame before evaluating bodies, so `d.b: a` sees the narrowed `a`
-- and `y.b` resolves to `1` (not `int`).
theorem eval_meet_lazy_sibling_ref :
    (resolveAndEval
      (mkStruct [
          ⟨"d", .regular, mkStruct [⟨"a", .regular, .kind .int, false⟩, ⟨"b", .regular, .ref "a", false⟩] .regularOpen none [], false⟩,
          ⟨"y", .regular, .conj [.ref "d", mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none []], false⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"d", .regular, mkStruct [⟨"a", .regular, .kind .int, false⟩, ⟨"b", .regular, .kind .int, false⟩] .regularOpen none [], false⟩,
          ⟨"y", .regular,
            mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 1), false⟩] .regularOpen none [], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- 2c.2: literal struct conjunction (no reference operand). `{a: int, b: a} & {a: 1}` → `b: 1`
-- via the merged frame.
theorem eval_meet_lazy_literal :
    (resolveAndEval
      (mkStruct [
          ⟨"x", .regular,
            .conj
              [
                mkStruct [⟨"a", .regular, .kind .int, false⟩, ⟨"b", .regular, .ref "a", false⟩] .regularOpen none [],
                mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none []
              ], false⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"x", .regular,
            mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 1), false⟩] .regularOpen none [], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- 2c.2: a chained sibling reference within one conjunct, narrowed across the meet —
-- `{a: int, b: a, c: b} & {a: 1}` resolves `a`, `b`, `c` all to `1`.
theorem eval_meet_lazy_chain :
    (resolveAndEval
      (mkStruct [
          ⟨"x", .regular,
            .conj
              [
                mkStruct [
                    ⟨"a", .regular, .kind .int, false⟩,
                    ⟨"b", .regular, .ref "a", false⟩,
                    ⟨"c", .regular, .ref "b", false⟩
                  ] .regularOpen none [],
                mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none []
              ], false⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"x", .regular,
            mkStruct [
                ⟨"a", .regular, .prim (.int 1), false⟩,
                ⟨"b", .regular, .prim (.int 1), false⟩,
                ⟨"c", .regular, .prim (.int 1), false⟩
              ] .regularOpen none [], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- 2c.2: nested sub-struct visibility through a *definition* meet. `out.val` references the
-- hidden `#x`; `#D & {#x: "hi"}` narrows `#x` and the nested `out.val` resolves to `"hi"`.
theorem eval_meet_lazy_hidden_def :
    (resolveAndEval
      (mkStruct [
          ⟨"#D", .definition,
            mkStruct [
                ⟨"#x", .definition, .kind .string, false⟩,
                ⟨"out", .regular, mkStruct [⟨"val", .regular, .ref "#x", false⟩] .regularOpen none [], false⟩
              ] .regularOpen none [], false⟩,
          ⟨"y", .regular, .conj [.ref "#D", mkStruct [⟨"#x", .definition, .prim (.string "hi"), false⟩] .regularOpen none []], false⟩
        ] .regularOpen none [])
      -- SC-2: `#D`'s nested regular field `out` is a plain struct WITHIN the def body, so the
      -- closing walker closes its value (`.defClosed`) — recursively, like every nested
      -- def-body plain struct. The closure carries through the `#D & {…}` meet to `y.out`
      -- (monotone). Formatted output is unchanged (closedness is invisible in `eval` display).
      == mkStruct [
          ⟨"#D", .definition,
            mkStruct [
                ⟨"#x", .definition, .kind .string, false⟩,
                ⟨"out", .regular, mkStruct [⟨"val", .regular, .kind .string, false⟩] .defClosed none [], false⟩
              ] .defClosed none [], false⟩,
          ⟨"y", .regular,
            mkStruct [
                ⟨"#x", .definition, .prim (.string "hi"), false⟩,
                ⟨"out", .regular, mkStruct [⟨"val", .regular, .prim (.string "hi"), false⟩] .defClosed none [], false⟩
              ] .defClosed none [], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- ## Concrete struct/list equality (`evalEq` beyond `.prim`)

-- Order-INDEPENDENT struct equality: `{a:1,b:2} == {b:2,a:1}` ⇒ `true`.
theorem eval_eq_struct_reordered_true :
    (evalEq
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none [])
        (mkStruct [⟨"b", .regular, .prim (.int 2), false⟩, ⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == .prim (.bool true)) = true := by
  native_decide

-- Quoted vs unquoted label is the SAME field (`quoted` bit ignored by `structuralEq`).
theorem eval_eq_struct_quoted_label_true :
    (evalEq
        (mkStruct [⟨"x", .regular, .prim (.int 1), true⟩] .regularOpen none [])
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == .prim (.bool true)) = true := by
  native_decide

-- Differing regular value ⇒ `false`.
theorem eval_eq_struct_unequal_false :
    (evalEq
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])
        (mkStruct [⟨"x", .regular, .prim (.int 2), false⟩] .regularOpen none [])
      == .prim (.bool false)) = true := by
  native_decide

-- Differing output-field COUNT ⇒ `false`.
theorem eval_eq_struct_diff_size_false :
    (evalEq
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩, ⟨"y", .regular, .prim (.int 2), false⟩] .regularOpen none [])
      == .prim (.bool false)) = true := by
  native_decide

-- Hidden field differs but is NON-output ⇒ still `true`.
theorem eval_eq_struct_hidden_ignored_true :
    (evalEq
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩, ⟨"_h", .hidden, .prim (.int 9), false⟩] .regularOpen none [])
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == .prim (.bool true)) = true := by
  native_decide

-- Empty structs are equal.
theorem eval_eq_empty_structs_true :
    (evalEq (mkStruct [] .regularOpen none []) (mkStruct [] .regularOpen none []) == .prim (.bool true)) = true := by
  native_decide

-- Lists are ORDER-sensitive: `[1,2,3] == [3,2,1]` ⇒ `false`.
theorem eval_eq_list_reordered_false :
    (evalEq
        (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)])
        (.list [.prim (.int 3), .prim (.int 2), .prim (.int 1)])
      == .prim (.bool false)) = true := by
  native_decide

-- Equal lists ⇒ `true`; different length ⇒ `false`.
theorem eval_eq_list_equal_true :
    (evalEq (.list [.prim (.int 1), .prim (.int 2)]) (.list [.prim (.int 1), .prim (.int 2)]) == .prim (.bool true)) = true := by
  native_decide

theorem eval_eq_list_diff_length_false :
    (evalEq (.list [.prim (.int 1)]) (.list [.prim (.int 1), .prim (.int 2)]) == .prim (.bool false)) = true := by
  native_decide

-- Open-tailed list drops its tail: `[1, ...] == [1]` ⇒ `true`.
theorem eval_eq_open_list_vs_closed_true :
    (evalEq (.listTail [.prim (.int 1)] .top) (.list [.prim (.int 1)]) == .prim (.bool true)) = true := by
  native_decide

-- Struct vs list ⇒ `false` (cross-shape).
theorem eval_eq_struct_vs_list_false :
    (evalEq (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none []) (.list [.prim (.int 1)])
      == .prim (.bool false)) = true := by
  native_decide

-- The over-eager DEFER guard: an INCOMPLETE (ref) field keeps `==` residual, NOT a bool —
-- even when another field already differs.
theorem eval_eq_incomplete_field_defers :
    (structEqConcrete?
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .ref "z", false⟩] .regularOpen none [])
        (mkStruct [⟨"a", .regular, .prim (.int 2), false⟩, ⟨"b", .regular, .ref "z", false⟩] .regularOpen none [])
      == none) = true := by
  native_decide

-- A REQUIRED field is not settled ⇒ DEFER.
theorem eval_eq_required_field_defers :
    (structEqConcrete?
        (mkStruct [⟨"x", .required, .prim (.int 1), false⟩] .regularOpen none [])
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == none) = true := by
  native_decide

-- `evalNe` inherits the negation for free.
theorem eval_ne_struct_reordered_false :
    (evalNe
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none [])
        (mkStruct [⟨"b", .regular, .prim (.int 2), false⟩, ⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == .prim (.bool false)) = true := by
  native_decide

-- int-vs-float leaves compare BY VALUE, recursively inside containers (CUE spec: list/struct
-- `==` is recursive element equality; number `==` converts int to float). `cue` v0.16.1 returns
-- `false` for the container cases (STRUCT-EQ-LEAF-TYPESENSE) — a `cue` bug; Kue is spec-correct.
theorem eval_eq_scalar_int_float_true :
    (evalEq (.prim (.int 1)) (.prim (mkFloatText "1.0")) == .prim (.bool true)) = true := by
  native_decide

theorem eval_eq_list_int_vs_float_true :
    (evalEq (.list [.prim (.int 1)]) (.list [.prim (mkFloatText "1.0")]) == .prim (.bool true)) = true := by
  native_decide

theorem eval_eq_struct_int_vs_float_true :
    (evalEq
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
        (mkStruct [⟨"a", .regular, .prim (mkFloatText "1.0"), false⟩] .regularOpen none [])
      == .prim (.bool true)) = true := by
  native_decide

-- Depth: int-vs-float nested two containers deep still compares by value.
theorem eval_eq_nested_list_int_vs_float_true :
    (evalEq (.list [.list [.prim (.int 1)]]) (.list [.list [.prim (mkFloatText "1.0")]])
      == .prim (.bool true)) = true := by
  native_decide

-- A value-UNEQUAL int-vs-float leaf inside a container is `false` (not merely type-blind).
theorem eval_eq_list_int_vs_float_unequal_false :
    (evalEq (.list [.prim (.int 1)]) (.list [.prim (mkFloatText "2.0")]) == .prim (.bool false)) = true := by
  native_decide

-- `evalNe` inherits the negation: `[1] != [1.0]` ⇒ `false`.
theorem eval_ne_list_int_vs_float_false :
    (evalNe (.list [.prim (.int 1)]) (.list [.prim (mkFloatText "1.0")]) == .prim (.bool false)) = true := by
  native_decide
-- COVERAGE TRIPWIRE (test-health). Anchors the LAST theorem of every section; a swallowed
-- section turns its anchor into an unknown identifier and `#check` fails to elaborate.
#check @eval_meet_lazy_hidden_def                            -- in-struct sibling merge / lazy meet
#check @eval_ne_list_int_vs_float_false                      -- concrete struct/list equality

end Kue
