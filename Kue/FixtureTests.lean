import Kue.Format
import Kue.Lattice
import Kue.Manifest
import Kue.Normalize
import Kue.Eval
import Kue.Resolve

namespace Kue

def formatField (name : String) (value : Value) : String :=
  s!"{name}: {formatValue value}"

def formatManifestField (name : String) (value : Value) : Except ManifestError String :=
  match manifest value with
  | .ok data => .ok s!"{name}: {formatManifestValue data}"
  | .error error => .error error

def manifestFieldMatches (name : String) (value : Value) (expected : String) : Bool :=
  match formatManifestField name value with
  | .ok actual => actual == expected
  | .error _ => false

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

theorem fixture_default_override_manifest :
    formatManifestField "x"
      (meet
        (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
        (.prim (.string "dev")))
      = .ok "x: \"dev\"" := by
  rfl

theorem fixture_regular_struct_meet :
    formatField "x"
      (meet
        (.struct [("a", .regular, .kind .int)] true)
        (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))
      = "x: {a: 1, b: \"x\"}" := by
  native_decide

theorem fixture_field_conflict :
    formatField "x"
      (meet
        (.struct [("a", .regular, .prim (.string "a"))] true)
        (.struct [("a", .regular, .prim (.string "b"))] true))
      = "x: {a: _|_}" := by
  native_decide

theorem fixture_closed_extra_field :
    formatField "x"
      (meet
        (.struct [("a", .regular, .kind .int)] false)
        (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))
      = "x: {a: 1, b: _|_}" := by
  native_decide

theorem fixture_typed_ellipsis :
    formatField "x"
      (meet
        (.structTail [("a", .regular, .kind .int)] (.kind .string))
        (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))
      = "x: {a: 1, b: \"x\", ...string}" := by
  native_decide

theorem fixture_definition_struct_normalizes_closed :
    (normalizeDefinitions
        (.struct [("#A", .definition, .struct [("a", .regular, .kind .int)] true)] true)
      == .struct [("#A", .definition, .struct [("a", .regular, .kind .int)] false)] true) = true := by
  native_decide

theorem fixture_definition_reference :
    formatField "x"
      (evalStructRefs (.struct [("#A", .definition, .kind .int), ("x", .regular, .ref "#A")] true))
      = "x: {#A: int, x: int}" := by
  native_decide

theorem fixture_list_unification :
    formatField "x"
      (meet
        (.list [.kind .int, .kind .string])
        (.list [.prim (.int 1), .prim (.string "x")]))
      = "x: [1, \"x\"]" := by
  native_decide

theorem fixture_int_bounds :
    formatField "x"
      (meet
        (meet (.intGe 0) (.intLe 10))
        (.prim (.int 7)))
      = "x: 7" := by
  native_decide

theorem fixture_strict_int_bounds :
    formatField "x"
      (meet
        (meet (.intGt 0) (.intLt 10))
        (.prim (.int 7)))
      = "x: 7" := by
  native_decide

theorem fixture_primitive_exclusion :
    formatField "x" (meet (.notPrim (.int 0)) (.prim (.int 1))) = "x: 1" := by
  native_decide

theorem fixture_bytes_kind :
    formatField "x" (meet (.kind .bytes) (.prim (.bytes "abc"))) = "x: #\"abc\"#" := by
  native_decide

theorem fixture_float_kind :
    formatField "x" (meet (.kind .float) (.prim (.float "1.5"))) = "x: 1.5" := by
  native_decide

theorem fixture_number_kind :
    formatField "x" (meet (.kind .number) (.prim (.float "1.5"))) = "x: 1.5" := by
  native_decide

theorem fixture_number_disjunction :
    formatField "x" (join (.kind .number) (.prim (.int 1))) = "x: number" := by
  native_decide

theorem fixture_open_list_tail :
    formatField "x"
      (meet
        (.listTail [.kind .int] (.kind .string))
        (.list [.prim (.int 1), .prim (.string "x"), .prim (.string "y")]))
      = "x: [1, \"x\", \"y\"]" := by
  native_decide

theorem fixture_manifest_field_filtering :
    manifest
      (.struct
        [
          ("a", .regular, .prim (.int 1)),
          ("b", .regular, .list [.prim (.string "x")]),
          ("_hidden", .hidden, .prim (.bool true)),
          ("#Schema", .definition, .kind .int),
          ("optional", .optional, .prim (.string "skip"))
        ]
        true)
      = .ok (.struct [("a", .prim (.int 1)), ("b", .list [.prim (.string "x")])]) := by
  rfl

theorem fixture_manifest_field_filtering_format :
    formatManifestField "x"
      (.struct
        [
          ("a", .regular, .prim (.int 1)),
          ("b", .regular, .list [.prim (.string "x")]),
          ("_hidden", .hidden, .prim (.bool true)),
          ("#Schema", .definition, .kind .int),
          ("optional", .optional, .prim (.string "skip"))
        ]
        true)
      = .ok "x: {a: 1, b: [\"x\"]}" := by
  rfl

theorem fixture_manifest_nested_default :
    formatManifestField "x"
      (.struct
        [
          ("mode", .regular,
            .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
        ]
        true)
      = .ok "x: {mode: \"prod\"}" := by
  rfl

theorem fixture_manifest_ignores_absent_optional_default :
    formatManifestField "x"
      (.struct
        [("mode", .optional, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])]
        true)
      = .ok "x: {}" := by
  rfl

theorem fixture_manifest_selects_materialized_optional_default :
    formatManifestField "x"
      (meet
        (.struct
          [("mode", .optional, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])]
          true)
        (.struct [("mode", .regular, .top)] true))
      = .ok "x: {mode: \"prod\"}" := by
  rfl

theorem fixture_manifest_selects_materialized_required_default :
    formatManifestField "x"
      (meet
        (.struct
          [("mode", .required, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])]
          true)
        (.struct [("mode", .regular, .top)] true))
      = .ok "x: {mode: \"prod\"}" := by
  rfl

theorem fixture_nested_reference_list :
    formatField "x"
      (evalStructRefs
        (resolveStructRefs
          (.struct [("#A", .definition, .kind .int), ("x", .regular, .list [.ref "#A"])] true)))
      = "x: {#A: int, x: [int]}" := by
  native_decide

theorem fixture_direct_self_reference_cycle :
    formatField "x"
      (evalStructRefs (resolveStructRefs (.struct [("x", .regular, .ref "x")] true)))
      = "x: {x: _}" := by
  native_decide

theorem fixture_mutual_reference_cycle :
    formatField "x"
      (evalStructRefs
        (resolveStructRefs (.struct [("x", .regular, .ref "y"), ("y", .regular, .ref "x")] true)))
      = "x: {x: _, y: _}" := by
  native_decide

theorem fixture_manifest_hidden_field_reference :
    manifestFieldMatches "x"
        (evalStructRefs
          (resolveStructRefs
            (.struct [("_secret", .hidden, .prim (.string "x")), ("value", .regular, .ref "_secret")] true)))
        "x: {value: \"x\"}" = true := by
  native_decide

end Kue
