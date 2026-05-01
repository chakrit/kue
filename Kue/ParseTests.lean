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

theorem parse_disjunction_defaults_and_bounds :
    parseOutputMatches
      "mode: *\"prod\" | \"dev\"\nsmall: >0 & <10 & 7\n"
      "mode: *\"prod\" | \"dev\"\nsmall: 7" = true := by
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
