import Kue.Format
import Kue.Lattice

namespace Kue

def smokeLines : List String :=
  [
    s!"int & 1 => {formatValue (meet (.kind .int) (.prim (.int 1)))}",
    s!"\"a\" & \"b\" => {formatValue (meet (.prim (.string "a")) (.prim (.string "b")))}",
    s!"\"a\" | \"b\" => {formatValue (join (.prim (.string "a")) (.prim (.string "b")))}",
    s!"*\"prod\" | \"dev\" => {formatValue (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])}"
  ]

theorem smoke_lines_match_plan :
    smokeLines =
      [
        "int & 1 => 1",
        "\"a\" & \"b\" => _|_",
        "\"a\" | \"b\" => \"a\" | \"b\"",
        "*\"prod\" | \"dev\" => *\"prod\" | \"dev\""
      ] := by
  native_decide

end Kue
