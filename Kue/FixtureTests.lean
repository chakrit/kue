import Kue.Format
import Kue.Lattice
import Kue.Manifest

namespace Kue

def formatField (name : String) (value : Value) : String :=
  s!"{name}: {formatValue value}"

def formatManifestField (name : String) (value : Value) : Except ManifestError String :=
  match manifest value with
  | .ok prim => .ok s!"{name}: {formatPrim prim}"
  | .error error => .error error

theorem fixture_kind_meet_int :
    formatField "x" (meet (.kind .int) (.prim (.int 1))) = "x: 1" := by
  native_decide

theorem fixture_disjunction :
    formatField "x" (join (.prim (.string "a")) (.prim (.string "b")))
      = "x: \"a\" | \"b\"" := by
  native_decide

theorem fixture_default_disjunction :
    formatField "x" (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
      = "x: *\"prod\" | \"dev\"" := by
  native_decide

theorem fixture_default_disjunction_manifest :
    formatManifestField "x" (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
      = .ok "x: \"prod\"" := by
  rfl

end Kue
