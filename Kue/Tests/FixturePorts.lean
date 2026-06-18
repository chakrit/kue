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
      fileName := "numeric/additive_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2))⟩,
                ⟨"diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3))⟩,
                ⟨"cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b"))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/bytes_additive_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"bytes", .regular, .binary .add (.prim (.bytes "ab")) (.prim (.bytes "cd"))⟩,
                ⟨
                  "left",
                  .regular,
                  .binary .add
                    (.binary .add (.prim (.bytes "a")) (.prim (.bytes "b")))
                    (.prim (.bytes "c"))
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/float_additive_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"floatSum", .regular, .binary .add (.prim (.float "1.5")) (.prim (.float "2.25"))⟩,
                ⟨"intFloat", .regular, .binary .add (.prim (.int 1)) (.prim (.float "2.5"))⟩,
                ⟨"floatSub", .regular, .binary .sub (.prim (.float "5.5")) (.prim (.int 2))⟩,
                ⟨"whole", .regular, .binary .add (.prim (.float "1.5")) (.prim (.float "1.5"))⟩,
                ⟨"exp", .regular, .binary .add (.prim (.float "1e+3")) (.prim (.int 2))⟩,
                ⟨"small", .regular, .binary .add (.prim (.float "0.1")) (.prim (.float "0.2"))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/multiplication_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"mul", .regular, .binary .mul (.prim (.int 3)) (.prim (.int 4))⟩,
                ⟨
                  "precedence",
                  .regular,
                  .binary .add (.prim (.int 1)) (.binary .mul (.prim (.int 2)) (.prim (.int 3)))
                ⟩,
                ⟨
                  "left",
                  .regular,
                  .binary .mul (.binary .mul (.prim (.int 2)) (.prim (.int 3))) (.prim (.int 4))
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/division_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"div", .regular, .binary .div (.prim (.int 5)) (.prim (.int 2))⟩,
                ⟨"whole", .regular, .binary .div (.prim (.int 6)) (.prim (.int 3))⟩,
                ⟨"third", .regular, .binary .div (.prim (.int 1)) (.prim (.int 3))⟩,
                ⟨"negative", .regular, .binary .div (.prim (.int (-5))) (.prim (.int 2))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/float_muldiv_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"mulFloats", .regular, .binary .mul (.prim (.float "1.5")) (.prim (.float "2.0"))⟩,
                ⟨"mulScale", .regular, .binary .mul (.prim (.float "1.0")) (.prim (.float "1.0"))⟩,
                ⟨"mulIntFloat", .regular, .binary .mul (.prim (.int 2)) (.prim (.float "1.5"))⟩,
                ⟨"mulNegative", .regular, .binary .mul (.prim (.float "-1.5")) (.prim (.float "2.0"))⟩,
                ⟨"divTerminate", .regular, .binary .div (.prim (.float "1.0")) (.prim (.float "4.0"))⟩,
                ⟨"divClean", .regular, .binary .div (.prim (.float "4.0")) (.prim (.float "2.0"))⟩,
                ⟨"divFloatInt", .regular, .binary .div (.prim (.float "3.0")) (.prim (.int 2))⟩,
                ⟨"divRepeat", .regular, .binary .div (.prim (.float "2.0")) (.prim (.float "3.0"))⟩,
                ⟨"divRepeatInt", .regular, .binary .div (.prim (.float "10.0")) (.prim (.float "3.0"))⟩,
                ⟨"divRoundUp", .regular, .binary .div (.prim (.float "100.0")) (.prim (.float "7.0"))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/integer_keyword_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"divValue", .regular, .binary .intDiv (.prim (.int (-7))) (.prim (.int 3))⟩,
                ⟨"modValue", .regular, .binary .intMod (.prim (.int (-7))) (.prim (.int 3))⟩,
                ⟨"quoValue", .regular, .binary .intQuo (.prim (.int (-7))) (.prim (.int 3))⟩,
                ⟨"remValue", .regular, .binary .intRem (.prim (.int (-7))) (.prim (.int 3))⟩,
                ⟨
                  "precedence",
                  .regular,
                  .binary .add (.prim (.int 1)) (.binary .intDiv (.prim (.int 7)) (.prim (.int 3)))
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/equality_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"same", .regular, .binary .eq (.prim (.int 1)) (.prim (.int 1))⟩,
                ⟨"diff", .regular, .binary .ne (.prim (.int 1)) (.prim (.int 2))⟩,
                ⟨"text", .regular, .binary .eq (.prim (.string "a")) (.prim (.string "b"))⟩,
                ⟨
                  "precedence",
                  .regular,
                  .binary .eq (.binary .add (.prim (.int 1)) (.prim (.int 1))) (.prim (.int 2))
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/ordering_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"lt", .regular, .binary .lt (.prim (.int 1)) (.prim (.int 2))⟩,
                ⟨"le", .regular, .binary .le (.prim (.int 2)) (.prim (.int 2))⟩,
                ⟨"gt", .regular, .binary .gt (.prim (.int 3)) (.prim (.int 2))⟩,
                ⟨"ge", .regular, .binary .ge (.prim (.int 3)) (.prim (.int 4))⟩,
                ⟨"slt", .regular, .binary .lt (.prim (.string "a")) (.prim (.string "b"))⟩,
                ⟨
                  "precedence",
                  .regular,
                  .binary .lt (.binary .add (.prim (.int 1)) (.prim (.int 2))) (.prim (.int 4))
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/numeric_comparison_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"lt", .regular, .binary .lt (.prim (.float "1.5")) (.prim (.int 2))⟩,
                ⟨"le", .regular, .binary .le (.prim (.float "1.5")) (.prim (.float "1.50"))⟩,
                ⟨"gt", .regular, .binary .gt (.prim (.float "1e+3")) (.prim (.float "999.9"))⟩,
                ⟨"ge", .regular, .binary .ge (.prim (.float "1.0")) (.prim (.int 1))⟩,
                ⟨"eq", .regular, .binary .eq (.prim (.int 1)) (.prim (.float "1.0"))⟩,
                ⟨"ne", .regular, .binary .ne (.prim (.int 1)) (.prim (.float "1.0"))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/logical_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"andFalse", .regular, .binary .boolAnd (.prim (.bool true)) (.prim (.bool false))⟩,
                ⟨"orTrue", .regular, .binary .boolOr (.prim (.bool false)) (.prim (.bool true))⟩,
                ⟨
                  "andCmp",
                  .regular,
                  .binary .boolAnd
                    (.binary .lt (.prim (.int 1)) (.prim (.int 2)))
                    (.binary .gt (.prim (.int 3)) (.prim (.int 2)))
                ⟩,
                ⟨
                  "orCmp",
                  .regular,
                  .binary .boolOr
                    (.prim (.bool false))
                    (.binary .eq (.binary .add (.prim (.int 1)) (.prim (.int 1))) (.prim (.int 2)))
                ⟩,
                ⟨
                  "grouped",
                  .regular,
                  .binary .boolAnd
                    (.binary .boolOr (.prim (.bool false)) (.prim (.bool true)))
                    (.prim (.bool true))
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/logical_not_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"notFalse", .regular, .unary .boolNot (.prim (.bool false))⟩,
                ⟨"notCmp", .regular, .unary .boolNot (.binary .lt (.prim (.int 1)) (.prim (.int 2)))⟩,
                ⟨"double", .regular, .unary .boolNot (.unary .boolNot (.prim (.bool true)))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/unary_numeric_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"negGroup", .regular, .unary .numNeg (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
                ⟨"posGroup", .regular, .unary .numPos (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
                ⟨"negRefBase", .regular, .prim (.int 3)⟩,
                ⟨"negRef", .regular, .unary .numNeg (.ref "negRefBase")⟩,
                ⟨"precedence", .regular, .binary .mul (.unary .numNeg (.prim (.int 2))) (.prim (.int 3))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/regex_match_expressions.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"match", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "^a"))⟩,
                ⟨"miss", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "z"))⟩,
                ⟨"notMatch", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "z"))⟩,
                ⟨"notMiss", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "^a"))⟩,
                ⟨
                  "precedence",
                  .regular,
                  .binary .regexMatch
                    (.binary .add (.prim (.string "ab")) (.prim (.string "c")))
                    (.prim (.string "^abc$"))
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/bytes_kind.expected",
      content := formatField "x" (meet (.kind .bytes) (.prim (.bytes "abc")))
    },
    {
      fileName := "refs/builtin_reference_eval.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"x", .regular, .prim (.string "abc")⟩,
                ⟨"n", .regular, .prim (.int (-7))⟩,
                ⟨"lenX", .regular, .builtinCall "len" [.ref "x"]⟩,
                ⟨"divN", .regular, .builtinCall "div" [.ref "n", .prim (.int 3)]⟩,
                ⟨"incomplete", .regular, .builtinCall "len" [.kind .string]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/and_or_builtin.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"andValue", .regular, andValues [.kind .int, .boundConstraint (intDecimal 0) .gt .number, .prim (.int 7)]⟩,
              ⟨"orValue", .regular, orValues [.prim (.string "a"), .prim (.string "b")]⟩
            ] .regularOpen none [])
    },
    {
      fileName := "builtins/integer_builtin.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"divValue", .regular, divValue (.prim (.int (-7))) (.prim (.int 3))⟩,
              ⟨"modValue", .regular, modValue (.prim (.int (-7))) (.prim (.int 3))⟩,
              ⟨"quoValue", .regular, quoValue (.prim (.int (-7))) (.prim (.int 3))⟩,
              ⟨"remValue", .regular, remValue (.prim (.int (-7))) (.prim (.int 3))⟩,
              ⟨"incompleteDiv", .regular, divValue (.kind .int) (.prim (.int 3))⟩,
              ⟨"zeroDivisor", .regular, divValue (.prim (.int 7)) (.prim (.int 0))⟩
            ] .regularOpen none [])
    },
    {
      fileName := "definitions/closed_extra_field.expected",
      content :=
        formatField "x"
          (meet
            (closeValue (.struct [⟨"a", .regular, .kind .int⟩] .regularOpen none []))
            (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/closed_hidden_definition.expected",
      content :=
        formatField "x"
          (meet
            (closeValue (.struct [⟨"a", .regular, .kind .int⟩] .regularOpen none []))
            (.struct [
                ⟨"a", .regular, .prim (.int 1)⟩,
                ⟨"_h", .hidden, .prim (.string "secret")⟩,
                ⟨"#D", .definition, .kind .string⟩
              ] .regularOpen none []))
    },
    {
      -- Optional definition (`#x?`) and optional hidden (`_x?`) fields: both modifiers are
      -- orthogonal, so the optional field merges with the provided value (`#x?` + `#x` →
      -- present definition), and selection sees the narrowed value. Driven through parse so
      -- the `#x?`/`_y?` lexing is exercised alongside the merge.
      fileName := "definitions/optional_definition_field.expected",
      content :=
        match parseSource
            "#D: {\n\t#x?: string\n\t_y?: int\n}\nprovided: #D & {\n\t#x: \"hi\"\n\t_y: 7\n}\nselected: provided.#x\nhidden:   provided._y\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      fileName := "definitions/closed_regex_pattern.expected",
      content :=
        formatField "x"
          (meet
            (closeValue (.struct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))]))
            (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none []))
    },
    {
      fileName := "disjunctions/default_disjunction.expected",
      content :=
        formatField "x"
          (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
    },
    {
      fileName := "disjunctions/default_disjunction.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
    },
    {
      fileName := "disjunctions/default_override.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (meet
            (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
            (.prim (.string "dev")))
    },
    -- F1 default-mark algebra. Arithmetic resolves each disjunction operand to its single
    -- default FIRST, then operates: `(1|*2)+(10|*20) → 2+20 → 22` (NOT a cross-product).
    {
      fileName := "disjunctions/default_arithmetic_cross.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [⟨"x", .regular,
                .binary .add
                  (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
                  (.disj [(.regular, .prim (.int 10)), (.default, .prim (.int 20))])⟩] .regularOpen none []))
    },
    {
      fileName := "disjunctions/default_arithmetic_cross.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (selectEvaluatedField
            (resolveAndEval
              (.struct [⟨"x", .regular,
                  .binary .add
                    (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
                    (.disj [(.regular, .prim (.int 10)), (.default, .prim (.int 20))])⟩] .regularOpen none []))
            "x")
    },
    -- F1. Equal defaults dedup: `*1 | *1 | 2 → 1` (two equal defaults collapse to one, the
    -- unique default wins). The eval-form keeps the written disjunction; manifest resolves.
    {
      fileName := "disjunctions/default_dedup.expected",
      content :=
        formatField "x"
          (.disj
            [(.default, .prim (.int 1)), (.default, .prim (.int 1)), (.regular, .prim (.int 2))])
    },
    {
      fileName := "disjunctions/default_dedup.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (.disj
            [(.default, .prim (.int 1)), (.default, .prim (.int 1)), (.regular, .prim (.int 2))])
    },
    -- F1. Unification crosses value sets and ANDs default sets (no-`*` operand contributes
    -- its whole set): `(1|*2) & (1|2|3) → *2` survives as the unique default → `2`.
    {
      fileName := "disjunctions/default_unify_cross.expected",
      content :=
        formatField "x"
          (meet
            (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
            (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2)), (.regular, .prim (.int 3))]))
    },
    {
      fileName := "disjunctions/default_unify_cross.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (meet
            (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
            (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2)), (.regular, .prim (.int 3))]))
    },
    {
      fileName := "definitions/definition_closed.expected",
      content :=
        formatField "x"
          (normalizeDefinitions
            (.struct [⟨"#A", .definition, .struct [⟨"a", .regular, .kind .int⟩] .regularOpen none []⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/definition_reference.expected",
      content :=
        formatField "x"
          (resolveAndEval (.struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] .regularOpen none []))
    },
    {
      fileName := "refs/direct_self_reference.expected",
      content := formatTopLevel (resolveAndEval (.struct [⟨"x", .regular, .ref "x"⟩] .regularOpen none []))
    },
    {
      -- Repeated selection into a shared sub-struct (`components.X.who`), the eval-blowup
      -- shape: each of the three `*Who` fields re-selects `components` and its child. Before
      -- memoization this re-evaluated `components` per selection, multiplying per fuel level;
      -- the frame-id cache computes it once and shares it. Behavior is unchanged — this pins
      -- both the correct shared value and (implicitly) that it completes under normal fuel.
      fileName := "structs/shared_selection_fan.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"base", .regular, .prim (.string "stage9")⟩,
                ⟨"components", .regular,
                  .struct [
                      ⟨"repo", .regular, .struct [⟨"who", .regular, .ref "base"⟩] .regularOpen none []⟩,
                      ⟨"project", .regular, .struct [⟨"who", .regular, .ref "base"⟩] .regularOpen none []⟩,
                      ⟨"app", .regular, .struct [⟨"who", .regular, .ref "base"⟩] .regularOpen none []⟩
                    ] .regularOpen none []⟩,
                ⟨"repoWho", .regular,
                  .selector (.selector (.ref "components") "repo") "who"⟩,
                ⟨"projectWho", .regular,
                  .selector (.selector (.ref "components") "project") "who"⟩,
                ⟨"appWho", .regular,
                  .selector (.selector (.ref "components") "app") "who"⟩
              ] .regularOpen none []))
    },
    {
      fileName := "refs/constrained_reference_cycle.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"x", .regular, .conj [.ref "x", .boundConstraint (intDecimal 0) .ge .number]⟩,
                ⟨"a", .regular, .conj [.ref "b", .boundConstraint (intDecimal 0) .ge .number]⟩,
                ⟨"b", .regular, .ref "a"⟩
              ] .regularOpen none []))
    },
    {
      fileName := "disjunctions/disjunction.expected",
      content := formatField "x" (join (.prim (.string "a")) (.prim (.string "b")))
    },
    {
      fileName := "definitions/exact_label_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
            (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/string_kind_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.kind .string), (.kind .int))])
            (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/string_kind_pattern_mismatch.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.kind .string), (.kind .int))])
            (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/string_kind_pattern_only.expected",
      content := formatField "x" (.struct [] .regularOpen none [((.kind .string), (.kind .int))])
    },
    {
      fileName := "structs/type_label_colon_shorthand.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [⟨"#labels", .optional, .struct [] .regularOpen none [((.kind .string), (.kind .string))]⟩] .regularOpen none []))
    },
    {
      fileName := "structs/field_conflict.expected",
      content :=
        formatField "x"
          (meet
            (.struct [⟨"a", .regular, .prim (.string "a")⟩] .regularOpen none [])
            (.struct [⟨"a", .regular, .prim (.string "b")⟩] .regularOpen none []))
    },
    {
      fileName := "structs/field_alias.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"not an identifier", .regular, .prim (.int 4)⟩,
                ⟨"A", .letBinding, .ref "not an identifier"⟩,
                ⟨"foo", .regular, .ref "A"⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/field_selector.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"base", .regular, .struct [⟨"inner", .regular, .prim (.int 4)⟩] .regularOpen none []⟩,
                ⟨"x", .regular, .selector (.ref "base") "inner"⟩
              ] .regularOpen none []))
    },
    {
      fileName := "lists/list_index.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"xs", .regular, .list [.prim (.int 10), .prim (.int 20)]⟩,
                ⟨"x", .regular, .index (.ref "xs") (.prim (.int 1))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/string_field_index.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"base", .regular, .struct [⟨"inner", .regular, .prim (.int 4)⟩] .regularOpen none []⟩,
                ⟨"x", .regular, .index (.ref "base") (.prim (.string "inner"))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/duplicate_fields.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"x", .regular, .kind .int⟩,
                ⟨"x", .regular, .prim (.int 1)⟩,
                ⟨"conflict", .regular, .prim (.string "a")⟩,
                ⟨"conflict", .regular, .prim (.string "b")⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/float_kind.expected",
      content := formatField "x" (meet (.kind .float) (.prim (.float "1.5")))
    },
    {
      fileName := "numeric/number_literals.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"x", .regular, .prim (.int 1000)⟩,
              ⟨"y", .regular, .prim (.float "1.25e+3")⟩,
              ⟨"z", .regular, .prim (.float "-2e+3")⟩
            ] .regularOpen none [])
    },
    {
      fileName := "numeric/non_decimal_numbers.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"hex", .regular, .prim (.int 31)⟩,
              ⟨"oct", .regular, .prim (.int 15)⟩,
              ⟨"bin", .regular, .prim (.int 10)⟩,
              ⟨"negHex", .regular, .prim (.int (-16))⟩,
              ⟨"sep", .regular, .prim (.int 10)⟩
            ] .regularOpen none [])
    },
    {
      fileName := "numeric/unary_plus_numbers.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"x", .regular, .prim (.int 1)⟩,
              ⟨"y", .regular, .prim (.float "1.5")⟩,
              ⟨"z", .regular, .prim (.int 16)⟩
            ] .regularOpen none [])
    },
    {
      fileName := "numeric/numeric_suffixes.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"k", .regular, .prim (.int 1000)⟩,
              ⟨"ki", .regular, .prim (.int 1024)⟩,
              ⟨"fracK", .regular, .prim (.int 1500)⟩,
              ⟨"fracKi", .regular, .prim (.int 1536)⟩,
              ⟨"neg", .regular, .prim (.int (-1500))⟩
            ] .regularOpen none [])
    },
    {
      fileName := "refs/hidden_field_reference.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (resolveAndEval
            (.struct [⟨"_secret", .hidden, .prim (.string "x")⟩, ⟨"value", .regular, .ref "_secret"⟩] .regularOpen none []))
    },
    {
      fileName := "refs/underscore_ident_reference.expected",
      content :=
        formatField "out"
          (resolveAndEval
            (.struct [
                ⟨"_base", .hidden, .prim (.int 5)⟩,
                ⟨"ref", .regular, .ref "_base"⟩,
                ⟨"cmp", .regular, .binary .ne (.ref "_base") (.prim (.int 3))⟩,
                ⟨"sum", .regular, .binary .add (.ref "_base") (.prim (.int 1))⟩,
                ⟨"eq", .regular, .binary .eq (.ref "_base") (.prim (.int 5))⟩,
                ⟨"nested", .regular, .binary .ne (.ref "_base") (.ref "_base")⟩
              ] .regularOpen none []))
    },
    {
      fileName := "refs/underscore_top_bottom.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"bottom", .regular,
                  .disj [(.regular, .bottom), (.regular, .prim (.int 2))]⟩,
                ⟨"self", .regular,
                  bindValueAlias "X"
                    (.struct [
                        ⟨"n", .regular, .prim (.int 1)⟩,
                        ⟨"m", .regular, .selector (.ref "X") "n"⟩
                      ] .regularOpen none [])⟩
              ] .regularOpen none []))
    },
    {
      fileName := "disjunctions/int_bound_disjunction.expected",
      content := formatField "x" (join (.boundConstraint (intDecimal 5) .ge .number) (.boundConstraint (intDecimal 0) .ge .number))
    },
    {
      fileName := "bounds/int_bounds.expected",
      content := formatField "x" (meet (meet (.boundConstraint (intDecimal 0) .ge .number) (.boundConstraint (intDecimal 10) .le .number)) (.prim (.int 7)))
    },
    {
      fileName := "bounds/kind_meet_int.expected",
      content := formatField "x" (meet (.kind .int) (.prim (.int 1)))
    },
    {
      fileName := "disjunctions/list_item_disjunction.expected",
      content :=
        formatField "x"
          (meet
            (.list [.disj [(.regular, .kind .int), (.regular, .kind .string)]])
            (.list [.prim (.int 1)]))
    },
    {
      fileName := "lists/list_unification.expected",
      content :=
        formatField "x"
          (meet
            (.list [.kind .int, .kind .string])
            (.list [.prim (.int 1), .prim (.string "x")]))
    },
    {
      fileName := "builtins/len_builtin.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"stringLen", .regular, lenValue (.prim (.string "abc"))⟩,
              ⟨"listLen", .regular, lenValue (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)])⟩,
              ⟨"structLen", .regular,
                lenValue
                  (.struct [
                      ⟨"a", .regular, .prim (.int 1)⟩,
                      ⟨"b", .optional, .prim (.int 2)⟩,
                      ⟨"_c", .hidden, .prim (.int 3)⟩,
                      ⟨"#D", .definition, .prim (.int 4)⟩
                    ] .regularOpen none [])⟩
            ] .regularOpen none [])
    },
    {
      fileName := "builtins/unresolved_builtin.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"lenString", .regular, lenValue (.kind .string)⟩,
              ⟨"emptyOr", .regular, orValues []⟩
            ] .regularOpen none [])
    },
    {
      fileName := "manifest/manifest_field_filtering.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (.struct [
              ⟨"a", .regular, .prim (.int 1)⟩,
              ⟨"b", .regular, .list [.prim (.string "x")]⟩,
              ⟨"_hidden", .hidden, .prim (.bool true)⟩,
              ⟨"#Schema", .definition, .kind .int⟩,
              ⟨"optional", .optional, .prim (.string "skip")⟩
            ] .regularOpen none [])
    },
    {
      fileName := "manifest/manifest_nested_default.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (.struct [
              ⟨"mode", .regular,
                .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩
            ] .regularOpen none [])
    },
    {
      fileName := "refs/let_binding.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"base", .letBinding, .prim (.int 2)⟩,
                ⟨"x", .regular, .conj [.ref "base", .kind .int]⟩,
                ⟨"nested", .regular,
                  .struct [
                      ⟨"kind", .letBinding, .kind .string⟩,
                      ⟨"value", .regular, .conj [.ref "kind", .prim (.string "ok")]⟩
                    ] .regularOpen none []⟩
              ] .regularOpen none []))
    },
    {
      fileName := "refs/let_chain.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"a", .letBinding, .prim (.int 1)⟩,
                ⟨"b", .letBinding, .binary .add (.ref "a") (.prim (.int 1))⟩,
                ⟨"x", .regular, .ref "b"⟩
              ] .regularOpen none []))
    },
    {
      fileName := "refs/let_shadow.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"v", .letBinding, .prim (.int 1)⟩,
                ⟨"outer", .regular, .ref "v"⟩,
                ⟨"inner", .regular,
                  .struct [
                      ⟨"v", .letBinding, .prim (.int 2)⟩,
                      ⟨"val", .regular, .ref "v"⟩
                    ] .regularOpen none []⟩
              ] .regularOpen none []))
    },
    {
      fileName := "refs/let_sibling.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"top", .regular,
                  .struct [
                      ⟨"base", .regular, .prim (.int 10)⟩,
                      ⟨"doubled", .letBinding, .binary .mul (.ref "base") (.prim (.int 2))⟩,
                      ⟨"out", .regular, .ref "doubled"⟩
                    ] .regularOpen none []⟩
              ] .regularOpen none []))
    },
    {
      fileName := "refs/let_not_in_output.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"secret", .letBinding, .prim (.string "abc")⟩,
                ⟨"shown", .regular, .ref "secret"⟩,
                ⟨"other", .regular, .prim (.int 1)⟩
              ] .regularOpen none []))
    },
    {
      fileName := "refs/mutual_reference_cycle.expected",
      content :=
        formatTopLevel
          (resolveAndEval (.struct [⟨"x", .regular, .ref "y"⟩, ⟨"y", .regular, .ref "x"⟩] .regularOpen none []))
    },
    {
      fileName := "lists/nested_list_field.expected",
      content :=
        formatField "x"
          (meet
            (.struct [⟨"items", .regular, .list [.kind .int, .kind .string]⟩] .regularOpen none [])
            (.struct [⟨"items", .regular, .list [.prim (.int 1), .prim (.string "x")]⟩] .regularOpen none []))
    },
    {
      fileName := "lists/nested_reference_list.expected",
      content :=
        formatTopLevel
          (resolveAndEval (.struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .list [.ref "#A"]⟩] .regularOpen none []))
    },
    {
      fileName := "structs/nested_struct_field.expected",
      content :=
        formatField "x"
          (meet
            (.struct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
            (.struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []))
    },
    {
      fileName := "disjunctions/number_disjunction.expected",
      content := formatField "x" (join (.kind .number) (.prim (.int 1)))
    },
    {
      fileName := "bounds/number_int_bound.expected",
      content := formatField "x" (meet (meet (.kind .number) (.boundConstraint (intDecimal 0) .ge .number)) (.prim (.int 7)))
    },
    {
      fileName := "numeric/number_kind.expected",
      content := formatField "x" (meet (.kind .number) (.prim (.float "1.5")))
    },
    {
      fileName := "lists/open_list_tail.expected",
      content :=
        formatField "x"
          (meet
            (.listTail [.kind .int] (.kind .string))
            (.list [.prim (.int 1), .prim (.string "x"), .prim (.string "y")]))
    },
    {
      fileName := "manifest/optional_default_absent.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (.struct [⟨"mode", .optional,
              .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
    },
    {
      fileName := "manifest/optional_default_materialized.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (meet
            (.struct [⟨"mode", .optional,
                .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
            (.struct [⟨"mode", .regular, .top⟩] .regularOpen none []))
    },
    {
      fileName := "numeric/primitive_exclusion.expected",
      content := formatField "x" (meet (.notPrim (.int 0)) (.prim (.int 1)))
    },
    {
      fileName := "structs/regular_struct_meet.expected",
      content :=
        formatField "x"
          (meet
            (.struct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
            (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_label_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
            (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/multiple_pattern_fields.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)])
            (.struct [
                ⟨"az", .regular, .prim (.int 1)⟩,
                ⟨"ax", .regular, .prim (.int 2)⟩,
                ⟨"bz", .regular, .prim (.string "ok")⟩
              ] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_wildcard_pattern.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"x", .regular,
                meet
                  (.struct [] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))])
                  (.struct [⟨"abcz", .regular, .prim (.int 1)⟩, ⟨"abcy", .regular, .prim (.string "skip")⟩] .regularOpen none [])⟩,
              ⟨"y", .regular,
                meet
                  (.struct [] .regularOpen none [((.stringRegex "^a.+z$"), (.kind .int))])
                  (.struct [⟨"az", .regular, .prim (.string "skip")⟩, ⟨"abz", .regular, .prim (.int 2)⟩] .regularOpen none [])⟩
            ] .regularOpen none [])
    },
    {
      fileName := "definitions/regex_class_pattern.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"x", .regular,
                meet
                  (.struct [] .regularOpen none [((.stringRegex "^[ab]cz$"), (.kind .int))])
                  (.struct [
                      ⟨"acz", .regular, .prim (.int 1)⟩,
                      ⟨"bcz", .regular, .prim (.int 2)⟩,
                      ⟨"ccz", .regular, .prim (.string "skip")⟩
                    ] .regularOpen none [])⟩,
              ⟨"y", .regular,
                meet
                  (.struct [] .regularOpen none [((.stringRegex "^a[0-9]z$"), (.kind .int))])
                  (.struct [⟨"a5z", .regular, .prim (.int 1)⟩, ⟨"axz", .regular, .prim (.string "skip")⟩] .regularOpen none [])⟩
            ] .regularOpen none [])
    },
    {
      fileName := "definitions/regex_escape_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.stringRegex "^a\\.z$"), (.kind .int))])
            (.struct [⟨"a.z", .regular, .prim (.string "bad")⟩, ⟨"abz", .regular, .prim (.string "skip")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_question_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.stringRegex "^colou?r$"), (.kind .int))])
            (.struct [
                ⟨"color", .regular, .prim (.string "bad")⟩,
                ⟨"colour", .regular, .prim (.int 2)⟩,
                ⟨"colouur", .regular, .prim (.string "skip")⟩
              ] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_shorthand_pattern.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"x", .regular,
                meet
                  (.struct [] .regularOpen none [((.stringRegex "^a\\dz$"), (.kind .int))])
                  (.struct [⟨"a5z", .regular, .prim (.string "bad")⟩, ⟨"adz", .regular, .prim (.string "skip")⟩] .regularOpen none [])⟩,
              ⟨"y", .regular,
                meet
                  (.struct [] .regularOpen none [((.stringRegex "^a\\Dz$"), (.kind .int))])
                  (.struct [⟨"a5z", .regular, .prim (.string "skip")⟩, ⟨"adz", .regular, .prim (.int 1)⟩] .regularOpen none [])⟩
            ] .regularOpen none [])
    },
    {
      fileName := "definitions/regex_alternation_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.stringRegex "^cat$|^dog$"), (.kind .int))])
            (.struct [
                ⟨"cat", .regular, .prim (.string "bad")⟩,
                ⟨"dog", .regular, .prim (.int 2)⟩,
                ⟨"cow", .regular, .prim (.string "skip")⟩
              ] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_group_alternation_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.stringRegex "^(cat|dog)$"), (.kind .int))])
            (.struct [
                ⟨"cat", .regular, .prim (.string "bad")⟩,
                ⟨"dog", .regular, .prim (.int 2)⟩,
                ⟨"cow", .regular, .prim (.string "skip")⟩
              ] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_word_shorthand_pattern.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"x", .regular,
                meet
                  (.struct [] .regularOpen none [((.stringRegex "^a\\wz$"), (.kind .int))])
                  (.struct [⟨"a_z", .regular, .prim (.string "bad")⟩, ⟨"a-z", .regular, .prim (.string "skip")⟩] .regularOpen none [])⟩,
              ⟨"y", .regular,
                meet
                  (.struct [] .regularOpen none [((.stringRegex "^a\\Wz$"), (.kind .int))])
                  (.struct [⟨"a_z", .regular, .prim (.string "skip")⟩, ⟨"a-z", .regular, .prim (.string "bad")⟩] .regularOpen none [])⟩
            ] .regularOpen none [])
    },
    {
      fileName := "definitions/regex_space_shorthand_pattern.expected",
      content :=
        formatTopLevel
          (.struct [
              ⟨"x", .regular,
                meet
                  (.struct [] .regularOpen none [((.stringRegex "^a\\sz$"), (.kind .int))])
                  (.struct [⟨"a z", .regular, .prim (.string "bad")⟩, ⟨"a_z", .regular, .prim (.string "skip")⟩] .regularOpen none [])⟩,
              ⟨"y", .regular,
                meet
                  (.struct [] .regularOpen none [((.stringRegex "^a\\Sz$"), (.kind .int))])
                  (.struct [⟨"a z", .regular, .prim (.string "skip")⟩, ⟨"a_z", .regular, .prim (.string "bad")⟩] .regularOpen none [])⟩
            ] .regularOpen none [])
    },
    {
      fileName := "definitions/regex_exact_repetition_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.stringRegex "^a\\d{2}z$"), (.kind .int))])
            (.struct [⟨"a12z", .regular, .prim (.string "bad")⟩, ⟨"a1z", .regular, .prim (.string "skip")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_bounded_repetition_pattern.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.stringRegex "^a\\d{2,3}z$"), (.kind .int))])
            (.struct [
                ⟨"a12z", .regular, .prim (.int 2)⟩,
                ⟨"a123z", .regular, .prim (.string "bad")⟩,
                ⟨"a1z", .regular, .prim (.string "skip")⟩
              ] .regularOpen none []))
    },
    {
      fileName := "manifest/required_default_materialized.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (meet
            (.struct [⟨"mode", .required,
                .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
            (.struct [⟨"mode", .regular, .top⟩] .regularOpen none []))
    },
    {
      fileName := "bounds/strict_int_bounds.expected",
      content := formatField "x" (meet (meet (.boundConstraint (intDecimal 0) .gt .number) (.boundConstraint (intDecimal 10) .lt .number)) (.prim (.int 7)))
    },
    {
      -- A bare bound is number-domain: it admits a float operand (`>0 & 1.5` ⇒ `1.5`),
      -- where an int-only bound would conflict. The 2b fix to the prior over-strict bound.
      fileName := "bounds/number_bound_float.expected",
      content := formatField "x" (meet (.boundConstraint (intDecimal 0) .gt .number) (.prim (.float "1.5")))
    },
    {
      -- A decimal bound literal (`>0.5`) compares its limit exactly against a float operand.
      fileName := "bounds/decimal_bound_float.expected",
      content := formatField "x" (meet (.boundConstraint { numerator := 5, scale := 1 } .gt .number) (.prim (.float "1.0")))
    },
    {
      -- A bare two-sided range is number-domain on both ends: `>=0 & <=10 & 5.5` ⇒ `5.5`.
      fileName := "bounds/number_range_float.expected",
      content :=
        formatField "x"
          (meet (meet (.boundConstraint (intDecimal 0) .ge .number) (.boundConstraint (intDecimal 10) .le .number)) (.prim (.float "5.5")))
    },
    {
      fileName := "definitions/string_pattern_conflict.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.kind .string), (.kind .int))])
            (.struct [⟨"a", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/string_pattern_constraint.expected",
      content :=
        formatField "x"
          (meet
            (.struct [] .regularOpen none [((.kind .string), (.kind .int))])
            (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none []))
    },
    {
      fileName := "structs/struct_ellipsis.expected",
      content :=
        formatField "x"
          (meet
            (.struct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some .top) [])
            (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "ok")⟩] .regularOpen none []))
    },
    {
      fileName := "disjunctions/struct_disjunction_meet.expected",
      content :=
        formatField "x"
          (meet
            (.disj
              [
                (.regular, .struct [⟨"kind", .regular, .prim (.string "web")⟩] .regularOpen none []),
                (.regular, .struct [⟨"kind", .regular, .prim (.string "db")⟩] .regularOpen none [])
              ])
            (.struct [
                ⟨"kind", .regular, .prim (.string "web")⟩,
                ⟨"port", .regular, .prim (.int 80)⟩
              ] .regularOpen none []))
    },
    {
      fileName := "refs/three_reference_cycle.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"x", .regular, .ref "y"⟩,
                ⟨"y", .regular, .ref "z"⟩,
                ⟨"z", .regular, .ref "x"⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/comprehension_for.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    []
                    [
                      .comprehension
                        [.forIn (some "k") "v" (.struct [⟨"x", .regular, .prim (.int 1)⟩] .regularOpen none [])]
                        (.struct [
                            ⟨"key", .regular, .ref "k"⟩,
                            ⟨"val", .regular, .ref "v"⟩
                          ] .regularOpen none [])
                    ]
                    true false⟩
              ] .regularOpen none []))
    },
    {
      -- A5 regression (B1 comprehension-body remap depth): a comprehension body's ref to a
      -- merged-conjunction sibling (`zz`) sits `#forClauses` frames deeper than the comprehension
      -- node, so `remapConjRefs` must reindex it at `frameDepth + #for`. Pre-fix it was remapped at
      -- flat `frameDepth`, missed, and resolved to the wrong merged slot (`q` = 20). Driven through
      -- parse so the lazy-conjunction-merge + clause-frame-depth path is exercised end-to-end;
      -- oracle cue v0.16.1 → `s.a.out: 99`.
      fileName := "comprehensions/comprehension_conj_body_remap.expected",
      content :=
        match parseSource
            "t: {s: {p: 10, q: 20}} & {s: {a: {for v in [1] {out: zz}}, zz: 99}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      fileName := "comprehensions/comprehension_guard.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    [⟨"base", .regular, .prim (.int 0)⟩]
                    [
                      .comprehension
                        [.forIn none "v" (.list [.prim (.int 42)])]
                        (.struct [⟨"only", .regular, .ref "v"⟩] .regularOpen none []),
                      .comprehension
                        [.guard (.prim (.bool true))]
                        (.struct [⟨"flag", .regular, .prim (.bool true)⟩] .regularOpen none []),
                      .comprehension
                        [.guard (.prim (.bool false))]
                        (.struct [⟨"hidden", .regular, .prim (.int 1)⟩] .regularOpen none [])
                    ]
                    true false⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/default_in_guard.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"staging", .regular,
                  .disj [(.regular, .kind .bool), (.default, .prim (.bool false))]⟩,
                ⟨
                  "out",
                  .regular,
                  .structComp
                    []
                    [
                      .comprehension
                        [.guard (.unary .boolNot (.ref "staging"))]
                        (.struct [⟨"prod", .regular, .prim (.bool true)⟩] .regularOpen none []),
                      .comprehension
                        [.guard (.ref "staging")]
                        (.struct [⟨"dev", .regular, .prim (.bool true)⟩] .regularOpen none [])
                    ]
                    true false⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/string_interpolation.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"n", .regular, .prim (.int 3)⟩,
                ⟨
                  "out",
                  .regular,
                  .interpolation [.prim (.string "v"), .ref "n", .prim (.string "x")]
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "multiline/multiline_string.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [⟨"x", .regular, .prim (.string "hello\nworld")⟩] .regularOpen none []))
    },
    {
      fileName := "multiline/multiline_dedent.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [⟨"x", .regular, .prim (.string "line1\n  line2")⟩] .regularOpen none []))
    },
    {
      fileName := "multiline/multiline_interpolation.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"n", .regular, .prim (.string "bob")⟩,
                ⟨
                  "x",
                  .regular,
                  .interpolation [.prim (.string "hi "), .ref "n", .prim (.string "\nbye")]
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "multiline/multiline_empty.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [⟨"x", .regular, .prim (.string "")⟩] .regularOpen none []))
    },
    {
      fileName := "multiline/multiline_cert.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨
                  "cert",
                  .regular,
                  .prim (.string "-----BEGIN CERTIFICATE-----\nMIIBIjANBg\n-----END CERTIFICATE-----")
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "multiline/multiline_bytes.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [⟨"x", .regular, .prim (.bytes "abc\ndef")⟩] .regularOpen none []))
    },
    {
      fileName := "structs/dynamic_field.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"k", .regular, .prim (.string "name")⟩,
                ⟨
                  "out",
                  .regular,
                  .structComp [] [.dynamicField (.ref "k") .regular (.prim (.int 42))] true false
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/dynamic_field_comprehension.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    []
                    [
                      .comprehension
                        [.forIn (some "k") "v"
                          (.struct [
                              ⟨"a", .regular, .prim (.int 1)⟩,
                              ⟨"b", .regular, .prim (.int 2)⟩
                            ] .regularOpen none [])]
                        (.structComp
                          []
                          [.dynamicField (.interpolation [.ref "k"]) .regular (.ref "v")]
                          true false)
                    ]
                    true false⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_for.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn none "x"
                        (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)])]
                      (.structComp [] [.binary .mul (.ref "x") (.prim (.int 2))] true false)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_for_index.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn (some "i") "x"
                        (.list [.prim (.int 10), .prim (.int 20), .prim (.int 30)])]
                      (.structComp []
                        [.binary .add
                          (.binary .mul (.ref "i") (.prim (.int 100)))
                          (.ref "x")]
                        true false)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_for_kv.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn (some "k") "v"
                        (.struct [
                            ⟨"a", .regular, .prim (.int 1)⟩,
                            ⟨"b", .regular, .prim (.int 2)⟩
                          ] .regularOpen none [])]
                      (.structComp [] [.ref "v"] true false)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_guard_for.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"l", .regular,
                  .list [.prim (.int 1), .prim (.int 2), .prim (.int 3), .prim (.int 4)]⟩,
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn none "x" (.ref "l"),
                       .guard (.binary .gt (.ref "x") (.prim (.int 2)))]
                      (.structComp [] [.ref "x"] true false)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_nested.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"xs", .regular, .list [.prim (.int 1), .prim (.int 2)]⟩,
                ⟨"ys", .regular, .list [.prim (.int 10), .prim (.int 20)]⟩,
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn none "x" (.ref "xs"), .forIn none "y" (.ref "ys")]
                      (.structComp [] [.binary .add (.ref "x") (.ref "y")] true false)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_mixed.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"xs", .regular, .list [.prim (.int 5), .prim (.int 6)]⟩,
                ⟨"out", .regular,
                  .list
                    [.prim (.int 1),
                     .listComprehension
                       [.forIn none "x" (.ref "xs")]
                       (.structComp [] [.ref "x"] true false),
                     .prim (.int 2)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/scalar_embedding_collapse.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"a", .regular, .prim (.int 7)⟩,
                ⟨"out", .regular, .structComp [] [.ref "a"] true false⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/comprehension_loopvar_shadow.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"v", .regular, .prim (.string "sibling")⟩,
                ⟨
                  "out",
                  .regular,
                  .structComp
                    [⟨"keep", .regular, .ref "v"⟩]
                    [
                      .comprehension
                        [.forIn none "v" (.list [.prim (.int 10), .prim (.int 20)])]
                        (.structComp
                          []
                          [.dynamicField
                            (.interpolation [.prim (.string "k"), .ref "v"]) .regular (.ref "v")]
                          true false)
                    ]
                    true false⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/struct_embedding_scope.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    [⟨"base", .regular, .prim (.int 7)⟩]
                    [.struct [⟨"copy", .regular, .ref "base"⟩] .regularOpen none []]
                    true false⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/struct_embedding_nested.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    [⟨"base", .regular, .prim (.int 7)⟩]
                    [.struct [⟨"inner", .regular, .struct [⟨"deep", .regular, .ref "base"⟩] .regularOpen none []⟩] .regularOpen none []]
                    true false⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/struct_embedding_siblings.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    [
                      ⟨"base", .regular, .prim (.int 7)⟩,
                      ⟨"sib", .regular, .prim (.int 9)⟩
                    ]
                    [.struct [
                        ⟨"copy", .regular, .ref "base"⟩,
                        ⟨"copy2", .regular, .ref "sib"⟩
                      ] .regularOpen none []]
                    true false⟩
              ] .regularOpen none []))
    },
    {
      -- `{[1, 2, 3]}`: a list embedded in a struct with no other members IS the list.
      fileName := "lists/list_embedding_pure.expected",
      content :=
        formatField "x"
          (resolveAndEval
            (.structComp [] [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]] true false))
    },
    {
      -- `{#a: 1, [1, 2]}`: only-non-output struct + list embed → embeddedList with decls.
      fileName := "lists/list_embedding_hidden.expected",
      content :=
        formatField "x"
          (resolveAndEval
            (.structComp
              [⟨"#a", .definition, .prim (.int 1)⟩]
              [.list [.prim (.int 1), .prim (.int 2)]]
              true false))
    },
    {
      -- `{#a: 1, [...]}`: open list embed; manifests as `[]`, eval keeps `[...]`.
      fileName := "lists/list_embedding_open.expected",
      content :=
        formatField "x"
          (resolveAndEval
            (.structComp
              [⟨"#a", .definition, .prim (.int 1)⟩]
              [.listTail [] .top]
              true false))
    },
    {
      -- `{a: 1, [1, 2]}`: a regular (output) field present → genuine struct/list conflict.
      fileName := "lists/list_embedding_regular_conflict.expected",
      content :=
        formatField "x"
          (resolveAndEval
            (.structComp
              [⟨"a", .regular, .prim (.int 1)⟩]
              [.list [.prim (.int 1), .prim (.int 2)]]
              true false))
    },
    {
      -- `{a: 1} & [1, 2]`: explicit struct meet list, struct has an output field → bottom.
      fileName := "lists/list_struct_genuine_conflict.expected",
      content :=
        formatField "x"
          (meet
            (.struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
            (.list [.prim (.int 1), .prim (.int 2)]))
    },
    {
      -- `{a?: int, [1, 2]}`: optional is non-output, so the list embed survives.
      fileName := "lists/list_embedding_optional.expected",
      content :=
        formatField "x"
          (resolveAndEval
            (.structComp
              [⟨"a", .optional, .kind .int⟩]
              [.list [.prim (.int 1), .prim (.int 2)]]
              true false))
    },
    {
      -- `{#a: 1, [...int]} & {#b: 2, [1, 2]}`: meet of two embeddedLists — decls merge,
      -- lists meet (`[...int] & [1, 2] = [1, 2]`).
      fileName := "lists/list_embedding_meet_two.expected",
      content :=
        formatField "x"
          (meet
            (resolveAndEval
              (.structComp [⟨"#a", .definition, .prim (.int 1)⟩] [.listTail [] (.kind .int)] true false))
            (resolveAndEval
              (.structComp [⟨"#b", .definition, .prim (.int 2)⟩]
                [.list [.prim (.int 1), .prim (.int 2)]] true false)))
    },
    {
      -- `{#a: 1, [10, 20]}.#a` selects a decl; `[0]` indexes the embedded list.
      fileName := "lists/list_embedding_select_index.expected",
      content :=
        let base : Value :=
          .structComp [⟨"#a", .definition, .prim (.int 1)⟩]
            [.list [.prim (.int 10), .prim (.int 20)]] true false
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"p", .regular, .selector base "#a"⟩,
                ⟨"q", .regular, .index base (.prim (.int 0))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/strings_builtin.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"contains", .regular,
                  .builtinCall "strings.Contains" [.prim (.string "seafood"), .prim (.string "foo")]⟩,
                ⟨"hasPrefix", .regular,
                  .builtinCall "strings.HasPrefix" [.prim (.string "seafood"), .prim (.string "sea")]⟩,
                ⟨"hasSuffix", .regular,
                  .builtinCall "strings.HasSuffix" [.prim (.string "seafood"), .prim (.string "food")]⟩,
                ⟨"index", .regular,
                  .builtinCall "strings.Index" [.prim (.string "héllo"), .prim (.string "llo")]⟩,
                ⟨"indexMiss", .regular,
                  .builtinCall "strings.Index" [.prim (.string "chicken"), .prim (.string "xyz")]⟩,
                ⟨"count", .regular,
                  .builtinCall "strings.Count" [.prim (.string "cheese"), .prim (.string "e")]⟩,
                ⟨"split", .regular,
                  .builtinCall "strings.Split" [.prim (.string "a,b,c"), .prim (.string ",")]⟩,
                ⟨"splitEmptySep", .regular,
                  .builtinCall "strings.Split" [.prim (.string "héllo"), .prim (.string "")]⟩,
                ⟨"splitTrailing", .regular,
                  .builtinCall "strings.Split" [.prim (.string "a,b,"), .prim (.string ",")]⟩,
                ⟨"join", .regular,
                  .builtinCall "strings.Join"
                    [.list [.prim (.string "a"), .prim (.string "b"), .prim (.string "c")],
                     .prim (.string "-")]⟩,
                ⟨"replaceN", .regular,
                  .builtinCall "strings.Replace"
                    [.prim (.string "aaaa"), .prim (.string "a"), .prim (.string "b"), .prim (.int 2)]⟩,
                ⟨"replaceAll", .regular,
                  .builtinCall "strings.Replace"
                    [.prim (.string "oink oink"), .prim (.string "k"), .prim (.string "ky"), .prim (.int (-1))]⟩,
                ⟨"repeat", .regular,
                  .builtinCall "strings.Repeat" [.prim (.string "ab"), .prim (.int 3)]⟩,
                ⟨"trimSpace", .regular,
                  .builtinCall "strings.TrimSpace" [.prim (.string "  hi  ")]⟩,
                ⟨"fields", .regular,
                  .builtinCall "strings.Fields" [.prim (.string "  a  b c ")]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/list_builtin.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"concat", .regular,
                  .builtinCall "list.Concat"
                    [.list [.list [.prim (.int 1), .prim (.int 2)], .list [.prim (.int 3)],
                            .list [.prim (.int 4), .prim (.int 5)]]]⟩,
                ⟨"concatEmpty", .regular,
                  .builtinCall "list.Concat" [.list []]⟩,
                ⟨"flatten1", .regular,
                  .builtinCall "list.FlattenN"
                    [.list [.list [.prim (.int 1), .list [.prim (.int 2)]], .list [.prim (.int 3)]],
                     .prim (.int 1)]⟩,
                ⟨"flatten2", .regular,
                  .builtinCall "list.FlattenN"
                    [.list [.list [.prim (.int 1), .list [.prim (.int 2)]], .list [.prim (.int 3)]],
                     .prim (.int 2)]⟩,
                ⟨"flattenAll", .regular,
                  .builtinCall "list.FlattenN"
                    [.list [.prim (.int 1),
                            .list [.prim (.int 2), .list [.prim (.int 3), .list [.prim (.int 4)]]]],
                     .prim (.int (-1))]⟩,
                ⟨"flatten0", .regular,
                  .builtinCall "list.FlattenN"
                    [.list [.list [.prim (.int 1)], .list [.prim (.int 2)]], .prim (.int 0)]⟩,
                ⟨"repeat", .regular,
                  .builtinCall "list.Repeat"
                    [.list [.prim (.int 1), .prim (.int 2)], .prim (.int 3)]⟩,
                ⟨"repeat0", .regular,
                  .builtinCall "list.Repeat"
                    [.list [.prim (.int 1), .prim (.int 2)], .prim (.int 0)]⟩,
                ⟨"rangeUp", .regular,
                  .builtinCall "list.Range" [.prim (.int 0), .prim (.int 5), .prim (.int 1)]⟩,
                ⟨"rangeStep", .regular,
                  .builtinCall "list.Range" [.prim (.int 0), .prim (.int 10), .prim (.int 2)]⟩,
                ⟨"rangeDown", .regular,
                  .builtinCall "list.Range" [.prim (.int 5), .prim (.int 0), .prim (.int (-1))]⟩,
                ⟨"rangeEmpty", .regular,
                  .builtinCall "list.Range" [.prim (.int 1), .prim (.int 1), .prim (.int 1)]⟩,
                ⟨"slice", .regular,
                  .builtinCall "list.Slice"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3), .prim (.int 4)],
                     .prim (.int 1), .prim (.int 3)]⟩,
                ⟨"take", .regular,
                  .builtinCall "list.Take"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3), .prim (.int 4)],
                     .prim (.int 2)]⟩,
                ⟨"takeOver", .regular,
                  .builtinCall "list.Take"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], .prim (.int 5)]⟩,
                ⟨"drop", .regular,
                  .builtinCall "list.Drop"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3), .prim (.int 4)],
                     .prim (.int 2)]⟩,
                ⟨"dropOver", .regular,
                  .builtinCall "list.Drop"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], .prim (.int 5)]⟩,
                ⟨"contains", .regular,
                  .builtinCall "list.Contains"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], .prim (.int 2)]⟩,
                ⟨"containsNo", .regular,
                  .builtinCall "list.Contains"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], .prim (.int 9)]⟩,
                ⟨"containsSub", .regular,
                  .builtinCall "list.Contains"
                    [.list [.list [.prim (.int 1)], .list [.prim (.int 2)]], .list [.prim (.int 1)]]⟩,
                ⟨"sum", .regular,
                  .builtinCall "list.Sum"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]]⟩,
                ⟨"sumEmpty", .regular,
                  .builtinCall "list.Sum" [.list []]⟩,
                ⟨"min", .regular,
                  .builtinCall "list.Min"
                    [.list [.prim (.int 3), .prim (.int 1), .prim (.int 2)]]⟩,
                ⟨"max", .regular,
                  .builtinCall "list.Max"
                    [.list [.prim (.int 3), .prim (.int 1), .prim (.int 2)]]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/list_sort_strings.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"basic", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "banana"), .prim (.string "apple"), .prim (.string "cherry")]]⟩,
                ⟨"dup", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "b"), .prim (.string "a"), .prim (.string "b"), .prim (.string "a")]]⟩,
                ⟨"empty", .regular,
                  .builtinCall "list.SortStrings" [.list []]⟩,
                ⟨"single", .regular,
                  .builtinCall "list.SortStrings" [.list [.prim (.string "x")]]⟩,
                ⟨"sorted", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "a"), .prim (.string "b"), .prim (.string "c")]]⟩,
                ⟨"reverse", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "c"), .prim (.string "b"), .prim (.string "a")]]⟩,
                ⟨"caps", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "b"), .prim (.string "A"), .prim (.string "a"), .prim (.string "B")]]⟩,
                ⟨"unicode", .regular,
                  .builtinCall "list.SortStrings"
                    [.list [.prim (.string "é"), .prim (.string "a"), .prim (.string "z"), .prim (.string "Z")]]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/strings_case.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"upperLower", .regular,
                  .builtinCall "strings.ToUpper" [.prim (.string "hello World 123!")]⟩,
                ⟨"upperUpper", .regular,
                  .builtinCall "strings.ToUpper" [.prim (.string "ALREADY UP")]⟩,
                ⟨"lowerMixed", .regular,
                  .builtinCall "strings.ToLower" [.prim (.string "Hello WORLD 123!")]⟩,
                ⟨"lowerLower", .regular,
                  .builtinCall "strings.ToLower" [.prim (.string "already low")]⟩,
                ⟨"upperEmpty", .regular,
                  .builtinCall "strings.ToUpper" [.prim (.string "")]⟩,
                ⟨"lowerEmpty", .regular,
                  .builtinCall "strings.ToLower" [.prim (.string "")]⟩,
                ⟨"upperPunct", .regular,
                  .builtinCall "strings.ToUpper" [.prim (.string "abc123!@#")]⟩,
                ⟨"lowerPunct", .regular,
                  .builtinCall "strings.ToLower" [.prim (.string "ABC123!@#")]⟩,
                ⟨"titleWords", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "hello world foo")]⟩,
                ⟨"titleUpper", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "HELLO WORLD")]⟩,
                ⟨"titleEmpty", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "")]⟩,
                ⟨"titleSeps", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "a-b a.b a_b a/b")]⟩,
                ⟨"titleDigit", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "3 abc a3bc")]⟩,
                ⟨"titleLead", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "  leading")]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/strings_splitn.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"remainder", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 2)]⟩,
                ⟨"zero", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 0)]⟩,
                ⟨"negative", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int (-1))]⟩,
                ⟨"exceed", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 5)]⟩,
                ⟨"exact", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 3)]⟩,
                ⟨"one", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 1)]⟩,
                ⟨"absent", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "xyz"), .prim (.string ","), .prim (.int 2)]⟩,
                ⟨"emptyStr", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string ""), .prim (.string ","), .prim (.int 2)]⟩,
                ⟨"emptySepN", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "abc"), .prim (.string ""), .prim (.int 2)]⟩,
                ⟨"emptySepA", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string "abc"), .prim (.string ""), .prim (.int (-1))]⟩,
                ⟨"emptyBoth", .regular,
                  .builtinCall "strings.SplitN"
                    [.prim (.string ""), .prim (.string ""), .prim (.int (-1))]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/list_builtin_float.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"avgDiv", .regular,
                  .builtinCall "list.Avg"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]]⟩,
                ⟨"avgNoDiv", .regular,
                  .builtinCall "list.Avg" [.list [.prim (.int 1), .prim (.int 2)]]⟩,
                ⟨"avgThirds", .regular,
                  .builtinCall "list.Avg"
                    [.list [.prim (.int 1), .prim (.int 1), .prim (.int 2)]]⟩,
                ⟨"avgQuarter", .regular,
                  .builtinCall "list.Avg"
                    [.list [.prim (.int 1), .prim (.int 1), .prim (.int 1), .prim (.int 2)]]⟩,
                ⟨"avgFloat", .regular,
                  .builtinCall "list.Avg"
                    [.list [.prim (.float "1.0"), .prim (.float "2.0")]]⟩,
                ⟨"avgMixed", .regular,
                  .builtinCall "list.Avg" [.list [.prim (.int 1), .prim (.float "2.0")]]⟩,
                ⟨"sumFloat", .regular,
                  .builtinCall "list.Sum"
                    [.list [.prim (.float "1.0"), .prim (.float "2.0"), .prim (.float "3.0")]]⟩,
                ⟨"sumMixed", .regular,
                  .builtinCall "list.Sum"
                    [.list [.prim (.int 1), .prim (.float "2.0"), .prim (.int 3)]]⟩,
                ⟨"sumMixedFrac", .regular,
                  .builtinCall "list.Sum"
                    [.list [.prim (.int 1), .prim (.float "2.5"), .prim (.int 3)]]⟩,
                ⟨"minFloat", .regular,
                  .builtinCall "list.Min"
                    [.list [.prim (.float "3.0"), .prim (.float "1.0"), .prim (.float "2.0")]]⟩,
                ⟨"minMixed", .regular,
                  .builtinCall "list.Min"
                    [.list [.prim (.int 3), .prim (.float "1.5"), .prim (.int 2)]]⟩,
                ⟨"maxFloat", .regular,
                  .builtinCall "list.Max"
                    [.list [.prim (.float "3.0"), .prim (.float "1.0"), .prim (.float "2.0")]]⟩,
                ⟨"maxMixed", .regular,
                  .builtinCall "list.Max"
                    [.list [.prim (.int 3), .prim (.float "1.5"), .prim (.int 2)]]⟩,
                ⟨"rangeFloat", .regular,
                  .builtinCall "list.Range"
                    [.prim (.float "0.0"), .prim (.float "2.0"), .prim (.float "0.5")]⟩,
                ⟨"rangeNeg", .regular,
                  .builtinCall "list.Range"
                    [.prim (.float "2.0"), .prim (.float "0.0"), .prim (.float "-0.5")]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/math_builtin.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"absNegInt", .regular,
                  .builtinCall "math.Abs" [.prim (.int (-5))]⟩,
                ⟨"absPosInt", .regular,
                  .builtinCall "math.Abs" [.prim (.int 5)]⟩,
                ⟨"absZero", .regular,
                  .builtinCall "math.Abs" [.prim (.int 0)]⟩,
                ⟨"absFloat", .regular,
                  .builtinCall "math.Abs" [.prim (.float "-3.5")]⟩,
                ⟨"absBigFloat", .regular,
                  .builtinCall "math.Abs" [.prim (.float "-123.456")]⟩,
                ⟨"multTrue", .regular,
                  .builtinCall "math.MultipleOf" [.prim (.int 12), .prim (.int 3)]⟩,
                ⟨"multFalse", .regular,
                  .builtinCall "math.MultipleOf" [.prim (.int 13), .prim (.int 3)]⟩,
                ⟨"multNegValue", .regular,
                  .builtinCall "math.MultipleOf" [.prim (.int (-12)), .prim (.int 3)]⟩,
                ⟨"multNegDivisor", .regular,
                  .builtinCall "math.MultipleOf" [.prim (.int 12), .prim (.int (-3))]⟩,
                ⟨"floorPos", .regular,
                  .builtinCall "math.Floor" [.prim (.float "3.7")]⟩,
                ⟨"floorNeg", .regular,
                  .builtinCall "math.Floor" [.prim (.float "-3.2")]⟩,
                ⟨"floorInt", .regular,
                  .builtinCall "math.Floor" [.prim (.int 5)]⟩,
                ⟨"floorExact", .regular,
                  .builtinCall "math.Floor" [.prim (.float "3.0")]⟩,
                ⟨"ceilPos", .regular,
                  .builtinCall "math.Ceil" [.prim (.float "3.2")]⟩,
                ⟨"ceilNeg", .regular,
                  .builtinCall "math.Ceil" [.prim (.float "-3.7")]⟩,
                ⟨"ceilInt", .regular,
                  .builtinCall "math.Ceil" [.prim (.int 5)]⟩,
                ⟨"roundHalf", .regular,
                  .builtinCall "math.Round" [.prim (.float "2.5")]⟩,
                ⟨"roundNegHalf", .regular,
                  .builtinCall "math.Round" [.prim (.float "-2.5")]⟩,
                ⟨"roundDown", .regular,
                  .builtinCall "math.Round" [.prim (.float "2.4")]⟩,
                ⟨"roundUp", .regular,
                  .builtinCall "math.Round" [.prim (.float "0.5")]⟩,
                ⟨"truncPos", .regular,
                  .builtinCall "math.Trunc" [.prim (.float "3.7")]⟩,
                ⟨"truncNeg", .regular,
                  .builtinCall "math.Trunc" [.prim (.float "-3.99")]⟩,
                ⟨"truncInt", .regular,
                  .builtinCall "math.Trunc" [.prim (.int 5)]⟩
              ] .regularOpen none []))
    },
    {
      -- Colon-shorthand (`a: b: c: 1`) desugars to the brace form. This port builds the
      -- explicit-brace AST; the CLI port independently evaluates the shorthand `.cue`.
      -- Both matching `.expected` pins that shorthand produces the brace-identical value.
      fileName := "structs/colon_shorthand.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"metadata", .regular,
                  .struct [⟨"name", .regular, .prim (.string "api")⟩] .regularOpen none []⟩,
                ⟨"spec", .regular,
                  .struct [
                      ⟨"replicas", .regular, .prim (.int 3)⟩,
                      ⟨"template", .regular,
                        .struct [⟨"spec", .regular,
                            .struct [⟨"containers", .regular, .list [.prim (.string "c")]⟩] .regularOpen none []⟩] .regularOpen none []⟩
                    ] .regularOpen none []⟩,
                ⟨"labels", .regular,
                  .struct [⟨"prodigy9.co/app", .regular, .prim (.string "web")⟩] .regularOpen none []⟩,
                ⟨"mixed", .regular,
                  .struct [⟨"a", .regular,
                      .struct [⟨"b", .regular,
                        .struct [⟨"c", .regular, .prim (.int 1)⟩] .regularOpen none []⟩] .regularOpen none []⟩] .regularOpen none []⟩
              ] .regularOpen none []))
    },
    {
      -- Value aliases (`label: X={…}`, esp. `#Def: Self={…}`). This port builds the
      -- desugared AST: a value alias prepends a non-output `Self`/`X` let-binding whose
      -- value is `.thisStruct`, so `Self.field` resolves as a same-struct sibling
      -- reference. The CLI port independently parses/evaluates the alias `.cue`; both
      -- matching `.expected` pins that the alias binding resolves correctly.
      fileName := "refs/value_aliases.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"#Secret", .definition,
                  .struct [
                      ⟨"Self", .letBinding, .thisStruct⟩,
                      ⟨"#name", .definition, .prim (.string "tls")⟩,
                      ⟨"data", .regular, .selector (.ref "Self") "#name"⟩
                    ] .defClosed none []⟩,
                ⟨"aliased", .regular,
                  .struct [
                      ⟨"X", .letBinding, .thisStruct⟩,
                      ⟨"greeting", .regular, .prim (.string "hi")⟩,
                      ⟨"echo", .regular, .selector (.ref "X") "greeting"⟩
                    ] .regularOpen none []⟩,
                ⟨"nestedSelf", .regular,
                  .struct [
                      ⟨"Self", .letBinding, .thisStruct⟩,
                      ⟨"port", .regular, .prim (.int 8080)⟩,
                      ⟨"inner", .regular,
                        .struct [⟨"lo", .regular, .selector (.ref "Self") "port"⟩] .regularOpen none []⟩
                    ] .regularOpen none []⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/base64_encode.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"ascii", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "hello")]⟩,
                ⟨"empty", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "")]⟩,
                ⟨"multibyte", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "héllo")]⟩,
                ⟨"pad1", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "a")]⟩,
                ⟨"pad2", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "ab")]⟩,
                ⟨"pad0", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "abc")]⟩,
                ⟨"overBytes", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.bytes "hello")]⟩,
                ⟨"nonNull", .regular,
                  .builtinCall "base64.Encode" [.prim (.string "std"), .prim (.string "hello")]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/json_marshal.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"str", .regular, .builtinCall "json.Marshal" [.prim (.string "hi")]⟩,
                ⟨"intVal", .regular, .builtinCall "json.Marshal" [.prim (.int 42)]⟩,
                ⟨"negInt", .regular, .builtinCall "json.Marshal" [.prim (.int (-5))]⟩,
                ⟨"floatVal", .regular, .builtinCall "json.Marshal" [.prim (.float "1.5")]⟩,
                ⟨"floatWhole", .regular, .builtinCall "json.Marshal" [.prim (.float "1.0")]⟩,
                ⟨"boolVal", .regular, .builtinCall "json.Marshal" [.prim (.bool true)]⟩,
                ⟨"nullVal", .regular, .builtinCall "json.Marshal" [.prim .null]⟩,
                ⟨"nested", .regular,
                  .builtinCall "json.Marshal"
                    [.struct [
                        ⟨"b", .regular, .prim (.int 2)⟩,
                        ⟨"a", .regular, .prim (.int 1)⟩,
                        ⟨"c", .regular,
                          .struct [⟨"z", .regular, .prim (.int 1)⟩, ⟨"y", .regular, .prim (.int 2)⟩] .regularOpen none []⟩
                      ] .regularOpen none []]⟩,
                ⟨"listVal", .regular,
                  .builtinCall "json.Marshal"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]]⟩,
                ⟨"emptyObj", .regular, .builtinCall "json.Marshal" [.struct [] .regularOpen none []]⟩,
                ⟨"emptyList", .regular, .builtinCall "json.Marshal" [.list []]⟩,
                ⟨"escapes", .regular,
                  .builtinCall "json.Marshal"
                    [.struct [⟨"html", .regular, .prim (.string "<a>&\"b\\c\n\t")⟩] .regularOpen none []]⟩,
                ⟨"incomplete", .regular,
                  .builtinCall "json.Marshal" [.struct [⟨"a", .regular, .kind .int⟩] .regularOpen none []]⟩
              ] .regularOpen none []))
    },
    {
      -- The prod9/infra docker-config chain: a registry-auth struct is JSON-marshalled
      -- then base64-encoded. The CLI port independently evaluates the `.cue`; both
      -- matching `.expected` pins that `base64.Encode(null, json.Marshal({...}))` composes.
      fileName := "builtins/encoding_infra_chain.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"registry", .regular,
                  .struct [⟨"reg.io", .regular,
                      .struct [⟨"auth", .regular, .prim (.string "abc")⟩] .regularOpen none []⟩] .regularOpen none []⟩,
                ⟨"data", .regular,
                  .builtinCall "base64.Encode"
                    [.prim .null,
                      .builtinCall "json.Marshal"
                        [.struct [⟨"auths", .regular, .ref "registry"⟩] .regularOpen none []]]⟩
              ] .regularOpen none []))
    },
    {
      -- `e == _|_` / `e != _|_` is CUE's definedness test, not value equality. A concrete
      -- operand is "defined" (`!= _|_` true); an absent-field selection is "incomplete" so
      -- the guard drops. Pins the comparison + the comprehension guard firing on present
      -- and dropping on absent.
      fileName := "comprehensions/presence_test_guard.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"concrete", .regular, .binary .ne (.prim (.int 1)) .bottom⟩,
                ⟨"missing", .regular, .binary .eq (.prim (.int 1)) .bottom⟩,
                ⟨"streq", .regular, .binary .eq (.prim (.string "a")) .bottom⟩,
                ⟨
                  "present",
                  .regular,
                  .structComp
                    [⟨"f", .regular, .prim (.int 3)⟩]
                    [
                      .comprehension
                        [.guard (.binary .ne (.ref "f") .bottom)]
                        (.struct [⟨"seen", .regular, .ref "f"⟩] .regularOpen none [])
                    ]
                    true false
                ⟩,
                ⟨
                  "absent",
                  .regular,
                  .structComp
                    [⟨"base", .regular, .struct [⟨"f", .regular, .prim (.int 3)⟩] .regularOpen none []⟩]
                    [
                      .comprehension
                        [.guard (.binary .ne (.selector (.ref "base") "g") .bottom)]
                        (.struct [⟨"seen", .regular, .prim (.bool true)⟩] .regularOpen none [])
                    ]
                    true false
                ⟩,
                ⟨"ordinary", .regular, .binary .ne (.prim (.int 1)) (.prim (.int 2))⟩
              ] .regularOpen none []))
    },
    {
      -- In-struct duplicate-label canonicalization (slice 2c.1). A sibling body (`b: a`)
      -- must see the fully-merged value of the duplicated label `a`, not the first
      -- conjunct. Canonicalization collapses the two `a` slots into one first-occurrence
      -- slot carrying `.conj [int, 1]`, so `b`'s ref lands on `1`.
      fileName := "structs/in_struct_sibling_merge.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"a", .regular, .kind .int⟩,
                ⟨"b", .regular, .ref "a"⟩,
                ⟨"a", .regular, .prim (.int 1)⟩
              ] .regularOpen none []))
    },
    {
      -- A duplicate-label conflict still bottoms both the conflicting label and any sibling
      -- referencing it (`a: 1; b: a; a: 2` -> `a` and `b` both bottom).
      fileName := "structs/in_struct_sibling_conflict.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"a", .regular, .prim (.int 1)⟩,
                ⟨"b", .regular, .ref "a"⟩,
                ⟨"a", .regular, .prim (.int 2)⟩
              ] .regularOpen none []))
    },
    {
      -- Canonicalization is visible through nested sub-structs: `c.e` references the
      -- outer `a`, which sees the merged `int & 1 = 1`.
      fileName := "structs/nested_sibling_merge.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"a", .regular, .kind .int⟩,
                ⟨"c", .regular, .struct [⟨"e", .regular, .ref "a"⟩] .regularOpen none []⟩,
                ⟨"a", .regular, .prim (.int 1)⟩
              ] .regularOpen none []))
    },
    {
      -- A self-referential merged slot must not loop: `a: a; a: 1` canonicalizes to
      -- `.conj [a, 1]` at slot 0; the self-ref hits the `slotVisited` -> `.top` guard, so
      -- the meet collapses to `1` rather than diverging.
      fileName := "refs/merged_self_ref_cycle.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"a", .regular, .ref "a"⟩,
                ⟨"a", .regular, .prim (.int 1)⟩
              ] .regularOpen none []))
    },
    {
      -- 2c.2: a struct conjunction (`&`) merges its conjuncts' *declarations* into one
      -- frame before evaluating bodies, so a body referencing a sibling that another
      -- conjunct narrows sees the narrowed slot. Here `d.b` references `d.a` (int); the
      -- referenced-def conjunction `d & {a: 1}` narrows `a` to `1`, and `y.b` resolves to `1`.
      fileName := "structs/meet_lazy_sibling_ref.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"d", .regular, .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] .regularOpen none []⟩,
                ⟨"y", .regular, .conj [.ref "d", .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []]⟩
              ] .regularOpen none []))
    },
    {
      -- 2c.2: literal struct conjunction (no reference operand) — `{a: int, b: a} & {a: 1}`;
      -- `b` tracks the narrowed `a` through the merged frame.
      fileName := "structs/meet_lazy_literal.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"x", .regular,
                  .conj
                    [
                      .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] .regularOpen none [],
                      .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []
                    ]⟩
              ] .regularOpen none []))
    },
    {
      -- 2c.2: a still-incomplete merged slot stays symbolic and the sibling tracks it —
      -- `d.b: a`, `d & {a: >0}` leaves `a` (and thus `b`) as `int & >0`: the `int` kind from
      -- `d.a` is retained alongside the `>0` bound (oracle cue v0.16.1: `{a: int & >0, b: int & >0}`).
      fileName := "structs/meet_lazy_incomplete.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"d", .regular, .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] .regularOpen none []⟩,
                ⟨"y", .regular, .conj [.ref "d", .struct [⟨"a", .regular, .boundConstraint (intDecimal 0) .gt .number⟩] .regularOpen none []]⟩
              ] .regularOpen none []))
    },
    {
      -- 2c.2: nested sub-struct visibility through a *definition* meet. `out.val` references
      -- the hidden `#x`; meeting `#D & {#x: "hi"}` narrows `#x` and the nested `out.val`
      -- resolves to `"hi"`. Pins the hidden-sibling-through-nested-struct path.
      fileName := "structs/meet_lazy_hidden_def.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"#D", .definition,
                  .struct [
                      ⟨"#x", .definition, .kind .string⟩,
                      ⟨"out", .regular, .struct [⟨"val", .regular, .ref "#x"⟩] .regularOpen none []⟩
                    ] .regularOpen none []⟩,
                ⟨"y", .regular, .conj [.ref "#D", .struct [⟨"#x", .definition, .prim (.string "hi")⟩] .regularOpen none []]⟩
              ] .regularOpen none []))
    },
    {
      -- 2c.2: a chained sibling reference within one conjunct, narrowed across the meet —
      -- `{a: int, b: a, c: b} & {a: 1}` resolves `a`, `b`, `c` all to `1`.
      fileName := "structs/meet_lazy_chain.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"x", .regular,
                  .conj
                    [
                      .struct [
                          ⟨"a", .regular, .kind .int⟩,
                          ⟨"b", .regular, .ref "a"⟩,
                          ⟨"c", .regular, .ref "b"⟩
                        ] .regularOpen none [],
                      .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []
                    ]⟩
              ] .regularOpen none []))
    },
    {
      -- 2c.2: a disjunction operand keeps the eval-then-`meet` path (not the lazy merge):
      -- `({kind: "web"} | {kind: "db"}) & {kind: "web", port: 80}` selects the `web` arm.
      fileName := "structs/meet_lazy_disj_operand.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (.struct [
                ⟨"x", .regular,
                  .conj
                    [
                      .disj
                        [
                          (.regular, .struct [⟨"kind", .regular, .prim (.string "web")⟩] .regularOpen none []),
                          (.regular, .struct [⟨"kind", .regular, .prim (.string "db")⟩] .regularOpen none [])
                        ],
                      .struct [
                          ⟨"kind", .regular, .prim (.string "web")⟩,
                          ⟨"port", .regular, .prim (.int 80)⟩
                        ] .regularOpen none []
                    ]⟩
              ] .regularOpen none []))
    },
    {
      -- A5-followup (Pass-2 / deferral-gate for a comprehension-valued field). A static field
      -- (`out`) whose value is a list comprehension reading `Self.#t` inside the `for` body, where
      -- `#t` is supplied by an embedded def (`#H`) AND narrowed at the use site (`#R & {#t: "y"}`).
      -- The `Self.#t` self-ref lands `#forClauses` frames deeper than the comprehension node; the
      -- deferral gate `hasSelfRefAtDepth` scanned the comprehension body at the SHALLOW depth and
      -- missed it, so `#R & {…}` took the eager-then-meet path (which cannot re-evaluate the
      -- comprehension against the narrowed frame) instead of the closure-force path. Result: a stale
      -- `out: [{v: string | *"def"}]`. Threading the loop-frame depth (`hasSelfRefAtDepthClauses`)
      -- restores deferral, so the body resolves against the narrowed `#t`. Oracle cue v0.16.1 →
      -- `v.out: [{v: "y"}]`, `v.#t: "y"`. `#R` standalone is correctly un-narrowed (`string | *"def"`).
      fileName := "comprehensions/comprehension_embed_self_narrow_body.expected",
      content :=
        match parseSource
            "#H: {#t: string | *\"def\"}\n#R: Self={#H, out: [for x in [1] {v: Self.#t}]}\nv: #R & {#t: \"y\"}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    }
  ]

def writeFixturePort (targetDir : System.FilePath) (port : FixturePort) : IO Unit := do
  let path := targetDir / port.fileName
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile path (port.content ++ "\n")

def writeFixturePorts (targetDir : System.FilePath) : IO Unit := do
  IO.FS.createDirAll targetDir
  for port in fixturePorts do
    writeFixturePort targetDir port

end Kue
