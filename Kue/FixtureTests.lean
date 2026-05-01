import Kue.FixturePorts

namespace Kue

theorem fixture_kind_meet_int :
    formatField "x" (meet (.kind .int) (.prim (.int 1))) = "x: 1" := by
  native_decide

theorem fixture_and_or_builtin :
    formatTopLevel
      (.struct
        [
          ("andValue", .regular, andValues [.kind .int, .intGt 0, .prim (.int 7)]),
          ("orValue", .regular, orValues [.prim (.string "a"), .prim (.string "b")])
        ]
        true)
      = "andValue: 7\norValue: \"a\" | \"b\"" := by
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

theorem fixture_len_builtin :
    formatTopLevel
      (.struct
        [
          ("stringLen", .regular, lenValue (.prim (.string "abc"))),
          ("listLen", .regular, lenValue (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)])),
          ("structLen", .regular,
            lenValue
              (.struct
                [
                  ("a", .regular, .prim (.int 1)),
                  ("b", .optional, .prim (.int 2)),
                  ("_c", .hidden, .prim (.int 3)),
                  ("#D", .definition, .prim (.int 4))
                ]
                true))
        ]
        true)
      = "stringLen: 3\nlistLen: 3\nstructLen: 1" := by
  native_decide

theorem fixture_unresolved_builtin :
    formatTopLevel
      (.struct
        [
          ("lenString", .regular, lenValue (.kind .string)),
          ("emptyOr", .regular, orValues [])
        ]
        true)
      = "lenString: len(string)\nemptyOr: or([])" := by
  native_decide

theorem fixture_nested_struct_field :
    formatField "x"
      (meet
        (.struct [("a", .regular, .kind .int)] true)
        (.struct [("a", .regular, .prim (.int 1))] true))
      = "x: {a: 1}" := by
  native_decide

theorem fixture_nested_list_field :
    formatField "x"
      (meet
        (.struct [("items", .regular, .list [.kind .int, .kind .string])] true)
        (.struct [("items", .regular, .list [.prim (.int 1), .prim (.string "x")])] true))
      = "x: {items: [1, \"x\"]}" := by
  native_decide

theorem fixture_list_item_disjunction :
    formatField "x"
      (meet
        (.list [.disj [(.regular, .kind .int), (.regular, .kind .string)]])
        (.list [.prim (.int 1)]))
      = "x: [1]" := by
  native_decide

theorem fixture_struct_disjunction_meet :
    formatField "x"
      (meet
        (.disj
          [
            (.regular, .struct [("kind", .regular, .prim (.string "web"))] true),
            (.regular, .struct [("kind", .regular, .prim (.string "db"))] true)
          ])
        (.struct
          [
            ("kind", .regular, .prim (.string "web")),
            ("port", .regular, .prim (.int 80))
          ]
          true))
      = "x: {kind: \"web\", port: 80}" := by
  native_decide

theorem fixture_string_pattern_constraint :
    formatField "x"
      (meet
        (.structPattern [] (.kind .string) (.kind .int))
        (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true))
      = "x: {a: 1, b: 2, [string]: int}" := by
  native_decide

theorem fixture_string_pattern_conflict :
    formatField "x"
      (meet
        (.structPattern [] (.kind .string) (.kind .int))
        (.struct [("a", .regular, .prim (.string "x"))] true))
      = "x: {a: _|_, [string]: int}" := by
  native_decide

theorem fixture_exact_label_pattern :
    formatField "x"
      (meet
        (.structPattern [] (.prim (.string "a")) (.kind .int))
        (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))
      = "x: {a: 1, b: \"x\", [\"a\"]: int}" := by
  native_decide

theorem fixture_regex_label_pattern :
    formatField "x"
      (meet
        (.structPattern [] (.stringRegex "^a$") (.kind .int))
        (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))
      = "x: {a: 1, b: \"x\", [=~\"^a$\"]: int}" := by
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

theorem fixture_int_bound_disjunction :
    formatField "x" (join (.intGe 5) (.intGe 0)) = "x: >=0" := by
  native_decide

theorem fixture_primitive_exclusion :
    formatField "x" (meet (.notPrim (.int 0)) (.prim (.int 1))) = "x: 1" := by
  native_decide

theorem fixture_bytes_kind :
    formatField "x" (meet (.kind .bytes) (.prim (.bytes "abc"))) = "x: 'abc'" := by
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

theorem fixture_number_int_bound :
    formatField "x" (meet (meet (.kind .number) (.intGe 0)) (.prim (.int 7))) = "x: 7" := by
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
    formatTopLevel
      (resolveAndEval
        (.struct [("#A", .definition, .kind .int), ("x", .regular, .list [.ref "#A"])] true))
      = "#A: int\nx: [int]" := by
  native_decide

theorem fixture_direct_self_reference_cycle :
    formatTopLevel (resolveAndEval (.struct [("x", .regular, .ref "x")] true)) = "x: _" := by
  native_decide

theorem fixture_mutual_reference_cycle :
    formatTopLevel
      (resolveAndEval (.struct [("x", .regular, .ref "y"), ("y", .regular, .ref "x")] true))
      = "x: _\ny: _" := by
  native_decide

theorem fixture_three_reference_cycle :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ("x", .regular, .ref "y"),
            ("y", .regular, .ref "z"),
            ("z", .regular, .ref "x")
          ]
          true))
      = "x: _\ny: _\nz: _" := by
  native_decide

theorem fixture_manifest_hidden_field_reference :
    manifestFieldMatches "x"
        (evalStructRefs
          (resolveStructRefs
            (.struct [("_secret", .hidden, .prim (.string "x")), ("value", .regular, .ref "_secret")] true)))
        "x: {value: \"x\"}" = true := by
  native_decide

end Kue
