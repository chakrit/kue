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
    classifyDefinedness (.struct [⟨"x", .regular, .prim (.int 1)⟩] true) = .defined := by
  native_decide

theorem classify_bottom_error :
    classifyDefinedness .bottom = .error := by native_decide

theorem classify_kind_incomplete :
    classifyDefinedness (.kind .int) = .incomplete := by native_decide

theorem classify_selector_incomplete :
    classifyDefinedness (.selector (.ref "x") "g") = .incomplete := by native_decide

-- A concrete operand: `!= _|_` is true, `== _|_` is false.
theorem concrete_ne_bottom_true :
    (evalStructRefs (resolveStructRefs
      (.struct [⟨"b", .regular, .binary .ne (.prim (.int 1)) .bottom⟩] true))
      == .struct [⟨"b", .regular, .prim (.bool true)⟩] true) = true := by
  native_decide

theorem concrete_eq_bottom_false :
    (evalStructRefs (resolveStructRefs
      (.struct [⟨"b", .regular, .binary .eq (.prim (.int 1)) .bottom⟩] true))
      == .struct [⟨"b", .regular, .prim (.bool false)⟩] true) = true := by
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
          (.struct [⟨"seen", .regular, .ref "f"⟩] true)]
        true false))
      == .struct
        [⟨"f", .regular, .prim (.int 3)⟩, ⟨"seen", .regular, .prim (.int 3)⟩] true)
      = true := by
  native_decide

-- The comprehension guard drops when the tested field is absent (residual selector).
theorem guard_drops_on_absent :
    (evalStructRefs (resolveStructRefs
      (.structComp
        [⟨"base", .regular, .struct [⟨"f", .regular, .prim (.int 3)⟩] true⟩]
        [.comprehension
          [.guard (.binary .ne (.selector (.ref "base") "g") .bottom)]
          (.struct [⟨"seen", .regular, .prim (.bool true)⟩] true)]
        true false))
      == .struct
        [⟨"base", .regular, .struct [⟨"f", .regular, .prim (.int 3)⟩] true⟩] true)
      = true := by
  native_decide

-- Regression: ordinary `!=`/`==` on non-`_|_` operands is unchanged.
theorem ordinary_ne_unchanged :
    (evalEq (.prim (.int 1)) (.prim (.int 2)) == .prim (.bool false)) = true := by
  native_decide

theorem ordinary_eq_unchanged :
    (evalEq (.prim (.int 1)) (.prim (.int 1)) == .prim (.bool true)) = true := by
  native_decide

end Kue
