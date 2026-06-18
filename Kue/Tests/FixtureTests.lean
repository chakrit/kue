import Kue.Tests.FixturePorts

namespace Kue

theorem fixture_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3))⟩,
            ⟨"cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b"))⟩
          ] .regularOpen none []))
      = "sum: 3\ndiff: 2\ncat: \"ab\"" := by
  native_decide

theorem fixture_bytes_additive_expressions :
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
      = "bytes: 'abcd'\nleft: 'abc'" := by
  native_decide

theorem fixture_float_additive_expressions :
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
      = "floatSum: 3.75\nintFloat: 3.5\nfloatSub: 3.5\nwhole: 3.0\nexp: 1002.0\nsmall: 0.3" := by
  native_decide

theorem fixture_multiplication_expressions :
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
      = "mul: 12\nprecedence: 7\nleft: 24" := by
  native_decide

theorem fixture_division_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"div", .regular, .binary .div (.prim (.int 5)) (.prim (.int 2))⟩,
            ⟨"whole", .regular, .binary .div (.prim (.int 6)) (.prim (.int 3))⟩,
            ⟨"third", .regular, .binary .div (.prim (.int 1)) (.prim (.int 3))⟩,
            ⟨"negative", .regular, .binary .div (.prim (.int (-5))) (.prim (.int 2))⟩
          ] .regularOpen none []))
      = "div: 2.5\nwhole: 2.0\nthird: 0.3333333333333333333333333333333333\nnegative: -2.5" := by
  native_decide

theorem fixture_integer_keyword_expressions :
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
      = "divValue: -3\nmodValue: 2\nquoValue: -2\nremValue: -1\nprecedence: 3" := by
  native_decide

theorem fixture_equality_expressions :
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
      = "same: true\ndiff: true\ntext: false\nprecedence: true" := by
  native_decide

theorem fixture_ordering_expressions :
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
      = "lt: true\nle: true\ngt: true\nge: false\nslt: true\nprecedence: true" := by
  native_decide

theorem fixture_numeric_comparison_expressions :
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
      = "lt: true\nle: true\ngt: true\nge: true\neq: true\nne: false" := by
  native_decide

theorem fixture_logical_expressions :
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
      = "andFalse: false\norTrue: true\nandCmp: true\norCmp: true\ngrouped: true" := by
  native_decide

theorem fixture_logical_not_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"notFalse", .regular, .unary .boolNot (.prim (.bool false))⟩,
            ⟨"notCmp", .regular, .unary .boolNot (.binary .lt (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"double", .regular, .unary .boolNot (.unary .boolNot (.prim (.bool true)))⟩
          ] .regularOpen none []))
      = "notFalse: true\nnotCmp: false\ndouble: true" := by
  native_decide

theorem fixture_unary_numeric_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"negGroup", .regular, .unary .numNeg (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"posGroup", .regular, .unary .numPos (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"negRefBase", .regular, .prim (.int 3)⟩,
            ⟨"negRef", .regular, .unary .numNeg (.ref "negRefBase")⟩,
            ⟨"precedence", .regular, .binary .mul (.unary .numNeg (.prim (.int 2))) (.prim (.int 3))⟩
          ] .regularOpen none []))
      = "negGroup: -3\nposGroup: 3\nnegRefBase: 3\nnegRef: -3\nprecedence: -6" := by
  native_decide

theorem fixture_regex_match_expressions :
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
      = "match: true\nmiss: false\nnotMatch: true\nnotMiss: false\nprecedence: true" := by
  native_decide

theorem fixture_kind_meet_int :
    formatField "x" (meet (.kind .int) (.prim (.int 1))) = "x: 1" := by
  native_decide

theorem fixture_builtin_reference_eval :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"x", .regular, .prim (.string "abc")⟩,
            ⟨"n", .regular, .prim (.int (-7))⟩,
            ⟨"lenX", .regular, .builtinCall "len" [.ref "x"]⟩,
            ⟨"divN", .regular, .builtinCall "div" [.ref "n", .prim (.int 3)]⟩,
            ⟨"incomplete", .regular, .builtinCall "len" [.kind .string]⟩
          ] .regularOpen none []))
      = "x: \"abc\"\nn: -7\nlenX: 3\ndivN: -3\nincomplete: len(string)" := by
  native_decide

theorem fixture_and_or_builtin :
    formatTopLevel
      (.struct [
          ⟨"andValue", .regular, andValues [.kind .int, .boundConstraint (intDecimal 0) .gt .number, .prim (.int 7)]⟩,
          ⟨"orValue", .regular, orValues [.prim (.string "a"), .prim (.string "b")]⟩
        ] .regularOpen none [])
      = "andValue: 7\norValue: \"a\" | \"b\"" := by
  native_decide

theorem fixture_integer_builtin :
    formatTopLevel
      (.struct [
          ⟨"divValue", .regular, divValue (.prim (.int (-7))) (.prim (.int 3))⟩,
          ⟨"modValue", .regular, modValue (.prim (.int (-7))) (.prim (.int 3))⟩,
          ⟨"quoValue", .regular, quoValue (.prim (.int (-7))) (.prim (.int 3))⟩,
          ⟨"remValue", .regular, remValue (.prim (.int (-7))) (.prim (.int 3))⟩,
          ⟨"incompleteDiv", .regular, divValue (.kind .int) (.prim (.int 3))⟩,
          ⟨"zeroDivisor", .regular, divValue (.prim (.int 7)) (.prim (.int 0))⟩
        ] .regularOpen none [])
      =
        "divValue: -3\nmodValue: 2\nquoValue: -2\nremValue: -1\n"
        ++ "incompleteDiv: div(int, 3)\nzeroDivisor: _|_" := by
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
    manifestFieldMatches "x" (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
      "x: \"prod\"" = true := by
  native_decide

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
        (.struct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
        (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
      = "x: {a: 1, b: \"x\"}" := by
  native_decide

theorem fixture_field_conflict :
    formatField "x"
      (meet
        (.struct [⟨"a", .regular, .prim (.string "a")⟩] .regularOpen none [])
        (.struct [⟨"a", .regular, .prim (.string "b")⟩] .regularOpen none []))
      = "x: {a: _|_}" := by
  native_decide

theorem fixture_field_alias :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"not an identifier", .regular, .prim (.int 4)⟩,
            ⟨"A", .letBinding, .ref "not an identifier"⟩,
            ⟨"foo", .regular, .ref "A"⟩
          ] .regularOpen none []))
      = "\"not an identifier\": 4\nfoo: 4" := by
  native_decide

theorem fixture_field_selector :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"base", .regular, .struct [⟨"inner", .regular, .prim (.int 4)⟩] .regularOpen none []⟩,
            ⟨"x", .regular, .selector (.ref "base") "inner"⟩
          ] .regularOpen none []))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

theorem fixture_list_index :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"xs", .regular, .list [.prim (.int 10), .prim (.int 20)]⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 1))⟩
          ] .regularOpen none []))
      = "xs: [10, 20]\nx: 20" := by
  native_decide

theorem fixture_string_field_index :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"base", .regular, .struct [⟨"inner", .regular, .prim (.int 4)⟩] .regularOpen none []⟩,
            ⟨"x", .regular, .index (.ref "base") (.prim (.string "inner"))⟩
          ] .regularOpen none []))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

theorem fixture_number_literals :
    formatTopLevel
      (.struct [
          ⟨"x", .regular, .prim (.int 1000)⟩,
          ⟨"y", .regular, .prim (.float "1.25e+3")⟩,
          ⟨"z", .regular, .prim (.float "-2e+3")⟩
        ] .regularOpen none [])
      = "x: 1000\ny: 1.25e+3\nz: -2e+3" := by
  native_decide

theorem fixture_non_decimal_numbers :
    formatTopLevel
      (.struct [
          ⟨"hex", .regular, .prim (.int 31)⟩,
          ⟨"oct", .regular, .prim (.int 15)⟩,
          ⟨"bin", .regular, .prim (.int 10)⟩,
          ⟨"negHex", .regular, .prim (.int (-16))⟩,
          ⟨"sep", .regular, .prim (.int 10)⟩
        ] .regularOpen none [])
      = "hex: 31\noct: 15\nbin: 10\nnegHex: -16\nsep: 10" := by
  native_decide

theorem fixture_unary_plus_numbers :
    formatTopLevel
      (.struct [
          ⟨"x", .regular, .prim (.int 1)⟩,
          ⟨"y", .regular, .prim (.float "1.5")⟩,
          ⟨"z", .regular, .prim (.int 16)⟩
        ] .regularOpen none [])
      = "x: 1\ny: 1.5\nz: 16" := by
  native_decide

theorem fixture_numeric_suffixes :
    formatTopLevel
      (.struct [
          ⟨"k", .regular, .prim (.int 1000)⟩,
          ⟨"ki", .regular, .prim (.int 1024)⟩,
          ⟨"fracK", .regular, .prim (.int 1500)⟩,
          ⟨"fracKi", .regular, .prim (.int 1536)⟩,
          ⟨"neg", .regular, .prim (.int (-1500))⟩
        ] .regularOpen none [])
      = "k: 1000\nki: 1024\nfracK: 1500\nfracKi: 1536\nneg: -1500" := by
  native_decide

theorem fixture_duplicate_fields :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"x", .regular, .kind .int⟩,
            ⟨"x", .regular, .prim (.int 1)⟩,
            ⟨"conflict", .regular, .prim (.string "a")⟩,
            ⟨"conflict", .regular, .prim (.string "b")⟩
          ] .regularOpen none []))
      = "x: 1\nconflict: _|_" := by
  native_decide

theorem fixture_closed_extra_field :
    formatField "x"
      (meet
        (.struct [⟨"a", .regular, .kind .int⟩] .defClosed none [])
        (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
      = "x: {a: 1, b: _|_}" := by
  native_decide

theorem fixture_closed_hidden_definition :
    formatField "x"
      (meet
        (closeValue (.struct [⟨"a", .regular, .kind .int⟩] .regularOpen none []))
        (.struct [
            ⟨"a", .regular, .prim (.int 1)⟩,
            ⟨"_h", .hidden, .prim (.string "secret")⟩,
            ⟨"#D", .definition, .kind .string⟩
          ] .regularOpen none []))
      = "x: {a: 1, _h: \"secret\", #D: string}" := by
  native_decide

theorem fixture_closed_regex_pattern :
    formatField "x"
      (meet
        (closeValue (.struct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))]))
        (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none []))
      = "x: {a: 1, b: _|_, [=~\"^a$\"]: int}" := by
  native_decide

theorem fixture_definition_struct_normalizes_closed :
    (normalizeDefinitions
        (.struct [⟨"#A", .definition, .struct [⟨"a", .regular, .kind .int⟩] .regularOpen none []⟩] .regularOpen none [])
      == .struct [⟨"#A", .definition, .struct [⟨"a", .regular, .kind .int⟩] .defClosed none []⟩] .regularOpen none []) = true := by
  native_decide

theorem fixture_definition_reference :
    formatField "x"
      (evalStructRefs (resolveStructRefs (.struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] .regularOpen none [])))
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
      = "stringLen: 3\nlistLen: 3\nstructLen: 1" := by
  native_decide

theorem fixture_unresolved_builtin :
    formatTopLevel
      (.struct [
          ⟨"lenString", .regular, lenValue (.kind .string)⟩,
          ⟨"emptyOr", .regular, orValues []⟩
        ] .regularOpen none [])
      = "lenString: len(string)\nemptyOr: or([])" := by
  native_decide

theorem fixture_nested_struct_field :
    formatField "x"
      (meet
        (.struct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
        (.struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []))
      = "x: {a: 1}" := by
  native_decide

theorem fixture_nested_list_field :
    formatField "x"
      (meet
        (.struct [⟨"items", .regular, .list [.kind .int, .kind .string]⟩] .regularOpen none [])
        (.struct [⟨"items", .regular, .list [.prim (.int 1), .prim (.string "x")]⟩] .regularOpen none []))
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
            (.regular, .struct [⟨"kind", .regular, .prim (.string "web")⟩] .regularOpen none []),
            (.regular, .struct [⟨"kind", .regular, .prim (.string "db")⟩] .regularOpen none [])
          ])
        (.struct [
            ⟨"kind", .regular, .prim (.string "web")⟩,
            ⟨"port", .regular, .prim (.int 80)⟩
          ] .regularOpen none []))
      = "x: {kind: \"web\", port: 80}" := by
  native_decide

theorem fixture_struct_ellipsis :
    formatField "x"
      (meet
        (.struct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some .top) [])
        (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "ok")⟩] .regularOpen none []))
      = "x: {a: 1, b: \"ok\", ...}" := by
  native_decide

theorem fixture_string_pattern_constraint :
    formatField "x"
      (meet
        (.struct [] .regularOpen none [((.kind .string), (.kind .int))])
        (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none []))
      = "x: {a: 1, b: 2, [string]: int}" := by
  native_decide

theorem fixture_string_pattern_conflict :
    formatField "x"
      (meet
        (.struct [] .regularOpen none [((.kind .string), (.kind .int))])
        (.struct [⟨"a", .regular, .prim (.string "x")⟩] .regularOpen none []))
      = "x: {a: _|_, [string]: int}" := by
  native_decide

theorem fixture_exact_label_pattern :
    formatField "x"
      (meet
        (.struct [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
        (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
      = "x: {a: 1, b: \"x\", [\"a\"]: int}" := by
  native_decide

theorem fixture_regex_label_pattern :
    formatField "x"
      (meet
        (.struct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
        (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none []))
      = "x: {a: 1, b: \"x\", [=~\"^a$\"]: int}" := by
  native_decide

theorem fixture_regex_wildcard_pattern :
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
      =
        "x: {abcz: 1, abcy: \"skip\", [=~\"^a.*z$\"]: int}\n"
        ++ "y: {az: \"skip\", abz: 2, [=~\"^a.+z$\"]: int}" := by
  native_decide

theorem fixture_regex_class_pattern :
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
      =
        "x: {acz: 1, bcz: 2, ccz: \"skip\", [=~\"^[ab]cz$\"]: int}\n"
        ++ "y: {a5z: 1, axz: \"skip\", [=~\"^a[0-9]z$\"]: int}" := by
  native_decide

theorem fixture_regex_escape_pattern :
    formatField "x"
      (meet
        (.struct [] .regularOpen none [((.stringRegex "^a\\.z$"), (.kind .int))])
        (.struct [⟨"a.z", .regular, .prim (.string "bad")⟩, ⟨"abz", .regular, .prim (.string "skip")⟩] .regularOpen none []))
      = "x: {\"a.z\": _|_, abz: \"skip\", [=~\"^a\\\\.z$\"]: int}" := by
  native_decide

theorem fixture_regex_question_pattern :
    formatField "x"
      (meet
        (.struct [] .regularOpen none [((.stringRegex "^colou?r$"), (.kind .int))])
        (.struct [
            ⟨"color", .regular, .prim (.string "bad")⟩,
            ⟨"colour", .regular, .prim (.int 2)⟩,
            ⟨"colouur", .regular, .prim (.string "skip")⟩
          ] .regularOpen none []))
      = "x: {color: _|_, colour: 2, colouur: \"skip\", [=~\"^colou?r$\"]: int}" := by
  native_decide

theorem fixture_regex_shorthand_pattern :
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
      =
        "x: {a5z: _|_, adz: \"skip\", [=~\"^a\\\\dz$\"]: int}\n"
        ++ "y: {a5z: \"skip\", adz: 1, [=~\"^a\\\\Dz$\"]: int}" := by
  native_decide

theorem fixture_regex_alternation_pattern :
    formatField "x"
      (meet
        (.struct [] .regularOpen none [((.stringRegex "^cat$|^dog$"), (.kind .int))])
        (.struct [
            ⟨"cat", .regular, .prim (.string "bad")⟩,
            ⟨"dog", .regular, .prim (.int 2)⟩,
            ⟨"cow", .regular, .prim (.string "skip")⟩
          ] .regularOpen none []))
      = "x: {cat: _|_, dog: 2, cow: \"skip\", [=~\"^cat$|^dog$\"]: int}" := by
  native_decide

theorem fixture_regex_group_alternation_pattern :
    formatField "x"
      (meet
        (.struct [] .regularOpen none [((.stringRegex "^(cat|dog)$"), (.kind .int))])
        (.struct [
            ⟨"cat", .regular, .prim (.string "bad")⟩,
            ⟨"dog", .regular, .prim (.int 2)⟩,
            ⟨"cow", .regular, .prim (.string "skip")⟩
          ] .regularOpen none []))
      = "x: {cat: _|_, dog: 2, cow: \"skip\", [=~\"^(cat|dog)$\"]: int}" := by
  native_decide

theorem fixture_regex_word_shorthand_pattern :
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
      =
        "x: {a_z: _|_, \"a-z\": \"skip\", [=~\"^a\\\\wz$\"]: int}\n"
        ++ "y: {a_z: \"skip\", \"a-z\": _|_, [=~\"^a\\\\Wz$\"]: int}" := by
  native_decide

theorem fixture_regex_space_shorthand_pattern :
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
      =
        "x: {\"a z\": _|_, a_z: \"skip\", [=~\"^a\\\\sz$\"]: int}\n"
        ++ "y: {\"a z\": \"skip\", a_z: _|_, [=~\"^a\\\\Sz$\"]: int}" := by
  native_decide

theorem fixture_regex_exact_repetition_pattern :
    formatField "x"
      (meet
        (.struct [] .regularOpen none [((.stringRegex "^a\\d{2}z$"), (.kind .int))])
        (.struct [⟨"a12z", .regular, .prim (.string "bad")⟩, ⟨"a1z", .regular, .prim (.string "skip")⟩] .regularOpen none []))
      = "x: {a12z: _|_, a1z: \"skip\", [=~\"^a\\\\d{2}z$\"]: int}" := by
  native_decide

theorem fixture_regex_bounded_repetition_pattern :
    formatField "x"
      (meet
        (.struct [] .regularOpen none [((.stringRegex "^a\\d{2,3}z$"), (.kind .int))])
        (.struct [
            ⟨"a12z", .regular, .prim (.int 2)⟩,
            ⟨"a123z", .regular, .prim (.string "bad")⟩,
            ⟨"a1z", .regular, .prim (.string "skip")⟩
          ] .regularOpen none []))
      = "x: {a12z: 2, a123z: _|_, a1z: \"skip\", [=~\"^a\\\\d{2,3}z$\"]: int}" := by
  native_decide

theorem fixture_int_bounds :
    formatField "x"
      (meet
        (meet (.boundConstraint (intDecimal 0) .ge .number) (.boundConstraint (intDecimal 10) .le .number))
        (.prim (.int 7)))
      = "x: 7" := by
  native_decide

theorem fixture_strict_int_bounds :
    formatField "x"
      (meet
        (meet (.boundConstraint (intDecimal 0) .gt .number) (.boundConstraint (intDecimal 10) .lt .number))
        (.prim (.int 7)))
      = "x: 7" := by
  native_decide

theorem fixture_int_bound_disjunction :
    formatField "x" (join (.boundConstraint (intDecimal 5) .ge .number) (.boundConstraint (intDecimal 0) .ge .number)) = "x: >=0" := by
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
    formatField "x" (meet (meet (.kind .number) (.boundConstraint (intDecimal 0) .ge .number)) (.prim (.int 7))) = "x: 7" := by
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
      (.struct [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"b", .regular, .list [.prim (.string "x")]⟩,
          ⟨"_hidden", .hidden, .prim (.bool true)⟩,
          ⟨"#Schema", .definition, .kind .int⟩,
          ⟨"optional", .optional, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = .ok (.struct [("a", .prim (.int 1)), ("b", .list [.prim (.string "x")])]) := by
  rfl

theorem fixture_manifest_field_filtering_format :
    formatManifestField "x"
      (.struct [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"b", .regular, .list [.prim (.string "x")]⟩,
          ⟨"_hidden", .hidden, .prim (.bool true)⟩,
          ⟨"#Schema", .definition, .kind .int⟩,
          ⟨"optional", .optional, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = .ok "x: {a: 1, b: [\"x\"]}" := by
  rfl

theorem fixture_manifest_nested_default :
    manifestFieldMatches "x"
      (.struct [
          ⟨"mode", .regular,
            .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩
        ] .regularOpen none [])
      "x: {mode: \"prod\"}" = true := by
  native_decide

theorem fixture_manifest_ignores_absent_optional_default :
    formatManifestField "x"
      (.struct [⟨"mode", .optional, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
      = .ok "x: {}" := by
  rfl

theorem fixture_manifest_selects_materialized_optional_default :
    manifestFieldMatches "x"
      (meet
        (.struct [⟨"mode", .optional, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
        (.struct [⟨"mode", .regular, .top⟩] .regularOpen none []))
      "x: {mode: \"prod\"}" = true := by
  native_decide

theorem fixture_manifest_selects_materialized_required_default :
    manifestFieldMatches "x"
      (meet
        (.struct [⟨"mode", .required, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]⟩] .regularOpen none [])
        (.struct [⟨"mode", .regular, .top⟩] .regularOpen none []))
      "x: {mode: \"prod\"}" = true := by
  native_decide

theorem fixture_let_binding :
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
      = "x: 2\nnested: {value: \"ok\"}" := by
  native_decide

theorem fixture_nested_reference_list :
    formatTopLevel
      (resolveAndEval
        (.struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .list [.ref "#A"]⟩] .regularOpen none []))
      = "#A: int\nx: [int]" := by
  native_decide

theorem fixture_direct_self_reference_cycle :
    formatTopLevel (resolveAndEval (.struct [⟨"x", .regular, .ref "x"⟩] .regularOpen none [])) = "x: _" := by
  native_decide

theorem fixture_mutual_reference_cycle :
    formatTopLevel
      (resolveAndEval (.struct [⟨"x", .regular, .ref "y"⟩, ⟨"y", .regular, .ref "x"⟩] .regularOpen none []))
      = "x: _\ny: _" := by
  native_decide

theorem fixture_constrained_reference_cycle :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"x", .regular, .conj [.ref "x", .boundConstraint (intDecimal 0) .ge .number]⟩,
            ⟨"a", .regular, .conj [.ref "b", .boundConstraint (intDecimal 0) .ge .number]⟩,
            ⟨"b", .regular, .ref "a"⟩
          ] .regularOpen none []))
      = "x: >=0\na: >=0\nb: >=0" := by
  native_decide

theorem fixture_three_reference_cycle :
    formatTopLevel
      (resolveAndEval
        (.struct [
            ⟨"x", .regular, .ref "y"⟩,
            ⟨"y", .regular, .ref "z"⟩,
            ⟨"z", .regular, .ref "x"⟩
          ] .regularOpen none []))
      = "x: _\ny: _\nz: _" := by
  native_decide

theorem fixture_manifest_hidden_field_reference :
    manifestFieldMatches "x"
        (evalStructRefs
          (resolveStructRefs
            (.struct [⟨"_secret", .hidden, .prim (.string "x")⟩, ⟨"value", .regular, .ref "_secret"⟩] .regularOpen none [])))
        "x: {value: \"x\"}" = true := by
  native_decide

/-- `_`-prefixed identifiers (`_base`) tokenize as identifiers, not as bare `_` (top).
    Pins the parse fix: a reference, a comparison, an additive op, and equality over a
    hidden underscore field all resolve against its value. -/
theorem fixture_underscore_ident_reference :
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
      = "out: {_base: 5, ref: 5, cmp: true, sum: 6, eq: true, nested: false}" := by
  native_decide

/-- Regression: a bare `_` still means top (not an identifier prefix) when not followed
    by an identifier char, and `_|_` still parses as bottom. -/
theorem fixture_underscore_top_unaffected :
    formatField "a" (meet .top (.prim (.int 1))) = "a: 1" := by
  native_decide

/-- Regression: `_|_` parses as bottom (disjunction drops it) and the B2 value-position
    struct alias (`X={…X.n…}`) still resolves the self-reference. -/
theorem fixture_underscore_top_bottom :
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
      = "bottom: 2\nself: {n: 1, m: 1}" := by
  native_decide

/-! ### link-5 hidden-bottom-field propagation (argocd `packs.#Argo`, sub-fix 2 + regression fix).

A HIDDEN/definition field is OMITTED from output, but a field whose value IS bottom (`{#u: _|_}`,
or a conflict `{#u: string} & {#u: int}`) bottoms the enclosing struct (cue: explicit error).
Pre-fix `manifestFieldsWithFuel` skipped a hidden present field's value unconditionally, silently
dropping the bottom. The check is SHALLOW (`isBottom` on the field value, no recursion into its
subtree): a deep recurse spuriously bottomed the export when a hidden field is an imported-PACKAGE
binding (`defs`/`parts`) carrying `tests`/unreferenced definitions whose isolated conflicts cue
never evaluates (the cert-manager regression — cue is lazy on unreferenced imported content). The
shallow check stays SOUND (never a false error → no regression) while catching the explicit-bottom
and arm-kill cases; a nested-non-propagating hidden bottom (`{#u: {#c: string & int}}`) is a known
incompleteness vs cue (deferred — it needs imported-package laziness, not eager deep checking).
Exercised through the full manifest path (`exportSourcesToString`), which the eval-format
`formatTopLevel` pins above do not reach. The companion behaviour — an UNSET impossible OPTIONAL
field (`#u?: _|_`) does NOT bottom the struct, and arm-prunes correctly in a disjunction — lives in
`containsBottom` (`fieldBottomCounts`) and is pinned by the `link5_disj_*` EvalTests + the fixture. -/

-- Flatten an export result to its inner string (the JSON or the manifest-error message), or a
-- parse-error marker. `ParseError` has no `DecidableEq`, so `native_decide` cannot compare the raw
-- nested `Except`; this reduces to a plain `String` the pins compare exactly.
def exportResultString (source : String) : String :=
  match exportSourcesToString .json [source] with
  | .ok (.ok json) => json
  | .ok (.error err) => "ERR:" ++ err
  | .error _ => "PARSE-ERR"

-- A hidden field whose value is BOTTOM bottoms the enclosing struct (cue: explicit `_|_` error).
theorem link5_hidden_bottom_field_contradicts :
    exportResultString "out: {#u: _|_, k: 1}\n" = "ERR:conflicting values (bottom)" := by
  native_decide

-- A hidden field bottomed by a CONFLICT (`string & int`) likewise bottoms the struct.
theorem link5_hidden_conflict_field_contradicts :
    exportResultString "out: ({#u: string} & {#u: int}) & {k: 1}\n"
      = "ERR:conflicting values (bottom)" := by
  native_decide

-- A hidden field left INCOMPLETE (a bare type) is TOLERATED — omitted, no error (cue exports it).
-- Pins that the bottom-propagation does not over-fire on hidden incompleteness.
theorem link5_hidden_incomplete_field_tolerated :
    exportResultString "out: {#u: int, k: 1}\n"
      = "{\n    \"out\": {\n        \"k\": 1\n    }\n}\n" := by
  native_decide

-- An UNSET impossible OPTIONAL field (`#u?: _|_`) does NOT bottom the struct (cue keeps it).
theorem link5_unset_optional_bottom_field_tolerated :
    exportResultString "out: {#u?: _|_, k: 1}\n"
      = "{\n    \"out\": {\n        \"k\": 1\n    }\n}\n" := by
  native_decide

-- A2-followup: a DEEP conflict in a real IN-FILE nested definition surfaces — cue ENFORCES a
-- bottom reached anywhere in a reached hidden/def field (`out: {#pkg: {#Tmpl: {#c: string} &
-- {#c: int}}, …}` → `conflicting values string and int`, oracle-confirmed v0.16.1). This INVERTS
-- the prior `link5_..._does_not_overfire` pin, which asserted clean export — that was Kue-WRONG:
-- it conflated an in-file literal with an import binding to dodge the cert-manager trap. The marker
-- decouples the two: in-file hidden/def fields are REACHED and strict; only an `.importBinding`
-- stays lazy. The genuine lazy-import guard is the `dup_import_binding` module fixture (an
-- unreferenced `parts.#Other` conflict still exports `main` clean).
theorem infile_hidden_nested_conflict_surfaces :
    exportResultString "out: {#pkg: {#Tmpl: {#c: string} & {#c: int}}, k: 1}\n"
      = "ERR:conflicting values (bottom)" := by
  native_decide

-- A2-followup: a DEEP explicit `_|_` in a REACHED in-file definition field surfaces at manifest
-- (`{#u: {x: _|_}}` → cue: `explicit error (_|_ literal)`, oracle-confirmed v0.16.1). The Manifest
-- split recurses the value's output spine for a real in-file hidden/def field (NOT an import
-- binding) and lifts a deep `.contradiction`.
theorem a2followup_deep_hidden_def_bottom_surfaces :
    exportResultString "#u: {x: _|_}\nout: 1\n" = "ERR:conflicting values (bottom)" := by
  native_decide

-- A2-followup: the same shape with a real in-file HIDDEN field (`_u`, not a def) also surfaces.
theorem a2followup_deep_infile_hidden_bottom_surfaces :
    exportResultString "_u: {x: _|_}\nout: 1\n" = "ERR:conflicting values (bottom)" := by
  native_decide

-- A2-followup tolerance: a DEEP INCOMPLETE (not a contradiction) in a hidden/def field is NOT an
-- error — hidden/def fields are non-output and an unreached incomplete is tolerated (`{#u: {x:
-- string}}` exports clean, oracle-confirmed v0.16.1). Only `.contradiction` lifts; incomplete skips.
theorem a2followup_deep_hidden_incomplete_tolerated :
    exportResultString "#u: {x: string}\nout: 1\n" = "{\n    \"out\": 1\n}\n" := by
  native_decide

end Kue
