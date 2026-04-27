import Kue.Manifest

namespace Kue

theorem manifest_primitive :
    manifest (.prim (.int 1)) = .ok (.int 1) := by
  rfl

theorem manifest_kind_incomplete :
    manifest (.kind .int) = .error (.incomplete (.kind .int)) := by
  rfl

theorem manifest_top_incomplete :
    manifest .top = .error (.incomplete .top) := by
  rfl

theorem manifest_bottom_contradiction :
    manifest .bottom = .error .contradiction := by
  rfl

theorem manifest_ambiguous_disjunction :
    manifest (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))])
      = .error (.ambiguous [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))]) := by
  rfl

theorem manifest_selects_single_default :
    manifest (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
      = .ok (.string "prod") := by
  rfl

end Kue
