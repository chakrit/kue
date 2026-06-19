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

end Kue
