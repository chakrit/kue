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
      -- E#4: a concrete operand outside an arithmetic operator's domain (list/struct/bool/null)
      -- is a TYPE ERROR for every op, not a held residual (cue hard-errors; Kue used to leave
      -- `incomplete value`). Pins all four ops × the non-prim/wrong-prim concrete operands.
      fileName := "numeric/list_arithmetic_type_error.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"listAdd", .regular, .binary .add (.list [.prim (.int 1), .prim (.int 2)]) (.list [.prim (.int 3), .prim (.int 4)])⟩,
                ⟨"listMul", .regular, .binary .mul (.prim (.int 3)) (.list [.prim (.int 1), .prim (.int 2)])⟩,
                ⟨"listMul2", .regular, .binary .mul (.list [.prim (.int 1), .prim (.int 2)]) (.prim (.int 3))⟩,
                ⟨"listSub", .regular, .binary .sub (.list [.prim (.int 1), .prim (.int 2)]) (.prim (.int 3))⟩,
                ⟨"listDiv", .regular, .binary .div (.list [.prim (.int 1), .prim (.int 2)]) (.prim (.int 3))⟩,
                ⟨"structAdd", .regular, .binary .add (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []) (mkStruct [⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])⟩,
                ⟨"boolMul", .regular, .binary .mul (.prim (.bool true)) (.prim (.bool false))⟩,
                ⟨"nullSub", .regular, .binary .sub (.prim .null) (.prim .null)⟩
              ] .regularOpen none []))
    },
    {
      -- E#4 sibling: `*` over (string|bytes, int) is REPETITION (cue, superseding
      -- strings/bytes.Repeat), in either operand order; a zero count yields the empty value.
      -- `+` over two strings is concat; `-` over strings is a type error (the per-op asymmetry).
      fileName := "numeric/string_repeat_multiplication.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"concat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b"))⟩,
                ⟨"repeat", .regular, .binary .mul (.prim (.string "ab")) (.prim (.int 2))⟩,
                ⟨"repeatL", .regular, .binary .mul (.prim (.int 2)) (.prim (.string "ab"))⟩,
                ⟨"zero", .regular, .binary .mul (.prim (.string "xyz")) (.prim (.int 0))⟩,
                ⟨"strSub", .regular, .binary .sub (.prim (.string "a")) (.prim (.string "b"))⟩
              ] .regularOpen none []))
    },
    {
      -- E#4 critical regression pin: an INCOMPLETE operand keeps arithmetic DEFERRED (residual),
      -- never a premature type error — even paired with a concrete list (the concrete-nonarith ×
      -- incomplete case). It resolves once the abstract side concretizes (`resolved + 3` → 8).
      fileName := "numeric/arithmetic_incomplete_operand_defers.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"abstract", .regular, .kind .int⟩,
                ⟨"listDefer", .regular, .binary .add (.ref "abstract") (.list [.prim (.int 1)])⟩,
                ⟨"numDefer", .regular, .binary .mul (.ref "abstract") (.prim (.int 2))⟩,
                ⟨"resolved", .regular, .kind .int⟩,
                ⟨"resolved", .regular, .prim (.int 5)⟩,
                ⟨"sum", .regular, .binary .add (.ref "resolved") (.prim (.int 3))⟩
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
      fileName := "numeric/regex_in_class_negated.expected",
      content :=
        -- RX-2a: in-class `\D`/`\W`/`\S` fold their complement into the class union; whole-class
        -- `[^…]` negation applies after the fold. End-to-end `=~`/`!~` over the Pike-VM.
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"classD", .regular,
                  .binary .regexMatch (.prim (.string "a")) (.prim (.string "^[\\D]$"))⟩,
                ⟨"classDdigit", .regular,
                  .binary .regexMatch (.prim (.string "5")) (.prim (.string "^[\\D]$"))⟩,
                ⟨"classW", .regular,
                  .binary .regexMatch (.prim (.string " ")) (.prim (.string "^[\\W]$"))⟩,
                ⟨"classS", .regular,
                  .binary .regexMatch (.prim (.string " ")) (.prim (.string "^[\\S]$"))⟩,
                ⟨"union", .regular,
                  .binary .regexMatch (.prim (.string "5")) (.prim (.string "^[\\D5]$"))⟩,
                ⟨"unionDigit", .regular,
                  .binary .regexMatch (.prim (.string "7")) (.prim (.string "^[\\D5]$"))⟩,
                ⟨"unionMember", .regular,
                  .binary .regexMatch (.prim (.string "a")) (.prim (.string "^[a\\W]$"))⟩,
                ⟨"everything", .regular,
                  .binary .regexMatch (.prim (.string " ")) (.prim (.string "^[\\d\\D]$"))⟩,
                ⟨"negMember", .regular,
                  .binary .regexMatch (.prim (.string "5")) (.prim (.string "^[^\\D]$"))⟩,
                ⟨"negMemberNo", .regular,
                  .binary .regexMatch (.prim (.string "a")) (.prim (.string "^[^\\D]$"))⟩,
                ⟨"notClass", .regular,
                  .binary .regexNotMatch (.prim (.string "5")) (.prim (.string "^[\\D]$"))⟩
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
      -- SC-1b: the meet of two closed pattern defs is closed to the INTERSECTION of their
      -- allowed-sets. `x1` matches `#A`'s `^x` but not `#B`'s `^y`, so the later meet rejects
      -- it (`x1: _|_`); both patterns survive as value-constraints. Driven through parse so the
      -- full closed×closed-pattern path (not just the `meet` primitive) is exercised.
      fileName := "definitions/sc1b_closed_pattern_intersection.expected",
      content :=
        match parseSource
            "#A: {[=~\"^x\"]: int}\n#B: {[=~\"^y\"]: int}\nout: (#A & #B) & {x1: 5}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
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
      -- Bug2-6: two SEPARATE declarations of one definition path UNIFY their field-sets and close
      -- ONCE over the union (`#Foo: {a:1}` + `#Foo: {c:3}` → `{a,c}` closed). cue v0.16.1 gives
      -- `{a:1,c:3}`. Pre-fix Kue `.conj`-ed two SEPARATELY-closed bodies, so the meet mutually
      -- rejected (`{a:_|_, c:_|_}`). Fixed by `mergeDefinitionDecls`: `canonicalizeFields` unions
      -- same-label def decls into ONE close-once body.
      fileName := "definitions/bug26_same_def_multi_decl_close_once.expected",
      content :=
        match parseSource "#Foo: {a: 1}\n#Foo: {c: 3}\nout: #Foo\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-6 close-once is still CLOSED: three same-def decls union `{a,b,c}` and close ONCE, so a
      -- use-site `extra` (in NO decl) is rejected (`extra: _|_`). The 3-decl argocd `#additions:`
      -- shape; the union admits exactly `a∪b∪c`, never re-opening.
      fileName := "definitions/bug26_three_decl_close_once_rejects_extra.expected",
      content :=
        match parseSource "#Foo: {a: 1}\n#Foo: {b: 2}\n#Foo: {c: 3}\nout: #Foo & {extra: 9}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-6 SOUNDNESS GUARD: two DISTINCT closed defs (`#A`, `#B`) met at the USE site STILL
      -- reject (`{a:_|_, c:_|_}`). The use-site `meet` CONCATENATES `closedClauses` (conjunction),
      -- never routing through the same-decl union — so close-once does NOT leak into `#A & #B`.
      fileName := "definitions/bug26_distinct_closed_defs_still_reject.expected",
      content :=
        match parseSource "#A: {a: 1}\n#B: {c: 3}\nout: #A & #B\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-6 CLOSED-PATTERN multi-decl (the cert-manager `#data: [string]: string` class — the
      -- over-union canary): a `[string]: string` pattern decl unioned with a concrete decl keeps the
      -- PATTERN as a value-constraint, NOT a re-opened tail. A string-typed use-site `extra` is
      -- admitted by the pattern; the union closes-once. A naive union would re-open this to a bare `...`.
      fileName := "definitions/bug26_closed_pattern_multi_decl_admits_string.expected",
      content :=
        match parseSource "#data: {[string]: string}\n#data: {known: \"x\"}\nout: #data & {extra: \"ok\"}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-6 4-DECL close-once: four same-def decls union `{a,b,c,d}` and close ONCE — a use-site
      -- `extra` (in no decl) is rejected (`extra: _|_`). Pins that the fold over decls scales past the
      -- 3-decl argocd shape without leaking openness.
      fileName := "definitions/bug26_four_decl_close_once_rejects_extra.expected",
      content :=
        match parseSource "#Foo: {a: 1}\n#Foo: {b: 2}\n#Foo: {c: 3}\n#Foo: {d: 4}\nout: #Foo & {extra: 9}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-7: same-def multi-decl close-once survives a def-REFERENCE through a sibling. `#Use`
      -- declares `#additions` twice and references it via `vis`; the def wrapper defers to a closure
      -- and the force-fold reconstruction (`mergeConjOperands`) now canonicalizes each operand's OWN
      -- fields FIRST, so the within-operand `#additions` decls UNION (close-once) instead of being
      -- `.conj`-collapsed + re-closed separately. cue v0.16.1: `{cert_gw:{}, cert_ing:{}}`; pre-fix
      -- kue bottomed (`{cert_gw:_|_, cert_ing:_|_}`).
      fileName := "definitions/bug27_multi_decl_def_ref_close_once.expected",
      content :=
        match parseSource "#Use: {\n\t#additions: cert_gw: {#kind: \"Gateway\"}\n\t#additions: cert_ing: {#kind: \"Ingress\"}\n\tvis: #additions\n}\nout: #Use.vis\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-7 SOUNDNESS GUARD: same-def CONFLICT on a shared label, referenced through a sibling,
      -- STILL bottoms — close-once unions LABELS, the shared label's VALUES still `meet`. The union
      -- never papers over a real conflict (`a: _|_`).
      fileName := "definitions/bug27_same_def_conflict_via_ref_bottoms.expected",
      content :=
        match parseSource "#Use: {\n\t#m: {a: 1}\n\t#m: {a: 2}\n\tvis: #m\n}\nout: #Use.vis\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-7 SOUNDNESS GUARD: two DISTINCT closed defs `#A & #B`, referenced through a sibling,
      -- STILL reject (`{a:_|_, c:_|_}`) — they are CROSS-operand conjuncts, so the cross-operand
      -- `.conj` (NOT the within-operand union) fires. The within-operand canonicalization never
      -- touches a genuine cross-conjunct meet, so the Bug2-7 fix does not leak into `#A & #B`.
      fileName := "definitions/bug27_distinct_closed_defs_via_ref_reject.expected",
      content :=
        match parseSource "#A: {a: 1}\n#B: {c: 3}\n#Use: {\n\tval: #A & #B\n}\nout: #Use.val\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-8: same-def multi-decl close-once ACROSS AN EMBED boundary. `#Use` declares `#m` once
      -- and EMBEDS `#A` which also declares `#m` — the two decls of the ONE def path `#m` close-once-
      -- UNION across the embed (`{c:3, a:1}`), and the sibling `vis: #m` resolves against the union.
      -- Pre-fix kue `.conj`-met them across the embed and bottomed.
      fileName := "definitions/bug28_embed_cross_decl_close_once_unions.expected",
      content :=
        match parseSource "#A: {#m: {a: 1}}\n#Use: {\n\t#A\n\t#m: {c: 3}\n\tvis: #m\n}\nout: #Use.vis\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-8: the argocd `#additions` shape — host declares `#additions` once and EMBEDS TWO defs
      -- each declaring it; all THREE decls of the ONE path union, close once.
      fileName := "definitions/bug28_three_decl_host_plus_two_embeds_union.expected",
      content :=
        match parseSource "#A1: {#additions: {cert_gw: {x: 1}}}\n#A2: {#additions: {cert_ls: {z: 3}}}\n#Use: {\n\t#A1\n\t#A2\n\t#additions: {cert_ing: {y: 2}}\n\tvis: #additions\n}\nout: #Use.vis\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-8 SOUNDNESS BOUNDARY: a host's REGULAR closed PATTERN field meeting an embed's same
      -- pattern field stays closed-MEET (a regular field never enters the DEFINITION decl-union), so
      -- the cert-manager `data: [string]: string` shape admits `extra` WITHOUT re-opening. Keeps green.
      fileName := "definitions/bug28_embed_closed_pattern_field_stays_meet.expected",
      content :=
        match parseSource "#Data: {data: [string]: string}\n#Use: {\n\t#Data\n\tdata: {extra: \"x\"}\n\tvis: data\n}\nout: #Use.vis\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-9: use-site narrowing of a REFERENCED NAMED multi-conjunct def. `#LS: #Base & {#extra}`
      -- is itself a `.conj`; referencing it and narrowing (`#LS & {#name}`) must flow `#name` into
      -- `#Base`'s sibling self-ref `vis: #name`. cue: `vis: "argocd-ls"`. Pre-fix kue forced `#LS`'s
      -- `.conj` body STANDALONE (no use-operands), collapsing `vis` to `string` before the narrowing
      -- arrived → `incomplete value: string`. Fixed by `flattenConjDefRef`: the `.conj` body's
      -- conjuncts splice into the use-site fold, identical to the inlined `#Base & {#extra} & {#name}`.
      fileName := "definitions/bug29_named_multiconjunct_def_narrowed.expected",
      content :=
        match parseSource "#Base: {#name: string, vis: #name}\n#LS: #Base & {#extra: \"x\"}\nout: #LS & {#name: \"argocd-ls\"}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-9: the real-def shape — a conjunct carries a bare `...` tail (`defs.#ListenerSet` and
      -- every prod9 def are `...`-open). The flatten admits a bare-`...` conjunct (lossless: the
      -- merged result is open via `open_`); the narrowing still reaches `vis`.
      fileName := "definitions/bug29_named_multiconjunct_tail_narrowed.expected",
      content :=
        match parseSource "#Base: {#name: string, vis: #name, ...}\n#LS: #Base & {#extra: \"x\"}\nout: #LS & {#name: \"argocd-ls\"}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-9: a CHAIN of named multi-conjunct defs (`#C: #B & …`, `#B: #A & …`) flattens fully —
      -- `flattenConjDefRef` recurses through each `.conj` body, so the narrowing at the outermost use
      -- site reaches the deepest conjunct's self-ref.
      fileName := "definitions/bug29_nested_named_multiconjunct_narrowed.expected",
      content :=
        match parseSource "#A: {#name: string, vis: #name}\n#B: #A & {#p: \"b\"}\n#C: #B & {#q: \"c\"}\nout: #C & {#name: \"deep\"}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-9 SOUNDNESS: flattening does NOT mask a real conflict. `val: 1` (in `#Base`, via the named
      -- def) meets `val: 2` (use site) and BOTTOMS, exactly as cue. The flatten folds operands; it never
      -- drops a conjunct.
      fileName := "definitions/bug29_named_multiconjunct_conflict_bottoms.expected",
      content :=
        match parseSource "#Base: {#name: string, val: 1}\n#LS: #Base & {#extra: \"x\"}\nout: #LS & {#name: \"n\", val: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-9 SOUNDNESS: closedness is preserved through the flatten. The named def is closed (no
      -- `...`), so a use-site field declared by NO conjunct (`notallowed`) is rejected — the per-operand
      -- `applyConjClosedness` re-derives each conjunct's allowed-set, same as the inlined meet.
      fileName := "definitions/bug29_named_multiconjunct_closed_rejects_extra.expected",
      content :=
        match parseSource "#Base: {#name: string, vis: #name}\n#LS: #Base & {#extra: \"x\"}\nout: #LS & {#name: \"n\", notallowed: 9}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-10: use-site narrowing of a `.structComp` HOST that EMBEDS a def with a sibling
      -- self-ref. `{#Meta} & {#name:"x"}` — the host `{#Meta}` is a structComp (embed in
      -- `comprehensions`); `conjStructCompDefer?` defers it to a `.closure` so the conj fold splices
      -- `#name` into the embedded `Self.#name` BEFORE it collapses. Pre-fix kue forced the host
      -- STANDALONE (no use-operands) → `metadata.name: string` frozen → `incomplete value: string`.
      fileName := "definitions/bug210_embed_self_ref_narrowed.expected",
      content :=
        match parseSource "#Meta: Self={#name: string, metadata: {name: Self.#name}}\nout: {#Meta} & {#name: \"x\"}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-10 TRANSITIVE (composes with Bug2-5): the host embeds `#Mid` which embeds `#Meta` —
      -- `bodyNeedsDefer` walks the embed chain (`embedChainAny`), so a transitively-embedded
      -- sibling self-ref still triggers the deferral and the narrowing reaches the deepest self-ref.
      fileName := "definitions/bug210_transitive_embed_narrowed.expected",
      content :=
        match parseSource "#Meta: Self={#name: string, metadata: {name: Self.#name}}\n#Mid: {#Meta}\nout: {#Mid} & {#name: \"x\"}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-10 SOUNDNESS (closedness): the embedded def `#Meta` is closed, so a use-site field it
      -- does not declare (`notallowed`) is REJECTED — the structComp-host force re-closes over the
      -- embed's labels (`embeddingClosesHost` overrides the open host). cue: `field not allowed`.
      fileName := "definitions/bug210_embed_closed_rejects_extra.expected",
      content :=
        match parseSource "#Meta: Self={#name: string, copy: Self.#name}\nout: {#Meta} & {#name: \"n\", notallowed: 9}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-10 SOUNDNESS (conflict): a real conflict still bottoms. `val: 1` (in `#Meta`) meets
      -- `val: 2` (use site) → `_|_`, exactly as cue. Delivery never masks a genuine conflict.
      fileName := "definitions/bug210_embed_conflict_bottoms.expected",
      content :=
        match parseSource "#Meta: Self={#name: string, val: 1, copy: Self.#name}\nout: {#Meta} & {#name: \"n\", val: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-10 closedness (pre-existing leak FIXED): embedding a CLOSED def closes the host, so a
      -- later MEET against it rejects an undeclared extra. `{#Meta} & {b}` REJECTS `b` (cue: `field
      -- not allowed`); pre-fix kue admitted `b` (the open-host embed-meet leak, no self-ref needed).
      fileName := "definitions/bug210_embed_meet_extra_rejected.expected",
      content :=
        match parseSource "#Meta: {a: 1}\nout: {#Meta} & {b: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-10 EDGE (deep nested self-ref): the embed's self-ref is read 2 frames deep
      -- (`spec: acme: val: Self.#name`). `hasSelfRefAtDepth` (in `defBodyHasSiblingSelfRef`)
      -- descends nested frames, so the deferral fires and the narrowing reaches the deep read.
      fileName := "definitions/bug210_deep_nested_self_ref_narrowed.expected",
      content :=
        match parseSource "#Meta: Self={#name: string, spec: {acme: {val: Self.#name}}}\nout: {#Meta} & {#name: \"deep\"}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-10 over-fire NEGATIVE / closedness boundary: the EMBED-FORM `{#Meta, b}` (sibling `b`
      -- declared in the SAME struct literal as the embed) ADMITS `b` — a sibling field is part of
      -- the embedding struct's own declaration, NOT a later meet. Distinguishes embed-form (admit)
      -- from meet-form (reject); both cue-faithful. Pins `embeddingClosesHost` does not over-close.
      fileName := "definitions/bug210_embed_form_sibling_admitted.expected",
      content :=
        match parseSource "#Meta: {a: 1}\nout: {#Meta, b: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-11: use-site narrowing of an INLINED def-OF-def (`#Defaults: #Defs & {…}` where `#Defs`
      -- embeds the self-ref `#Meta`) reaches the embedded `metadata.name`. The same-file analogue of
      -- the cross-package fixture (`testdata/modules/crosspkg_defofdef_narrowed`): `metadata.name`
      -- narrows to "x", not frozen `string`. Pre-fix kue bottomed.
      fileName := "definitions/bug211_defofdef_disj_narrowed.expected",
      content :=
        match parseSource "#Meta: Self={\n\t#name: string\n\tmetadata: name: Self.#name\n}\n#Defs: {\n\t#Meta\n\t#gateway_name: string\n\t#passthrough_hosts: [...string] | *[]\n\tkind: \"ListenerSet\"\n}\n#Defaults: #Defs & {#gateway_name: \"nginx\"}\nout: #Defaults & {#name: \"x\", #passthrough_hosts: [\"a.example.com\"]}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-11 SOUNDNESS: a use-site EXTRA the closed def-of-def does not declare (`notInDef`) is
      -- still REJECTED (`notInDef: _|_`) — narrowing-delivery is not laxity; closedness survives the
      -- def-of-def re-fold.
      fileName := "definitions/bug211_defofdef_rejects_extra.expected",
      content :=
        match parseSource "#Meta: Self={\n\t#name: string\n\tmetadata: name: Self.#name\n}\n#Defs: {\n\t#Meta\n\t#gateway_name: string\n\tkind: \"ListenerSet\"\n}\n#Defaults: #Defs & {#gateway_name: \"nginx\"}\nout: #Defaults & {#name: \"x\", notInDef: true}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-11 SOUNDNESS: a real CONFLICT (use-site `kind` vs the def's fixed `"ListenerSet"`) still
      -- bottoms the field (`kind: _|_`) AFTER the def-of-def narrowing-delivery fix.
      fileName := "definitions/bug211_defofdef_conflict.expected",
      content :=
        match parseSource "#Meta: Self={\n\t#name: string\n\tmetadata: name: Self.#name\n}\n#Defs: {\n\t#Meta\n\t#gateway_name: string\n\tkind: \"ListenerSet\"\n}\n#Defaults: #Defs & {#gateway_name: \"nginx\"}\nout: #Defaults & {#name: \"x\", kind: \"Other\"}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-12: a SELF-recursive CLOSED def (`#X: #X & {a:1}`) must still REJECT a use-site extra —
      -- self-recursion does not re-open the definition. `out: #X & {b: 2}` bottoms `b`. Pre-fix the
      -- `.conj` def body lost its closedness on the flatten and admitted `b`.
      fileName := "definitions/bug212_selfrec_closed_rejects_extra.expected",
      content :=
        match parseSource "#X: #X & {a: 1}\nout: #X & {b: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-12 ADMIT boundary: a field the closed self-recursive body DECLARES (`a`) still admits
      -- and narrows (`a: int` & `a: 5` → `a: 5`). The fix must not over-close.
      fileName := "definitions/bug212_selfrec_admits_declared.expected",
      content :=
        match parseSource "#X: #X & {a: int}\nout: #X & {a: 5}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-12 OPEN-TAIL boundary: a self-recursive def with an explicit `...` stays OPEN — the
      -- use-site extra is admitted (`b: 2`). The closer preserves a `defOpenViaTail` conjunct's
      -- openness, so this is NOT over-closed.
      fileName := "definitions/bug212_selfrec_opentail_admits.expected",
      content :=
        match parseSource "#X: #X & {a: 1, ...}\nout: #X & {b: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-12 PATTERN boundary: a use-site field MATCHING the closed self-recursive def's own
      -- pattern (`[=~"^p"]`) is ADMITTED (`p1: 5`); the closed-pattern allowed-set survives the
      -- cycle-flatten path. A non-matching extra is rejected (pinned in `Bug2xTests`).
      fileName := "definitions/bug212_selfrec_pattern_admits.expected",
      content :=
        match parseSource "#X: #X & {a: 1, [=~\"^p\"]: int}\nout: #X & {p1: 5}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-12b: a self-rec def whose literals are SPLIT across `&` (`#X & {a:1} & {c:3}`) closes its
      -- literals over their COMBINED allowed-set, so a use-site re-declaring an existing field
      -- (`& {c:3}`) ADMITS `{a:1,c:3}` — the def's OWN field. Pre-fix each split conjunct closed
      -- SEPARATELY and the meet over-closed (`c` absent from the `{a}` clause → bottom).
      fileName := "definitions/bug212b_multiconjunct_redeclare_admits.expected",
      content :=
        match parseSource "#X: #X & {a: 1} & {c: 3}\nout: #X & {c: 3}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-12b GENUINE-EXTRA: a field in NO split literal (`b`) is still rejected across the split —
      -- the union closes over `{a,c}` only, so `b` bottoms.
      fileName := "definitions/bug212b_multiconjunct_genuine_extra_rejects.expected",
      content :=
        match parseSource "#X: #X & {a: 1} & {c: 3}\nout: #X & {b: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-12b OPEN-TAIL across the split: a `...` in ONE split conjunct opens the UNION
      -- (`defOpenViaTail` dominates in `unionDefOpenness`), so a use-site extra (`b`) is ADMITTED.
      fileName := "definitions/bug212b_multiconjunct_opentail_admits.expected",
      content :=
        match parseSource "#X: #X & {a: 1} & {c: 3, ...}\nout: #X & {b: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-12b CONFLICT across the split: a shared label declared with conflicting values in two
      -- split conjuncts (`{a:1}` & `{a:2}`) still `.conj`-meets — `mergeDefinitionDecls` unions FIELDS,
      -- so the shared label's values meet and conflict to bottom.
      fileName := "definitions/bug212b_multiconjunct_conflict_bottoms.expected",
      content :=
        match parseSource "#X: #X & {a: 1} & {a: 2}\nout: #X\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-12 MUTUAL: a CLOSED mutual cycle (`#A: #B & {a}`, `#B: #A & {b}`) closes over the
      -- TRANSITIVE union of every cycle member's declared labels (`{a,b}`), so the transitively-declared
      -- fields ADMIT. cue OVER-REJECTS even the def's own field (lattice-questionable — see
      -- `cue-divergences.md`); Kue conforms to the lattice-principled answer, not to cue.
      fileName := "definitions/bug212_mutual_admits_transitive.expected",
      content :=
        match parseSource "#A: #B & {a: 1}\n#B: #A & {b: 2}\nout: #A & {a: 1, b: 2}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-12 MUTUAL GENUINE-EXTRA: a field in NO cycle member (`c` ∉ {a,b}) is rejected by the
      -- closed union — pins the under-close fix (pre-fix Kue admitted `c` because the cross-def back-ref
      -- bottomed `#B` and dropped its closedness, leaving `#B & {a}` OPEN).
      fileName := "definitions/bug212_mutual_genuine_extra_rejects.expected",
      content :=
        match parseSource "#A: #B & {a: 1}\n#B: #A & {b: 2}\nout: #A & {c: 3}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Bug2-12 MUTUAL OPEN-TAIL: a `...` in ONE cycle member opens the merged union, so a use-site
      -- extra is ADMITTED — the cycle close preserves a tail-opened body (`defOpenViaTail` dominates).
      fileName := "definitions/bug212_mutual_opentail_admits.expected",
      content :=
        match parseSource "#A: #B & {a: 1, ...}\n#B: #A & {b: 2}\nout: #A & {c: 3}\n" with
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
      -- SC-1e: a CLOSED struct (here the closed-pattern intersection `#A & #B`) met with an
      -- open-`...` partner stays CLOSED — closedness is monotone under meet, so the `...` does
      -- NOT re-open the closed conjunct. `x1` matches `#A`'s `^x` but not `#B`'s `^y`, so it
      -- bottoms exactly as in the no-`...` control (`sc1b_closed_pattern_intersection`), and the
      -- result carries NO `...`. Pre-SC-1e the tail-arm dropped `bothClauses` and re-opened: it
      -- admitted `x1: 5` and emitted a trailing `...`.
      fileName := "definitions/sc1e_closed_open_tail_rejects.expected",
      content :=
        match parseSource
            "#A: {[=~\"^x\"]: int}\n#B: {[=~\"^y\"]: int}\nout: (#A & #B) & {x1: 5, ...}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- SC-1e admit-side: the open-`...` partner does not re-open, but a field the closed
      -- allowed-set PERMITS still unifies. `x1` matches `^x`, so `x1: 5` survives; the `...` is
      -- dropped (the result is closed to `^x`). Guards that the fix rejects only the forbidden
      -- extras, not every tail-side field.
      fileName := "definitions/sc1e_closed_open_tail_admits.expected",
      content :=
        match parseSource "#A: {[=~\"^x\"]: int}\nout: (#A & {x1: 5}) & {x1: 5, ...}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- SC-1e field-closed arm: the closed operand `#C: {a: int}` is FIELD-closed (no patterns),
      -- so it routes through the `struct × structTail` arm, NOT the tail×patterns catch-all. That
      -- arm dropped the clause too — `b` (not in `#C`) bottoms and the `...` is dropped. Pins the
      -- SC-1e fix across ALL tail-bearing arms, not just the pattern-closed catch-all.
      fileName := "definitions/sc1e_field_closed_open_tail_rejects.expected",
      content :=
        match parseSource "#C: {a: int}\nout: #C & {a: 1, b: 2, ...}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- EMBED-CLOSE-1 pin: kue rejects `y1` (∉ `#A`'s `^x`) in BOTH the embed form `{#A, y1}` and
      -- the meet form `#A & {y1}` — closedness is preserved through embedding, monotone like
      -- SC-1e. cue SELF-CONTRADICTS (admits the embed form, rejects the meet form); kue follows the
      -- spec and stays consistent (recorded in cue-divergences.md). Neither form carries a `...`, so
      -- this is unaffected by the SC-1e tail-arm fix — the pin locks the existing-correct behavior.
      fileName := "definitions/embed_close1_pin.expected",
      content :=
        match parseSource "#A: {[=~\"^x\"]: int}\nembed: {#A, y1: 5}\nmeet: #A & {y1: 5}\n" with
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
    -- DYN-DEF-1 regression pins: a definition's dynamic field, dropped pre-fix when its key was
    -- narrowed at the use site, is now re-keyed (an abstract key DEFERS as a residual, never
    -- drops). Parse-driven so the real dyn-field expand/defer path flows through. Oracle cue
    -- v0.16.1-exact. (The `#Add`/`#M` def-display line shows the held residual key as `@d.i` —
    -- the pre-existing reference rendering; the `out` re-key is the load-bearing observable.)
    {
      -- The named witness: `(kind)` keyed on a `string` field narrowed to `"specific"` re-keys
      -- to `specific: "m"`. cue → `out: {kind: "specific", specific: "m"}`.
      fileName := "definitions/dyndef_dynfield_rekeyed_by_narrowing.expected",
      content :=
        match parseSource "#Add: {kind: string, (kind): \"m\"}\nout: #Add & {kind: \"specific\"}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Regression: a key already concrete in the def keys eagerly (the path the fix must not
      -- disturb). cue → `out: {kind: "fixed", fixed: "m"}`.
      fileName := "definitions/dyndef_dynfield_concrete_key.expected",
      content :=
        match parseSource "#K: {kind: \"fixed\", (kind): \"m\"}\nout: #K\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- Plain struct (no def): the same key, narrowed by a later conjunct in the SAME struct,
      -- re-keys with a fully concrete display (no residual). cue → `out: {kind: "x", x: "m"}`.
      fileName := "definitions/dyndef_dynfield_plain_struct_rekeyed.expected",
      content :=
        match parseSource "out: {kind: string, (kind): \"m\", kind: \"x\"}\n" with
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
    -- SC-4 closedness pins (cue+spec AGREE on direct paths; oracle-checked v0.16.1). A def's
    -- HIDDEN-field (`_h`) nested PLAIN-struct value closes EXACTLY like a regular-field one
    -- (obligation 1) — visibility of the carrying field does not change whether its nested value
    -- is closed. A nested `...` under the hidden field still opens it.
    {
      -- hidden nested closes: `#A:{_h:{x:int}}` & `{_h:{x:1,extra:2}}` → `out._h.extra: _|_`.
      fileName := "definitions/sc4_hidden_nested_closes.expected",
      content :=
        match parseSource "#A: {_h: {x: int}}\nout: #A & {_h: {x: 1, extra: 2}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- a nested `...` under the hidden field keeps it OPEN — `extra` admitted (regression guard).
      fileName := "definitions/sc4_hidden_nested_tail_stays_open.expected",
      content :=
        match parseSource "#A: {_h: {x: int, ...}}\nout: #A & {_h: {x: 1, extra: 2}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- depth-2 hidden→regular nested struct closes recursively (`out._h.r.extra: _|_`).
      fileName := "definitions/sc4_hidden_nested_depth2.expected",
      content :=
        match parseSource "#A: {_h: {r: {b: int}}}\nout: #A & {_h: {r: {b: 1, extra: 2}}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- LET analog: a let-bound struct read into a regular field of a closed def closes
      -- (`out.v.extra: _|_`); cue v0.16.1 agrees.
      fileName := "definitions/sc4_let_read_nested_closes.expected",
      content :=
        match parseSource "#A: {let _t = {x: 5}, v: _t}\nout: #A & {v: {extra: 2}}\n" with
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
      -- D#1d: a comprehension body's `...` tail is BODY-LOCAL — emit the named fields, drop the
      -- tail (it does not propagate out of the `for`). Pre-fix the `.struct _ _ none [] _` match
      -- dropped the tail-bearing body wholesale (`a: 1` vanished). cue v0.16.1 → `out: {a: 1}`.
      fileName := "comprehensions/comprehension_body_tail_local.expected",
      content :=
        match parseSource "out: {for x in [\"s\"] {a: 1, ...}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- D#1d: a comprehension body's `[pattern]:` constraint is BODY-LOCAL — same as the tail.
      -- cue v0.16.1 → `out: {a: 1}` (the pattern bounds the body block, not the enclosing struct).
      fileName := "comprehensions/comprehension_body_pattern_local.expected",
      content :=
        match parseSource "out: {for x in [\"s\"] {a: 1, [string]: int}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
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
      -- D#1c: a CONCRETE non-bool guard (`if "x"`) is a TYPE ERROR (cue: `cannot use "x" (type
      -- string) as type bool`), NOT a silent drop. The comprehension carries a `.nonBoolGuard`
      -- bottom, so `out` is `_|_`.
      fileName := "comprehensions/guard_nonbool_string.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"out", .regular,
                  .structComp []
                    [.comprehension [.guard (.prim (.string "x"))]
                      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])]
                    .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      -- D#1c: a concrete non-bool INT guard (`if 3`) is likewise a type error.
      fileName := "comprehensions/guard_nonbool_int.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"out", .regular,
                  .structComp []
                    [.comprehension [.guard (.prim (.int 3))]
                      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])]
                    .regularOpen⟩
              ] .regularOpen none []))
    },
    {
      -- D#1c list twin: a concrete non-bool guard in a LIST comprehension is a type error; the
      -- bottom occupies the element slot (`[1, _|_]`), the same convention as the D#1a list twin.
      fileName := "comprehensions/list_guard_nonbool.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"out", .regular,
                  .list
                    [
                      .prim (.int 1),
                      .listComprehension [.guard (.prim (.string "z"))]
                        (.structComp [] [.prim (.int 2)] .regularOpen)
                    ]⟩
              ] .regularOpen none []))
    },
    {
      -- D#1b: an INCOMPLETE guard (`if x` with `x: bool`) cannot be decided, so the comprehension
      -- DEFERS — it stays a residual `.structComp` carrying the unresolved `.comprehension` (cue
      -- eval holds `if x {…}`; `cue export` then errors `incomplete bool`). NOT a silent drop.
      -- Kue renders the resolved guard ref as `@d.i` (a known display divergence; cue prints `x`).
      fileName := "comprehensions/guard_incomplete_defers.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"x", .regular, .kind .bool⟩,
                ⟨"out", .regular,
                  .structComp []
                    [.comprehension [.guard (.ref "x")]
                      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])]
                    .regularOpen⟩
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
      -- `x: {#a: 1, 5}`: only-non-output struct + scalar embed → embeddedScalar carrier with decls.
      -- Manifests as `5`, keeps `.#a` selectable. The scalar analog of `list_embedding_hidden`.
      fileName := "structs/scalar_embedding_with_decls.expected",
      content :=
        match parseSource "x: {#a: 1, 5}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- `x: {#a: 1, 5}` + `y: x.#a`: the carrier's hidden decl is selectable (`y → 1`).
      fileName := "structs/scalar_embedding_decl_select.expected",
      content :=
        match parseSource "x: {#a: 1, 5}\ny: x.#a\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- `x: {#a: 1, #b: 2, 5}`: multiple decls ride alongside the scalar carrier, all selectable.
      fileName := "structs/scalar_embedding_multiple_decls.expected",
      content :=
        match parseSource "x: {#a: 1, #b: 2, 5}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- A carrier IS its scalar in every operator slot (`resolveOperand` unwrap): compare, arith,
      -- and unary all see `5`, not the struct. Oracle-matched against cue v0.16.1.
      fileName := "structs/scalar_embedding_operand_position.expected",
      content :=
        match parseSource "lt: {#a: 1, 5} < 6\nsum: {#a: 1, 5} + 10\nneg: -{#a: 1, 5}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- B3: `for x in {#a:1,[1,2]}` iterates the EMBEDDED LIST (not zero times) → `[1, 2]`.
      fileName := "comprehensions/for_over_embedded_list.expected",
      content :=
        match parseSource "out: [for x in {#a: 1, [1, 2]} {x}]\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- fix-slice (d), E#4: a CONCRETE non-iterable `for` source is a type error (spec mandates
      -- range over a list/struct), NOT a silent zero-iter. In a LIST comprehension the bottom is
      -- the single element (`[_|_]`); cue agrees (`cannot range over 5 …`).
      fileName := "comprehensions/for_scalar_type_error.expected",
      content :=
        match parseSource "out: [for x in 5 {x}]\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- fix-slice (d): the STRUCT-comprehension twin — a concrete non-iterable source bottoms the
      -- whole struct (`out: _|_`), the same shape as a struct-comprehension non-bool guard.
      fileName := "comprehensions/for_struct_scalar_type_error.expected",
      content :=
        match parseSource "out: {for x in 5 {a: x}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- fix-slice (d): a GENUINELY-UNRESOLVED source (`_`, which may still resolve to a
      -- list/struct) DEFERS — the comprehension stays a residual, NOT a type error. cue holds it
      -- too; Kue renders the resolved-ref residual with `@depth.index` (D#1b display-only family).
      fileName := "comprehensions/for_top_source_defers.expected",
      content :=
        match parseSource "y: _\nout: [for x in y {x}]\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- PA-1: a `for` source that EVALUATES to bottom (`1 & 2`) propagates the bottom (D#1a —
      -- short-circuits the comprehension), NOT defers as incomplete. In a LIST comprehension the
      -- bottom is the single element (`[_|_]`), the same shape as the concrete-non-iterable case.
      fileName := "comprehensions/for_bottom_source_list.expected",
      content :=
        match parseSource "out: [for x in (1 & 2) {x}]\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- PA-1: the STRUCT-comprehension twin — a bottom source bottoms the whole struct (`out: _|_`).
      fileName := "comprehensions/for_bottom_source_struct.expected",
      content :=
        match parseSource "out: {for x in (1 & 2) {a: x}}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- PA-1: the VALUE divergence — a bottom `for` source in a disjunction arm is ELIMINATED
      -- (`⊥ | x = x`), leaving `[5]`. Before the fix the arm deferred as incomplete and was
      -- retained, yielding "ambiguous value". cue agrees (`[5]`).
      fileName := "comprehensions/for_bottom_source_disjunction.expected",
      content :=
        match parseSource "out: [for x in (1 & 2) {x}] | [5]\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
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
      -- D#3 basic `let` clause in a list comprehension: `for x in [1,2,3] let y = x*2 {a: y}`
      -- → `[{a:2},{a:4},{a:6}]`. The let binds `y` in a +1 frame visible to the body.
      fileName := "comprehensions/list_let_basic.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn none "x" (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]),
                       .letClause "y" (.binary .mul (.ref "x") (.prim (.int 2)))]
                      (.structComp [] [.dynamicField (.prim (.string "a")) .regular (.ref "y")]
                        .regularOpen)]⟩
              ] .regularOpen none []))
    },
    {
      -- D#3 a `let` binding read by a LATER `if` guard (frame accounting across the let frame):
      -- `for x in [1..4] let half = div(x,2) if half*2 == x {even: x}` → keeps the evens
      -- `[{even:2},{even:4}]`. Proves the guard resolves the let-bound `half` at its post-let depth.
      fileName := "comprehensions/list_let_in_guard.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn none "x"
                        (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3), .prim (.int 4)]),
                       .letClause "half" (.builtinCall "div" [.ref "x", .prim (.int 2)]),
                       .guard (.binary .eq
                         (.binary .mul (.ref "half") (.prim (.int 2))) (.ref "x"))]
                      (.structComp [] [.dynamicField (.prim (.string "even")) .regular (.ref "x")]
                        .regularOpen)]⟩
              ] .regularOpen none []))
    },
    {
      -- D#3 multiple chained `let`s, the second reading the first, then an `if` on the second:
      -- `let y = x*2 let z = y+1 if z > 3 {a: z}` → `[{a:5},{a:7}]`. Each `let` is its own +1 frame.
      fileName := "comprehensions/list_let_multiple.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn none "x" (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]),
                       .letClause "y" (.binary .mul (.ref "x") (.prim (.int 2))),
                       .letClause "z" (.binary .add (.ref "y") (.prim (.int 1))),
                       .guard (.binary .gt (.ref "z") (.prim (.int 3)))]
                      (.structComp [] [.dynamicField (.prim (.string "a")) .regular (.ref "z")]
                        .regularOpen)]⟩
              ] .regularOpen none []))
    },
    {
      -- D#3 the frame-accounting case: a `for` AFTER a `let`. `for x in [1,2] let y = x+10
      -- for w in [y, y+1] {v: w}` → `[{v:11},{v:12},{v:12},{v:13}]`. The second `for`'s source +
      -- body must still resolve `y` (and the first `x`) correctly across the intervening let frame.
      fileName := "comprehensions/list_let_for_after.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn none "x" (.list [.prim (.int 1), .prim (.int 2)]),
                       .letClause "y" (.binary .add (.ref "x") (.prim (.int 10))),
                       .forIn none "w"
                         (.list [.ref "y", .binary .add (.ref "y") (.prim (.int 1))])]
                      (.structComp [] [.dynamicField (.prim (.string "v")) .regular (.ref "w")]
                        .regularOpen)]⟩
              ] .regularOpen none []))
    },
    {
      -- D#3 a `let` clause SHADOWING an outer field: outer `y:"outer"` is untouched; the
      -- comprehension body sees the let `y`. `out: [for x in [1,2] let y = x*10 {v: y}]` →
      -- `[{v:10},{v:20}]`, `y` stays `"outer"`. Lexical innermost-wins.
      fileName := "comprehensions/let_shadows_outer.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"y", .regular, .prim (.string "outer")⟩,
                ⟨"out", .regular,
                  .list
                    [.listComprehension
                      [.forIn none "x" (.list [.prim (.int 1), .prim (.int 2)]),
                       .letClause "y" (.binary .mul (.ref "x") (.prim (.int 10)))]
                      (.structComp [] [.dynamicField (.prim (.string "v")) .regular (.ref "y")]
                        .regularOpen)]⟩
              ] .regularOpen none []))
    },
    {
      -- D#3 a `let` clause in a STRUCT comprehension (not just list): the let-bound value feeds a
      -- dynamic field. `for x in [1,2] let y = x+100 {"k\(x)": y}` → `{k1:101, k2:102}`.
      fileName := "comprehensions/struct_let_basic.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"out", .regular,
                  .structComp
                    []
                    [.comprehension
                      [.forIn none "x" (.list [.prim (.int 1), .prim (.int 2)]),
                       .letClause "y" (.binary .add (.ref "x") (.prim (.int 100)))]
                      (.structComp
                        []
                        [.dynamicField (.interpolation [.prim (.string "k"), .ref "x"])
                          .regular (.ref "y")]
                        .regularOpen)]
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
      fileName := "builtins/math_pow.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"powSquare", .regular, .builtinCall "math.Pow" [.prim (.int 2), .prim (.int 10)]⟩,
                ⟨"powZeroExp", .regular, .builtinCall "math.Pow" [.prim (.int 5), .prim (.int 0)]⟩,
                ⟨"powBaseZero", .regular, .builtinCall "math.Pow" [.prim (.int 0), .prim (.int 5)]⟩,
                ⟨"powFloatBase", .regular, .builtinCall "math.Pow" [.prim (.float "1.5"), .prim (.int 3)]⟩,
                ⟨"powNegBase", .regular, .builtinCall "math.Pow" [.prim (.int (-2)), .prim (.int 3)]⟩,
                ⟨"powNegBaseEv", .regular, .builtinCall "math.Pow" [.prim (.int (-3)), .prim (.int 4)]⟩,
                ⟨"powFloatPow", .regular, .builtinCall "math.Pow" [.prim (.float "2.5"), .prim (.int 4)]⟩,
                ⟨"powWholeFlt", .regular, .builtinCall "math.Pow" [.prim (.int 3), .prim (.float "2.0")]⟩,
                ⟨"powBig", .regular, .builtinCall "math.Pow" [.prim (.int 10), .prim (.int 20)]⟩,
                ⟨"powDecExact", .regular, .builtinCall "math.Pow" [.prim (.float "0.1"), .prim (.int 2)]⟩,
                ⟨"powOne", .regular, .builtinCall "math.Pow" [.prim (.int 7), .prim (.int 1)]⟩,
                ⟨"powNegInt", .regular, .builtinCall "math.Pow" [.prim (.int 2), .prim (.int (-3))]⟩,
                ⟨"powNegInt10", .regular, .builtinCall "math.Pow" [.prim (.int 10), .prim (.int (-2))]⟩,
                ⟨"powNegOneBs", .regular, .builtinCall "math.Pow" [.prim (.int 1), .prim (.int (-5))]⟩,
                ⟨"powNegRep", .regular, .builtinCall "math.Pow" [.prim (.int 3), .prim (.int (-1))]⟩,
                ⟨"powZeroNeg", .regular, .builtinCall "math.Pow" [.prim (.int 0), .prim (.int (-1))]⟩,
                ⟨"powQuarter", .regular, .builtinCall "math.Pow" [.prim (.int 2), .prim (.float "0.25")]⟩,
                ⟨"powTenth", .regular, .builtinCall "math.Pow" [.prim (.int 2), .prim (.float "0.1")]⟩,
                ⟨"powThreeHalf", .regular, .builtinCall "math.Pow" [.prim (.int 4), .prim (.float "1.5")]⟩,
                ⟨"powCubeRoot", .regular,
                  .builtinCall "math.Pow"
                    [.prim (.int 8), .prim (.float "0.3333333333333333333333333333333333")]⟩,
                ⟨"powNegBaseFr", .regular, .builtinCall "math.Pow" [.prim (.int (-2)), .prim (.float "0.25")]⟩,
                ⟨"powZeroFr", .regular, .builtinCall "math.Pow" [.prim (.int 0), .prim (.float "0.25")]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/math_sqrt.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"sqrtTwo", .regular, .builtinCall "math.Sqrt" [.prim (.int 2)]⟩,
                ⟨"sqrtFive", .regular, .builtinCall "math.Sqrt" [.prim (.int 5)]⟩,
                ⟨"sqrtPerfect", .regular, .builtinCall "math.Sqrt" [.prim (.int 144)]⟩,
                ⟨"sqrtFour", .regular, .builtinCall "math.Sqrt" [.prim (.int 4)]⟩,
                ⟨"sqrtHundred", .regular, .builtinCall "math.Sqrt" [.prim (.int 100)]⟩,
                ⟨"sqrtBigSq", .regular, .builtinCall "math.Sqrt" [.prim (.int 1000000)]⟩,
                ⟨"sqrtZero", .regular, .builtinCall "math.Sqrt" [.prim (.int 0)]⟩,
                ⟨"sqrtOne", .regular, .builtinCall "math.Sqrt" [.prim (.int 1)]⟩,
                ⟨"sqrtDecSq", .regular, .builtinCall "math.Sqrt" [.prim (.float "2.25")]⟩,
                ⟨"sqrtDecQtr", .regular, .builtinCall "math.Sqrt" [.prim (.float "0.25")]⟩,
                ⟨"sqrtThree", .regular, .builtinCall "math.Sqrt" [.prim (.int 3)]⟩,
                ⟨"powHalf", .regular, .builtinCall "math.Pow" [.prim (.int 2), .prim (.float "0.5")]⟩,
                ⟨"powHalfSq", .regular, .builtinCall "math.Pow" [.prim (.int 4), .prim (.float "0.5")]⟩,
                ⟨"powHalfDec", .regular,
                  .builtinCall "math.Pow" [.prim (.float "2.25"), .prim (.float "0.5")]⟩
              ] .regularOpen none []))
    },
    {
      fileName := "builtins/list_sort.expected",
      content :=
        let ascending := (stdlibPackageValue? "list" "Ascending").getD .bottom
        let descending := (stdlibPackageValue? "list" "Descending").getD .bottom
        -- Inline comparators, built as the same AST the parser emits for `{x: _, y: _, less: …}`.
        let lessXY (op : BinaryOp) : Value :=
          mkStruct
            [⟨"x", .regular, .top⟩, ⟨"y", .regular, .top⟩,
             ⟨"less", .regular, .binary op (.ref "x") (.ref "y")⟩]
            .regularOpen none []
        let kStruct (k : Int) : Value := mkStruct [⟨"k", .regular, .prim (.int k)⟩] .regularOpen none []
        let kvStruct (k : Int) (v : String) : Value :=
          mkStruct [⟨"k", .regular, .prim (.int k)⟩, ⟨"v", .regular, .prim (.string v)⟩] .regularOpen none []
        -- Comparator over a `.k` sub-field: `{x: {k: _}, y: {k: _}, less: x.k < y.k}`.
        let lessByK : Value :=
          mkStruct
            [⟨"x", .regular, mkStruct [⟨"k", .regular, .top⟩] .regularOpen none []⟩,
             ⟨"y", .regular, mkStruct [⟨"k", .regular, .top⟩] .regularOpen none []⟩,
             ⟨"less", .regular, .binary .lt (.selector (.ref "x") "k") (.selector (.ref "y") "k")⟩]
            .regularOpen none []
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"ascending", .regular,
                  .builtinCall "list.Sort" [.list [.prim (.int 3), .prim (.int 1), .prim (.int 2)], ascending]⟩,
                ⟨"descending", .regular,
                  .builtinCall "list.Sort" [.list [.prim (.int 1), .prim (.int 3), .prim (.int 2)], descending]⟩,
                ⟨"alreadySort", .regular,
                  .builtinCall "list.Sort" [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], ascending]⟩,
                ⟨"empty", .regular, .builtinCall "list.Sort" [.list [], ascending]⟩,
                ⟨"single", .regular, .builtinCall "list.Sort" [.list [.prim (.int 5)], ascending]⟩,
                ⟨"duplicates", .regular,
                  .builtinCall "list.Sort"
                    [.list [.prim (.int 3), .prim (.int 1), .prim (.int 2), .prim (.int 1), .prim (.int 3)], ascending]⟩,
                ⟨"strings", .regular,
                  .builtinCall "list.Sort"
                    [.list [.prim (.string "banana"), .prim (.string "apple"), .prim (.string "cherry")], ascending]⟩,
                ⟨"negatives", .regular,
                  .builtinCall "list.Sort"
                    [.list [.prim (.int 3), .prim (.int (-1)), .prim (.int 2), .prim (.int (-5)), .prim (.int 0)], ascending]⟩,
                ⟨"inlineCmp", .regular,
                  .builtinCall "list.Sort" [.list [.prim (.int 3), .prim (.int 1), .prim (.int 2)], lessXY .lt]⟩,
                ⟨"byField", .regular,
                  .builtinCall "list.Sort" [.list [kStruct 3, kStruct 1, kStruct 2], lessByK]⟩,
                ⟨"stableTies", .regular,
                  .builtinCall "list.SortStable"
                    [.list [kvStruct 1 "a", kvStruct 1 "b", kvStruct 0 "c", kvStruct 1 "d"], lessByK]⟩,
                ⟨"stableEmpty", .regular, .builtinCall "list.SortStable" [.list [], ascending]⟩
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
      fileName := "builtins/strings_case_unicode.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"upLatin", .regular, .builtinCall "strings.ToUpper" [.prim (.string "café")]⟩,
                ⟨"loLatin", .regular, .builtinCall "strings.ToLower" [.prim (.string "CAFÉ")]⟩,
                ⟨"upGreek", .regular, .builtinCall "strings.ToUpper" [.prim (.string "αβγ")]⟩,
                ⟨"loGreek", .regular, .builtinCall "strings.ToLower" [.prim (.string "ΑΒΓ")]⟩,
                ⟨"upCyrillic", .regular, .builtinCall "strings.ToUpper" [.prim (.string "я")]⟩,
                ⟨"loCyrillic", .regular, .builtinCall "strings.ToLower" [.prim (.string "Я")]⟩,
                ⟨"upMicro", .regular, .builtinCall "strings.ToUpper" [.prim (.string "µ")]⟩,
                ⟨"upYdiaer", .regular, .builtinCall "strings.ToUpper" [.prim (.string "ÿ")]⟩,
                ⟨"upSharpS", .regular, .builtinCall "strings.ToUpper" [.prim (.string "ß")]⟩,
                ⟨"upUncased", .regular, .builtinCall "strings.ToUpper" [.prim (.string "中→")]⟩,
                ⟨"upMixed", .regular,
                  .builtinCall "strings.ToUpper" [.prim (.string "café 123 αβγ я 中")]⟩,
                ⟨"loMixed", .regular,
                  .builtinCall "strings.ToLower" [.prim (.string "CAFÉ 123 ΑΒΓ Я 中")]⟩,
                ⟨"titleNonAscii", .regular,
                  .builtinCall "strings.ToTitle" [.prim (.string "über alles")]⟩
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
      -- ALIASED builtin imports across every family. The Lean port builds the CANONICAL
      -- builtin-call AST (`json.Marshal`, `strings.ToUpper`, …) directly; the CLI port parses the
      -- `.cue` (whose imports are ALIASED: `j`/`s`/`m`/`l`/`b`/`y`) and the post-parse alias
      -- canonicalization must rewrite each head to the same canonical name. Both matching
      -- `.expected` pins that an aliased call resolves identically to its unaliased form.
      fileName := "builtins/aliased_builtin.expected",
      content :=
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"jsonMarshal", .regular,
                  .builtinCall "json.Marshal" [mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []]⟩,
                ⟨"jsonList", .regular,
                  .builtinCall "json.Marshal" [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]]⟩,
                ⟨"strUpper", .regular, .builtinCall "strings.ToUpper" [.prim (.string "hello")]⟩,
                ⟨"strLower", .regular, .builtinCall "strings.ToLower" [.prim (.string "WORLD")]⟩,
                ⟨"strContains", .regular,
                  .builtinCall "strings.Contains" [.prim (.string "foobar"), .prim (.string "oob")]⟩,
                ⟨"mathPow", .regular, .builtinCall "math.Pow" [.prim (.int 2), .prim (.int 10)]⟩,
                ⟨"mathSqrt", .regular, .builtinCall "math.Sqrt" [.prim (.int 144)]⟩,
                ⟨"listSum", .regular,
                  .builtinCall "list.Sum" [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3), .prim (.int 4)]]⟩,
                ⟨"listConcat", .regular,
                  .builtinCall "list.Concat"
                    [.list [.list [.prim (.int 1), .prim (.int 2)], .list [.prim (.int 3)]]]⟩,
                ⟨"b64Encode", .regular,
                  .builtinCall "base64.Encode" [.prim .null, .prim (.string "hi")]⟩,
                ⟨"yamlMarshal", .regular,
                  .builtinCall "yaml.Marshal" [mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []]⟩
              ] .regularOpen none []))
    },
    {
      -- ALIASED stdlib CONSTANTS (the no-call analog of `aliased_builtin` above). The Lean port
      -- builds the CANONICAL AST: `list.Sort` driven by `stdlibPackageValue? "list" "Ascending"/
      -- "Descending"` and the bare `list.Comparer` constant. The CLI port parses the `.cue` whose
      -- import is ALIASED (`import l "list"`), so the post-parse pass must re-resolve `l.Ascending`/
      -- `l.Descending`/`l.Comparer` to the SAME comparator structs. Both matching `.expected` pins
      -- that an aliased constant resolves identically to its unaliased form.
      fileName := "builtins/aliased_list_const.expected",
      content :=
        let ascending := (stdlibPackageValue? "list" "Ascending").getD .bottom
        let descending := (stdlibPackageValue? "list" "Descending").getD .bottom
        let comparer := (stdlibPackageValue? "list" "Comparer").getD .bottom
        formatTopLevel
          (resolveAndEval
            (mkStruct [
                ⟨"asc", .regular,
                  .builtinCall "list.Sort"
                    [.list [.prim (.int 3), .prim (.int 1), .prim (.int 2)], ascending]⟩,
                ⟨"desc", .regular,
                  .builtinCall "list.Sort"
                    [.list [.prim (.int 3), .prim (.int 1), .prim (.int 2)], descending]⟩,
                ⟨"cmp", .regular, comparer⟩
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
    },
    {
      -- A-EN3-DYN (REACHABLE wrong-result Violation): a comprehension inside an embedded def reads a
      -- regular def sibling (`kind`) SOLELY through a DYNAMIC field's value (`("k"): kind`). The
      -- sibling is narrowed at the use site (`patch: {kind: "specific", #Add}`), but two parallel
      -- depth-mirror bugs over-scanned the dyn-field value by one frame: `defFrameRefIndices`
      -- (`dynValShift=1`) missed `kind` as a splice seed, and `hasSelfRefAtDepth` (`+1` on the
      -- dyn-field value) made `defBodyHasSiblingSelfRef` miss the self-ref, gating OFF the deferral
      -- the narrowing needs. The def eagerly evaluated `out` against `kind: string`, so cue's
      -- `[{k: "specific"}]` became kue's incomplete `string`. The resolver pushes NO frame for a
      -- dynamic field (`Resolve.lean` resolves key+value in the parent scope), so both scans must
      -- read the value at the PARENT depth (no `+1`). Oracle cue v0.16.1 → `patch.out: [{k: "specific"}]`.
      fileName := "comprehensions/dynfield_comprehension_narrowed_sibling.expected",
      content :=
        match parseSource
            "#Add: {#kind: string, kind: string, out: [for x in [\"a\"] {(\"k\"): kind}]}\npatch: {#kind: \"specific\", kind: \"specific\", #Add}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- A-EN3-DYN static control (regression): the SAME shape with a STATIC body field (`k: kind`)
      -- instead of the dynamic `("k"): kind`. This already evaluated correctly before the fix (the
      -- self-ref `kind` resolves at the for-body struct frame, which the deferral gate scans at the
      -- right depth), and MUST stay correct — pinning that the dyn-field fix did not perturb the
      -- static comprehension path. Oracle cue v0.16.1 → `patch.out: [{k: "specific"}]` (identical
      -- to the dynamic case).
      fileName := "comprehensions/static_comprehension_narrowed_sibling.expected",
      content :=
        match parseSource
            "#Add: {#kind: string, kind: string, out: [for x in [\"a\"] {k: kind}]}\npatch: {#kind: \"specific\", kind: \"specific\", #Add}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- A-EN3-DYN multi-level: the dyn-field KEY reads a narrowed sibling (`(tag)`) AND the value
      -- reads another narrowed sibling one struct DEEPER (`{label: name}`). Exercises both halves of
      -- the `hasSelfRefAtDepth` dyn-field fix — the key scan (previously dropped entirely) and the
      -- nested-value scan at the parent depth. Standalone `#Add.out` HOLDS the abstract-keyed field
      -- residual (`[{(tag): {label: name}}]`; DYN-DEF-1 — an abstract key defers, not drops); the
      -- use site concretes both. Oracle cue v0.16.1 → `patch.out: [{t: {label: "n"}}]`.
      fileName := "comprehensions/dynfield_comprehension_key_and_nested_value.expected",
      content :=
        match parseSource
            "#Add: {tag: string, name: string, out: [for x in [\"a\"] {(tag): {label: name}}]}\npatch: {tag: \"t\", name: \"n\", #Add}\n" with
        | .ok value => formatResolvedTopLevel value
        | .error error => s!"parse error: {error.message}"
    },
    {
      -- A-EN3-DYN unaffected control: a dyn-field value that reads ONLY the loop variable (`x`), no
      -- def sibling. The fix widened the deferral gate to scan dyn-field key+value at the parent
      -- depth; this pins that the widening does NOT spuriously defer/alter a dyn field with no
      -- sibling self-ref (the value is concrete from the loop, narrowing-independent). Oracle cue
      -- v0.16.1 → `patch.out: [{k: "a"}]` (same standalone and at the use site).
      fileName := "comprehensions/dynfield_comprehension_no_sibling_read.expected",
      content :=
        match parseSource
            "#Add: {kind: string, out: [for x in [\"a\"] {(\"k\"): x}]}\npatch: {kind: \"specific\", #Add}\n" with
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
