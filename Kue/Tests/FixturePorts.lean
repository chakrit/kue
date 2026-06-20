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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
      fileName := "numeric/regex_invalid_patterns.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                -- Concrete invalid (`a(` unbalanced) bottoms at `=~` and `!~` (NOT `false`/`true`).
                ⟨"invalid", .regular,
                  .binary .regexMatch (.prim (.string "x")) (.prim (.string "a("))⟩,
                ⟨"notInvalid", .regular,
                  .binary .regexNotMatch (.prim (.string "x")) (.prim (.string "a("))⟩,
                -- Deferred RE2 construct (`(?i)`) bottoms too (surfaced, not silent-wrong).
                ⟨"deferred", .regular,
                  .binary .regexMatch (.prim (.string "x")) (.prim (.string "(?i)a"))⟩,
                -- Valid patterns unchanged: still match / still negate.
                ⟨"valid", .regular,
                  .binary .regexMatch (.prim (.string "abc")) (.prim (.string "^a"))⟩,
                ⟨"validNot", .regular,
                  .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "^a"))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/regex_re2_repros.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"groupPlus", .regular,
                  .binary .regexMatch (.prim (.string "abab")) (.prim (.string "^(ab)+$"))⟩,
                ⟨"groupPlusNo", .regular,
                  .binary .regexMatch (.prim (.string "aba")) (.prim (.string "^(ab)+$"))⟩,
                ⟨"nestedGroup", .regular,
                  .binary .regexMatch (.prim (.string "foo-bar-baz"))
                    (.prim (.string "^([a-z0-9]+(-[a-z0-9]+)*)$"))⟩,
                ⟨"semver", .regular,
                  .binary .regexMatch (.prim (.string "v1.2.3"))
                    (.prim (.string "^(v[0-9]+)(\\.[0-9]+)*$"))⟩,
                ⟨"altGroups", .regular,
                  .binary .regexMatch (.prim (.string "axyd")) (.prim (.string "a(b|x)(c|y)d"))⟩,
                ⟨"wordBoundary", .regular,
                  .binary .regexMatch (.prim (.string "cat dog")) (.prim (.string "\\bdog\\b"))⟩,
                ⟨"wordBoundNo", .regular,
                  .binary .regexMatch (.prim (.string "dogcat")) (.prim (.string "\\bdog\\b"))⟩,
                ⟨"lazyPlus", .regular,
                  .binary .regexMatch (.prim (.string "aaa")) (.prim (.string "a+?"))⟩,
                ⟨"altPlusSub", .regular,
                  .binary .regexMatch (.prim (.string "xfoobarx")) (.prim (.string "(foo|bar)+"))⟩
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
            (mkStruct [
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
          (mkStruct [
              ⟨"andValue", .regular, andValues [.kind .int, .boundConstraint (intDecimal 0) .gt .number, .prim (.int 7)]⟩,
              ⟨"orValue", .regular, orValues [.prim (.string "a"), .prim (.string "b")]⟩
            ] .regularOpen none [])
    },
    {
      fileName := "builtins/integer_builtin.expected",
      content :=
        formatTopLevel
          (mkStruct [
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
            (closeValue (mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none []))
            (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/closed_hidden_definition.expected",
      content :=
        formatField "x"
          (meet
            (closeValue (mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none []))
            (mkStruct [
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
            (closeValue (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))]))
            (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none []))
    },
    {
      -- RX-2b: a struct carrying an invalid concrete pattern-LABEL predicate (`[=~"a("]`)
      -- bottoms (cue errors `invalid regexp`). The label-application path is the 5th regex
      -- consumer; pre-RX-2b `labelMatchesPatternWith` swallowed the parse bottom into a
      -- non-match, so the invalid pattern silently failed to constrain `k`.
      fileName := "definitions/regex_invalid_pattern_label.expected",
      content :=
        match parseSource "out: {[=~\"a(\"]: int, k: 1}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- SC-1: a closed `#C` met with an OPEN pattern struct `P` stays closed — `z` matches
      -- `P`'s pattern but `P` is open (the pattern is non-closing), and `z ∉ #C`, so `z`
      -- bottoms. `a: 1` is allowed (in `#C`). Pre-SC-1 this re-opened `#C` and admitted `z`.
      fileName := "definitions/sc1_closed_meets_pattern_stays_closed.expected",
      content :=
        match parseSource "#C: {a: int}\nP: {[string]: int}\nout: #C & P & {a: 1, z: 9}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- SC-1c: a closed pattern DEF closes over its OWN selective pattern. `#A: {x, [=~"^a"]}`
      -- is a no-`...` def, so it is CLOSED; meeting `{a1, b}` admits `a1` (matches `[=~"^a"]`)
      -- and `x` (declared) but rejects `b` (neither declared nor matching). The def-body path
      -- (`normalizeDefinitionValueWithFuel` + `applyEvaluatedStructN`) is DISTINCT from the
      -- `close({…})` builtin path (`closed_regex_pattern`); pre-SC-1c the def never closed at all
      -- (openness stayed `regularOpen`, `closingPatterns = []`) and admitted `b`.
      fileName := "definitions/sc1c_closed_pattern_def_rejects_nonmatch.expected",
      content :=
        match parseSource "#A: {x: int, [=~\"^a\"]: int}\nout: #A & {a1: 1, b: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- SC-1d: a pattern def with a `...` tail stays OPEN. `#A: {x, [=~"^a"], ...}` carries BOTH
      -- a selective pattern AND a `...`; the `...` opens the struct regardless of patterns (the two
      -- are orthogonal axes on `Value.struct`). Meeting `{extra: 5}` admits `extra` even though it
      -- matches no pattern — the `...` admits it. Pre-SC-1d the parser dropped the `...` when patterns
      -- were present, so after SC-1c's closing this def wrongly CLOSED and bottomed `extra`.
      fileName := "definitions/sc1d_pattern_tail_stays_open.expected",
      content :=
        match parseSource "#A: {x: int, [=~\"^a\"]: int, ...}\nout: #A & {x: 1, extra: 5}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- SC-1d regression guard (SC-1c must still hold): the SAME def WITHOUT `...` CLOSES. `z`
      -- (neither declared nor matching `[=~"^a"]`) bottoms. Pins that the SC-1d tail-preservation
      -- did not re-open the no-`...` pattern def.
      fileName := "definitions/sc1d_pattern_notail_closes.expected",
      content :=
        match parseSource "#A: {x: int, [=~\"^a\"]: int}\nout: #A & {x: 1, z: 9}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- SC-1d: the `...` opens the struct but the pattern still value-constrains a MATCHING field.
      -- `abc` matches `[=~"^a"]: int`, so the string `"no"` conflicts with `int` and bottoms — the
      -- `...` admits the LABEL, the pattern constrains the VALUE (orthogonal).
      fileName := "definitions/sc1d_pattern_tail_value_constrains.expected",
      content :=
        match parseSource "#A: {x: int, [=~\"^a\"]: int, ...}\nout: #A & {x: 1, abc: \"no\"}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
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
            (mkStruct [⟨"x", .regular,
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
              (mkStruct [⟨"x", .regular,
                  .binary .add
                    (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
                    (.disj [(.regular, .prim (.int 10)), (.default, .prim (.int 20))])⟩] .regularOpen none []))
            "x")
    },
    -- F1. Equal defaults dedup: `*1 | *1 | 2 → 1` (two equal defaults collapse to one, the
    -- unique default wins). The eval-form DEDUPS the written disjunction to `*1 | 2` via
    -- `normalizeEvaluatedDisj`/`liveAlternatives` (SC-3); manifest resolves to `1`.
    {
      fileName := "disjunctions/default_dedup.expected",
      content :=
        formatField "x"
          (.disj
            [(.default, .prim (.int 1)), (.regular, .prim (.int 2))])
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
            (mkStruct [⟨"#A", .definition, mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none []⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/definition_reference.expected",
      content :=
        formatField "x"
          (resolveAndEval (mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] .regularOpen none []))
    },
    {
      -- B6 gap-1: a closed `#Def` nested under a REGULAR field. Selecting it (`a.#Inner`) and
      -- meeting an undeclared `extra` must REJECT `extra` (cue v0.16.1: `out.extra: field not
      -- allowed`). Pre-B6 `normalizeFieldWithFuel` left a regular field's value unwalked, so
      -- `#Inner` reached the meet still open and admitted `extra`.
      fileName := "definitions/nested_def_under_regular_field.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"a", .regular, mkStruct [⟨"#Inner", .definition, mkStruct [⟨"x", .regular, .kind .int⟩] .regularOpen none []⟩] .regularOpen none []⟩,
                ⟨"out", .regular, .conj [.selector (.ref "a") "#Inner", mkStruct [⟨"x", .regular, .prim (.int 1)⟩, ⟨"extra", .regular, .prim (.int 2)⟩] .regularOpen none []]⟩
              ] .regularOpen none []))
    },
    {
      -- B6 no-over-close guard: the same shape but the nested def is OPEN via `...`
      -- (`#Inner: {x:int, ...}`). cue admits `extra` (and Kue must too — the spine walker leaves
      -- a `defOpenViaTail` body open). Ensures gap-1 closes only genuinely-closed defs.
      fileName := "definitions/nested_def_open_under_regular_field.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"a", .regular, mkStruct [⟨"#Inner", .definition, mkStruct [⟨"x", .regular, .kind .int⟩] (.defOpenViaTail) (some .top) []⟩] .regularOpen none []⟩,
                ⟨"out", .regular, .conj [.selector (.ref "a") "#Inner", mkStruct [⟨"x", .regular, .prim (.int 1)⟩, ⟨"extra", .regular, .prim (.int 2)⟩] .regularOpen none []]⟩
              ] .regularOpen none []))
    },
    {
      -- B6-A2: a closed `#Def` nested under a `let`-bound value. Selecting it (`x.#I`) and meeting
      -- an undeclared `extra` must REJECT it (cue v0.16.1: `out.extra: field not allowed`). Before
      -- B6-A2, `normalizeFieldWithFuel` skipped `letBinding` field values alongside hidden, so the
      -- nested def reached the meet still open and admitted `extra`. `letBinding` is its OWN
      -- `FieldClass` kind (NOT the import-binding A2 trap), so the spine walker closes it safely.
      -- Parsed (not AST-constructed) so the real `let` → `letBinding` field is exercised.
      fileName := "definitions/let_nested_def_closes.expected",
      content :=
        match parseSource "let x = {#I: {y: int}}\nout: x.#I & {y: 1, extra: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- B6-A2 no-over-close sentinel: the same `let`-nested def but OPEN via `...`
      -- (`#I: {y:int, ...}`). cue admits `extra` (and Kue must too — the spine walker leaves a
      -- `defOpenViaTail` body open). Pins that the `let` arm closes only genuinely-closed defs.
      fileName := "definitions/let_nested_def_open.expected",
      content :=
        match parseSource "let x = {#I: {y: int, ...}}\nout: x.#I & {y: 1, extra: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- B6-A1: a `#Def` reached under a REAL in-file hidden field (`_pkg.#Svc & {extra}`) CLOSES.
      -- The Normalize 4-way split routes a real in-file `_x` (not an `.importBinding`) through the
      -- spine walker, so its nested `#Svc` closes. cue: `out.extra: field not allowed` (v0.16.1).
      -- The marker scopes the import-laziness skip to `.importBinding` ONLY, so the in-file hidden
      -- field no longer escapes closedness. Parsed so the real `_`-prefixed `.hidden` field flows.
      fileName := "definitions/b6a1_infile_hidden_def_closes.expected",
      content :=
        match parseSource "_pkg: {#Svc: {name: string}}\nout: _pkg.#Svc & {name: \"x\", extra: 1}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- B6-A1 no-over-close sentinel: the same in-file hidden def but OPEN via `...`. cue admits
      -- `extra` (v0.16.1) and Kue must too — the spine walker leaves a `defOpenViaTail` body open.
      fileName := "definitions/b6a1_infile_hidden_def_open.expected",
      content :=
        match parseSource "_pkg: {#Svc: {name: string, ...}}\nout: _pkg.#Svc & {name: \"x\", extra: 1}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    -- B6-T1 closedness regression pins. B6 is the most regression-prone class (prior closedness
    -- changes bottomed `#ListenerSet`/cert-manager); these lock the shapes the Phase-A over-close
    -- hunt exercised so future closedness work cannot silently regress them. Each oracle-checked
    -- vs cue v0.16.1. Parse-driven so the real field-class/openness flows through.
    {
      -- (1) depth-2 nesting: `a.b.#Inner & {extra}` closes — the spine walker descends two regular
      -- fields and still closes the leaf `#Def`. cue: `out.extra: field not allowed`.
      fileName := "definitions/b6_depth2_nested_def_closes.expected",
      content :=
        match parseSource "a: {b: {#Inner: {x: int}}}\nout: a.b.#Inner & {x: 1, extra: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- (2) plain (non-def) struct under a regular field stays OPEN — admits `extra`. The spine
      -- walker preserves a regular struct's openness; only nested `#Def`s close. cue admits.
      fileName := "definitions/b6_plain_struct_under_regular_open.expected",
      content :=
        match parseSource "a: {b: {x: int}}\nout: a.b & {x: 1, extra: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- (4a) def-meet rejects an unallowed field: `#D & {c}` where `c ∉ #D`. cue: `out.c: field
      -- not allowed`. The direct closed-def meet (the canonical closedness check).
      fileName := "definitions/b6_def_meet_rejects_unallowed.expected",
      content :=
        match parseSource "#D: {a: int, b: string}\nout: #D & {a: 1, c: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- (4b) a comprehension-bearing REGULAR field admits its legit siblings — a regular struct
      -- carrying a `if`/`for` is not a def and stays open. cue admits `y`. No over-close.
      fileName := "definitions/b6_comprehension_field_admits_sibling.expected",
      content :=
        match parseSource "a: {x: int, if true {y: 1}}\nout: a & {x: 1, y: 1}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- (4c) an embedding-bearing REGULAR field admits its legit siblings — embedding unions
      -- labels, it does not close the host. cue admits `m` (embedded) and `n` (sibling).
      fileName := "definitions/b6_embedding_field_admits_sibling.expected",
      content :=
        match parseSource "base: {m: int}\na: {base, n: int}\nout: a & {m: 1, n: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- (5) SC-2b — DIVERGES from cue. `(#D & {}).r & {extra}` REJECTS `extra`: nested closedness
      -- is monotone through meet (the closed `r` stays closed). cue RE-OPENS on the no-op `& {}`
      -- instantiation (admits `extra`) — an eval-strategy artifact, not lattice-derivable. cue is
      -- internally inconsistent (the direct path `#D.r & {extra}` rejects). Kue follows the spec
      -- on both paths. Recorded in cue-divergences.md.
      fileName := "definitions/sc2b_instantiated_def_field_stays_closed.expected",
      content :=
        match parseSource "#D: {r: {x: int}}\nout: (#D & {}).r & {x: 1, extra: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    -- SC-2a closedness pins (cue+spec AGREE; oracle-checked v0.16.1). The closing field-walker
    -- twin closes a referenced def's nested PLAIN-struct field VALUES recursively, so an added
    -- field is rejected at any depth — UNLESS a nested `...` opens it. Plain (non-def) structs and
    -- hidden fields stay open (their own controls live in b6_plain_struct_under_regular_open / etc).
    {
      -- nested def field closes: `#A:{a:{b:int}}` & `{a:{b:1,extra:5}}` → `out.a.extra: _|_`.
      fileName := "definitions/sc2a_nested_def_field_closes.expected",
      content :=
        match parseSource "#A: {a: {b: int}}\nout: #A & {a: {b: 1, extra: 5}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- fully concrete repro (`b: int | *0`) — closes the same way, no abstract value involved.
      fileName := "definitions/sc2a_nested_def_field_closes_concrete.expected",
      content :=
        match parseSource "#A: {a: {b: int | *0}}\nout: #A & {a: {b: 1, extra: 5}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- depth-2: the closing recurses to any depth (`out.a.b.deep: _|_`).
      fileName := "definitions/sc2a_nested_def_field_depth2.expected",
      content :=
        match parseSource "#A: {a: {b: {c: int}}}\nout: #A & {a: {b: {c: 1, deep: 9}}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- a nested `...` keeps the nested struct OPEN (`defOpenViaTail` returned unchanged by the
      -- closing walker) — `extra` admitted. Regression guard for control #4.
      fileName := "definitions/sc2a_nested_def_field_tail_stays_open.expected",
      content :=
        match parseSource "#A: {a: {b: int, ...}}\nout: #A & {a: {b: 1, extra: 5}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- direct selector into a closed def's nested struct closes it: `#D.r & {b}` → `out.b: _|_`
      -- (oracle #6 — the same root cause as the meet path, no instantiation).
      fileName := "definitions/sc2a_direct_selector_closes.expected",
      content :=
        match parseSource "#D: {r: {a: int}}\nout: #D.r & {a: 1, b: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      fileName := "refs/direct_self_reference.expected",
      content := formatTopLevel (resolveAndEval (mkStruct [⟨"x", .regular, .ref "x"⟩] .regularOpen none []))
    },
    {
      -- D#2a: a self-referential def is a STRUCTURAL cycle — the body re-enters the same struct
      -- through `next: #L`, so the re-entry bottoms (`.structuralCycle`) instead of unrolling
      -- fuel-deep. The port runs the same parse→resolve→eval pipeline as the CLI (the nested-bottom
      -- value is impractical to hand-build; mirrors `sc2a_direct_selector_closes`).
      fileName := "refs/structural_cycle_struct.expected",
      content :=
        match parseSource "#L: {n: int, next: #L}\nx: #L\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- D#2a: MUTUAL recursion (`#A` → `#B` → `#A`) is detected for free — `#A`'s body re-enters
      -- the struct-body stack two hops down, same mechanism.
      fileName := "refs/structural_cycle_mutual.expected",
      content :=
        match parseSource "#A: {b: #B}\n#B: {a: #A}\nz: #A\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
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
            (mkStruct [
                ⟨"base", .regular, .prim (.string "stage9")⟩,
                ⟨"components", .regular,
                  mkStruct [
                      ⟨"repo", .regular, mkStruct [⟨"who", .regular, .ref "base"⟩] .regularOpen none []⟩,
                      ⟨"project", .regular, mkStruct [⟨"who", .regular, .ref "base"⟩] .regularOpen none []⟩,
                      ⟨"app", .regular, mkStruct [⟨"who", .regular, .ref "base"⟩] .regularOpen none []⟩
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
            (mkStruct [
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
            (mkStruct [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
            (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      -- B2.5: pattern-struct × tail-struct now UNIFIES (was `_|_`). The pattern constrains
      -- the field, the tail keeps the struct open, both axes retained. cue v0.16.1 → {a: 5}.
      fileName := "definitions/pattern_tail_unify.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
            (mkStruct [⟨"a", .regular, .prim (.int 5)⟩] .defOpenViaTail (some .top) []))
    },
    {
      -- B2.5: multi-pattern × tail. Both patterns retained; each constrains its matching field.
      -- cue v0.16.1 → {a: 5, b: "hi"}.
      fileName := "definitions/multi_pattern_tail_unify.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none
              [((.stringRegex "^a"), (.kind .int)), ((.stringRegex "^b"), (.kind .string))])
            (mkStruct [⟨"a", .regular, .prim (.int 5)⟩, ⟨"b", .regular, .prim (.string "hi")⟩]
              .defOpenViaTail (some .top) []))
    },
    {
      fileName := "definitions/string_kind_pattern.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
            (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/string_kind_pattern_mismatch.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
            (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/string_kind_pattern_only.expected",
      content := formatField "x" (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
    },
    {
      fileName := "structs/type_label_colon_shorthand.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [⟨"#labels", .optional, mkStruct [] .regularOpen none [((.kind .string), (.kind .string))]⟩] .regularOpen none []))
    },
    {
      fileName := "structs/field_conflict.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [⟨"a", .regular, .prim (.string "a")⟩] .regularOpen none [])
            (mkStruct [⟨"a", .regular, .prim (.string "b")⟩] .regularOpen none []))
    },
    {
      fileName := "structs/field_alias.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
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
            (mkStruct [
                ⟨"base", .regular, mkStruct [⟨"inner", .regular, .prim (.int 4)⟩] .regularOpen none []⟩,
                ⟨"x", .regular, .selector (.ref "base") "inner"⟩
              ] .regularOpen none []))
    },
    {
      fileName := "lists/list_index.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"xs", .regular, .list [.prim (.int 10), .prim (.int 20)]⟩,
                ⟨"x", .regular, .index (.ref "xs") (.prim (.int 1))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/string_field_index.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"base", .regular, mkStruct [⟨"inner", .regular, .prim (.int 4)⟩] .regularOpen none []⟩,
                ⟨"x", .regular, .index (.ref "base") (.prim (.string "inner"))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/duplicate_fields.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
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
          (mkStruct [
              ⟨"x", .regular, .prim (.int 1000)⟩,
              ⟨"y", .regular, .prim (.float "1.25e+3")⟩,
              ⟨"z", .regular, .prim (.float "-2e+3")⟩
            ] .regularOpen none [])
    },
    {
      fileName := "numeric/non_decimal_numbers.expected",
      content :=
        formatTopLevel
          (mkStruct [
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
          (mkStruct [
              ⟨"x", .regular, .prim (.int 1)⟩,
              ⟨"y", .regular, .prim (.float "1.5")⟩,
              ⟨"z", .regular, .prim (.int 16)⟩
            ] .regularOpen none [])
    },
    {
      fileName := "numeric/numeric_suffixes.expected",
      content :=
        formatTopLevel
          (mkStruct [
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
            (mkStruct [⟨"_secret", .hidden, .prim (.string "x")⟩, ⟨"value", .regular, .ref "_secret"⟩] .regularOpen none []))
    },
    {
      fileName := "refs/underscore_ident_reference.expected",
      content :=
        formatField "out"
          (resolveAndEval
            (mkStruct [
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
            (mkStruct [
                ⟨"bottom", .regular,
                  .disj [(.regular, .bottom), (.regular, .prim (.int 2))]⟩,
                ⟨"self", .regular,
                  bindValueAlias "X"
                    (mkStruct [
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
          (mkStruct [
              ⟨"stringLen", .regular, lenValue (.prim (.string "abc"))⟩,
              ⟨"listLen", .regular, lenValue (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)])⟩,
              ⟨"structLen", .regular,
                lenValue
                  (mkStruct [
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
          (mkStruct [
              ⟨"lenString", .regular, lenValue (.kind .string)⟩,
              ⟨"emptyOr", .regular, orValues []⟩
            ] .regularOpen none [])
    },
    {
      fileName := "manifest/manifest_field_filtering.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (mkStruct [
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
          (mkStruct [
              ⟨"mode", .regular,
                .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩
            ] .regularOpen none [])
    },
    {
      fileName := "refs/let_binding.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"base", .letBinding, .prim (.int 2)⟩,
                ⟨"x", .regular, .conj [.ref "base", .kind .int]⟩,
                ⟨"nested", .regular,
                  mkStruct [
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
            (mkStruct [
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
            (mkStruct [
                ⟨"v", .letBinding, .prim (.int 1)⟩,
                ⟨"outer", .regular, .ref "v"⟩,
                ⟨"inner", .regular,
                  mkStruct [
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
            (mkStruct [
                ⟨"top", .regular,
                  mkStruct [
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
            (mkStruct [
                ⟨"secret", .letBinding, .prim (.string "abc")⟩,
                ⟨"shown", .regular, .ref "secret"⟩,
                ⟨"other", .regular, .prim (.int 1)⟩
              ] .regularOpen none []))
    },
    {
      fileName := "refs/mutual_reference_cycle.expected",
      content :=
        formatTopLevel
          (resolveAndEval (mkStruct [⟨"x", .regular, .ref "y"⟩, ⟨"y", .regular, .ref "x"⟩] .regularOpen none []))
    },
    {
      fileName := "lists/nested_list_field.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [⟨"items", .regular, .list [.kind .int, .kind .string]⟩] .regularOpen none [])
            (mkStruct [⟨"items", .regular, .list [.prim (.int 1), .prim (.string "x")]⟩] .regularOpen none []))
    },
    {
      fileName := "lists/nested_reference_list.expected",
      content :=
        formatTopLevel
          (resolveAndEval (mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .list [.ref "#A"]⟩] .regularOpen none []))
    },
    {
      fileName := "structs/nested_struct_field.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
            (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []))
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
          (mkStruct [⟨"mode", .optional,
              .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
    },
    {
      fileName := "manifest/optional_default_materialized.manifest.expected",
      content :=
        formatManifestFieldResult "x"
          (meet
            (mkStruct [⟨"mode", .optional,
                .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
            (mkStruct [⟨"mode", .regular, .top⟩] .regularOpen none []))
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
            (mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
            (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_label_pattern.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
            (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/multiple_pattern_fields.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)])
            (mkStruct [
                ⟨"az", .regular, .prim (.int 1)⟩,
                ⟨"ax", .regular, .prim (.int 2)⟩,
                ⟨"bz", .regular, .prim (.string "ok")⟩
              ] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_wildcard_pattern.expected",
      content :=
        formatTopLevel
          (mkStruct [
              ⟨"x", .regular,
                meet
                  (mkStruct [] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))])
                  (mkStruct [⟨"abcz", .regular, .prim (.int 1)⟩, ⟨"abcy", .regular, .prim (.string "skip")⟩] .regularOpen none [])⟩,
              ⟨"y", .regular,
                meet
                  (mkStruct [] .regularOpen none [((.stringRegex "^a.+z$"), (.kind .int))])
                  (mkStruct [⟨"az", .regular, .prim (.string "skip")⟩, ⟨"abz", .regular, .prim (.int 2)⟩] .regularOpen none [])⟩
            ] .regularOpen none [])
    },
    {
      fileName := "definitions/regex_class_pattern.expected",
      content :=
        formatTopLevel
          (mkStruct [
              ⟨"x", .regular,
                meet
                  (mkStruct [] .regularOpen none [((.stringRegex "^[ab]cz$"), (.kind .int))])
                  (mkStruct [
                      ⟨"acz", .regular, .prim (.int 1)⟩,
                      ⟨"bcz", .regular, .prim (.int 2)⟩,
                      ⟨"ccz", .regular, .prim (.string "skip")⟩
                    ] .regularOpen none [])⟩,
              ⟨"y", .regular,
                meet
                  (mkStruct [] .regularOpen none [((.stringRegex "^a[0-9]z$"), (.kind .int))])
                  (mkStruct [⟨"a5z", .regular, .prim (.int 1)⟩, ⟨"axz", .regular, .prim (.string "skip")⟩] .regularOpen none [])⟩
            ] .regularOpen none [])
    },
    {
      fileName := "definitions/regex_escape_pattern.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none [((.stringRegex "^a\\.z$"), (.kind .int))])
            (mkStruct [⟨"a.z", .regular, .prim (.string "bad")⟩, ⟨"abz", .regular, .prim (.string "skip")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_question_pattern.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none [((.stringRegex "^colou?r$"), (.kind .int))])
            (mkStruct [
                ⟨"color", .regular, .prim (.string "bad")⟩,
                ⟨"colour", .regular, .prim (.int 2)⟩,
                ⟨"colouur", .regular, .prim (.string "skip")⟩
              ] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_shorthand_pattern.expected",
      content :=
        formatTopLevel
          (mkStruct [
              ⟨"x", .regular,
                meet
                  (mkStruct [] .regularOpen none [((.stringRegex "^a\\dz$"), (.kind .int))])
                  (mkStruct [⟨"a5z", .regular, .prim (.string "bad")⟩, ⟨"adz", .regular, .prim (.string "skip")⟩] .regularOpen none [])⟩,
              ⟨"y", .regular,
                meet
                  (mkStruct [] .regularOpen none [((.stringRegex "^a\\Dz$"), (.kind .int))])
                  (mkStruct [⟨"a5z", .regular, .prim (.string "skip")⟩, ⟨"adz", .regular, .prim (.int 1)⟩] .regularOpen none [])⟩
            ] .regularOpen none [])
    },
    {
      fileName := "definitions/regex_alternation_pattern.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none [((.stringRegex "^cat$|^dog$"), (.kind .int))])
            (mkStruct [
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
            (mkStruct [] .regularOpen none [((.stringRegex "^(cat|dog)$"), (.kind .int))])
            (mkStruct [
                ⟨"cat", .regular, .prim (.string "bad")⟩,
                ⟨"dog", .regular, .prim (.int 2)⟩,
                ⟨"cow", .regular, .prim (.string "skip")⟩
              ] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_word_shorthand_pattern.expected",
      content :=
        formatTopLevel
          (mkStruct [
              ⟨"x", .regular,
                meet
                  (mkStruct [] .regularOpen none [((.stringRegex "^a\\wz$"), (.kind .int))])
                  (mkStruct [⟨"a_z", .regular, .prim (.string "bad")⟩, ⟨"a-z", .regular, .prim (.string "skip")⟩] .regularOpen none [])⟩,
              ⟨"y", .regular,
                meet
                  (mkStruct [] .regularOpen none [((.stringRegex "^a\\Wz$"), (.kind .int))])
                  (mkStruct [⟨"a_z", .regular, .prim (.string "skip")⟩, ⟨"a-z", .regular, .prim (.string "bad")⟩] .regularOpen none [])⟩
            ] .regularOpen none [])
    },
    {
      fileName := "definitions/regex_space_shorthand_pattern.expected",
      content :=
        formatTopLevel
          (mkStruct [
              ⟨"x", .regular,
                meet
                  (mkStruct [] .regularOpen none [((.stringRegex "^a\\sz$"), (.kind .int))])
                  (mkStruct [⟨"a z", .regular, .prim (.string "bad")⟩, ⟨"a_z", .regular, .prim (.string "skip")⟩] .regularOpen none [])⟩,
              ⟨"y", .regular,
                meet
                  (mkStruct [] .regularOpen none [((.stringRegex "^a\\Sz$"), (.kind .int))])
                  (mkStruct [⟨"a z", .regular, .prim (.string "skip")⟩, ⟨"a_z", .regular, .prim (.string "bad")⟩] .regularOpen none [])⟩
            ] .regularOpen none [])
    },
    {
      fileName := "definitions/regex_exact_repetition_pattern.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none [((.stringRegex "^a\\d{2}z$"), (.kind .int))])
            (mkStruct [⟨"a12z", .regular, .prim (.string "bad")⟩, ⟨"a1z", .regular, .prim (.string "skip")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/regex_bounded_repetition_pattern.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none [((.stringRegex "^a\\d{2,3}z$"), (.kind .int))])
            (mkStruct [
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
            (mkStruct [⟨"mode", .required,
                .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
            (mkStruct [⟨"mode", .regular, .top⟩] .regularOpen none []))
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
            (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
            (mkStruct [⟨"a", .regular, .prim (.string "x")⟩] .regularOpen none []))
    },
    {
      fileName := "definitions/string_pattern_constraint.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
            (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none []))
    },
    {
      fileName := "structs/struct_ellipsis.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some .top) [])
            (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "ok")⟩] .regularOpen none []))
    },
    {
      fileName := "disjunctions/struct_disjunction_meet.expected",
      content :=
        formatField "x"
          (meet
            (.disj
              [
                (.regular, mkStruct [⟨"kind", .regular, .prim (.string "web")⟩] .regularOpen none []),
                (.regular, mkStruct [⟨"kind", .regular, .prim (.string "db")⟩] .regularOpen none [])
              ])
            (mkStruct [
                ⟨"kind", .regular, .prim (.string "web")⟩,
                ⟨"port", .regular, .prim (.int 80)⟩
              ] .regularOpen none []))
    },
    {
      fileName := "refs/three_reference_cycle.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
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
            (mkStruct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    []
                    [
                      .comprehension
                        [.forIn (some "k") "v" (mkStruct [⟨"x", .regular, .prim (.int 1)⟩] .regularOpen none [])]
                        (mkStruct [
                            ⟨"key", .regular, .ref "k"⟩,
                            ⟨"val", .regular, .ref "v"⟩
                          ] .regularOpen none [])
                    ]
                    .regularOpen⟩
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
            (mkStruct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    [⟨"base", .regular, .prim (.int 0)⟩]
                    [
                      .comprehension
                        [.forIn none "v" (.list [.prim (.int 42)])]
                        (mkStruct [⟨"only", .regular, .ref "v"⟩] .regularOpen none []),
                      .comprehension
                        [.guard (.prim (.bool true))]
                        (mkStruct [⟨"flag", .regular, .prim (.bool true)⟩] .regularOpen none []),
                      .comprehension
                        [.guard (.prim (.bool false))]
                        (mkStruct [⟨"hidden", .regular, .prim (.int 1)⟩] .regularOpen none [])
                    ]
                    .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/default_in_guard.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
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
                        (mkStruct [⟨"prod", .regular, .prim (.bool true)⟩] .regularOpen none []),
                      .comprehension
                        [.guard (.ref "staging")]
                        (mkStruct [⟨"dev", .regular, .prim (.bool true)⟩] .regularOpen none [])
                    ]
                    .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      -- D#1a: a BOTTOM comprehension guard PROPAGATES (does not vanish). The guard `1/0 > 0`
      -- evaluates to bottom; the comprehension becomes that bottom, so `out` is `_|_`.
      fileName := "comprehensions/guard_bottom_propagates.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    []
                    [
                      .comprehension
                        [.guard (.binary .gt (.binary .div (.prim (.int 1)) (.prim (.int 0))) (.prim (.int 0)))]
                        (mkStruct [⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none [])
                    ]
                    .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      -- D#1a list twin: a bottom guard in a LIST comprehension propagates. Kue positions the
      -- bottom in the element slot (`[_|_]`), the same convention as an explicit `[1/0]`; the
      -- soundness fix is that the bottom is PRESERVED, not swallowed to `[]`.
      fileName := "comprehensions/list_guard_bottom_propagates.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨
                  "out",
                  .regular,
                  .list
                    [
                      .listComprehension
                        [.guard (.binary .gt (.binary .div (.prim (.int 1)) (.prim (.int 0))) (.prim (.int 0)))]
                        (.structComp [] [.prim (.int 1)] .regularOpen)
                    ]⟩
              ] .regularOpen none []))
    },
    {
      -- D#1a edge: the guard reads a sibling that is itself bottom (`x: 1 & 2`). The bottom
      -- flows through the guard and propagates out of the comprehension.
      fileName := "comprehensions/guard_bottom_from_sibling.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"x", .regular, .conj [.prim (.int 1), .prim (.int 2)]⟩,
                ⟨
                  "out",
                  .regular,
                  .structComp
                    []
                    [
                      .comprehension
                        [.guard (.binary .gt (.ref "x") (.prim (.int 0)))]
                        (mkStruct [⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none [])
                    ]
                    .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      fileName := "numeric/string_interpolation.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
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
            (mkStruct [⟨"x", .regular, .prim (.string "hello\nworld")⟩] .regularOpen none []))
    },
    {
      fileName := "multiline/multiline_dedent.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [⟨"x", .regular, .prim (.string "line1\n  line2")⟩] .regularOpen none []))
    },
    {
      fileName := "multiline/multiline_interpolation.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
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
            (mkStruct [⟨"x", .regular, .prim (.string "")⟩] .regularOpen none []))
    },
    {
      fileName := "multiline/multiline_cert.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
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
            (mkStruct [⟨"x", .regular, .prim (.bytes "abc\ndef")⟩] .regularOpen none []))
    },
    {
      fileName := "structs/dynamic_field.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"k", .regular, .prim (.string "name")⟩,
                ⟨
                  "out",
                  .regular,
                  .structComp [] [.dynamicField (.ref "k") .regular (.prim (.int 42))] .regularOpen
                ⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/dynamic_field_comprehension.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    []
                    [
                      .comprehension
                        [.forIn (some "k") "v"
                          (mkStruct [
                              ⟨"a", .regular, .prim (.int 1)⟩,
                              ⟨"b", .regular, .prim (.int 2)⟩
                            ] .regularOpen none [])]
                        (.structComp
                          []
                          [.dynamicField (.interpolation [.ref "k"]) .regular (.ref "v")]
                          .regularOpen)
                    ]
                    .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_for.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn none "x"
                        (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)])]
                      (.structComp [] [.binary .mul (.ref "x") (.prim (.int 2))] .regularOpen)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_for_index.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn (some "i") "x"
                        (.list [.prim (.int 10), .prim (.int 20), .prim (.int 30)])]
                      (.structComp []
                        [.binary .add
                          (.binary .mul (.ref "i") (.prim (.int 100)))
                          (.ref "x")]
                        .regularOpen)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_for_kv.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn (some "k") "v"
                        (mkStruct [
                            ⟨"a", .regular, .prim (.int 1)⟩,
                            ⟨"b", .regular, .prim (.int 2)⟩
                          ] .regularOpen none [])]
                      (.structComp [] [.ref "v"] .regularOpen)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_guard_for.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"l", .regular,
                  .list [.prim (.int 1), .prim (.int 2), .prim (.int 3), .prim (.int 4)]⟩,
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn none "x" (.ref "l"),
                       .guard (.binary .gt (.ref "x") (.prim (.int 2)))]
                      (.structComp [] [.ref "x"] .regularOpen)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_nested.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"xs", .regular, .list [.prim (.int 1), .prim (.int 2)]⟩,
                ⟨"ys", .regular, .list [.prim (.int 10), .prim (.int 20)]⟩,
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn none "x" (.ref "xs"), .forIn none "y" (.ref "ys")]
                      (.structComp [] [.binary .add (.ref "x") (.ref "y")] .regularOpen)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/list_comprehension_mixed.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"xs", .regular, .list [.prim (.int 5), .prim (.int 6)]⟩,
                ⟨"out", .regular,
                  .list
                    [.prim (.int 1),
                     .listComprehension
                       [.forIn none "x" (.ref "xs")]
                       (.structComp [] [.ref "x"] .regularOpen),
                     .prim (.int 2)]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/scalar_embedding_collapse.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"a", .regular, .prim (.int 7)⟩,
                ⟨"out", .regular, .structComp [] [.ref "a"] .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      fileName := "comprehensions/comprehension_loopvar_shadow.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
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
                          .regularOpen)
                    ]
                    .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/struct_embedding_scope.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    [⟨"base", .regular, .prim (.int 7)⟩]
                    [mkStruct [⟨"copy", .regular, .ref "base"⟩] .regularOpen none []]
                    .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/struct_embedding_nested.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    [⟨"base", .regular, .prim (.int 7)⟩]
                    [mkStruct [⟨"inner", .regular, mkStruct [⟨"deep", .regular, .ref "base"⟩] .regularOpen none []⟩] .regularOpen none []]
                    .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      fileName := "structs/struct_embedding_siblings.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨
                  "out",
                  .regular,
                  .structComp
                    [
                      ⟨"base", .regular, .prim (.int 7)⟩,
                      ⟨"sib", .regular, .prim (.int 9)⟩
                    ]
                    [mkStruct [
                        ⟨"copy", .regular, .ref "base"⟩,
                        ⟨"copy2", .regular, .ref "sib"⟩
                      ] .regularOpen none []]
                    .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      -- `{[1, 2, 3]}`: a list embedded in a struct with no other members IS the list.
      fileName := "lists/list_embedding_pure.expected",
      content :=
        formatField "x"
          (resolveAndEval
            (.structComp [] [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]] .regularOpen))
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
              .regularOpen))
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
              .regularOpen))
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
              .regularOpen))
    },
    {
      -- `{a: 1} & [1, 2]`: explicit struct meet list, struct has an output field → bottom.
      fileName := "lists/list_struct_genuine_conflict.expected",
      content :=
        formatField "x"
          (meet
            (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
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
              .regularOpen))
    },
    {
      -- `{#a: 1, [...int]} & {#b: 2, [1, 2]}`: meet of two embeddedLists — decls merge,
      -- lists meet (`[...int] & [1, 2] = [1, 2]`).
      fileName := "lists/list_embedding_meet_two.expected",
      content :=
        formatField "x"
          (meet
            (resolveAndEval
              (.structComp [⟨"#a", .definition, .prim (.int 1)⟩] [.listTail [] (.kind .int)] .regularOpen))
            (resolveAndEval
              (.structComp [⟨"#b", .definition, .prim (.int 2)⟩]
                [.list [.prim (.int 1), .prim (.int 2)]] .regularOpen)))
    },
    {
      -- `{#a: 1, [10, 20]}.#a` selects a decl; `[0]` indexes the embedded list.
      fileName := "lists/list_embedding_select_index.expected",
      content :=
        let base : Value :=
          .structComp [⟨"#a", .definition, .prim (.int 1)⟩]
            [.list [.prim (.int 10), .prim (.int 20)]] .regularOpen
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"p", .regular, .selector base "#a"⟩,
                ⟨"q", .regular, .index base (.prim (.int 0))⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/strings_builtin.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
                ⟨"metadata", .regular,
                  mkStruct [⟨"name", .regular, .prim (.string "api")⟩] .regularOpen none []⟩,
                ⟨"spec", .regular,
                  mkStruct [
                      ⟨"replicas", .regular, .prim (.int 3)⟩,
                      ⟨"template", .regular,
                        mkStruct [⟨"spec", .regular,
                            mkStruct [⟨"containers", .regular, .list [.prim (.string "c")]⟩] .regularOpen none []⟩] .regularOpen none []⟩
                    ] .regularOpen none []⟩,
                ⟨"labels", .regular,
                  mkStruct [⟨"prodigy9.co/app", .regular, .prim (.string "web")⟩] .regularOpen none []⟩,
                ⟨"mixed", .regular,
                  mkStruct [⟨"a", .regular,
                      mkStruct [⟨"b", .regular,
                        mkStruct [⟨"c", .regular, .prim (.int 1)⟩] .regularOpen none []⟩] .regularOpen none []⟩] .regularOpen none []⟩
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
            (mkStruct [
                ⟨"#Secret", .definition,
                  mkStruct [
                      ⟨"Self", .letBinding, .thisStruct⟩,
                      ⟨"#name", .definition, .prim (.string "tls")⟩,
                      ⟨"data", .regular, .selector (.ref "Self") "#name"⟩
                    ] .defClosed none []⟩,
                ⟨"aliased", .regular,
                  mkStruct [
                      ⟨"X", .letBinding, .thisStruct⟩,
                      ⟨"greeting", .regular, .prim (.string "hi")⟩,
                      ⟨"echo", .regular, .selector (.ref "X") "greeting"⟩
                    ] .regularOpen none []⟩,
                ⟨"nestedSelf", .regular,
                  mkStruct [
                      ⟨"Self", .letBinding, .thisStruct⟩,
                      ⟨"port", .regular, .prim (.int 8080)⟩,
                      ⟨"inner", .regular,
                        mkStruct [⟨"lo", .regular, .selector (.ref "Self") "port"⟩] .regularOpen none []⟩
                    ] .regularOpen none []⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/base64_encode.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
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
            (mkStruct [
                ⟨"str", .regular, .builtinCall "json.Marshal" [.prim (.string "hi")]⟩,
                ⟨"intVal", .regular, .builtinCall "json.Marshal" [.prim (.int 42)]⟩,
                ⟨"negInt", .regular, .builtinCall "json.Marshal" [.prim (.int (-5))]⟩,
                ⟨"floatVal", .regular, .builtinCall "json.Marshal" [.prim (.float "1.5")]⟩,
                ⟨"floatWhole", .regular, .builtinCall "json.Marshal" [.prim (.float "1.0")]⟩,
                ⟨"boolVal", .regular, .builtinCall "json.Marshal" [.prim (.bool true)]⟩,
                ⟨"nullVal", .regular, .builtinCall "json.Marshal" [.prim .null]⟩,
                ⟨"nested", .regular,
                  .builtinCall "json.Marshal"
                    [mkStruct [
                        ⟨"b", .regular, .prim (.int 2)⟩,
                        ⟨"a", .regular, .prim (.int 1)⟩,
                        ⟨"c", .regular,
                          mkStruct [⟨"z", .regular, .prim (.int 1)⟩, ⟨"y", .regular, .prim (.int 2)⟩] .regularOpen none []⟩
                      ] .regularOpen none []]⟩,
                ⟨"listVal", .regular,
                  .builtinCall "json.Marshal"
                    [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]]⟩,
                ⟨"emptyObj", .regular, .builtinCall "json.Marshal" [mkStruct [] .regularOpen none []]⟩,
                ⟨"emptyList", .regular, .builtinCall "json.Marshal" [.list []]⟩,
                ⟨"escapes", .regular,
                  .builtinCall "json.Marshal"
                    [mkStruct [⟨"html", .regular, .prim (.string "<a>&\"b\\c\n\t")⟩] .regularOpen none []]⟩,
                ⟨"incomplete", .regular,
                  .builtinCall "json.Marshal" [mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none []]⟩
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
            (mkStruct [
                ⟨"registry", .regular,
                  mkStruct [⟨"reg.io", .regular,
                      mkStruct [⟨"auth", .regular, .prim (.string "abc")⟩] .regularOpen none []⟩] .regularOpen none []⟩,
                ⟨"data", .regular,
                  .builtinCall "base64.Encode"
                    [.prim .null,
                      .builtinCall "json.Marshal"
                        [mkStruct [⟨"auths", .regular, .ref "registry"⟩] .regularOpen none []]]⟩
              ] .regularOpen none []))
    },
    {
      -- `regexp.Match(pattern, string)` is an UNANCHORED search (matches anywhere), the
      -- same engine entrypoint as `=~` — so `regexp.Match` and `=~` agree by construction.
      -- Patterns here are simple anchored/literal/char-class forms the current engine
      -- handles; grouped/`\b`/lazy patterns are RX-1's domain and deliberately excluded.
      fileName := "builtins/regexp_match.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"anchoredStart", .regular,
                  .builtinCall "regexp.Match" [.prim (.string "^x"), .prim (.string "xyz")]⟩,
                ⟨"unanchored", .regular,
                  .builtinCall "regexp.Match" [.prim (.string "y"), .prim (.string "xyz")]⟩,
                ⟨"midMatch", .regular,
                  .builtinCall "regexp.Match" [.prim (.string "b"), .prim (.string "abc")]⟩,
                ⟨"noMatch", .regular,
                  .builtinCall "regexp.Match" [.prim (.string "q"), .prim (.string "xyz")]⟩,
                ⟨"anchoredEnd", .regular,
                  .builtinCall "regexp.Match" [.prim (.string "z$"), .prim (.string "xyz")]⟩,
                ⟨"charClass", .regular,
                  .builtinCall "regexp.Match" [.prim (.string "[0-9]"), .prim (.string "a1b")]⟩
              ] .regularOpen none []))
    },
    {
      -- RX-1c: submatch / Find* / ReplaceAll over the Pike-VM capture array. `ReplaceAll`
      -- expands the Go `Expand` template (`$n`/`${n}`/`$$`); `${1}suffix` is group 1 then
      -- literal `suffix` while bare `$1suffix` names the (nonexistent) group `1suffix`.
      -- `ReplaceAllLiteral` splices verbatim. All oracle-checked vs cue v0.16.1; the
      -- prod9-filter case (`([hb][^\s]+)lo` → `${1}ly`) is the lever F-1 + RX-1c unblock.
      fileName := "builtins/regexp_submatch.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"replaceLiteral", .regular,
                  .builtinCall "regexp.ReplaceAll"
                    [.prim (.string "a(x*)b"), .prim (.string "-axxb-"), .prim (.string "T")]⟩,
                ⟨"replaceGroup", .regular,
                  .builtinCall "regexp.ReplaceAll"
                    [.prim (.string "a(x*)b"), .prim (.string "-axxb-"), .prim (.string "$1")]⟩,
                ⟨"replaceBrace", .regular,
                  .builtinCall "regexp.ReplaceAll"
                    [.prim (.string "a(x*)b"), .prim (.string "-axxb-"),
                      .prim (.string "${1}suffix")]⟩,
                ⟨"replaceBareName", .regular,
                  .builtinCall "regexp.ReplaceAll"
                    [.prim (.string "a(x*)b"), .prim (.string "-axxb-"),
                      .prim (.string "$1suffix")]⟩,
                ⟨"replaceDollar", .regular,
                  .builtinCall "regexp.ReplaceAll"
                    [.prim (.string "a(x*)b"), .prim (.string "-axxb-"), .prim (.string "$$")]⟩,
                ⟨"replaceMulti", .regular,
                  .builtinCall "regexp.ReplaceAll"
                    [.prim (.string "a(x*)b"), .prim (.string "-axxb-axxxb-"),
                      .prim (.string "T")]⟩,
                ⟨"replaceNoMatch", .regular,
                  .builtinCall "regexp.ReplaceAll"
                    [.prim (.string "a(x*)b"), .prim (.string "-aQb-"), .prim (.string "T")]⟩,
                ⟨"replaceZeroWidth", .regular,
                  .builtinCall "regexp.ReplaceAll"
                    [.prim (.string "x*"), .prim (.string "abc"), .prim (.string "-")]⟩,
                ⟨"replaceLiteralFn", .regular,
                  .builtinCall "regexp.ReplaceAllLiteral"
                    [.prim (.string "a(x*)b"), .prim (.string "-axxb-"), .prim (.string "$1")]⟩,
                ⟨"prod9Filter", .regular,
                  .builtinCall "regexp.ReplaceAll"
                    [.prim (.string "([hb][^\\s]+)lo"), .prim (.string "hello jello bello"),
                      .prim (.string "${1}ly")]⟩,
                ⟨"findOne", .regular,
                  .builtinCall "regexp.Find"
                    [.prim (.string "a(x*)b"), .prim (.string "-axxb-")]⟩,
                ⟨"findSub", .regular,
                  .builtinCall "regexp.FindSubmatch"
                    [.prim (.string "a(x*)b"), .prim (.string "-axxb-")]⟩,
                ⟨"findAllSpans", .regular,
                  .builtinCall "regexp.FindAll"
                    [.prim (.string "ab"), .prim (.string "abab"), .prim (.int (-1))]⟩,
                ⟨"findAllSub", .regular,
                  .builtinCall "regexp.FindAllSubmatch"
                    [.prim (.string "a(x*)b"), .prim (.string "-axb-axxb-"),
                      .prim (.int (-1))]⟩
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
            (mkStruct [
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
                        (mkStruct [⟨"seen", .regular, .ref "f"⟩] .regularOpen none [])
                    ]
                    .regularOpen
                ⟩,
                ⟨
                  "absent",
                  .regular,
                  .structComp
                    [⟨"base", .regular, mkStruct [⟨"f", .regular, .prim (.int 3)⟩] .regularOpen none []⟩]
                    [
                      .comprehension
                        [.guard (.binary .ne (.selector (.ref "base") "g") .bottom)]
                        (mkStruct [⟨"seen", .regular, .prim (.bool true)⟩] .regularOpen none [])
                    ]
                    .regularOpen
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
            (mkStruct [
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
            (mkStruct [
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
            (mkStruct [
                ⟨"a", .regular, .kind .int⟩,
                ⟨"c", .regular, mkStruct [⟨"e", .regular, .ref "a"⟩] .regularOpen none []⟩,
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
            (mkStruct [
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
            (mkStruct [
                ⟨"d", .regular, mkStruct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] .regularOpen none []⟩,
                ⟨"y", .regular, .conj [.ref "d", mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []]⟩
              ] .regularOpen none []))
    },
    {
      -- 2c.2: literal struct conjunction (no reference operand) — `{a: int, b: a} & {a: 1}`;
      -- `b` tracks the narrowed `a` through the merged frame.
      fileName := "structs/meet_lazy_literal.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"x", .regular,
                  .conj
                    [
                      mkStruct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] .regularOpen none [],
                      mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []
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
            (mkStruct [
                ⟨"d", .regular, mkStruct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] .regularOpen none []⟩,
                ⟨"y", .regular, .conj [.ref "d", mkStruct [⟨"a", .regular, .boundConstraint (intDecimal 0) .gt .number⟩] .regularOpen none []]⟩
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
            (mkStruct [
                ⟨"#D", .definition,
                  mkStruct [
                      ⟨"#x", .definition, .kind .string⟩,
                      ⟨"out", .regular, mkStruct [⟨"val", .regular, .ref "#x"⟩] .regularOpen none []⟩
                    ] .regularOpen none []⟩,
                ⟨"y", .regular, .conj [.ref "#D", mkStruct [⟨"#x", .definition, .prim (.string "hi")⟩] .regularOpen none []]⟩
              ] .regularOpen none []))
    },
    {
      -- 2c.2: a chained sibling reference within one conjunct, narrowed across the meet —
      -- `{a: int, b: a, c: b} & {a: 1}` resolves `a`, `b`, `c` all to `1`.
      fileName := "structs/meet_lazy_chain.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"x", .regular,
                  .conj
                    [
                      mkStruct [
                          ⟨"a", .regular, .kind .int⟩,
                          ⟨"b", .regular, .ref "a"⟩,
                          ⟨"c", .regular, .ref "b"⟩
                        ] .regularOpen none [],
                      mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []
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
            (mkStruct [
                ⟨"x", .regular,
                  .conj
                    [
                      .disj
                        [
                          (.regular, mkStruct [⟨"kind", .regular, .prim (.string "web")⟩] .regularOpen none []),
                          (.regular, mkStruct [⟨"kind", .regular, .prim (.string "db")⟩] .regularOpen none [])
                        ],
                      mkStruct [
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
