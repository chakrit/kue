import Kue.Format
import Kue.Lattice

namespace Kue

def smokeLines : List String :=
  [
    s!"int & 1 => {formatValue (meet (.kind .int) (.prim (.int 1)))}",
    s!"\"a\" & \"b\" => {formatValue (meet (.prim (.string "a")) (.prim (.string "b")))}"
  ]

theorem smoke_lines_match_plan :
    smokeLines = ["int & 1 => 1", "\"a\" & \"b\" => _|_"] := by
  rfl

end Kue
