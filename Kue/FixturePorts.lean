import Kue.Builtin
import Kue.Format
import Kue.Lattice
import Kue.Manifest
import Kue.Runtime

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

def fixturePorts : List FixturePort :=
  [
    {
      fileName := "additive_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2))),
                ("diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3))),
                ("cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b")))
              ]
              true))
    },
    {
      fileName := "bytes_additive_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("bytes", .regular, .binary .add (.prim (.bytes "ab")) (.prim (.bytes "cd"))),
                (
                  "left",
                  .regular,
                  .binary .add
                    (.binary .add (.prim (.bytes "a")) (.prim (.bytes "b")))
                    (.prim (.bytes "c"))
                )
              ]
              true))
    },
    {
      fileName := "float_additive_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("floatSum", .regular, .binary .add (.prim (.float "1.5")) (.prim (.float "2.25"))),
                ("intFloat", .regular, .binary .add (.prim (.int 1)) (.prim (.float "2.5"))),
                ("floatSub", .regular, .binary .sub (.prim (.float "5.5")) (.prim (.int 2))),
                ("whole", .regular, .binary .add (.prim (.float "1.5")) (.prim (.float "1.5"))),
                ("exp", .regular, .binary .add (.prim (.float "1e+3")) (.prim (.int 2))),
                ("small", .regular, .binary .add (.prim (.float "0.1")) (.prim (.float "0.2")))
              ]
              true))
    },
    {
      fileName := "multiplication_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("mul", .regular, .binary .mul (.prim (.int 3)) (.prim (.int 4))),
                (
                  "precedence",
                  .regular,
                  .binary .add (.prim (.int 1)) (.binary .mul (.prim (.int 2)) (.prim (.int 3)))
                ),
                (
                  "left",
                  .regular,
                  .binary .mul (.binary .mul (.prim (.int 2)) (.prim (.int 3))) (.prim (.int 4))
                )
              ]
              true))
    },
    {
      fileName := "division_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("div", .regular, .binary .div (.prim (.int 5)) (.prim (.int 2))),
                ("whole", .regular, .binary .div (.prim (.int 6)) (.prim (.int 3))),
                ("third", .regular, .binary .div (.prim (.int 1)) (.prim (.int 3))),
                ("negative", .regular, .binary .div (.prim (.int (-5))) (.prim (.int 2)))
              ]
              true))
    },
    {
      fileName := "float_muldiv_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("mulFloats", .regular, .binary .mul (.prim (.float "1.5")) (.prim (.float "2.0"))),
                ("mulScale", .regular, .binary .mul (.prim (.float "1.0")) (.prim (.float "1.0"))),
                ("mulIntFloat", .regular, .binary .mul (.prim (.int 2)) (.prim (.float "1.5"))),
                ("mulNegative", .regular, .binary .mul (.prim (.float "-1.5")) (.prim (.float "2.0"))),
                ("divTerminate", .regular, .binary .div (.prim (.float "1.0")) (.prim (.float "4.0"))),
                ("divClean", .regular, .binary .div (.prim (.float "4.0")) (.prim (.float "2.0"))),
                ("divFloatInt", .regular, .binary .div (.prim (.float "3.0")) (.prim (.int 2))),
                ("divRepeat", .regular, .binary .div (.prim (.float "2.0")) (.prim (.float "3.0"))),
                ("divRepeatInt", .regular, .binary .div (.prim (.float "10.0")) (.prim (.float "3.0"))),
                ("divRoundUp", .regular, .binary .div (.prim (.float "100.0")) (.prim (.float "7.0")))
              ]
              true))
    },
    {
      fileName := "integer_keyword_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("divValue", .regular, .binary .intDiv (.prim (.int (-7))) (.prim (.int 3))),
                ("modValue", .regular, .binary .intMod (.prim (.int (-7))) (.prim (.int 3))),
                ("quoValue", .regular, .binary .intQuo (.prim (.int (-7))) (.prim (.int 3))),
                ("remValue", .regular, .binary .intRem (.prim (.int (-7))) (.prim (.int 3))),
                (
                  "precedence",
                  .regular,
                  .binary .add (.prim (.int 1)) (.binary .intDiv (.prim (.int 7)) (.prim (.int 3)))
                )
              ]
              true))
    },
    {
      fileName := "equality_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("same", .regular, .binary .eq (.prim (.int 1)) (.prim (.int 1))),
                ("diff", .regular, .binary .ne (.prim (.int 1)) (.prim (.int 2))),
                ("text", .regular, .binary .eq (.prim (.string "a")) (.prim (.string "b"))),
                (
                  "precedence",
                  .regular,
                  .binary .eq (.binary .add (.prim (.int 1)) (.prim (.int 1))) (.prim (.int 2))
                )
              ]
              true))
    },
    {
      fileName := "ordering_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("lt", .regular, .binary .lt (.prim (.int 1)) (.prim (.int 2))),
                ("le", .regular, .binary .le (.prim (.int 2)) (.prim (.int 2))),
                ("gt", .regular, .binary .gt (.prim (.int 3)) (.prim (.int 2))),
                ("ge", .regular, .binary .ge (.prim (.int 3)) (.prim (.int 4))),
                ("slt", .regular, .binary .lt (.prim (.string "a")) (.prim (.string "b"))),
                (
                  "precedence",
                  .regular,
                  .binary .lt (.binary .add (.prim (.int 1)) (.prim (.int 2))) (.prim (.int 4))
                )
              ]
              true))
    },
    {
      fileName := "numeric_comparison_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("lt", .regular, .binary .lt (.prim (.float "1.5")) (.prim (.int 2))),
                ("le", .regular, .binary .le (.prim (.float "1.5")) (.prim (.float "1.50"))),
                ("gt", .regular, .binary .gt (.prim (.float "1e+3")) (.prim (.float "999.9"))),
                ("ge", .regular, .binary .ge (.prim (.float "1.0")) (.prim (.int 1))),
                ("eq", .regular, .binary .eq (.prim (.int 1)) (.prim (.float "1.0"))),
                ("ne", .regular, .binary .ne (.prim (.int 1)) (.prim (.float "1.0")))
              ]
              true))
    },
    {
      fileName := "logical_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("andFalse", .regular, .binary .boolAnd (.prim (.bool true)) (.prim (.bool false))),
                ("orTrue", .regular, .binary .boolOr (.prim (.bool false)) (.prim (.bool true))),
                (
                  "andCmp",
                  .regular,
                  .binary .boolAnd
                    (.binary .lt (.prim (.int 1)) (.prim (.int 2)))
                    (.binary .gt (.prim (.int 3)) (.prim (.int 2)))
                ),
                (
                  "orCmp",
                  .regular,
                  .binary .boolOr
                    (.prim (.bool false))
                    (.binary .eq (.binary .add (.prim (.int 1)) (.prim (.int 1))) (.prim (.int 2)))
                ),
                (
                  "grouped",
                  .regular,
                  .binary .boolAnd
                    (.binary .boolOr (.prim (.bool false)) (.prim (.bool true)))
                    (.prim (.bool true))
                )
              ]
              true))
    },
    {
      fileName := "logical_not_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("notFalse", .regular, .unary .boolNot (.prim (.bool false))),
                ("notCmp", .regular, .unary .boolNot (.binary .lt (.prim (.int 1)) (.prim (.int 2)))),
                ("double", .regular, .unary .boolNot (.unary .boolNot (.prim (.bool true))))
              ]
              true))
    },
    {
      fileName := "unary_numeric_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("negGroup", .regular, .unary .numNeg (.binary .add (.prim (.int 1)) (.prim (.int 2)))),
                ("posGroup", .regular, .unary .numPos (.binary .add (.prim (.int 1)) (.prim (.int 2)))),
                ("negRefBase", .regular, .prim (.int 3)),
                ("negRef", .regular, .unary .numNeg (.ref "negRefBase")),
                ("precedence", .regular, .binary .mul (.unary .numNeg (.prim (.int 2))) (.prim (.int 3)))
              ]
              true))
    },
    {
      fileName := "regex_match_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("match", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "^a"))),
                ("miss", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "z"))),
                ("notMatch", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "z"))),
                ("notMiss", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "^a"))),
                (
                  "precedence",
                  .regular,
                  .binary .regexMatch
                    (.binary .add (.prim (.string "ab")) (.prim (.string "c")))
                    (.prim (.string "^abc$"))
                )
              ]
              true))
    },
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
      -- Repeated selection into a shared sub-struct (`components.X.who`), the eval-blowup
      -- shape: each of the three `*Who` fields re-selects `components` and its child. Before
      -- memoization this re-evaluated `components` per selection, multiplying per fuel level;
      -- the frame-id cache computes it once and shares it. Behavior is unchanged — this pins
      -- both the correct shared value and (implicitly) that it completes under normal fuel.
      fileName := "shared_selection_fan.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("base", .regular, .prim (.string "stage9")),
                ("components", .regular,
                  .struct
                    [
                      ("repo", .regular, .struct [("who", .regular, .ref "base")] true),
                      ("project", .regular, .struct [("who", .regular, .ref "base")] true),
                      ("app", .regular, .struct [("who", .regular, .ref "base")] true)
                    ]
                    true),
                ("repoWho", .regular,
                  .selector (.selector (.ref "components") "repo") "who"),
                ("projectWho", .regular,
                  .selector (.selector (.ref "components") "project") "who"),
                ("appWho", .regular,
                  .selector (.selector (.ref "components") "app") "who")
              ]
              true))
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
      fileName := "string_kind_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.kind .string) (.kind .int) true)
            (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true))
    },
    {
      fileName := "string_kind_pattern_mismatch.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.kind .string) (.kind .int) true)
            (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true))
    },
    {
      fileName := "string_kind_pattern_only.expected",
      content := formatField "x" (.structPattern [] (.kind .string) (.kind .int) true)
    },
    {
      fileName := "type_label_colon_shorthand.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [("#labels", .optional, .structPattern [] (.kind .string) (.kind .string) true)]
              true))
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
      fileName := "field_alias.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("not an identifier", .regular, .prim (.int 4)),
                ("A", .letBinding, .ref "not an identifier"),
                ("foo", .regular, .ref "A")
              ]
              true))
    },
    {
      fileName := "field_selector.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("base", .regular, .struct [("inner", .regular, .prim (.int 4))] true),
                ("x", .regular, .selector (.ref "base") "inner")
              ]
              true))
    },
    {
      fileName := "list_index.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("xs", .regular, .list [.prim (.int 10), .prim (.int 20)]),
                ("x", .regular, .index (.ref "xs") (.prim (.int 1)))
              ]
              true))
    },
    {
      fileName := "string_field_index.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("base", .regular, .struct [("inner", .regular, .prim (.int 4))] true),
                ("x", .regular, .index (.ref "base") (.prim (.string "inner")))
              ]
              true))
    },
    {
      fileName := "duplicate_fields.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("x", .regular, .kind .int),
                ("x", .regular, .prim (.int 1)),
                ("conflict", .regular, .prim (.string "a")),
                ("conflict", .regular, .prim (.string "b"))
              ]
              true))
    },
    {
      fileName := "float_kind.expected",
      content := formatField "x" (meet (.kind .float) (.prim (.float "1.5")))
    },
    {
      fileName := "number_literals.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("x", .regular, .prim (.int 1000)),
              ("y", .regular, .prim (.float "1.25e+3")),
              ("z", .regular, .prim (.float "-2e+3"))
            ]
            true)
    },
    {
      fileName := "non_decimal_numbers.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("hex", .regular, .prim (.int 31)),
              ("oct", .regular, .prim (.int 15)),
              ("bin", .regular, .prim (.int 10)),
              ("negHex", .regular, .prim (.int (-16))),
              ("sep", .regular, .prim (.int 10))
            ]
            true)
    },
    {
      fileName := "unary_plus_numbers.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("x", .regular, .prim (.int 1)),
              ("y", .regular, .prim (.float "1.5")),
              ("z", .regular, .prim (.int 16))
            ]
            true)
    },
    {
      fileName := "numeric_suffixes.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("k", .regular, .prim (.int 1000)),
              ("ki", .regular, .prim (.int 1024)),
              ("fracK", .regular, .prim (.int 1500)),
              ("fracKi", .regular, .prim (.int 1536)),
              ("neg", .regular, .prim (.int (-1500)))
            ]
            true)
    },
    {
      fileName := "hidden_field_reference.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (resolveAndEval
            (.struct [("_secret", .hidden, .prim (.string "x")), ("value", .regular, .ref "_secret")] true))
    },
    {
      fileName := "underscore_ident_reference.expected",
      content :=
        formatField "out"
          (resolveAndEval
            (.struct
              [
                ("_base", .hidden, .prim (.int 5)),
                ("ref", .regular, .ref "_base"),
                ("cmp", .regular, .binary .ne (.ref "_base") (.prim (.int 3))),
                ("sum", .regular, .binary .add (.ref "_base") (.prim (.int 1))),
                ("eq", .regular, .binary .eq (.ref "_base") (.prim (.int 5))),
                ("nested", .regular, .binary .ne (.ref "_base") (.ref "_base"))
              ]
              true))
    },
    {
      fileName := "underscore_top_bottom.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("bottom", .regular,
                  .disj [(.regular, .bottom), (.regular, .prim (.int 2))]),
                ("self", .regular,
                  bindValueAlias "X"
                    (.struct
                      [
                        ("n", .regular, .prim (.int 1)),
                        ("m", .regular, .selector (.ref "X") "n")
                      ]
                      true))
              ]
              true))
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
      fileName := "let_binding.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("base", .letBinding, .prim (.int 2)),
                ("x", .regular, .conj [.ref "base", .kind .int]),
                ("nested", .regular,
                  .struct
                    [
                      ("kind", .letBinding, .kind .string),
                      ("value", .regular, .conj [.ref "kind", .prim (.string "ok")])
                    ]
                    true)
              ]
              true))
    },
    {
      fileName := "let_chain.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("a", .letBinding, .prim (.int 1)),
                ("b", .letBinding, .binary .add (.ref "a") (.prim (.int 1))),
                ("x", .regular, .ref "b")
              ]
              true))
    },
    {
      fileName := "let_shadow.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("v", .letBinding, .prim (.int 1)),
                ("outer", .regular, .ref "v"),
                ("inner", .regular,
                  .struct
                    [
                      ("v", .letBinding, .prim (.int 2)),
                      ("val", .regular, .ref "v")
                    ]
                    true)
              ]
              true))
    },
    {
      fileName := "let_sibling.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("top", .regular,
                  .struct
                    [
                      ("base", .regular, .prim (.int 10)),
                      ("doubled", .letBinding, .binary .mul (.ref "base") (.prim (.int 2))),
                      ("out", .regular, .ref "doubled")
                    ]
                    true)
              ]
              true))
    },
    {
      fileName := "let_not_in_output.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("secret", .letBinding, .prim (.string "abc")),
                ("shown", .regular, .ref "secret"),
                ("other", .regular, .prim (.int 1))
              ]
              true))
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
      fileName := "multiple_pattern_fields.expected",
      content :=
        formatField "x"
          (meet
            (.structPatterns
              []
              [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)]
              true)
            (.struct
              [
                ("az", .regular, .prim (.int 1)),
                ("ax", .regular, .prim (.int 2)),
                ("bz", .regular, .prim (.string "ok"))
              ]
              true))
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
      fileName := "regex_class_pattern.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("x", .regular,
                meet
                  (.structPattern [] (.stringRegex "^[ab]cz$") (.kind .int) true)
                  (.struct
                    [
                      ("acz", .regular, .prim (.int 1)),
                      ("bcz", .regular, .prim (.int 2)),
                      ("ccz", .regular, .prim (.string "skip"))
                    ]
                    true)),
              ("y", .regular,
                meet
                  (.structPattern [] (.stringRegex "^a[0-9]z$") (.kind .int) true)
                  (.struct
                    [("a5z", .regular, .prim (.int 1)), ("axz", .regular, .prim (.string "skip"))]
                    true))
            ]
            true)
    },
    {
      fileName := "regex_escape_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.stringRegex "^a\\.z$") (.kind .int) true)
            (.struct
              [("a.z", .regular, .prim (.string "bad")), ("abz", .regular, .prim (.string "skip"))]
              true))
    },
    {
      fileName := "regex_question_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.stringRegex "^colou?r$") (.kind .int) true)
            (.struct
              [
                ("color", .regular, .prim (.string "bad")),
                ("colour", .regular, .prim (.int 2)),
                ("colouur", .regular, .prim (.string "skip"))
              ]
              true))
    },
    {
      fileName := "regex_shorthand_pattern.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("x", .regular,
                meet
                  (.structPattern [] (.stringRegex "^a\\dz$") (.kind .int) true)
                  (.struct
                    [("a5z", .regular, .prim (.string "bad")), ("adz", .regular, .prim (.string "skip"))]
                    true)),
              ("y", .regular,
                meet
                  (.structPattern [] (.stringRegex "^a\\Dz$") (.kind .int) true)
                  (.struct
                    [("a5z", .regular, .prim (.string "skip")), ("adz", .regular, .prim (.int 1))]
                    true))
            ]
            true)
    },
    {
      fileName := "regex_alternation_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.stringRegex "^cat$|^dog$") (.kind .int) true)
            (.struct
              [
                ("cat", .regular, .prim (.string "bad")),
                ("dog", .regular, .prim (.int 2)),
                ("cow", .regular, .prim (.string "skip"))
              ]
              true))
    },
    {
      fileName := "regex_group_alternation_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.stringRegex "^(cat|dog)$") (.kind .int) true)
            (.struct
              [
                ("cat", .regular, .prim (.string "bad")),
                ("dog", .regular, .prim (.int 2)),
                ("cow", .regular, .prim (.string "skip"))
              ]
              true))
    },
    {
      fileName := "regex_word_shorthand_pattern.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("x", .regular,
                meet
                  (.structPattern [] (.stringRegex "^a\\wz$") (.kind .int) true)
                  (.struct
                    [("a_z", .regular, .prim (.string "bad")), ("a-z", .regular, .prim (.string "skip"))]
                    true)),
              ("y", .regular,
                meet
                  (.structPattern [] (.stringRegex "^a\\Wz$") (.kind .int) true)
                  (.struct
                    [("a_z", .regular, .prim (.string "skip")), ("a-z", .regular, .prim (.string "bad"))]
                    true))
            ]
            true)
    },
    {
      fileName := "regex_space_shorthand_pattern.expected",
      content :=
        formatTopLevel
          (.struct
            [
              ("x", .regular,
                meet
                  (.structPattern [] (.stringRegex "^a\\sz$") (.kind .int) true)
                  (.struct
                    [("a z", .regular, .prim (.string "bad")), ("a_z", .regular, .prim (.string "skip"))]
                    true)),
              ("y", .regular,
                meet
                  (.structPattern [] (.stringRegex "^a\\Sz$") (.kind .int) true)
                  (.struct
                    [("a z", .regular, .prim (.string "skip")), ("a_z", .regular, .prim (.string "bad"))]
                    true))
            ]
            true)
    },
    {
      fileName := "regex_exact_repetition_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.stringRegex "^a\\d{2}z$") (.kind .int) true)
            (.struct
              [("a12z", .regular, .prim (.string "bad")), ("a1z", .regular, .prim (.string "skip"))]
              true))
    },
    {
      fileName := "regex_bounded_repetition_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.structPattern [] (.stringRegex "^a\\d{2,3}z$") (.kind .int) true)
            (.struct
              [
                ("a12z", .regular, .prim (.int 2)),
                ("a123z", .regular, .prim (.string "bad")),
                ("a1z", .regular, .prim (.string "skip"))
              ]
              true))
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
      fileName := "struct_ellipsis.expected",
      content :=
        formatField "x"
          (meet
            (.structTail [("a", .regular, .kind .int)] .top)
            (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "ok"))] true))
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
    },
    {
      fileName := "comprehension_for.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                (
                  "out",
                  .regular,
                  .structComp
                    []
                    [
                      .comprehension
                        [.forIn (some "k") "v" (.struct [("x", .regular, .prim (.int 1))] true)]
                        (.struct
                          [
                            ("key", .regular, .ref "k"),
                            ("val", .regular, .ref "v")
                          ]
                          true)
                    ]
                    true)
              ]
              true))
    },
    {
      fileName := "comprehension_guard.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                (
                  "out",
                  .regular,
                  .structComp
                    [("base", .regular, .prim (.int 0))]
                    [
                      .comprehension
                        [.forIn none "v" (.list [.prim (.int 42)])]
                        (.struct [("only", .regular, .ref "v")] true),
                      .comprehension
                        [.guard (.prim (.bool true))]
                        (.struct [("flag", .regular, .prim (.bool true))] true),
                      .comprehension
                        [.guard (.prim (.bool false))]
                        (.struct [("hidden", .regular, .prim (.int 1))] true)
                    ]
                    true)
              ]
              true))
    },
    {
      fileName := "string_interpolation.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("n", .regular, .prim (.int 3)),
                (
                  "out",
                  .regular,
                  .interpolation [.prim (.string "v"), .ref "n", .prim (.string "x")]
                )
              ]
              true))
    },
    {
      fileName := "multiline_string.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [("x", .regular, .prim (.string "hello\nworld"))] true))
    },
    {
      fileName := "multiline_dedent.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [("x", .regular, .prim (.string "line1\n  line2"))] true))
    },
    {
      fileName := "multiline_interpolation.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("n", .regular, .prim (.string "bob")),
                (
                  "x",
                  .regular,
                  .interpolation [.prim (.string "hi "), .ref "n", .prim (.string "\nbye")]
                )
              ]
              true))
    },
    {
      fileName := "multiline_empty.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [("x", .regular, .prim (.string ""))] true))
    },
    {
      fileName := "multiline_cert.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                (
                  "cert",
                  .regular,
                  .prim (.string "-----BEGIN CERTIFICATE-----\nMIIBIjANBg\n-----END CERTIFICATE-----")
                )
              ]
              true))
    },
    {
      fileName := "multiline_bytes.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [("x", .regular, .prim (.bytes "abc\ndef"))] true))
    },
    {
      fileName := "dynamic_field.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("k", .regular, .prim (.string "name")),
                (
                  "out",
                  .regular,
                  .structComp [] [.dynamicField (.ref "k") .regular (.prim (.int 42))] true
                )
              ]
              true))
    },
    {
      fileName := "dynamic_field_comprehension.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                (
                  "out",
                  .regular,
                  .structComp
                    []
                    [
                      .comprehension
                        [.forIn (some "k") "v"
                          (.struct
                            [
                              ("a", .regular, .prim (.int 1)),
                              ("b", .regular, .prim (.int 2))
                            ]
                            true)]
                        (.structComp
                          []
                          [.dynamicField (.interpolation [.ref "k"]) .regular (.ref "v")]
                          true)
                    ]
                    true)
              ]
              true))
    },
    {
      fileName := "comprehension_loopvar_shadow.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("v", .regular, .prim (.string "sibling")),
                (
                  "out",
                  .regular,
                  .structComp
                    [("keep", .regular, .ref "v")]
                    [
                      .comprehension
                        [.forIn none "v" (.list [.prim (.int 10), .prim (.int 20)])]
                        (.structComp
                          []
                          [.dynamicField
                            (.interpolation [.prim (.string "k"), .ref "v"]) .regular (.ref "v")]
                          true)
                    ]
                    true)
              ]
              true))
    },
    {
      fileName := "struct_embedding_scope.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                (
                  "out",
                  .regular,
                  .structComp
                    [("base", .regular, .prim (.int 7))]
                    [.struct [("copy", .regular, .ref "base")] true]
                    true)
              ]
              true))
    },
    {
      fileName := "struct_embedding_nested.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                (
                  "out",
                  .regular,
                  .structComp
                    [("base", .regular, .prim (.int 7))]
                    [.struct [("inner", .regular, .struct [("deep", .regular, .ref "base")] true)] true]
                    true)
              ]
              true))
    },
    {
      fileName := "struct_embedding_siblings.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                (
                  "out",
                  .regular,
                  .structComp
                    [
                      ("base", .regular, .prim (.int 7)),
                      ("sib", .regular, .prim (.int 9))
                    ]
                    [.struct
                      [
                        ("copy", .regular, .ref "base"),
                        ("copy2", .regular, .ref "sib")
                      ]
                      true]
                    true)
              ]
              true))
    },
    {
      -- `{[1, 2, 3]}`: a list embedded in a struct with no other members IS the list.
      fileName := "list_embedding_pure.expected",
      content :=
        formatField "x"
          (resolveAndEval
            (.structComp [] [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]] true))
    },
    {
      -- `{#a: 1, [1, 2]}`: only-non-output struct + list embed → embeddedList with decls.
      fileName := "list_embedding_hidden.expected",
      content :=
        formatField "x"
          (resolveAndEval
            (.structComp
              [("#a", .definition, .prim (.int 1))]
              [.list [.prim (.int 1), .prim (.int 2)]]
              true))
    },
    {
      -- `{#a: 1, [...]}`: open list embed; manifests as `[]`, eval keeps `[...]`.
      fileName := "list_embedding_open.expected",
      content :=
        formatField "x"
          (resolveAndEval
            (.structComp
              [("#a", .definition, .prim (.int 1))]
              [.listTail [] .top]
              true))
    },
    {
      -- `{a: 1, [1, 2]}`: a regular (output) field present → genuine struct/list conflict.
      fileName := "list_embedding_regular_conflict.expected",
      content :=
        formatField "x"
          (resolveAndEval
            (.structComp
              [("a", .regular, .prim (.int 1))]
              [.list [.prim (.int 1), .prim (.int 2)]]
              true))
    },
    {
      -- `{a: 1} & [1, 2]`: explicit struct meet list, struct has an output field → bottom.
      fileName := "list_struct_genuine_conflict.expected",
      content :=
        formatField "x"
          (meet
            (.struct [("a", .regular, .prim (.int 1))] true)
            (.list [.prim (.int 1), .prim (.int 2)]))
    },
    {
      -- `{a?: int, [1, 2]}`: optional is non-output, so the list embed survives.
      fileName := "list_embedding_optional.expected",
      content :=
        formatField "x"
          (resolveAndEval
            (.structComp
              [("a", .optional, .kind .int)]
              [.list [.prim (.int 1), .prim (.int 2)]]
              true))
    },
    {
      -- `{#a: 1, [...int]} & {#b: 2, [1, 2]}`: meet of two embeddedLists — decls merge,
      -- lists meet (`[...int] & [1, 2] = [1, 2]`).
      fileName := "list_embedding_meet_two.expected",
      content :=
        formatField "x"
          (meet
            (resolveAndEval
              (.structComp [("#a", .definition, .prim (.int 1))] [.listTail [] (.kind .int)] true))
            (resolveAndEval
              (.structComp [("#b", .definition, .prim (.int 2))]
                [.list [.prim (.int 1), .prim (.int 2)]] true)))
    },
    {
      -- `{#a: 1, [10, 20]}.#a` selects a decl; `[0]` indexes the embedded list.
      fileName := "list_embedding_select_index.expected",
      content :=
        let base : Value :=
          .structComp [("#a", .definition, .prim (.int 1))]
            [.list [.prim (.int 10), .prim (.int 20)]] true
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("p", .regular, .selector base "#a"),
                ("q", .regular, .index base (.prim (.int 0)))
              ]
              true))
    },
    {
      fileName := "strings_builtin.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("contains", .regular,
                  .builtinCall "strings.Contains" [.prim (.string "seafood"), .prim (.string "foo")]),
                ("hasPrefix", .regular,
                  .builtinCall "strings.HasPrefix" [.prim (.string "seafood"), .prim (.string "sea")]),
                ("hasSuffix", .regular,
                  .builtinCall "strings.HasSuffix" [.prim (.string "seafood"), .prim (.string "food")]),
                ("index", .regular,
                  .builtinCall "strings.Index" [.prim (.string "héllo"), .prim (.string "llo")]),
                ("indexMiss", .regular,
                  .builtinCall "strings.Index" [.prim (.string "chicken"), .prim (.string "xyz")]),
                ("count", .regular,
                  .builtinCall "strings.Count" [.prim (.string "cheese"), .prim (.string "e")]),
                ("split", .regular,
                  .builtinCall "strings.Split" [.prim (.string "a,b,c"), .prim (.string ",")]),
                ("splitEmptySep", .regular,
                  .builtinCall "strings.Split" [.prim (.string "héllo"), .prim (.string "")]),
                ("splitTrailing", .regular,
                  .builtinCall "strings.Split" [.prim (.string "a,b,"), .prim (.string ",")]),
                ("join", .regular,
                  .builtinCall "strings.Join"
                    [.list [.prim (.string "a"), .prim (.string "b"), .prim (.string "c")],
                     .prim (.string "-")]),
                ("replaceN", .regular,
                  .builtinCall "strings.Replace"
                    [.prim (.string "aaaa"), .prim (.string "a"), .prim (.string "b"), .prim (.int 2)]),
                ("replaceAll", .regular,
                  .builtinCall "strings.Replace"
                    [.prim (.string "oink oink"), .prim (.string "k"), .prim (.string "ky"), .prim (.int (-1))]),
                ("repeat", .regular,
                  .builtinCall "strings.Repeat" [.prim (.string "ab"), .prim (.int 3)]),
                ("trimSpace", .regular,
                  .builtinCall "strings.TrimSpace" [.prim (.string "  hi  ")]),
                ("fields", .regular,
                  .builtinCall "strings.Fields" [.prim (.string "  a  b c ")])
              ]
              true))
    },
    {
      fileName := "list_builtin.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("concat", .regular,
                  .builtinCall "list.Concat"
                    [.list [.list [.prim (.int 1), .prim (.int 2)], .list [.prim (.int 3)],
                            .list [.prim (.int 4), .prim (.int 5)]]]),
                ("concatEmpty", .regular,
                  .builtinCall "list.Concat" [.list []]),
                ("flatten1", .regular,
                  .builtinCall "list.FlattenN"
                    [.list [.list [.prim (.int 1), .list [.prim (.int 2)]], .list [.prim (.int 3)]],
                     .prim (.int 1)]),
                ("flatten2", .regular,
                  .builtinCall "list.FlattenN"
                    [.list [.list [.prim (.int 1), .list [.prim (.int 2)]], .list [.prim (.int 3)]],
                     .prim (.int 2)]),
                ("flattenAll", .regular,
                  .builtinCall "list.FlattenN"
                    [.list [.prim (.int 1),
                            .list [.prim (.int 2), .list [.prim (.int 3), .list [.prim (.int 4)]]]],
                     .prim (.int (-1))]),
                ("flatten0", .regular,
                  .builtinCall "list.FlattenN"
                    [.list [.list [.prim (.int 1)], .list [.prim (.int 2)]], .prim (.int 0)]),
                ("repeat", .regular,
                  .builtinCall "list.Repeat"
                    [.list [.prim (.int 1), .prim (.int 2)], .prim (.int 3)]),
                ("repeat0", .regular,
                  .builtinCall "list.Repeat"
                    [.list [.prim (.int 1), .prim (.int 2)], .prim (.int 0)]),
                ("rangeUp", .regular,
                  .builtinCall "list.Range" [.prim (.int 0), .prim (.int 5), .prim (.int 1)]),
                ("rangeStep", .regular,
                  .builtinCall "list.Range" [.prim (.int 0), .prim (.int 10), .prim (.int 2)]),
                ("rangeDown", .regular,
                  .builtinCall "list.Range" [.prim (.int 5), .prim (.int 0), .prim (.int (-1))]),
                ("rangeEmpty", .regular,
                  .builtinCall "list.Range" [.prim (.int 1), .prim (.int 1), .prim (.int 1)]),
                ("slice", .regular,
                  .builtinCall "list.Slice"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3), .prim (.int 4)],
                     .prim (.int 1), .prim (.int 3)]),
                ("take", .regular,
                  .builtinCall "list.Take"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3), .prim (.int 4)],
                     .prim (.int 2)]),
                ("takeOver", .regular,
                  .builtinCall "list.Take"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], .prim (.int 5)]),
                ("drop", .regular,
                  .builtinCall "list.Drop"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3), .prim (.int 4)],
                     .prim (.int 2)]),
                ("dropOver", .regular,
                  .builtinCall "list.Drop"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], .prim (.int 5)]),
                ("contains", .regular,
                  .builtinCall "list.Contains"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], .prim (.int 2)]),
                ("containsNo", .regular,
                  .builtinCall "list.Contains"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], .prim (.int 9)]),
                ("containsSub", .regular,
                  .builtinCall "list.Contains"
                    [.list [.list [.prim (.int 1)], .list [.prim (.int 2)]], .list [.prim (.int 1)]]),
                ("sum", .regular,
                  .builtinCall "list.Sum"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]]),
                ("sumEmpty", .regular,
                  .builtinCall "list.Sum" [.list []]),
                ("min", .regular,
                  .builtinCall "list.Min"
                    [.list [.prim (.int 3), .prim (.int 1), .prim (.int 2)]]),
                ("max", .regular,
                  .builtinCall "list.Max"
                    [.list [.prim (.int 3), .prim (.int 1), .prim (.int 2)]])
              ]
              true))
    },
    {
      fileName := "list_sort_strings.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("basic", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "banana"), .prim (.string "apple"), .prim (.string "cherry")]]),
                ("dup", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "b"), .prim (.string "a"), .prim (.string "b"), .prim (.string "a")]]),
                ("empty", .regular,
                  .builtinCall "list.SortStrings" [.list []]),
                ("single", .regular,
                  .builtinCall "list.SortStrings" [.list [.prim (.string "x")]]),
                ("sorted", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "a"), .prim (.string "b"), .prim (.string "c")]]),
                ("reverse", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "c"), .prim (.string "b"), .prim (.string "a")]]),
                ("caps", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "b"), .prim (.string "A"), .prim (.string "a"), .prim (.string "B")]]),
                ("unicode", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "é"), .prim (.string "a"), .prim (.string "z"), .prim (.string "Z")]])
              ]
              true))
    },
    {
      fileName := "strings_case.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("upperLower", .regular,
                  .builtinCall "strings.ToUpper" [.prim (.string "hello World 123!")]),
                ("upperUpper", .regular,
                  .builtinCall "strings.ToUpper" [.prim (.string "ALREADY UP")]),
                ("lowerMixed", .regular,
                  .builtinCall "strings.ToLower" [.prim (.string "Hello WORLD 123!")]),
                ("lowerLower", .regular,
                  .builtinCall "strings.ToLower" [.prim (.string "already low")]),
                ("upperEmpty", .regular,
                  .builtinCall "strings.ToUpper" [.prim (.string "")]),
                ("lowerEmpty", .regular,
                  .builtinCall "strings.ToLower" [.prim (.string "")]),
                ("upperPunct", .regular,
                  .builtinCall "strings.ToUpper" [.prim (.string "abc123!@#")]),
                ("lowerPunct", .regular,
                  .builtinCall "strings.ToLower" [.prim (.string "ABC123!@#")]),
                ("titleWords", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "hello world foo")]),
                ("titleUpper", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "HELLO WORLD")]),
                ("titleEmpty", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "")]),
                ("titleSeps", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "a-b a.b a_b a/b")]),
                ("titleDigit", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "3 abc a3bc")]),
                ("titleLead", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "  leading")])
              ]
              true))
    },
    {
      fileName := "strings_splitn.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("remainder", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 2)]),
                ("zero", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 0)]),
                ("negative", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int (-1))]),
                ("exceed", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 5)]),
                ("exact", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 3)]),
                ("one", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 1)]),
                ("absent", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "xyz"), .prim (.string ","), .prim (.int 2)]),
                ("emptyStr", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string ""), .prim (.string ","), .prim (.int 2)]),
                ("emptySepN", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "abc"), .prim (.string ""), .prim (.int 2)]),
                ("emptySepA", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "abc"), .prim (.string ""), .prim (.int (-1))]),
                ("emptyBoth", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string ""), .prim (.string ""), .prim (.int (-1))])
              ]
              true))
    },
    {
      fileName := "list_builtin_float.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("avgDiv", .regular,
                  .builtinCall "list.Avg"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]]),
                ("avgNoDiv", .regular,
                  .builtinCall "list.Avg" [.list [.prim (.int 1), .prim (.int 2)]]),
                ("avgThirds", .regular,
                  .builtinCall "list.Avg"
                    [.list [.prim (.int 1), .prim (.int 1), .prim (.int 2)]]),
                ("avgQuarter", .regular,
                  .builtinCall "list.Avg"
                    [.list [.prim (.int 1), .prim (.int 1), .prim (.int 1), .prim (.int 2)]]),
                ("avgFloat", .regular,
                  .builtinCall "list.Avg"
                    [.list [.prim (.float "1.0"), .prim (.float "2.0")]]),
                ("avgMixed", .regular,
                  .builtinCall "list.Avg" [.list [.prim (.int 1), .prim (.float "2.0")]]),
                ("sumFloat", .regular,
                  .builtinCall "list.Sum"
                    [.list [.prim (.float "1.0"), .prim (.float "2.0"), .prim (.float "3.0")]]),
                ("sumMixed", .regular,
                  .builtinCall "list.Sum"
                    [.list [.prim (.int 1), .prim (.float "2.0"), .prim (.int 3)]]),
                ("sumMixedFrac", .regular,
                  .builtinCall "list.Sum"
                    [.list [.prim (.int 1), .prim (.float "2.5"), .prim (.int 3)]]),
                ("minFloat", .regular,
                  .builtinCall "list.Min"
                    [.list [.prim (.float "3.0"), .prim (.float "1.0"), .prim (.float "2.0")]]),
                ("minMixed", .regular,
                  .builtinCall "list.Min"
                    [.list [.prim (.int 3), .prim (.float "1.5"), .prim (.int 2)]]),
                ("maxFloat", .regular,
                  .builtinCall "list.Max"
                    [.list [.prim (.float "3.0"), .prim (.float "1.0"), .prim (.float "2.0")]]),
                ("maxMixed", .regular,
                  .builtinCall "list.Max"
                    [.list [.prim (.int 3), .prim (.float "1.5"), .prim (.int 2)]]),
                ("rangeFloat", .regular,
                  .builtinCall "list.Range"
                    [.prim (.float "0.0"), .prim (.float "2.0"), .prim (.float "0.5")]),
                ("rangeNeg", .regular,
                  .builtinCall "list.Range"
                    [.prim (.float "2.0"), .prim (.float "0.0"), .prim (.float "-0.5")])
              ]
              true))
    },
    {
      fileName := "math_builtin.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("absNegInt", .regular,
                  .builtinCall "math.Abs" [.prim (.int (-5))]),
                ("absPosInt", .regular,
                  .builtinCall "math.Abs" [.prim (.int 5)]),
                ("absZero", .regular,
                  .builtinCall "math.Abs" [.prim (.int 0)]),
                ("absFloat", .regular,
                  .builtinCall "math.Abs" [.prim (.float "-3.5")]),
                ("absBigFloat", .regular,
                  .builtinCall "math.Abs" [.prim (.float "-123.456")]),
                ("multTrue", .regular,
                  .builtinCall "math.MultipleOf" [.prim (.int 12), .prim (.int 3)]),
                ("multFalse", .regular,
                  .builtinCall "math.MultipleOf" [.prim (.int 13), .prim (.int 3)]),
                ("multNegValue", .regular,
                  .builtinCall "math.MultipleOf" [.prim (.int (-12)), .prim (.int 3)]),
                ("multNegDivisor", .regular,
                  .builtinCall "math.MultipleOf" [.prim (.int 12), .prim (.int (-3))]),
                ("floorPos", .regular,
                  .builtinCall "math.Floor" [.prim (.float "3.7")]),
                ("floorNeg", .regular,
                  .builtinCall "math.Floor" [.prim (.float "-3.2")]),
                ("floorInt", .regular,
                  .builtinCall "math.Floor" [.prim (.int 5)]),
                ("floorExact", .regular,
                  .builtinCall "math.Floor" [.prim (.float "3.0")]),
                ("ceilPos", .regular,
                  .builtinCall "math.Ceil" [.prim (.float "3.2")]),
                ("ceilNeg", .regular,
                  .builtinCall "math.Ceil" [.prim (.float "-3.7")]),
                ("ceilInt", .regular,
                  .builtinCall "math.Ceil" [.prim (.int 5)]),
                ("roundHalf", .regular,
                  .builtinCall "math.Round" [.prim (.float "2.5")]),
                ("roundNegHalf", .regular,
                  .builtinCall "math.Round" [.prim (.float "-2.5")]),
                ("roundDown", .regular,
                  .builtinCall "math.Round" [.prim (.float "2.4")]),
                ("roundUp", .regular,
                  .builtinCall "math.Round" [.prim (.float "0.5")]),
                ("truncPos", .regular,
                  .builtinCall "math.Trunc" [.prim (.float "3.7")]),
                ("truncNeg", .regular,
                  .builtinCall "math.Trunc" [.prim (.float "-3.99")]),
                ("truncInt", .regular,
                  .builtinCall "math.Trunc" [.prim (.int 5)])
              ]
              true))
    },
    {
      -- Colon-shorthand (`a: b: c: 1`) desugars to the brace form. This port builds the
      -- explicit-brace AST; the CLI port independently evaluates the shorthand `.cue`.
      -- Both matching `.expected` pins that shorthand produces the brace-identical value.
      fileName := "colon_shorthand.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("metadata", .regular,
                  .struct [("name", .regular, .prim (.string "api"))] true),
                ("spec", .regular,
                  .struct
                    [
                      ("replicas", .regular, .prim (.int 3)),
                      ("template", .regular,
                        .struct
                          [("spec", .regular,
                            .struct
                              [("containers", .regular, .list [.prim (.string "c")])]
                              true)]
                          true)
                    ]
                    true),
                ("labels", .regular,
                  .struct [("prodigy9.co/app", .regular, .prim (.string "web"))] true),
                ("mixed", .regular,
                  .struct
                    [("a", .regular,
                      .struct [("b", .regular,
                        .struct [("c", .regular, .prim (.int 1))] true)] true)]
                    true)
              ]
              true))
    },
    {
      -- Value aliases (`label: X={…}`, esp. `#Def: Self={…}`). This port builds the
      -- desugared AST: a value alias prepends a non-output `Self`/`X` let-binding whose
      -- value is `.thisStruct`, so `Self.field` resolves as a same-struct sibling
      -- reference. The CLI port independently parses/evaluates the alias `.cue`; both
      -- matching `.expected` pins that the alias binding resolves correctly.
      fileName := "value_aliases.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("#Secret", .definition,
                  .struct
                    [
                      ("Self", .letBinding, .thisStruct),
                      ("#name", .definition, .prim (.string "tls")),
                      ("data", .regular, .selector (.ref "Self") "#name")
                    ]
                    false),
                ("aliased", .regular,
                  .struct
                    [
                      ("X", .letBinding, .thisStruct),
                      ("greeting", .regular, .prim (.string "hi")),
                      ("echo", .regular, .selector (.ref "X") "greeting")
                    ]
                    true),
                ("nestedSelf", .regular,
                  .struct
                    [
                      ("Self", .letBinding, .thisStruct),
                      ("port", .regular, .prim (.int 8080)),
                      ("inner", .regular,
                        .struct [("lo", .regular, .selector (.ref "Self") "port")] true)
                    ]
                    true)
              ]
              true))
    },
    {
      fileName := "base64_encode.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("ascii", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "hello")]),
                ("empty", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "")]),
                ("multibyte", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "héllo")]),
                ("pad1", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "a")]),
                ("pad2", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "ab")]),
                ("pad0", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "abc")]),
                ("overBytes", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.bytes "hello")]),
                ("nonNull", .regular,
                  .builtinCall "base64.Encode" [.prim (.string "std"), .prim (.string "hello")])
              ]
              true))
    },
    {
      fileName := "json_marshal.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("str", .regular, .builtinCall "json.Marshal" [.prim (.string "hi")]),
                ("intVal", .regular, .builtinCall "json.Marshal" [.prim (.int 42)]),
                ("negInt", .regular, .builtinCall "json.Marshal" [.prim (.int (-5))]),
                ("floatVal", .regular, .builtinCall "json.Marshal" [.prim (.float "1.5")]),
                ("floatWhole", .regular, .builtinCall "json.Marshal" [.prim (.float "1.0")]),
                ("boolVal", .regular, .builtinCall "json.Marshal" [.prim (.bool true)]),
                ("nullVal", .regular, .builtinCall "json.Marshal" [.prim .null]),
                ("nested", .regular,
                  .builtinCall "json.Marshal"
                    [.struct
                      [
                        ("b", .regular, .prim (.int 2)),
                        ("a", .regular, .prim (.int 1)),
                        ("c", .regular,
                          .struct
                            [("z", .regular, .prim (.int 1)), ("y", .regular, .prim (.int 2))]
                            true)
                      ]
                      true]),
                ("listVal", .regular,
                  .builtinCall "json.Marshal"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]]),
                ("emptyObj", .regular, .builtinCall "json.Marshal" [.struct [] true]),
                ("emptyList", .regular, .builtinCall "json.Marshal" [.list []]),
                ("escapes", .regular,
                  .builtinCall "json.Marshal"
                    [.struct [("html", .regular, .prim (.string "<a>&\"b\\c\n\t"))] true]),
                ("incomplete", .regular,
                  .builtinCall "json.Marshal" [.struct [("a", .regular, .kind .int)] true])
              ]
              true))
    },
    {
      -- The prod9/infra docker-config chain: a registry-auth struct is JSON-marshalled
      -- then base64-encoded. The CLI port independently evaluates the `.cue`; both
      -- matching `.expected` pins that `base64.Encode(null, json.Marshal({...}))` composes.
      fileName := "encoding_infra_chain.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct
              [
                ("registry", .regular,
                  .struct
                    [("reg.io", .regular,
                      .struct [("auth", .regular, .prim (.string "abc"))] true)]
                    true),
                ("data", .regular,
                  .builtinCall "base64.Encode"
                    [.prim .null,
                      .builtinCall "json.Marshal"
                        [.struct [("auths", .regular, .ref "registry")] true]])
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
