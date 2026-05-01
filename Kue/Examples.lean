import Kue.Format
import Kue.Lattice
import Kue.Eval
import Kue.Resolve

namespace Kue

def structSmokeResult : String :=
  formatValue
    (meet
      (.struct [("a", .regular, .kind .int)] true)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))

def fieldConflictSmokeResult : String :=
  formatValue
    (meet
      (.struct [("a", .regular, .prim (.string "a"))] true)
      (.struct [("a", .regular, .prim (.string "b"))] true))

def typedTailSmokeResult : String :=
  formatValue
    (meet
      (.structTail [("a", .regular, .kind .int)] (.kind .string))
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))

def refSmokeResult : String :=
  formatValue
    (evalStructRefs
      (resolveStructRefs
        (.struct [("#A", .definition, .kind .int), ("x", .regular, .ref "#A")] true)))

def listSmokeResult : String :=
  formatValue
    (meet
      (.list [.kind .int, .kind .string])
      (.list [.prim (.int 1), .prim (.string "x")]))

def intBoundsSmokeResult : String :=
  formatValue
    (meet
      (meet (.intGe 0) (.intLe 10))
      (.prim (.int 7)))

def strictIntBoundsSmokeResult : String :=
  formatValue
    (meet
      (meet (.intGt 0) (.intLt 10))
      (.prim (.int 7)))

def primitiveExclusionSmokeResult : String :=
  formatValue (meet (.notPrim (.int 0)) (.prim (.int 1)))

def bytesSmokeResult : String :=
  formatValue (meet (.kind .bytes) (.prim (.bytes "abc")))

def floatSmokeResult : String :=
  formatValue (meet (.kind .float) (.prim (.float "1.5")))

def numberSmokeResult : String :=
  formatValue (meet (.kind .number) (.prim (.float "1.5")))

def openListTailSmokeResult : String :=
  formatValue
    (meet
      (.listTail [.kind .int] (.kind .string))
      (.list [.prim (.int 1), .prim (.string "x"), .prim (.string "y")]))

def smokeLines : List String :=
  [
    s!"int & 1 => {formatValue (meet (.kind .int) (.prim (.int 1)))}",
    s!"\"a\" & \"b\" => {formatValue (meet (.prim (.string "a")) (.prim (.string "b")))}",
    s!"\"a\" | \"b\" => {formatValue (join (.prim (.string "a")) (.prim (.string "b")))}",
    s!"*\"prod\" | \"dev\" => {formatValue (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])}",
    "{a: int} & {a: 1, b: \"x\"} => " ++ structSmokeResult,
    "{a: \"a\"} & {a: \"b\"} => " ++ fieldConflictSmokeResult,
    "{a: int, ...string} & {a: 1, b: \"x\"} => " ++ typedTailSmokeResult,
    "{#A: int, x: #A} => " ++ refSmokeResult,
    "[int, string] & [1, \"x\"] => " ++ listSmokeResult,
    ">=0 & <=10 & 7 => " ++ intBoundsSmokeResult,
    ">0 & <10 & 7 => " ++ strictIntBoundsSmokeResult,
    "!=0 & 1 => " ++ primitiveExclusionSmokeResult,
    "bytes & 'abc' => " ++ bytesSmokeResult,
    "float & 1.5 => " ++ floatSmokeResult,
    "number & 1.5 => " ++ numberSmokeResult,
    "[int, ...string] & [1, \"x\", \"y\"] => " ++ openListTailSmokeResult
  ]

theorem smoke_lines_match_plan :
    smokeLines =
      [
        "int & 1 => 1",
        "\"a\" & \"b\" => _|_",
        "\"a\" | \"b\" => \"a\" | \"b\"",
        "*\"prod\" | \"dev\" => *\"prod\" | \"dev\"",
        "{a: int} & {a: 1, b: \"x\"} => {a: 1, b: \"x\"}",
        "{a: \"a\"} & {a: \"b\"} => {a: _|_}",
        "{a: int, ...string} & {a: 1, b: \"x\"} => {a: 1, b: \"x\", ...string}",
        "{#A: int, x: #A} => {#A: int, x: int}",
        "[int, string] & [1, \"x\"] => [1, \"x\"]",
        ">=0 & <=10 & 7 => 7",
        ">0 & <10 & 7 => 7",
        "!=0 & 1 => 1",
        "bytes & 'abc' => 'abc'",
        "float & 1.5 => 1.5",
        "number & 1.5 => 1.5",
        "[int, ...string] & [1, \"x\", \"y\"] => [1, \"x\", \"y\"]"
      ] := by
  native_decide

end Kue
