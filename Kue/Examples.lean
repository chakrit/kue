import Kue.Format
import Kue.Lattice

namespace Kue

def structSmokeResult : String :=
  formatValue
    (meet
      (.struct [("a", .regular, .kind .int)] true)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))

def smokeLines : List String :=
  [
    s!"int & 1 => {formatValue (meet (.kind .int) (.prim (.int 1)))}",
    s!"\"a\" & \"b\" => {formatValue (meet (.prim (.string "a")) (.prim (.string "b")))}",
    s!"\"a\" | \"b\" => {formatValue (join (.prim (.string "a")) (.prim (.string "b")))}",
    s!"*\"prod\" | \"dev\" => {formatValue (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])}",
    "{a: int} & {a: 1, b: \"x\"} => " ++ structSmokeResult
  ]

theorem smoke_lines_match_plan :
    smokeLines =
      [
        "int & 1 => 1",
        "\"a\" & \"b\" => _|_",
        "\"a\" | \"b\" => \"a\" | \"b\"",
        "*\"prod\" | \"dev\" => *\"prod\" | \"dev\"",
        "{a: int} & {a: 1, b: \"x\"} => {a: 1, b: \"x\"}"
      ] := by
  native_decide

end Kue
