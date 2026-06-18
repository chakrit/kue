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

def parseSucceeds (source : String) : Bool :=
  match parseSource source with
  | .ok _ => true
  | .error _ => false

def parseFailsAt (source : String) (line col : Nat) : Bool :=
  match parseSource source with
  | .ok _ => false
  | .error error => error.line == line && error.column == col

theorem parse_basic_document_resolves_references :
    parseOutputMatches
      "package demo\n#Port: int & >=0 & <=65535\nport: #Port & 8080\nname: \"api\"\n"
      "#Port: int & >=0 & <=65535\nport: 8080\nname: \"api\"" = true := by
  native_decide

/-- An optional definition field (`#x?`) parses with both modifiers — definition and
    optional — and meeting the definition against a provided `#x` merges the slot to a
    present definition. Oracle: `cue v0.16.1` evals `y` to `{#x: "hi"}`. The flat-enum
    parser dropped the definition-ness when it saw `?`, so this never merged. -/
theorem parse_optional_definition_merges_when_provided :
    parseOutputMatches
      "#D: {#x?: string}\ny: #D & {#x: \"hi\"}\n"
      "#D: {#x?: string}\ny: {#x: \"hi\"}" = true := by
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

/-- Field-name axes are orthogonal (CUE): `_#x` is a HIDDEN DEFINITION — both `isDefinition`
    and `isHidden` true. The flat parser classified `_#x` as hidden-only (`isDefinition` false),
    which dropped its definition-ness: a hidden-def embedding's sibling self-ref never deferred to
    a closure and missed use-site narrowing (argocd `#OpaqueSecret` link 2). Pin each axis. -/
theorem parse_field_class_definition :
    (parseFieldClass "#x" "#x".toList).fst == FieldClass.field true false .regular := by
  native_decide

theorem parse_field_class_hidden :
    (parseFieldClass "_x" "_x".toList).fst == FieldClass.field false true .regular := by
  native_decide

theorem parse_field_class_hidden_definition :
    (parseFieldClass "_#x" "_#x".toList).fst == FieldClass.field true true .regular := by
  native_decide

theorem parse_static_field_alias :
    parseOutputMatches
      "A=\"not an identifier\": 4\nfoo: A\n"
      "\"not an identifier\": 4\nfoo: 4" = true := by
  native_decide

/-- A `#Def: Self={…}` value alias: `Self.field` self-reference resolves within the
    definition (the load-bearing prod9/infra pattern). -/
theorem parse_value_alias_self_reference :
    parseOutputMatches
      "#D: Self={\n\tx: 5\n\ty: Self.x\n}\n"
      "#D: {x: 5, y: 5}" = true := by
  native_decide

/-- A `Self.#hidden` self-reference resolves the hidden field — the `#Secret`/`#ConfigMap`
    shape that base64/encoding builtins wrap. -/
theorem parse_value_alias_hidden_self_reference :
    parseOutputMatches
      "#S: Self={\n\t#name: \"tls\"\n\tdata: Self.#name\n}\n"
      "#S: {#name: \"tls\", data: \"tls\"}" = true := by
  native_decide

/-- A non-`Self` value alias whose name is referenced inside its own value. The alias is
    visible within the value it labels (not to siblings, per CUE scoping). -/
theorem parse_value_alias_named :
    parseOutputMatches
      "a: X={\n\tg: \"hi\"\n\te: X.g\n}\n"
      "a: {g: \"hi\", e: \"hi\"}" = true := by
  native_decide

/-- The alias is visible from arbitrarily deep nested fields within its value. -/
theorem parse_value_alias_deep_nested :
    parseOutputMatches
      "a: Self={\n\tx: 1\n\tinner: {q: Self.x}\n}\n"
      "a: {x: 1, inner: {q: 1}}" = true := by
  native_decide

/-- Value alias composes with B1 colon-shorthand: `b: c: Self.a` desugars under the alias. -/
theorem parse_value_alias_with_colon_shorthand :
    parseOutputMatches
      "f: Self={\n\ta: 7\n\tb: c: Self.a\n}\n"
      "f: {a: 7, b: {c: 7}}" = true := by
  native_decide

/-- A self-reference cycle through the alias terminates at top (bounded), never loops. -/
theorem parse_value_alias_cycle_bounded :
    parseOutputMatches
      "a: Self={\n\tx: Self.y\n\ty: Self.x\n}\n"
      "a: {x: _, y: _}" = true := by
  native_decide

/-- Regression: `a == b` stays an equality expression, NOT a `X=`-style alias. Asserted at
    the Value level — the evaluated result is the concrete boolean. -/
theorem parse_equality_not_alias :
    parseOutputMatches
      "r: 1 == 1\ns: 1 == 2\n"
      "r: true\ns: false" = true := by
  native_decide

/-- A malformed `X=` with no value expression reports a sensible line:col. -/
theorem parse_value_alias_missing_value_fails :
    parseFailsAt "a: X=\n" 2 1 = true := by
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

theorem parse_let_chain_references_prior_let :
    parseOutputMatches
      "let a = 1\nlet b = a + 1\nx: b\n"
      "x: 2" = true := by
  native_decide

theorem parse_let_inner_shadows_outer :
    parseOutputMatches
      "let v = 1\nouter: v\ninner: {let v = 2, val: v}\n"
      "outer: 1\ninner: {val: 2}" = true := by
  native_decide

theorem parse_let_references_sibling_field :
    parseOutputMatches
      "top: {base: 10, let doubled = base * 2, out: doubled}\n"
      "top: {base: 10, out: 20}" = true := by
  native_decide

theorem parse_let_not_emitted_in_output :
    parseOutputMatches
      "let secret = \"abc\"\nshown: secret\nother: 1\n"
      "shown: \"abc\"\nother: 1" = true := by
  native_decide

-- A `[...]`-led struct member is a list embedding (CUE: open list `[...]`), not a pattern
-- constraint. The parser must accept it as an embedding rather than committing to the
-- `[label]: value` pattern form. (Eval-time struct&list-embedding semantics are tracked
-- separately as the open-list slice; this pins the parse-level acceptance.)
theorem parse_open_list_embedding_in_struct :
    parseSucceeds "x: {#a: 1, [...]}\n" = true := by
  native_decide

theorem parse_list_literal_embedding_in_struct :
    parseSucceeds "x: {[1, 2, 3]}\n" = true := by
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

theorem parse_float_additive_expressions :
    parseOutputMatches
      "floatSum: 1.5 + 2.25\nintFloat: 1 + 2.5\nfloatSub: 5.5 - 2\nwhole: 1.5 + 1.5\nexp: 1e3 + 2\nsmall: 0.1 + 0.2\n"
      "floatSum: 3.75\nintFloat: 3.5\nfloatSub: 3.5\nwhole: 3.0\nexp: 1002.0\nsmall: 0.3" = true := by
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

theorem parse_numeric_comparison_expressions :
    parseOutputMatches
      "lt: 1.5 < 2\nle: 1.5 <= 1.50\ngt: 1e3 > 999.9\nge: 1.0 >= 1\neq: 1 == 1.0\nne: 1 != 1.0\n"
      "lt: true\nle: true\ngt: true\nge: true\neq: true\nne: false" = true := by
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

theorem parse_import_clause_is_ignored :
    parseOutputMatches
      "import \"strings\"\nx: 1\n"
      "x: 1" = true := by
  native_decide

theorem parse_grouped_import_clause_is_ignored :
    parseOutputMatches
      "import (\n\t\"strings\"\n)\nx: 1\n"
      "x: 1" = true := by
  native_decide

-- Parse errors carry 1-based source positions (line:column at the stuck offset).

theorem parse_error_position_line_one_column_one :
    parseFailsAt "@\n" 1 1 = true := by
  native_decide

theorem parse_error_position_line_one_midline :
    parseFailsAt "name: 4 @ 5\n" 1 9 = true := by
  native_decide

theorem parse_error_position_selector_after_dot :
    parseFailsAt "foo: bar.@\n" 1 10 = true := by
  native_decide

theorem parse_error_position_later_line :
    parseFailsAt "a: 1\nb: @\n" 2 4 = true := by
  native_decide

theorem parse_error_position_multiline_struct :
    parseFailsAt "x: {\n  a: 1\n  b: @\n}\n" 3 6 = true := by
  native_decide

theorem parse_error_position_eof_unclosed_list :
    parseFailsAt "a: 1\nb: 2\nx: [1, 2\n" 4 1 = true := by
  native_decide

theorem parse_error_position_unterminated_string :
    parseFailsAt "a: \"unterminated\n" 2 1 = true := by
  native_decide

/-- Two sources parse to the same pre-resolution `Value` AST. The colon-shorthand
    contract: `a: b: 1` must build exactly what `a: {b: 1}` builds. -/
def parseSameValue (left right : String) : Bool :=
  match parseSource left, parseSource right with
  | .ok l, .ok r => l == r
  | _, _ => false

theorem shorthand_two_level_equals_brace :
    parseSameValue "a: b: 1\n" "a: {b: 1}\n" = true := by
  native_decide

theorem shorthand_three_level_equals_brace :
    parseSameValue "a: b: c: 1\n" "a: {b: {c: 1}}\n" = true := by
  native_decide

theorem shorthand_quoted_inner_equals_brace :
    parseSameValue "a: \"x/y\": 1\n" "a: {\"x/y\": 1}\n" = true := by
  native_decide

theorem shorthand_mixed_with_brace_equals_brace :
    parseSameValue "a: b: {c: 1}\n" "a: {b: {c: 1}}\n" = true := by
  native_decide

theorem shorthand_dynamic_inner_equals_brace :
    parseSameValue "a: (\"k\"): 1\n" "a: {(\"k\"): 1}\n" = true := by
  native_decide

theorem shorthand_two_level_resolves :
    parseOutputMatches "a: b: 1\n" "a: {b: 1}" = true := by
  native_decide

theorem shorthand_three_level_resolves :
    parseOutputMatches "a: b: c: 1\n" "a: {b: {c: 1}}" = true := by
  native_decide

theorem shorthand_quoted_inner_resolves :
    parseOutputMatches "a: \"x/y\": 1\n" "a: {\"x/y\": 1}" = true := by
  native_decide

theorem shorthand_siblings_merge :
    parseOutputMatches "top: a: 1\ntop: b: 2\n" "top: {a: 1, b: 2}" = true := by
  native_decide

theorem shorthand_alongside_sibling_field :
    parseOutputMatches "a: b: 1\nx: 2\n" "a: {b: 1}\nx: 2" = true := by
  native_decide

theorem shorthand_prod9_metadata :
    parseOutputMatches
      "metadata: name: \"api\"\nspec: replicas: 3\n"
      "metadata: {name: \"api\"}\nspec: {replicas: 3}" = true := by
  native_decide

/-- The `a: b` reference form is unchanged: a bare label NOT followed by `:` stays an
    ordinary value, never a shorthand field. -/
theorem reference_value_not_treated_as_shorthand :
    parseOutputMatches "b: 2\na: b\n" "b: 2\na: 2" = true := by
  native_decide

/-- A multiline `"""…"""` literal parses to the same `Value` AST as the single-line string
    with the dedented content: the closing-line indentation is stripped from every content
    line, the leading/trailing newlines are dropped, and the lines join with `\n`. -/
theorem multiline_basic_equals_single_line :
    parseSameValue "x: \"\"\"\n\thello\n\tworld\n\t\"\"\"\n" "x: \"hello\\nworld\"\n" = true := by
  native_decide

theorem multiline_dedent_keeps_inner_indent :
    parseSameValue "x: \"\"\"\n\tline1\n\t  line2\n\t\"\"\"\n" "x: \"line1\\n  line2\"\n" = true := by
  native_decide

theorem multiline_empty_is_empty_string :
    parseSameValue "x: \"\"\"\n\t\"\"\"\n" "x: \"\"\n" = true := by
  native_decide

theorem multiline_no_indent_closing :
    parseSameValue "x: \"\"\"\nhello\nworld\n\"\"\"\n" "x: \"hello\\nworld\"\n" = true := by
  native_decide

theorem multiline_blank_content_line :
    parseSameValue "x: \"\"\"\n\ta\n\n\tb\n\t\"\"\"\n" "x: \"a\\n\\nb\"\n" = true := by
  native_decide

theorem multiline_escape_applies :
    parseSameValue "x: \"\"\"\n\ta\\tb\n\t\"\"\"\n" "x: \"a\\tb\"\n" = true := by
  native_decide

/-- Interpolation `\(expr)` works inside a multiline literal, building the same
    `.interpolation` AST as the single-line form. -/
theorem multiline_interpolation_equals_single_line :
    parseSameValue
      "n: \"bob\"\nx: \"\"\"\n\thi \\(n)\n\tbye\n\t\"\"\"\n"
      "n: \"bob\"\nx: \"hi \\(n)\\nbye\"\n" = true := by
  native_decide

/-- A `'''…'''` literal is the multiline bytes form, parsing to the same dedented bytes
    value as the single-line bytes literal. -/
theorem multiline_bytes_equals_single_line :
    parseSameValue "x: '''\n\tabc\n\tdef\n\t'''\n" "x: 'abc\\ndef'\n" = true := by
  native_decide

/-- A content line lacking the closing-line indentation prefix is rejected, matching CUE's
    "invalid whitespace". The bad line `bad` is line 4 here. -/
theorem multiline_under_indented_line_fails :
    parseFails "x: \"\"\"\n\tok\nbad\n\t\"\"\"\n" = true := by
  native_decide

/-- Content on the opening-delimiter line is rejected: the delimiter must be followed by a
    newline. -/
theorem multiline_content_on_opening_line_fails :
    parseFailsAt "x: \"\"\"hi\n\t\"\"\"\n" 1 7 = true := by
  native_decide

/-- Interpolation inside multiline bytes is a documented deferral, rejected at parse. -/
theorem multiline_bytes_interpolation_deferred :
    parseFails "n: 5\nx: '''\n\tv\\(n)\n\t'''\n" = true := by
  native_decide

end Kue
