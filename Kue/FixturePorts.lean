import Kue.Builtin
import Kue.Eval
import Kue.Format
import Kue.Lattice
import Kue.Manifest
import Kue.Normalize
import Kue.Resolve

namespace Kue

structure FixturePort where
  fileName : String
  content : String
deriving Repr, BEq

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

def formatManifestFieldResult (name : String) (value : Value) : String :=
  match formatManifestField name value with
  | .ok actual => actual
  | .error _ => "manifest error"

def formatTopLevel : Value -> String
  | .struct fields _ => joinWith "\n" (fields.map (formatStructFieldWithFuel formatFuel))
  | value => formatValue value

def resolveAndEval (value : Value) : Value :=
  evalStructRefs (resolveStructRefs value)

def fixturePorts : List FixturePort :=
  [
    {
      fileName := "bytes_kind.expected",
      content := formatField "x" (meet (.kind .bytes) (.prim (.bytes "abc")))
    },
    {
      fileName := "builtin_reference_eval.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("x", .regular, .prim (.string "abc")),
                ("n", .regular, .prim (.int (-7))),
                ("lenX", .regular, .builtinCall "len" [.ref "x"]),
                ("divN", .regular, .builtinCall "div" [.ref "n", .prim (.int 3)]),
                ("incomplete", .regular, .builtinCall "len" [.kind .string])
              ]
              true))
    },
    {
      fileName := "and_or_builtin.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("andValue", .regular, andValues [.kind .int, .intGt 0, .prim (.int 7)]),
              ("orValue", .regular, orValues [.prim (.string "a"), .prim (.string "b")])
            ]
            true)
    },
    {
      fileName := "integer_builtin.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("divValue", .regular, divValue (.prim (.int (-7))) (.prim (.int 3))),
              ("modValue", .regular, modValue (.prim (.int (-7))) (.prim (.int 3))),
              ("quoValue", .regular, quoValue (.prim (.int (-7))) (.prim (.int 3))),
              ("remValue", .regular, remValue (.prim (.int (-7))) (.prim (.int 3))),
              ("incompleteDiv", .regular, divValue (.kind .int) (.prim (.int 3))),
              ("zeroDivisor", .regular, divValue (.prim (.int 7)) (.prim (.int 0)))
            ]
            true)
    },
    {
      fileName := "closed_extra_field.expected",
      content :=
        formatField "x"
          (meet
            (closeValue (.struct [("a", .regular, .kind .int)] true))
            (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))
    },
    {
      fileName := "closed_hidden_definition.expected",
      content :=
        formatField "x"
          (meet
            (closeValue (.struct [("a", .regular, .kind .int)] true))
            (.struct
              [
                ("a", .regular, .prim (.int 1)),
                ("_h", .hidden, .prim (.string "secret")),
                ("#D", .definition, .kind .string)
              ]
              true))
    },
    {
      fileName := "closed_regex_pattern.expected",
      content :=
        formatField "x"
          (meet
            (closeValue (.structPattern [] (.stringRegex "^a$") (.kind .int) true))
            (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true))
    },
    {
      fileName := "default_disjunction.expected",
      content :=
        formatField "x"
          (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
    },
    {
      fileName := "default_disjunction.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
    },
    {
      fileName := "default_override.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (meet
            (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
            (.prim (.string "dev")))
    },
    {
      fileName := "definition_closed.expected",
      content :=
        formatField "x"
          (normalizeDefinitions
            (.struct [("#A", .definition, .struct [("a", .regular, .kind .int)] true)] true))
    },
    {
      fileName := "definition_reference.expected",
      content :=
        formatField "x"
          (resolveAndEval (.struct [("#A", .definition, .kind .int), ("x", .regular, .ref "#A")] true))
    },
    {
      fileName := "direct_self_reference.expected",
      content := formatTopLevel (resolveAndEval (.struct [("x", .regular, .ref "x")] true))
    },
    {
      fileName := "constrained_reference_cycle.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("x", .regular, .conj [.ref "x", .intGe 0]),
                ("a", .regular, .conj [.ref "b", .intGe 0]),
                ("b", .regular, .ref "a")
              ]
              true))
    },
    {
      fileName := "disjunction.expected",
      content := formatField "x" (join (.prim (.string "a")) (.prim (.string "b")))
    },
    {
      fileName := "exact_label_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.prim (.string "a")) (.kind .int) true)
            (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))
    },
    {
      fileName := "field_conflict.expected",
      content :=
        formatField "x"
          (meet
            (.struct [("a", .regular, .prim (.string "a"))] true)
            (.struct [("a", .regular, .prim (.string "b"))] true))
    },
    {
      fileName := "float_kind.expected",
      content := formatField "x" (meet (.kind .float) (.prim (.float "1.5")))
    },
    {
      fileName := "hidden_field_reference.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (resolveAndEval
            (.struct [("_secret", .hidden, .prim (.string "x")), ("value", .regular, .ref "_secret")] true))
    },
    {
      fileName := "int_bound_disjunction.expected",
      content := formatField "x" (join (.intGe 5) (.intGe 0))
    },
    {
      fileName := "int_bounds.expected",
      content := formatField "x" (meet (meet (.intGe 0) (.intLe 10)) (.prim (.int 7)))
    },
    {
      fileName := "kind_meet_int.expected",
      content := formatField "x" (meet (.kind .int) (.prim (.int 1)))
    },
    {
      fileName := "list_item_disjunction.expected",
      content :=
        formatField "x"
          (meet
            (.list [.disj [(.regular, .kind .int), (.regular, .kind .string)]])
            (.list [.prim (.int 1)]))
    },
    {
      fileName := "list_unification.expected",
      content :=
        formatField "x"
          (meet
            (.list [.kind .int, .kind .string])
            (.list [.prim (.int 1), .prim (.string "x")]))
    },
    {
      fileName := "len_builtin.expected",
      content :=
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
    },
    {
      fileName := "unresolved_builtin.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("lenString", .regular, lenValue (.kind .string)),
              ("emptyOr", .regular, orValues [])
            ]
            true)
    },
    {
      fileName := "manifest_field_filtering.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (.struct
            [
              ("a", .regular, .prim (.int 1)),
              ("b", .regular, .list [.prim (.string "x")]),
              ("_hidden", .hidden, .prim (.bool true)),
              ("#Schema", .definition, .kind .int),
              ("optional", .optional, .prim (.string "skip"))
            ]
            true)
    },
    {
      fileName := "manifest_nested_default.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (.struct
            [
              ("mode", .regular,
                .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
            ]
            true)
    },
    {
      fileName := "mutual_reference_cycle.expected",
      content :=
        formatTopLevel
          (resolveAndEval (.struct [("x", .regular, .ref "y"), ("y", .regular, .ref "x")] true))
    },
    {
      fileName := "nested_list_field.expected",
      content :=
        formatField "x"
          (meet
            (.struct [("items", .regular, .list [.kind .int, .kind .string])] true)
            (.struct [("items", .regular, .list [.prim (.int 1), .prim (.string "x")])] true))
    },
    {
      fileName := "nested_reference_list.expected",
      content :=
        formatTopLevel
          (resolveAndEval (.struct [("#A", .definition, .kind .int), ("x", .regular, .list [.ref "#A"])] true))
    },
    {
      fileName := "nested_struct_field.expected",
      content :=
        formatField "x"
          (meet
            (.struct [("a", .regular, .kind .int)] true)
            (.struct [("a", .regular, .prim (.int 1))] true))
    },
    {
      fileName := "number_disjunction.expected",
      content := formatField "x" (join (.kind .number) (.prim (.int 1)))
    },
    {
      fileName := "number_int_bound.expected",
      content := formatField "x" (meet (meet (.kind .number) (.intGe 0)) (.prim (.int 7)))
    },
    {
      fileName := "number_kind.expected",
      content := formatField "x" (meet (.kind .number) (.prim (.float "1.5")))
    },
    {
      fileName := "open_list_tail.expected",
      content :=
        formatField "x"
          (meet
            (.listTail [.kind .int] (.kind .string))
            (.list [.prim (.int 1), .prim (.string "x"), .prim (.string "y")]))
    },
    {
      fileName := "optional_default_absent.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (.struct
            [("mode", .optional,
              .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])]
            true)
    },
    {
      fileName := "optional_default_materialized.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (meet
            (.struct
              [("mode", .optional,
                .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])]
              true)
            (.struct [("mode", .regular, .top)] true))
    },
    {
      fileName := "primitive_exclusion.expected",
      content := formatField "x" (meet (.notPrim (.int 0)) (.prim (.int 1)))
    },
    {
      fileName := "regular_struct_meet.expected",
      content :=
        formatField "x"
          (meet
            (.struct [("a", .regular, .kind .int)] true)
            (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))
    },
    {
      fileName := "regex_label_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.stringRegex "^a$") (.kind .int) true)
            (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))
    },
    {
      fileName := "regex_wildcard_pattern.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("x", .regular,
                meet
                  (.structPattern [] (.stringRegex "^a.*z$") (.kind .int) true)
                  (.struct
                    [("abcz", .regular, .prim (.int 1)), ("abcy", .regular, .prim (.string "skip"))]
                    true)),
              ("y", .regular,
                meet
                  (.structPattern [] (.stringRegex "^a.+z$") (.kind .int) true)
                  (.struct
                    [("az", .regular, .prim (.string "skip")), ("abz", .regular, .prim (.int 2))]
                    true))
            ]
            true)
    },
    {
      fileName := "required_default_materialized.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (meet
            (.struct
              [("mode", .required,
                .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])]
              true)
            (.struct [("mode", .regular, .top)] true))
    },
    {
      fileName := "strict_int_bounds.expected",
      content := formatField "x" (meet (meet (.intGt 0) (.intLt 10)) (.prim (.int 7)))
    },
    {
      fileName := "string_pattern_conflict.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.kind .string) (.kind .int) true)
            (.struct [("a", .regular, .prim (.string "x"))] true))
    },
    {
      fileName := "string_pattern_constraint.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.kind .string) (.kind .int) true)
            (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true))
    },
    {
      fileName := "struct_disjunction_meet.expected",
      content :=
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
    },
    {
      fileName := "three_reference_cycle.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("x", .regular, .ref "y"),
                ("y", .regular, .ref "z"),
                ("z", .regular, .ref "x")
              ]
              true))
    }
  ]

def writeFixturePort (targetDir : System.FilePath) (port : FixturePort) : IO Unit := do
  IO.FS.writeFile (targetDir / port.fileName) (port.content ++ "\n")

def writeFixturePorts (targetDir : System.FilePath) : IO Unit := do
  IO.FS.createDirAll targetDir
  for port in fixturePorts do
    writeFixturePort targetDir port

end Kue
