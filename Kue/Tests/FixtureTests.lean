import Kue.Tests.FixturePorts

namespace Kue

theorem fixture_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2)), false⟩,
            ⟨"diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3)), false⟩,
            ⟨"cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b")), false⟩
          ] .regularOpen none []))
      = "sum: 3\ndiff: 2\ncat: \"ab\"" := by
  native_decide

theorem fixture_bytes_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"bytes", .regular, .binary .add (.prim (.bytes (textBytes "ab"))) (.prim (.bytes (textBytes "cd"))), false⟩,
            ⟨
              "left",
              .regular,
              .binary .add
                (.binary .add (.prim (.bytes (textBytes "a"))) (.prim (.bytes (textBytes "b"))))
                (.prim (.bytes (textBytes "c")))
            , false⟩
          ] .regularOpen none []))
      = "bytes: 'abcd'\nleft: 'abc'" := by
  native_decide

theorem fixture_float_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"floatSum", .regular, .binary .add (.prim (mkFloatText "1.5")) (.prim (mkFloatText "2.25")), false⟩,
            ⟨"intFloat", .regular, .binary .add (.prim (.int 1)) (.prim (mkFloatText "2.5")), false⟩,
            ⟨"floatSub", .regular, .binary .sub (.prim (mkFloatText "5.5")) (.prim (.int 2)), false⟩,
            ⟨"whole", .regular, .binary .add (.prim (mkFloatText "1.5")) (.prim (mkFloatText "1.5")), false⟩,
            ⟨"exp", .regular, .binary .add (.prim (mkFloatText "1e+3")) (.prim (.int 2)), false⟩,
            ⟨"small", .regular, .binary .add (.prim (mkFloatText "0.1")) (.prim (mkFloatText "0.2")), false⟩
          ] .regularOpen none []))
      = "floatSum: 3.75\nintFloat: 3.5\nfloatSub: 3.5\nwhole: 3.0\nexp: 1002.0\nsmall: 0.3" := by
  native_decide

theorem fixture_multiplication_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"mul", .regular, .binary .mul (.prim (.int 3)) (.prim (.int 4)), false⟩,
            ⟨
              "precedence",
              .regular,
              .binary .add (.prim (.int 1)) (.binary .mul (.prim (.int 2)) (.prim (.int 3)))
            , false⟩,
            ⟨
              "left",
              .regular,
              .binary .mul (.binary .mul (.prim (.int 2)) (.prim (.int 3))) (.prim (.int 4))
            , false⟩
          ] .regularOpen none []))
      = "mul: 12\nprecedence: 7\nleft: 24" := by
  native_decide

theorem fixture_division_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"div", .regular, .binary .div (.prim (.int 5)) (.prim (.int 2)), false⟩,
            ⟨"whole", .regular, .binary .div (.prim (.int 6)) (.prim (.int 3)), false⟩,
            ⟨"third", .regular, .binary .div (.prim (.int 1)) (.prim (.int 3)), false⟩,
            ⟨"negative", .regular, .binary .div (.prim (.int (-5))) (.prim (.int 2)), false⟩
          ] .regularOpen none []))
      = "div: 2.5\nwhole: 2.0\nthird: 0.3333333333333333333333333333333333\nnegative: -2.5" := by
  native_decide

theorem fixture_integer_keyword_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"divValue", .regular, .binary .intDiv (.prim (.int (-7))) (.prim (.int 3)), false⟩,
            ⟨"modValue", .regular, .binary .intMod (.prim (.int (-7))) (.prim (.int 3)), false⟩,
            ⟨"quoValue", .regular, .binary .intQuo (.prim (.int (-7))) (.prim (.int 3)), false⟩,
            ⟨"remValue", .regular, .binary .intRem (.prim (.int (-7))) (.prim (.int 3)), false⟩,
            ⟨
              "precedence",
              .regular,
              .binary .add (.prim (.int 1)) (.binary .intDiv (.prim (.int 7)) (.prim (.int 3)))
            , false⟩
          ] .regularOpen none []))
      = "divValue: -3\nmodValue: 2\nquoValue: -2\nremValue: -1\nprecedence: 3" := by
  native_decide

theorem fixture_equality_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"same", .regular, .binary .eq (.prim (.int 1)) (.prim (.int 1)), false⟩,
            ⟨"diff", .regular, .binary .ne (.prim (.int 1)) (.prim (.int 2)), false⟩,
            ⟨"text", .regular, .binary .eq (.prim (.string "a")) (.prim (.string "b")), false⟩,
            ⟨
              "precedence",
              .regular,
              .binary .eq (.binary .add (.prim (.int 1)) (.prim (.int 1))) (.prim (.int 2))
            , false⟩
          ] .regularOpen none []))
      = "same: true\ndiff: true\ntext: false\nprecedence: true" := by
  native_decide

theorem fixture_ordering_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"lt", .regular, .binary .lt (.prim (.int 1)) (.prim (.int 2)), false⟩,
            ⟨"le", .regular, .binary .le (.prim (.int 2)) (.prim (.int 2)), false⟩,
            ⟨"gt", .regular, .binary .gt (.prim (.int 3)) (.prim (.int 2)), false⟩,
            ⟨"ge", .regular, .binary .ge (.prim (.int 3)) (.prim (.int 4)), false⟩,
            ⟨"slt", .regular, .binary .lt (.prim (.string "a")) (.prim (.string "b")), false⟩,
            ⟨
              "precedence",
              .regular,
              .binary .lt (.binary .add (.prim (.int 1)) (.prim (.int 2))) (.prim (.int 4))
            , false⟩
          ] .regularOpen none []))
      = "lt: true\nle: true\ngt: true\nge: false\nslt: true\nprecedence: true" := by
  native_decide

theorem fixture_numeric_comparison_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"lt", .regular, .binary .lt (.prim (mkFloatText "1.5")) (.prim (.int 2)), false⟩,
            ⟨"le", .regular, .binary .le (.prim (mkFloatText "1.5")) (.prim (mkFloatText "1.50")), false⟩,
            ⟨"gt", .regular, .binary .gt (.prim (mkFloatText "1e+3")) (.prim (mkFloatText "999.9")), false⟩,
            ⟨"ge", .regular, .binary .ge (.prim (mkFloatText "1.0")) (.prim (.int 1)), false⟩,
            ⟨"eq", .regular, .binary .eq (.prim (.int 1)) (.prim (mkFloatText "1.0")), false⟩,
            ⟨"ne", .regular, .binary .ne (.prim (.int 1)) (.prim (mkFloatText "1.0")), false⟩
          ] .regularOpen none []))
      = "lt: true\nle: true\ngt: true\nge: true\neq: true\nne: false" := by
  native_decide

theorem fixture_logical_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"andFalse", .regular, .binary .boolAnd (.prim (.bool true)) (.prim (.bool false)), false⟩,
            ⟨"orTrue", .regular, .binary .boolOr (.prim (.bool false)) (.prim (.bool true)), false⟩,
            ⟨
              "andCmp",
              .regular,
              .binary .boolAnd
                (.binary .lt (.prim (.int 1)) (.prim (.int 2)))
                (.binary .gt (.prim (.int 3)) (.prim (.int 2)))
            , false⟩,
            ⟨
              "orCmp",
              .regular,
              .binary .boolOr
                (.prim (.bool false))
                (.binary .eq (.binary .add (.prim (.int 1)) (.prim (.int 1))) (.prim (.int 2)))
            , false⟩,
            ⟨
              "grouped",
              .regular,
              .binary .boolAnd
                (.binary .boolOr (.prim (.bool false)) (.prim (.bool true)))
                (.prim (.bool true))
            , false⟩
          ] .regularOpen none []))
      = "andFalse: false\norTrue: true\nandCmp: true\norCmp: true\ngrouped: true" := by
  native_decide

theorem fixture_logical_not_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"notFalse", .regular, .unary .boolNot (.prim (.bool false)), false⟩,
            ⟨"notCmp", .regular, .unary .boolNot (.binary .lt (.prim (.int 1)) (.prim (.int 2))), false⟩,
            ⟨"double", .regular, .unary .boolNot (.unary .boolNot (.prim (.bool true))), false⟩
          ] .regularOpen none []))
      = "notFalse: true\nnotCmp: false\ndouble: true" := by
  native_decide

theorem fixture_unary_numeric_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"negGroup", .regular, .unary .numNeg (.binary .add (.prim (.int 1)) (.prim (.int 2))), false⟩,
            ⟨"posGroup", .regular, .unary .numPos (.binary .add (.prim (.int 1)) (.prim (.int 2))), false⟩,
            ⟨"negRefBase", .regular, .prim (.int 3), false⟩,
            ⟨"negRef", .regular, .unary .numNeg (.ref "negRefBase"), false⟩,
            ⟨"precedence", .regular, .binary .mul (.unary .numNeg (.prim (.int 2))) (.prim (.int 3)), false⟩
          ] .regularOpen none []))
      = "negGroup: -3\nposGroup: 3\nnegRefBase: 3\nnegRef: -3\nprecedence: -6" := by
  native_decide

theorem fixture_regex_match_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"match", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "^a")), false⟩,
            ⟨"miss", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "z")), false⟩,
            ⟨"notMatch", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "z")), false⟩,
            ⟨"notMiss", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "^a")), false⟩,
            ⟨
              "precedence",
              .regular,
              .binary .regexMatch
                (.binary .add (.prim (.string "ab")) (.prim (.string "c")))
                (.prim (.string "^abc$"))
            , false⟩
          ] .regularOpen none []))
      = "match: true\nmiss: false\nnotMatch: true\nnotMiss: false\nprecedence: true" := by
  native_decide

theorem fixture_kind_meet_int :
    formatField "x" (meet (.kind .int) (.prim (.int 1))) = "x: 1" := by
  native_decide

theorem fixture_builtin_reference_eval :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"x", .regular, .prim (.string "abc"), false⟩,
            ⟨"n", .regular, .prim (.int (-7)), false⟩,
            ⟨"lenX", .regular, .builtinCall "len" [.ref "x"], false⟩,
            ⟨"divN", .regular, .builtinCall "div" [.ref "n", .prim (.int 3)], false⟩,
            ⟨"incomplete", .regular, .builtinCall "len" [.kind .string], false⟩
          ] .regularOpen none []))
      = "x: \"abc\"\nn: -7\nlenX: 3\ndivN: -3\nincomplete: len(string)" := by
  native_decide

theorem fixture_and_or_builtin :
    formatTopLevel
      (mkStruct [
          ⟨"andValue", .regular, andValues [.kind .int, .boundConstraint (intDecimal 0) .gt .number, .prim (.int 7)], false⟩,
          ⟨"orValue", .regular, orValues [.prim (.string "a"), .prim (.string "b")], false⟩
        ] .regularOpen none [])
      = "andValue: 7\norValue: \"a\" | \"b\"" := by
  native_decide

theorem fixture_integer_builtin :
    formatTopLevel
      (mkStruct [
          ⟨"divValue", .regular, divValue (.prim (.int (-7))) (.prim (.int 3)), false⟩,
          ⟨"modValue", .regular, modValue (.prim (.int (-7))) (.prim (.int 3)), false⟩,
          ⟨"quoValue", .regular, quoValue (.prim (.int (-7))) (.prim (.int 3)), false⟩,
          ⟨"remValue", .regular, remValue (.prim (.int (-7))) (.prim (.int 3)), false⟩,
          ⟨"incompleteDiv", .regular, divValue (.kind .int) (.prim (.int 3)), false⟩,
          ⟨"zeroDivisor", .regular, divValue (.prim (.int 7)) (.prim (.int 0)), false⟩
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
        (mkStruct [⟨"a", .regular, .kind .int, false⟩] .regularOpen none [])
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.string "x"), false⟩] .regularOpen none []))
      = "x: {a: 1, b: \"x\"}" := by
  native_decide

theorem fixture_field_conflict :
    formatField "x"
      (meet
        (mkStruct [⟨"a", .regular, .prim (.string "a"), false⟩] .regularOpen none [])
        (mkStruct [⟨"a", .regular, .prim (.string "b"), false⟩] .regularOpen none []))
      = "x: {a: _|_}" := by
  native_decide

theorem fixture_field_alias :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"not an identifier", .regular, .prim (.int 4), false⟩,
            ⟨"A", .letBinding, .ref "not an identifier", false⟩,
            ⟨"foo", .regular, .ref "A", false⟩
          ] .regularOpen none []))
      = "\"not an identifier\": 4\nfoo: 4" := by
  native_decide

theorem fixture_field_selector :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"base", .regular, mkStruct [⟨"inner", .regular, .prim (.int 4), false⟩] .regularOpen none [], false⟩,
            ⟨"x", .regular, .selector (.ref "base") "inner", false⟩
          ] .regularOpen none []))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

theorem fixture_list_index :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"xs", .regular, .list [.prim (.int 10), .prim (.int 20)], false⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 1)), false⟩
          ] .regularOpen none []))
      = "xs: [10, 20]\nx: 20" := by
  native_decide

theorem fixture_string_field_index :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"base", .regular, mkStruct [⟨"inner", .regular, .prim (.int 4), false⟩] .regularOpen none [], false⟩,
            ⟨"x", .regular, .index (.ref "base") (.prim (.string "inner")), false⟩
          ] .regularOpen none []))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

theorem fixture_number_literals :
    formatTopLevel
      (mkStruct [
          ⟨"x", .regular, .prim (.int 1000), false⟩,
          ⟨"y", .regular, .prim (mkFloatText "1.25e+3"), false⟩,
          ⟨"z", .regular, .prim (mkFloatText "-2e+3"), false⟩
        ] .regularOpen none [])
      = "x: 1000\ny: 1.25e+3\nz: -2e+3" := by
  native_decide

theorem fixture_non_decimal_numbers :
    formatTopLevel
      (mkStruct [
          ⟨"hex", .regular, .prim (.int 31), false⟩,
          ⟨"oct", .regular, .prim (.int 15), false⟩,
          ⟨"bin", .regular, .prim (.int 10), false⟩,
          ⟨"negHex", .regular, .prim (.int (-16)), false⟩,
          ⟨"sep", .regular, .prim (.int 10), false⟩
        ] .regularOpen none [])
      = "hex: 31\noct: 15\nbin: 10\nnegHex: -16\nsep: 10" := by
  native_decide

theorem fixture_unary_plus_numbers :
    formatTopLevel
      (mkStruct [
          ⟨"x", .regular, .prim (.int 1), false⟩,
          ⟨"y", .regular, .prim (mkFloatText "1.5"), false⟩,
          ⟨"z", .regular, .prim (.int 16), false⟩
        ] .regularOpen none [])
      = "x: 1\ny: 1.5\nz: 16" := by
  native_decide

theorem fixture_numeric_suffixes :
    formatTopLevel
      (mkStruct [
          ⟨"k", .regular, .prim (.int 1000), false⟩,
          ⟨"ki", .regular, .prim (.int 1024), false⟩,
          ⟨"fracK", .regular, .prim (.int 1500), false⟩,
          ⟨"fracKi", .regular, .prim (.int 1536), false⟩,
          ⟨"neg", .regular, .prim (.int (-1500)), false⟩
        ] .regularOpen none [])
      = "k: 1000\nki: 1024\nfracK: 1500\nfracKi: 1536\nneg: -1500" := by
  native_decide

theorem fixture_duplicate_fields :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"x", .regular, .kind .int, false⟩,
            ⟨"x", .regular, .prim (.int 1), false⟩,
            ⟨"conflict", .regular, .prim (.string "a"), false⟩,
            ⟨"conflict", .regular, .prim (.string "b"), false⟩
          ] .regularOpen none []))
      = "x: 1\nconflict: _|_" := by
  native_decide

theorem fixture_closed_extra_field :
    formatField "x"
      (meet
        (mkStruct [⟨"a", .regular, .kind .int, false⟩] .defClosed none [])
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.string "x"), false⟩] .regularOpen none []))
      = "x: {a: 1, b: _|_}" := by
  native_decide

theorem fixture_closed_hidden_definition :
    formatField "x"
      (meet
        (closeValue (mkStruct [⟨"a", .regular, .kind .int, false⟩] .regularOpen none []))
        (mkStruct [
            ⟨"a", .regular, .prim (.int 1), false⟩,
            ⟨"_h", .hidden, .prim (.string "secret"), false⟩,
            ⟨"#D", .definition, .kind .string, false⟩
          ] .regularOpen none []))
      = "x: {a: 1, _h: \"secret\", #D: string}" := by
  native_decide

theorem fixture_closed_regex_pattern :
    formatField "x"
      (meet
        (closeValue (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))]))
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none []))
      = "x: {a: 1, b: _|_, [=~\"^a$\"]: int}" := by
  native_decide

theorem fixture_definition_struct_normalizes_closed :
    (normalizeDefinitions
        (mkStruct [⟨"#A", .definition, mkStruct [⟨"a", .regular, .kind .int, false⟩] .regularOpen none [], false⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, mkStruct [⟨"a", .regular, .kind .int, false⟩] .defClosed none [], false⟩] .regularOpen none []) = true := by
  native_decide

theorem fixture_definition_reference :
    formatField "x"
      (evalStructRefs (resolveStructRefs (mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .ref "#A", false⟩] .regularOpen none [])))
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
      (mkStruct [
          ⟨"stringLen", .regular, lenValue (.prim (.string "abc")), false⟩,
          ⟨"listLen", .regular, lenValue (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]), false⟩,
          ⟨"structLen", .regular,
            lenValue
              (mkStruct [
                  ⟨"a", .regular, .prim (.int 1), false⟩,
                  ⟨"b", .optional, .prim (.int 2), false⟩,
                  ⟨"_c", .hidden, .prim (.int 3), false⟩,
                  ⟨"#D", .definition, .prim (.int 4), false⟩
                ] .regularOpen none []), false⟩
        ] .regularOpen none [])
      = "stringLen: 3\nlistLen: 3\nstructLen: 1" := by
  native_decide

theorem fixture_unresolved_builtin :
    formatTopLevel
      (mkStruct [
          ⟨"lenString", .regular, lenValue (.kind .string), false⟩,
          ⟨"emptyOr", .regular, orValues [], false⟩
        ] .regularOpen none [])
      = "lenString: len(string)\nemptyOr: or([])" := by
  native_decide

theorem fixture_nested_struct_field :
    formatField "x"
      (meet
        (mkStruct [⟨"a", .regular, .kind .int, false⟩] .regularOpen none [])
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none []))
      = "x: {a: 1}" := by
  native_decide

theorem fixture_nested_list_field :
    formatField "x"
      (meet
        (mkStruct [⟨"items", .regular, .list [.kind .int, .kind .string], false⟩] .regularOpen none [])
        (mkStruct [⟨"items", .regular, .list [.prim (.int 1), .prim (.string "x")], false⟩] .regularOpen none []))
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
            (.regular, mkStruct [⟨"kind", .regular, .prim (.string "web"), false⟩] .regularOpen none []),
            (.regular, mkStruct [⟨"kind", .regular, .prim (.string "db"), false⟩] .regularOpen none [])
          ])
        (mkStruct [
            ⟨"kind", .regular, .prim (.string "web"), false⟩,
            ⟨"port", .regular, .prim (.int 80), false⟩
          ] .regularOpen none []))
      = "x: {kind: \"web\", port: 80}" := by
  native_decide

theorem fixture_struct_ellipsis :
    formatField "x"
      (meet
        (mkStruct [⟨"a", .regular, .kind .int, false⟩] .defOpenViaTail (some .top) [])
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.string "ok"), false⟩] .regularOpen none []))
      = "x: {a: 1, b: \"ok\", ...}" := by
  native_decide

theorem fixture_string_pattern_constraint :
    formatField "x"
      (meet
        (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none []))
      = "x: {a: 1, b: 2, [string]: int}" := by
  native_decide

theorem fixture_string_pattern_conflict :
    formatField "x"
      (meet
        (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
        (mkStruct [⟨"a", .regular, .prim (.string "x"), false⟩] .regularOpen none []))
      = "x: {a: _|_, [string]: int}" := by
  native_decide

theorem fixture_exact_label_pattern :
    formatField "x"
      (meet
        (mkStruct [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.string "x"), false⟩] .regularOpen none []))
      = "x: {a: 1, b: \"x\", [\"a\"]: int}" := by
  native_decide

theorem fixture_regex_label_pattern :
    formatField "x"
      (meet
        (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.string "x"), false⟩] .regularOpen none []))
      = "x: {a: 1, b: \"x\", [=~\"^a$\"]: int}" := by
  native_decide

theorem fixture_regex_wildcard_pattern :
    formatTopLevel
      (mkStruct [
          ⟨"x", .regular,
            meet
              (mkStruct [] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))])
              (mkStruct [⟨"abcz", .regular, .prim (.int 1), false⟩, ⟨"abcy", .regular, .prim (.string "skip"), false⟩] .regularOpen none []), false⟩,
          ⟨"y", .regular,
            meet
              (mkStruct [] .regularOpen none [((.stringRegex "^a.+z$"), (.kind .int))])
              (mkStruct [⟨"az", .regular, .prim (.string "skip"), false⟩, ⟨"abz", .regular, .prim (.int 2), false⟩] .regularOpen none []), false⟩
        ] .regularOpen none [])
      =
        "x: {abcz: 1, abcy: \"skip\", [=~\"^a.*z$\"]: int}\n"
        ++ "y: {az: \"skip\", abz: 2, [=~\"^a.+z$\"]: int}" := by
  native_decide

theorem fixture_regex_class_pattern :
    formatTopLevel
      (mkStruct [
          ⟨"x", .regular,
            meet
              (mkStruct [] .regularOpen none [((.stringRegex "^[ab]cz$"), (.kind .int))])
              (mkStruct [
                  ⟨"acz", .regular, .prim (.int 1), false⟩,
                  ⟨"bcz", .regular, .prim (.int 2), false⟩,
                  ⟨"ccz", .regular, .prim (.string "skip"), false⟩
                ] .regularOpen none []), false⟩,
          ⟨"y", .regular,
            meet
              (mkStruct [] .regularOpen none [((.stringRegex "^a[0-9]z$"), (.kind .int))])
              (mkStruct [⟨"a5z", .regular, .prim (.int 1), false⟩, ⟨"axz", .regular, .prim (.string "skip"), false⟩] .regularOpen none []), false⟩
        ] .regularOpen none [])
      =
        "x: {acz: 1, bcz: 2, ccz: \"skip\", [=~\"^[ab]cz$\"]: int}\n"
        ++ "y: {a5z: 1, axz: \"skip\", [=~\"^a[0-9]z$\"]: int}" := by
  native_decide

theorem fixture_regex_escape_pattern :
    formatField "x"
      (meet
        (mkStruct [] .regularOpen none [((.stringRegex "^a\\.z$"), (.kind .int))])
        (mkStruct [⟨"a.z", .regular, .prim (.string "bad"), false⟩, ⟨"abz", .regular, .prim (.string "skip"), false⟩] .regularOpen none []))
      = "x: {\"a.z\": _|_, abz: \"skip\", [=~\"^a\\\\.z$\"]: int}" := by
  native_decide

theorem fixture_regex_question_pattern :
    formatField "x"
      (meet
        (mkStruct [] .regularOpen none [((.stringRegex "^colou?r$"), (.kind .int))])
        (mkStruct [
            ⟨"color", .regular, .prim (.string "bad"), false⟩,
            ⟨"colour", .regular, .prim (.int 2), false⟩,
            ⟨"colouur", .regular, .prim (.string "skip"), false⟩
          ] .regularOpen none []))
      = "x: {color: _|_, colour: 2, colouur: \"skip\", [=~\"^colou?r$\"]: int}" := by
  native_decide

theorem fixture_regex_shorthand_pattern :
    formatTopLevel
      (mkStruct [
          ⟨"x", .regular,
            meet
              (mkStruct [] .regularOpen none [((.stringRegex "^a\\dz$"), (.kind .int))])
              (mkStruct [⟨"a5z", .regular, .prim (.string "bad"), false⟩, ⟨"adz", .regular, .prim (.string "skip"), false⟩] .regularOpen none []), false⟩,
          ⟨"y", .regular,
            meet
              (mkStruct [] .regularOpen none [((.stringRegex "^a\\Dz$"), (.kind .int))])
              (mkStruct [⟨"a5z", .regular, .prim (.string "skip"), false⟩, ⟨"adz", .regular, .prim (.int 1), false⟩] .regularOpen none []), false⟩
        ] .regularOpen none [])
      =
        "x: {a5z: _|_, adz: \"skip\", [=~\"^a\\\\dz$\"]: int}\n"
        ++ "y: {a5z: \"skip\", adz: 1, [=~\"^a\\\\Dz$\"]: int}" := by
  native_decide

theorem fixture_regex_alternation_pattern :
    formatField "x"
      (meet
        (mkStruct [] .regularOpen none [((.stringRegex "^cat$|^dog$"), (.kind .int))])
        (mkStruct [
            ⟨"cat", .regular, .prim (.string "bad"), false⟩,
            ⟨"dog", .regular, .prim (.int 2), false⟩,
            ⟨"cow", .regular, .prim (.string "skip"), false⟩
          ] .regularOpen none []))
      = "x: {cat: _|_, dog: 2, cow: \"skip\", [=~\"^cat$|^dog$\"]: int}" := by
  native_decide

theorem fixture_regex_group_alternation_pattern :
    formatField "x"
      (meet
        (mkStruct [] .regularOpen none [((.stringRegex "^(cat|dog)$"), (.kind .int))])
        (mkStruct [
            ⟨"cat", .regular, .prim (.string "bad"), false⟩,
            ⟨"dog", .regular, .prim (.int 2), false⟩,
            ⟨"cow", .regular, .prim (.string "skip"), false⟩
          ] .regularOpen none []))
      = "x: {cat: _|_, dog: 2, cow: \"skip\", [=~\"^(cat|dog)$\"]: int}" := by
  native_decide

theorem fixture_regex_word_shorthand_pattern :
    formatTopLevel
      (mkStruct [
          ⟨"x", .regular,
            meet
              (mkStruct [] .regularOpen none [((.stringRegex "^a\\wz$"), (.kind .int))])
              (mkStruct [⟨"a_z", .regular, .prim (.string "bad"), false⟩, ⟨"a-z", .regular, .prim (.string "skip"), false⟩] .regularOpen none []), false⟩,
          ⟨"y", .regular,
            meet
              (mkStruct [] .regularOpen none [((.stringRegex "^a\\Wz$"), (.kind .int))])
              (mkStruct [⟨"a_z", .regular, .prim (.string "skip"), false⟩, ⟨"a-z", .regular, .prim (.string "bad"), false⟩] .regularOpen none []), false⟩
        ] .regularOpen none [])
      =
        "x: {a_z: _|_, \"a-z\": \"skip\", [=~\"^a\\\\wz$\"]: int}\n"
        ++ "y: {a_z: \"skip\", \"a-z\": _|_, [=~\"^a\\\\Wz$\"]: int}" := by
  native_decide

theorem fixture_regex_space_shorthand_pattern :
    formatTopLevel
      (mkStruct [
          ⟨"x", .regular,
            meet
              (mkStruct [] .regularOpen none [((.stringRegex "^a\\sz$"), (.kind .int))])
              (mkStruct [⟨"a z", .regular, .prim (.string "bad"), false⟩, ⟨"a_z", .regular, .prim (.string "skip"), false⟩] .regularOpen none []), false⟩,
          ⟨"y", .regular,
            meet
              (mkStruct [] .regularOpen none [((.stringRegex "^a\\Sz$"), (.kind .int))])
              (mkStruct [⟨"a z", .regular, .prim (.string "skip"), false⟩, ⟨"a_z", .regular, .prim (.string "bad"), false⟩] .regularOpen none []), false⟩
        ] .regularOpen none [])
      =
        "x: {\"a z\": _|_, a_z: \"skip\", [=~\"^a\\\\sz$\"]: int}\n"
        ++ "y: {\"a z\": \"skip\", a_z: _|_, [=~\"^a\\\\Sz$\"]: int}" := by
  native_decide

theorem fixture_regex_exact_repetition_pattern :
    formatField "x"
      (meet
        (mkStruct [] .regularOpen none [((.stringRegex "^a\\d{2}z$"), (.kind .int))])
        (mkStruct [⟨"a12z", .regular, .prim (.string "bad"), false⟩, ⟨"a1z", .regular, .prim (.string "skip"), false⟩] .regularOpen none []))
      = "x: {a12z: _|_, a1z: \"skip\", [=~\"^a\\\\d{2}z$\"]: int}" := by
  native_decide

theorem fixture_regex_bounded_repetition_pattern :
    formatField "x"
      (meet
        (mkStruct [] .regularOpen none [((.stringRegex "^a\\d{2,3}z$"), (.kind .int))])
        (mkStruct [
            ⟨"a12z", .regular, .prim (.int 2), false⟩,
            ⟨"a123z", .regular, .prim (.string "bad"), false⟩,
            ⟨"a1z", .regular, .prim (.string "skip"), false⟩
          ] .regularOpen none []))
      = "x: {a12z: 2, a123z: _|_, a1z: \"skip\", [=~\"^a\\\\d{2,3}z$\"]: int}" := by
  native_decide

-- struct.MinFields / struct.MaxFields validators (STDLIB-B). Counting semantics: only REGULAR
-- fields count (optional/required/hidden/definition/let excluded). Meet resolves asymmetrically
-- (satisfied `min` drops, violated `max` bottoms), retaining the undecided residual in a `.conj`
-- adjudicated at manifest; `manifestValueOk` pins the finalize pass/fail without a rendered string
-- (content is pinned by the `testdata/export/struct_field_count` fixture).
private def structAB : Value :=
  mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 2), false⟩]
    .regularOpen none []
private def structA : Value :=
  mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none []
private def structB : Value :=
  mkStruct [⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none []
private def structAoptB : Value :=
  mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .optional, .prim (.int 2), false⟩]
    .regularOpen none []
private def structAreqB : Value :=
  mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .required, .prim (.int 2), false⟩]
    .regularOpen none []
private def emptyStruct : Value := mkStruct [] .regularOpen none []
private def manifestValueOk (value : Value) : Bool :=
  match manifest value with
  | .ok _ => true
  | .error _ => false

-- A satisfied `min` drops eagerly: the meet is the struct itself, no residual.
theorem fieldcount_min_satisfied_drops :
    (meet structAB (.fieldCountConstraint .min 2) == structAB) = true := by native_decide

-- A violated `max` bottoms eagerly (count 2 > 1).
theorem fieldcount_max_violated_bottoms :
    (meet structAB (.fieldCountConstraint .max 1) == .bottomWith [.boundConflict]) = true := by
  native_decide

-- Manifest finalize: satisfied validators export, violated ones error.
theorem fieldcount_min_exact_ok :
    manifestValueOk (meet structAB (.fieldCountConstraint .min 2)) = true := by native_decide
theorem fieldcount_min_violated_err :
    manifestValueOk (meet structAB (.fieldCountConstraint .min 3)) = false := by native_decide
theorem fieldcount_min_zero_empty_ok :
    manifestValueOk (meet emptyStruct (.fieldCountConstraint .min 0)) = true := by native_decide
theorem fieldcount_max_ok :
    manifestValueOk (meet structAB (.fieldCountConstraint .max 3)) = true := by native_decide
theorem fieldcount_min_and_max_ok :
    manifestValueOk
      (meet (meet structAB (.fieldCountConstraint .min 1)) (.fieldCountConstraint .max 3)) = true := by
  native_decide
theorem fieldcount_negative_min_ok :
    manifestValueOk (meet structA (.fieldCountConstraint .min (-1))) = true := by native_decide

-- Accretion across conjuncts: a field added AFTER an unsatisfied `min` satisfies it.
theorem fieldcount_accretion_ok :
    manifestValueOk (meet (meet structA (.fieldCountConstraint .min 2)) structB) = true := by
  native_decide

-- Only regular fields count: optional / required / hidden are excluded from the tally.
theorem fieldcount_optional_excluded_err :
    manifestValueOk (meet structAoptB (.fieldCountConstraint .min 2)) = false := by native_decide
theorem fieldcount_optional_min1_ok :
    manifestValueOk (meet structAoptB (.fieldCountConstraint .min 1)) = true := by native_decide
theorem fieldcount_required_excluded_err :
    manifestValueOk (meet structAreqB (.fieldCountConstraint .min 2)) = false := by native_decide

-- A validator meeting a non-struct is a type conflict (bottom).
theorem fieldcount_scalar_conflict :
    (meet (.prim (.int 5)) (.fieldCountConstraint .min 1) == .bottom) = true := by native_decide

-- A bare validator is incomplete (cannot manifest).
theorem fieldcount_bare_incomplete :
    manifestValueOk (.fieldCountConstraint .min 0) = false := by native_decide

-- Display renders the CUE call form.
theorem fieldcount_format_min :
    formatField "x" (.fieldCountConstraint .min 2) = "x: struct.MinFields(2)" := by native_decide
theorem fieldcount_format_max :
    formatField "x" (.fieldCountConstraint .max 3) = "x: struct.MaxFields(3)" := by native_decide

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
    formatField "x" (meet (.kind .bytes) (.prim (.bytes (textBytes "abc")))) = "x: 'abc'" := by
  native_decide

theorem fixture_float_kind :
    formatField "x" (meet (.kind .float) (.prim (mkFloatText "1.5"))) = "x: 1.5" := by
  native_decide

theorem fixture_number_kind :
    formatField "x" (meet (.kind .number) (.prim (mkFloatText "1.5"))) = "x: 1.5" := by
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
      (mkStruct [
          ⟨"a", .regular, .prim (.int 1), false⟩,
          ⟨"b", .regular, .list [.prim (.string "x")], false⟩,
          ⟨"_hidden", .hidden, .prim (.bool true), false⟩,
          ⟨"#Schema", .definition, .kind .int, false⟩,
          ⟨"optional", .optional, .prim (.string "skip"), false⟩
        ] .regularOpen none [])
      = .ok (.struct [("a", .prim (.int 1)), ("b", .list [.prim (.string "x")])]) := by
  rfl

theorem fixture_manifest_field_filtering_format :
    formatManifestField "x"
      (mkStruct [
          ⟨"a", .regular, .prim (.int 1), false⟩,
          ⟨"b", .regular, .list [.prim (.string "x")], false⟩,
          ⟨"_hidden", .hidden, .prim (.bool true), false⟩,
          ⟨"#Schema", .definition, .kind .int, false⟩,
          ⟨"optional", .optional, .prim (.string "skip"), false⟩
        ] .regularOpen none [])
      = .ok "x: {a: 1, b: [\"x\"]}" := by
  rfl

theorem fixture_manifest_nested_default :
    manifestFieldMatches "x"
      (mkStruct [
          ⟨"mode", .regular,
            .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))], false⟩
        ] .regularOpen none [])
      "x: {mode: \"prod\"}" = true := by
  native_decide

theorem fixture_manifest_ignores_absent_optional_default :
    formatManifestField "x"
      (mkStruct [⟨"mode", .optional, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))], false⟩] .regularOpen none [])
      = .ok "x: {}" := by
  rfl

theorem fixture_manifest_selects_materialized_optional_default :
    manifestFieldMatches "x"
      (meet
        (mkStruct [⟨"mode", .optional, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))], false⟩] .regularOpen none [])
        (mkStruct [⟨"mode", .regular, .top, false⟩] .regularOpen none []))
      "x: {mode: \"prod\"}" = true := by
  native_decide

theorem fixture_manifest_selects_materialized_required_default :
    manifestFieldMatches "x"
      (meet
        (mkStruct [⟨"mode", .required, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))], false⟩] .regularOpen none [])
        (mkStruct [⟨"mode", .regular, .top, false⟩] .regularOpen none []))
      "x: {mode: \"prod\"}" = true := by
  native_decide

theorem fixture_let_binding :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"base", .letBinding, .prim (.int 2), false⟩,
            ⟨"x", .regular, .conj [.ref "base", .kind .int], false⟩,
            ⟨"nested", .regular,
              mkStruct [
                  ⟨"kind", .letBinding, .kind .string, false⟩,
                  ⟨"value", .regular, .conj [.ref "kind", .prim (.string "ok")], false⟩
                ] .regularOpen none [], false⟩
          ] .regularOpen none []))
      = "x: 2\nnested: {value: \"ok\"}" := by
  native_decide

theorem fixture_nested_reference_list :
    formatTopLevel
      (resolveAndEval
        (mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .list [.ref "#A"], false⟩] .regularOpen none []))
      = "#A: int\nx: [int]" := by
  native_decide

theorem fixture_direct_self_reference_cycle :
    formatTopLevel (resolveAndEval (mkStruct [⟨"x", .regular, .ref "x", false⟩] .regularOpen none [])) = "x: _" := by
  native_decide

theorem fixture_mutual_reference_cycle :
    formatTopLevel
      (resolveAndEval (mkStruct [⟨"x", .regular, .ref "y", false⟩, ⟨"y", .regular, .ref "x", false⟩] .regularOpen none []))
      = "x: _\ny: _" := by
  native_decide

theorem fixture_constrained_reference_cycle :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"x", .regular, .conj [.ref "x", .boundConstraint (intDecimal 0) .ge .number], false⟩,
            ⟨"a", .regular, .conj [.ref "b", .boundConstraint (intDecimal 0) .ge .number], false⟩,
            ⟨"b", .regular, .ref "a", false⟩
          ] .regularOpen none []))
      = "x: >=0\na: >=0\nb: >=0" := by
  native_decide

theorem fixture_three_reference_cycle :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"x", .regular, .ref "y", false⟩,
            ⟨"y", .regular, .ref "z", false⟩,
            ⟨"z", .regular, .ref "x", false⟩
          ] .regularOpen none []))
      = "x: _\ny: _\nz: _" := by
  native_decide

theorem fixture_manifest_hidden_field_reference :
    manifestFieldMatches "x"
        (evalStructRefs
          (resolveStructRefs
            (mkStruct [⟨"_secret", .hidden, .prim (.string "x"), false⟩, ⟨"value", .regular, .ref "_secret", false⟩] .regularOpen none [])))
        "x: {value: \"x\"}" = true := by
  native_decide

-- `_`-prefixed identifiers (`_base`) tokenize as identifiers, not as bare `_` (top).
-- Pins the parse fix: a reference, a comparison, an additive op, and equality over a
-- hidden underscore field all resolve against its value.
theorem fixture_underscore_ident_reference :
    formatField "out"
      (resolveAndEval
        (mkStruct [
            ⟨"_base", .hidden, .prim (.int 5), false⟩,
            ⟨"ref", .regular, .ref "_base", false⟩,
            ⟨"cmp", .regular, .binary .ne (.ref "_base") (.prim (.int 3)), false⟩,
            ⟨"sum", .regular, .binary .add (.ref "_base") (.prim (.int 1)), false⟩,
            ⟨"eq", .regular, .binary .eq (.ref "_base") (.prim (.int 5)), false⟩,
            ⟨"nested", .regular, .binary .ne (.ref "_base") (.ref "_base"), false⟩
          ] .regularOpen none []))
      = "out: {_base: 5, ref: 5, cmp: true, sum: 6, eq: true, nested: false}" := by
  native_decide

-- Regression: a bare `_` still means top (not an identifier prefix) when not followed
-- by an identifier char, and `_|_` still parses as bottom.
theorem fixture_underscore_top_unaffected :
    formatField "a" (meet .top (.prim (.int 1))) = "a: 1" := by
  native_decide

-- Regression: `_|_` parses as bottom (disjunction drops it) and the B2 value-position
-- struct alias (`X={…X.n…}`) still resolves the self-reference.
theorem fixture_underscore_top_bottom :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"bottom", .regular,
              .disj [(.regular, .bottom), (.regular, .prim (.int 2))], false⟩,
            ⟨"self", .regular,
              bindValueAlias "X"
                (mkStruct [
                    ⟨"n", .regular, .prim (.int 1), false⟩,
                    ⟨"m", .regular, .selector (.ref "X") "n", false⟩
                  ] .regularOpen none []), false⟩
          ] .regularOpen none []))
      = "bottom: 2\nself: {n: 1, m: 1}" := by
  native_decide

-- ### link-5 hidden-bottom-field propagation (argocd `packs.#Argo`, sub-fix 2 + regression fix).
--
-- A HIDDEN/definition field is OMITTED from output, but a field whose value IS bottom (`{#u: _|_}`,
-- or a conflict `{#u: string} & {#u: int}`) bottoms the enclosing struct (cue: explicit error).
-- Pre-fix `manifestFieldsWithFuel` skipped a hidden present field's value unconditionally, silently
-- dropping the bottom. The check is SHALLOW (`isBottom` on the field value, no recursion into its
-- subtree): a deep recurse spuriously bottomed the export when a hidden field is an imported-PACKAGE
-- binding (`defs`/`parts`) carrying `tests`/unreferenced definitions whose isolated conflicts cue
-- never evaluates (the cert-manager regression — cue is lazy on unreferenced imported content). The
-- shallow check stays SOUND (never a false error → no regression) while catching the explicit-bottom
-- and arm-kill cases; a nested-non-propagating hidden bottom (`{#u: {#c: string & int}}`) is a known
-- incompleteness vs cue (deferred — it needs imported-package laziness, not eager deep checking).
-- Exercised through the full manifest path (`exportSourcesToString`), which the eval-format
-- `formatTopLevel` pins above do not reach. The companion behaviour — an UNSET impossible OPTIONAL
-- field (`#u?: _|_`) does NOT bottom the struct, and arm-prunes correctly in a disjunction — lives in
-- `containsBottom` (`containsBottomFields`' optional-skip) and pinned by the `link5_disj_*` + fixture.

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



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @fixture_underscore_top_bottom
#check @a2followup_deep_hidden_incomplete_tolerated   -- link-5 hidden-bottom-field propagation (argocd `p...

end Kue
