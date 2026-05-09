import Kue.Parse
import Kue.Runtime

namespace Kue

def parseOutputMatches (source expected : String) : Bool :=
  match parseSource source with
  | .ok value => formatResolvedTopLevel value == expected
  | .error _ => false

def parseFails (source : String) : Bool :=
  match parseSource source with
  | .ok _ => false
  | .error _ => true

theorem parse_basic_document_resolves_references :
    parseOutputMatches
      "package demo\n#Port: int & >=0 & <=65535\nport: #Port & 8080\nname: \"api\"\n"
      "#Port: >=0 & <=65535\nport: 8080\nname: \"api\"" = true := by
  native_decide

theorem parse_compound_values_and_builtins :
    parseOutputMatches
      "xs: [1, \"x\"]\nmeta: {name: \"api\", n: len(xs)}\n"
      "xs: [1, \"x\"]\nmeta: {name: \"api\", n: 2}" = true := by
  native_decide

theorem parse_nested_struct_resolves_local_definition :
    parseOutputMatches
      "x: {#A: int, x: #A}\n"
      "x: {#A: int, x: int}" = true := by
  native_decide

theorem parse_static_field_selector :
    parseOutputMatches
      "base: {inner: 4}\nx: base.inner\n"
      "base: {inner: 4}\nx: 4" = true := by
  native_decide

theorem parse_static_list_index :
    parseOutputMatches
      "xs: [10, 20]\nx: xs[1]\n"
      "xs: [10, 20]\nx: 20" = true := by
  native_decide

theorem parse_static_string_field_index :
    parseOutputMatches
      "base: {inner: 4}\nx: base[\"inner\"]\n"
      "base: {inner: 4}\nx: 4" = true := by
  native_decide

theorem parse_duplicate_fields_unify :
    parseOutputMatches
      "a: int\na: 1\n"
      "a: 1" = true := by
  native_decide

theorem parse_duplicate_field_conflict_preserves_bottom_field :
    parseOutputMatches
      "a: \"x\"\na: \"y\"\n"
      "a: _|_" = true := by
  native_decide

theorem parse_struct_reference_embedding :
    parseOutputMatches
      "#Base: {a: int}\nx: {#Base, a: 1}\n"
      "#Base: {a: int}\nx: {a: 1}" = true := by
  native_decide

theorem parse_static_field_alias :
    parseOutputMatches
      "A=\"not an identifier\": 4\nfoo: A\n"
      "\"not an identifier\": 4\nfoo: 4" = true := by
  native_decide

theorem parse_struct_literal_embedding :
    parseOutputMatches
      "x: {{a: int}, a: 1, b: \"ok\"}\n"
      "x: {a: 1, b: \"ok\"}" = true := by
  native_decide

theorem parse_top_level_let_binding :
    parseOutputMatches
      "let base = 2\nx: base & int\n"
      "x: 2" = true := by
  native_decide

theorem parse_nested_let_binding :
    parseOutputMatches
      "x: {let base = string, value: base & \"ok\"}\n"
      "x: {value: \"ok\"}" = true := by
  native_decide

theorem parse_disjunction_defaults_and_bounds :
    parseOutputMatches
      "mode: *\"prod\" | \"dev\"\nsmall: >0 & <10 & 7\n"
      "mode: *\"prod\" | \"dev\"\nsmall: 7" = true := by
  native_decide

theorem parse_integer_bound_disjunction_normalizes :
    parseOutputMatches
      "x: >=5 | >=0\n"
      "x: >=0" = true := by
  native_decide

theorem parse_number_disjunction_normalizes :
    parseOutputMatches
      "x: number | 1\n"
      "x: number" = true := by
  native_decide

theorem parse_decimal_separators_and_exponents :
    parseOutputMatches
      "x: 1_000\ny: 1.25e3\nz: -2e3\n"
      "x: 1000\ny: 1.25e+3\nz: -2e+3" = true := by
  native_decide

theorem parse_non_decimal_integer_literals :
    parseOutputMatches
      "hex: 0x1f\noct: 0o17\nbin: 0b1010\nnegHex: -0x10\nsep: 0b10_10\n"
      "hex: 31\noct: 15\nbin: 10\nnegHex: -16\nsep: 10" = true := by
  native_decide

theorem parse_unary_plus_numeric_literals :
    parseOutputMatches
      "x: +1\ny: +1.5\nz: +0x10\n"
      "x: 1\ny: 1.5\nz: 16" = true := by
  native_decide

theorem parse_unary_numeric_expressions :
    parseOutputMatches
      "negGroup: -(1 + 2)\nposGroup: +(1 + 2)\nnegRefBase: 3\nnegRef: -negRefBase\nprecedence: -2 * 3\n"
      "negGroup: -3\nposGroup: 3\nnegRefBase: 3\nnegRef: -3\nprecedence: -6" = true := by
  native_decide

theorem parse_numeric_suffix_literals :
    parseOutputMatches
      "k: 1K\nki: 1Ki\nfracK: 1.5K\nfracKi: 1.5Ki\nneg: -1.5K\n"
      "k: 1000\nki: 1024\nfracK: 1500\nfracKi: 1536\nneg: -1500" = true := by
  native_decide

theorem parse_inexact_numeric_suffix_fails :
    parseFails "bad: 0.1Ki\n" = true := by
  native_decide

theorem parse_additive_expressions :
    parseOutputMatches
      "sum: 1 + 2\ndiff: 5 - 3\ncat: \"a\" + \"b\"\n"
      "sum: 3\ndiff: 2\ncat: \"ab\"" = true := by
  native_decide

theorem parse_bytes_additive_expressions :
    parseOutputMatches
      "bytes: 'ab' + 'cd'\nleft: 'a' + 'b' + 'c'\n"
      "bytes: 'abcd'\nleft: 'abc'" = true := by
  native_decide

theorem parse_multiplication_expressions :
    parseOutputMatches
      "mul: 3 * 4\nprecedence: 1 + 2 * 3\nleft: 2 * 3 * 4\n"
      "mul: 12\nprecedence: 7\nleft: 24" = true := by
  native_decide

theorem parse_division_expressions :
    parseOutputMatches
      "div: 5 / 2\nwhole: 6 / 3\nthird: 1 / 3\nnegative: -5 / 2\n"
      "div: 2.5\nwhole: 2.0\nthird: 0.3333333333333333333333333333333333\nnegative: -2.5" = true := by
  native_decide

theorem parse_integer_keyword_expressions :
    parseOutputMatches
      "divValue: -7 div 3\nmodValue: -7 mod 3\nquoValue: -7 quo 3\nremValue: -7 rem 3\nprecedence: 1 + 7 div 3\n"
      "divValue: -3\nmodValue: 2\nquoValue: -2\nremValue: -1\nprecedence: 3" = true := by
  native_decide

theorem parse_equality_expressions :
    parseOutputMatches
      "same: 1 == 1\ndiff: 1 != 2\ntext: \"a\" == \"b\"\nprecedence: 1 + 1 == 2\n"
      "same: true\ndiff: true\ntext: false\nprecedence: true" = true := by
  native_decide

theorem parse_ordering_expressions :
    parseOutputMatches
      "lt: 1 < 2\nle: 2 <= 2\ngt: 3 > 2\nge: 3 >= 4\nslt: \"a\" < \"b\"\nprecedence: 1 + 2 < 4\n"
      "lt: true\nle: true\ngt: true\nge: false\nslt: true\nprecedence: true" = true := by
  native_decide

theorem parse_logical_expressions :
    parseOutputMatches
      "andFalse: true && false\norTrue: false || true\nandCmp: 1 < 2 && 3 > 2\norCmp: false || 1 + 1 == 2\ngrouped: (false || true) && true\n"
      "andFalse: false\norTrue: true\nandCmp: true\norCmp: true\ngrouped: true" = true := by
  native_decide

theorem parse_logical_not_expressions :
    parseOutputMatches
      "notFalse: !false\nnotCmp: !(1 < 2)\ndouble: !!true\n"
      "notFalse: true\nnotCmp: false\ndouble: true" = true := by
  native_decide

theorem parse_regex_match_expressions :
    parseOutputMatches
      "match: \"abc\" =~ \"^a\"\nmiss: \"abc\" =~ \"z\"\nnotMatch: \"abc\" !~ \"z\"\nnotMiss: \"abc\" !~ \"^a\"\nprecedence: \"ab\" + \"c\" =~ \"^abc$\"\n"
      "match: true\nmiss: false\nnotMatch: true\nnotMiss: false\nprecedence: true" = true := by
  native_decide

theorem parse_string_pattern_field :
    parseOutputMatches
      "x: {[string]: int, a: 1, b: 2}\n"
      "x: {a: 1, b: 2, [string]: int}" = true := by
  native_decide

theorem parse_exact_label_pattern_field :
    parseOutputMatches
      "x: {[\"a\"]: int, a: 1, b: \"skip\"}\n"
      "x: {a: 1, b: \"skip\", [\"a\"]: int}" = true := by
  native_decide

theorem parse_regex_pattern_field :
    parseOutputMatches
      "x: {[=~\"^a$\"]: int, a: 1, b: \"skip\"}\n"
      "x: {a: 1, b: \"skip\", [=~\"^a$\"]: int}" = true := by
  native_decide

theorem parse_pattern_field_constrains_matching_fields :
    parseOutputMatches
      "x: {[string]: int, a: \"bad\"}\n"
      "x: {a: _|_, [string]: int}" = true := by
  native_decide

theorem parse_multiple_pattern_fields_remain_independent :
    parseOutputMatches
      "x: {[=~\"^a\"]: int, [=~\"z$\"]: string, az: 1, ax: 2, bz: \"ok\"}\n"
      "x: {az: _|_, ax: 2, bz: \"ok\", [=~\"^a\"]: int, [=~\"z$\"]: string}" = true := by
  native_decide

theorem parse_newline_pattern_field_after_identifier_constraint :
    parseOutputMatches
      "x: {\n[=~\"^a\"]: int\n[=~\"z$\"]: string\naz: 1\n}\n"
      "x: {az: _|_, [=~\"^a\"]: int, [=~\"z$\"]: string}" = true := by
  native_decide

theorem parse_list_tail_schema :
    parseOutputMatches
      "xs: [...int]\nys: [int, ...string]\n"
      "xs: [...int]\nys: [int, ...string]" = true := by
  native_decide

theorem parse_list_tail_unification :
    parseOutputMatches
      "x: [int, ...string] & [1, \"x\", \"y\"]\n"
      "x: [1, \"x\", \"y\"]" = true := by
  native_decide

theorem parse_struct_ellipsis_schema :
    parseOutputMatches
      "x: {a: int, ...}\n"
      "x: {a: int, ...}" = true := by
  native_decide

theorem parse_struct_ellipsis_unification :
    parseOutputMatches
      "x: {a: int, ...} & {a: 1, b: \"ok\"}\n"
      "x: {a: 1, b: \"ok\", ...}" = true := by
  native_decide

theorem parse_byte_literal :
    parseOutputMatches
      "data: 'abc'\n"
      "data: 'abc'" = true := by
  native_decide

theorem parse_bytes_kind_unification :
    parseOutputMatches
      "x: bytes & 'abc'\n"
      "x: 'abc'" = true := by
  native_decide

theorem parse_imports_are_unsupported :
    parseFails "import \"strings\"\nx: 1\n" = true := by
  native_decide

end Kue
