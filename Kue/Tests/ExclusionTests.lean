import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

theorem format_primitive_exclusion :
    formatValue (.notPrim (.int 0)) = "!=0" := by
  native_decide

theorem meet_exclusion_with_allowed_primitive :
    meet (.notPrim (.int 0)) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem meet_exclusion_with_forbidden_primitive :
    meet (.notPrim (.int 0)) (.prim (.int 0)) = .bottomWith [.excludedValue (.int 0)] := by
  rfl

theorem exclusion_subsumes_allowed_primitive :
    subsumes (.notPrim (.int 0)) (.prim (.int 1)) = true := by
  native_decide

theorem exclusion_rejects_forbidden_primitive :
    subsumes (.notPrim (.int 0)) (.prim (.int 0)) = false := by
  native_decide



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @exclusion_rejects_forbidden_primitive

end Kue
