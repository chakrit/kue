import Kue.Eval
import Kue.Format
import Kue.Resolve
import Kue.Runtime

namespace Kue

/-! `e == _|_` / `e != _|_` is CUE's definedness test, not value equality. These pin the
three-way classification (defined / error / incomplete) and the comprehension guard's use
of it, plus that ordinary `==`/`!=` on non-`_|_` operands is unchanged. -/

-- Classification: resolved values are `defined`, evaluated bottoms are `error`, residual
-- forms are `incomplete`.
theorem classify_prim_defined :
    classifyDefinedness (.prim (.int 1)) = .defined := by native_decide

theorem classify_struct_defined :
    classifyDefinedness (mkStruct [⟨"x", .regular, .prim (.int 1)⟩] .regularOpen none []) = .defined := by
  native_decide

theorem classify_bottom_error :
    classifyDefinedness .bottom = .error := by native_decide

theorem classify_kind_incomplete :
    classifyDefinedness (.kind .int) = .incomplete := by native_decide

theorem classify_selector_incomplete :
    classifyDefinedness (.selector (.ref "x") "g") = .incomplete := by native_decide

-- A disjunction with a live arm is a present value.
theorem classify_live_disj_defined :
    classifyDefinedness (.disj [(.regular, .prim (.int 1)), (.regular, .bottom)]) = .defined := by
  native_decide

-- A3 (untyped-invariant guard): an empty / all-bottom disjunction is bottom, NOT defined —
-- classified by its LIVE arms so a `.disj []` or `.disj [all-bottom]` slipping past pruning
-- cannot misclassify an absent value as present (`X != _|_` would wrongly be `true`).
theorem classify_empty_disj_error :
    classifyDefinedness (.disj []) = .error := by native_decide

theorem classify_all_bottom_disj_error :
    classifyDefinedness (.disj [(.regular, .bottom), (.regular, .bottomWith [.boundConflict])])
      = .error := by native_decide

-- The presence test over an all-bottom disjunction reports ABSENT: `!= _|_` is `false`.
theorem all_bottom_disj_ne_bottom_false :
    (evalPresenceTest false (.disj [(.regular, .bottom), (.regular, .bottom)])
      == .prim (.bool false)) = true := by
  native_decide

-- A concrete operand: `!= _|_` is true, `== _|_` is false.
theorem concrete_ne_bottom_true :
    (evalStructRefs (resolveStructRefs
      (mkStruct [⟨"b", .regular, .binary .ne (.prim (.int 1)) .bottom⟩] .regularOpen none []))
      == mkStruct [⟨"b", .regular, .prim (.bool true)⟩] .regularOpen none []) = true := by
  native_decide

theorem concrete_eq_bottom_false :
    (evalStructRefs (resolveStructRefs
      (mkStruct [⟨"b", .regular, .binary .eq (.prim (.int 1)) .bottom⟩] .regularOpen none []))
      == mkStruct [⟨"b", .regular, .prim (.bool false)⟩] .regularOpen none []) = true := by
  native_decide

-- An incomplete operand keeps the comparison residual (never resolves to a bool).
theorem incomplete_ne_bottom_residual :
    (evalPresenceTest false (.kind .int) == .binary .ne (.kind .int) .bottom) = true := by
  native_decide

-- The comprehension guard fires when the tested field is present.
theorem guard_fires_on_present :
    (evalStructRefs (resolveStructRefs
      (.structComp
        [⟨"f", .regular, .prim (.int 3)⟩]
        [.comprehension
          [.guard (.binary .ne (.ref "f") .bottom)]
          (mkStruct [⟨"seen", .regular, .ref "f"⟩] .regularOpen none [])]
        .regularOpen))
      == mkStruct [⟨"f", .regular, .prim (.int 3)⟩, ⟨"seen", .regular, .prim (.int 3)⟩] .regularOpen none [])
      = true := by
  native_decide

-- The comprehension guard drops when the tested field is absent (residual selector).
theorem guard_drops_on_absent :
    (evalStructRefs (resolveStructRefs
      (.structComp
        [⟨"base", .regular, mkStruct [⟨"f", .regular, .prim (.int 3)⟩] .regularOpen none []⟩]
        [.comprehension
          [.guard (.binary .ne (.selector (.ref "base") "g") .bottom)]
          (mkStruct [⟨"seen", .regular, .prim (.bool true)⟩] .regularOpen none [])]
        .regularOpen))
      == mkStruct [⟨"base", .regular, mkStruct [⟨"f", .regular, .prim (.int 3)⟩] .regularOpen none []⟩] .regularOpen none [])
      = true := by
  native_decide

-- Regression: ordinary `!=`/`==` on non-`_|_` operands is unchanged.
theorem ordinary_ne_unchanged :
    (evalEq (.prim (.int 1)) (.prim (.int 2)) == .prim (.bool false)) = true := by
  native_decide

theorem ordinary_eq_unchanged :
    (evalEq (.prim (.int 1)) (.prim (.int 1)) == .prim (.bool true)) = true := by
  native_decide

/-! D#1a — a BOTTOM comprehension guard PROPAGATES (does not vanish). The guard `1/0 > 0`
evaluates to bottom; the comprehension becomes that bottom. The `false`/`true` guards are
unchanged. -/

-- A bottom guard makes the comprehension struct bottom (not an empty struct).
theorem guard_bottom_propagates :
    isBottom (evalStructRefs (resolveStructRefs
      (.structComp
        []
        [.comprehension
          [.guard (.binary .gt (.binary .div (.prim (.int 1)) (.prim (.int 0))) (.prim (.int 0)))]
          (mkStruct [⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none [])]
        .regularOpen)))
      = true := by
  native_decide

-- A bottom guard reading a bottom sibling propagates that sibling's bottom.
theorem guard_bottom_from_sibling_propagates :
    isBottom (evalStructRefs (resolveStructRefs
      (.structComp
        []
        [.comprehension
          [.guard (.binary .gt (.conj [.prim (.int 1), .prim (.int 2)]) (.prim (.int 0)))]
          (mkStruct [⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none [])]
        .regularOpen)))
      = true := by
  native_decide

-- A `false` guard still DROPS its body (the spec drop), leaving an empty struct.
theorem guard_false_still_drops :
    (evalStructRefs (resolveStructRefs
      (.structComp
        []
        [.comprehension
          [.guard (.prim (.bool false))]
          (mkStruct [⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none [])]
        .regularOpen))
      == mkStruct [] .regularOpen none []) = true := by
  native_decide

-- A `true` guard still YIELDS its body.
theorem guard_true_still_yields :
    (evalStructRefs (resolveStructRefs
      (.structComp
        []
        [.comprehension
          [.guard (.prim (.bool true))]
          (mkStruct [⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none [])]
        .regularOpen))
      == mkStruct [⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none []) = true := by
  native_decide

/-! D#1b / D#1c — the guard classifier. `classifyGuard` enumerates every guard outcome with no
catch-all: concrete bool true/false, a propagating bottom, a CONCRETE non-bool type error (D#1c),
and a genuinely-incomplete DEFER (D#1b). The residual presence-test shape `X !=/== _|_` is NOT a
defer — it drops (the field's presence is undetermined), preserving the pre-D#1b behavior. -/

-- Unit: concrete bools classify true/false. (`GuardVerdict` derives `BEq`, not `DecidableEq` —
-- its `.bottom` arm carries a `Value`, which the project keeps off `DecidableEq` — so assert via
-- `==`, mirroring the `Value` convention.)
theorem classify_guard_bool_true : (classifyGuard (.prim (.bool true)) == .concreteTrue) = true := by
  native_decide
theorem classify_guard_bool_false : (classifyGuard (.prim (.bool false)) == .concreteFalse) = true := by
  native_decide

-- D#1c unit: concrete non-bool values (string / int / struct / list / null) are type errors,
-- carrying the offending type.
theorem classify_guard_string_nonbool :
    (classifyGuard (.prim (.string "x")) == .nonBool (.scalar .string)) = true := by native_decide
theorem classify_guard_int_nonbool :
    (classifyGuard (.prim (.int 3)) == .nonBool (.scalar .int)) = true := by native_decide
theorem classify_guard_null_nonbool :
    (classifyGuard (.prim .null) == .nonBool (.scalar .null)) = true := by native_decide
theorem classify_guard_struct_nonbool :
    (classifyGuard (mkStruct [⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none []) == .nonBool .struct) = true := by
  native_decide
theorem classify_guard_list_nonbool :
    (classifyGuard (.list [.prim (.int 1)]) == .nonBool .list) = true := by native_decide

-- D#1b unit: genuinely-abstract guards DEFER — an abstract bool kind, an unresolved disjunction
-- (even all-bool `true | false`), and a non-presence comparison (`x > 5`).
theorem classify_guard_kind_incomplete :
    (classifyGuard (.kind .bool) == .incomplete) = true := by native_decide
theorem classify_guard_unresolved_disj_incomplete :
    (classifyGuard (.disj [(.regular, .prim (.bool true)), (.regular, .prim (.bool false))]) == .incomplete) = true := by
  native_decide
theorem classify_guard_comparison_incomplete :
    (classifyGuard (.binary .gt (.refId ⟨0, 0⟩) (.prim (.int 5))) == .incomplete) = true := by native_decide

-- The residual presence test is NOT a defer — it drops (concrete-false), both polarities.
theorem classify_guard_presence_ne_drops :
    (classifyGuard (.binary .ne (.selector (.refId ⟨0, 0⟩) "g") .bottom) == .concreteFalse) = true := by
  native_decide
theorem classify_guard_presence_eq_drops :
    (classifyGuard (.binary .eq (.selector (.refId ⟨0, 0⟩) "g") .bottom) == .concreteFalse) = true := by
  native_decide

/-! DYN-DEF-1 — the dynamic-field label classifier. `classifyDynLabel` enumerates every label
outcome with no catch-all: a concrete string re-keys, a bottom propagates, a CONCRETE non-string
is a type error, and a genuinely-abstract label DEFERS (the field stays a residual `.dynamicField`
rather than dropping). The abstract `string` kind DEFERS — it may still narrow to a concrete
string at a use site, the property the bug fix restores. (`DynLabelVerdict` derives `BEq`, not
`DecidableEq`, so assert via `==`, mirroring the `Value`/`GuardVerdict` convention.) -/

-- Unit: a concrete string label re-keys to that name.
theorem classify_dynlabel_string_concrete :
    (classifyDynLabel (.prim (.string "k")) == .concreteString "k") = true := by native_decide

-- Unit: an abstract label DEFERS — both the `string` kind (the witness shape) and other kinds,
-- a reference, and an unresolved disjunction. The `string`-kind defer is the heart of DYN-DEF-1:
-- the key is not concrete YET, so the field is held for a later narrowing, never dropped.
theorem classify_dynlabel_string_kind_defers :
    (classifyDynLabel (.kind .string) == .incomplete) = true := by native_decide
theorem classify_dynlabel_int_kind_defers :
    (classifyDynLabel (.kind .int) == .incomplete) = true := by native_decide
theorem classify_dynlabel_ref_defers :
    (classifyDynLabel (.refId ⟨0, 0⟩) == .incomplete) = true := by native_decide
theorem classify_dynlabel_unresolved_disj_defers :
    (classifyDynLabel (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))]) == .incomplete)
      = true := by native_decide

-- Unit: a CONCRETE non-string value can never be a label ⇒ type error, carrying the offending
-- type (int / bool / null / struct / list).
theorem classify_dynlabel_int_nonstring :
    (classifyDynLabel (.prim (.int 3)) == .nonString (.scalar .int)) = true := by native_decide
theorem classify_dynlabel_bool_nonstring :
    (classifyDynLabel (.prim (.bool true)) == .nonString (.scalar .bool)) = true := by native_decide
theorem classify_dynlabel_null_nonstring :
    (classifyDynLabel (.prim .null) == .nonString (.scalar .null)) = true := by native_decide
theorem classify_dynlabel_struct_nonstring :
    (classifyDynLabel (mkStruct [⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none []) == .nonString .struct)
      = true := by native_decide
theorem classify_dynlabel_list_nonstring :
    (classifyDynLabel (.list [.prim (.int 1)]) == .nonString .list) = true := by native_decide

-- Unit: a bottom label propagates the bottom (the conflict surfaces; never a silent drop).
theorem classify_dynlabel_bottom_propagates :
    (classifyDynLabel .bottom == .bottom .bottom) = true := by native_decide

-- `resolveDynLabelDefault` collapses a DEFAULT disjunction to its default (so `classifyDynLabel`
-- then sees the concrete string), but leaves a NON-default disjunction untouched (stays incomplete).
theorem resolve_dynlabel_default_collapses_marked :
    (resolveDynLabelDefault (.disj [(.default, .prim (.string "a")), (.regular, .prim (.string "b"))])
      == .prim (.string "a")) = true := by native_decide
theorem resolve_dynlabel_default_keeps_ambiguous :
    (resolveDynLabelDefault (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))])
      == .disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))]) = true := by
  native_decide
-- Composed with the classifier: a marked default keys concretely; an ambiguous disjunction defers.
theorem classify_dynlabel_after_default_collapse_concrete :
    (classifyDynLabel (resolveDynLabelDefault
      (.disj [(.default, .prim (.string "a")), (.regular, .prim (.string "b"))]))
      == .concreteString "a") = true := by native_decide

-- D#1c end-to-end: a concrete non-bool guard makes the comprehension struct BOTTOM (not `{}`).
theorem guard_nonbool_string_bottoms :
    isBottom (evalStructRefs (resolveStructRefs
      (.structComp []
        [.comprehension [.guard (.prim (.string "x"))]
          (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])]
        .regularOpen)))
      = true := by
  native_decide

theorem guard_nonbool_int_bottoms :
    isBottom (evalStructRefs (resolveStructRefs
      (.structComp []
        [.comprehension [.guard (.prim (.int 3))]
          (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])]
        .regularOpen)))
      = true := by
  native_decide

-- D#1c list twin: a concrete non-bool guard in a LIST comprehension puts a `.nonBoolGuard`
-- bottom in the element slot (`[1, _|_]`), the same convention as the D#1a list twin — preserved,
-- not swallowed to `[]`.
theorem list_guard_nonbool_bottoms_element :
    (evalStructRefs (resolveStructRefs
      (mkStruct [⟨"out", .regular,
          .list [.prim (.int 1),
            .listComprehension [.guard (.prim (.string "z"))]
              (.structComp [] [.prim (.int 2)] .regularOpen)]⟩]
        .regularOpen none []))
      == mkStruct [⟨"out", .regular,
          .list [.prim (.int 1), .bottomWith [.nonBoolGuard (.scalar .string)]]⟩]
        .regularOpen none []) = true := by
  native_decide

-- D#1b end-to-end: an incomplete guard (`if x`, x : bool) DEFERS — the result keeps the
-- comprehension residual (a `.structComp`), it does NOT collapse to an empty/plain struct. The
-- guard ref resolves to `@1.0` (`x`'s frame slot); the body is unchanged.
theorem guard_incomplete_defers_residual :
    (evalStructRefs (resolveStructRefs
      (mkStruct [
          ⟨"x", .regular, .kind .bool⟩,
          ⟨"out", .regular,
            .structComp []
              [.comprehension [.guard (.ref "x")]
                (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])]
              .regularOpen⟩]
        .regularOpen none []))
      == mkStruct [
          ⟨"x", .regular, .kind .bool⟩,
          ⟨"out", .regular,
            .structComp []
              [.comprehension [.guard (.refId ⟨1, 0⟩)]
                (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])]
              .regularOpen⟩]
        .regularOpen none []) = true := by
  native_decide

-- D#1b: the abstract guard does NOT silently drop — the residual struct is distinct from the
-- collapsed empty form the old catch-all produced.
theorem guard_incomplete_not_dropped :
    (evalStructRefs (resolveStructRefs
      (.structComp []
        [.comprehension [.guard (.kind .bool)]
          (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])]
        .regularOpen))
      == mkStruct [] .regularOpen none []) = false := by
  native_decide

end Kue
