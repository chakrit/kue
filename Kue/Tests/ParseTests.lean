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

-- An optional definition field (`#x?`) parses with both modifiers — definition and
-- optional — and meeting the definition against a provided `#x` merges the slot to a
-- present definition. Oracle: `cue v0.16.1` evals `y` to `{#x: "hi"}`. The flat-enum
-- parser dropped the definition-ness when it saw `?`, so this never merged.
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

-- Field-name axes are orthogonal (CUE): `_#x` is a HIDDEN DEFINITION — both `isDefinition`
-- and `isHidden` true. The flat parser classified `_#x` as hidden-only (`isDefinition` false),
-- which dropped its definition-ness: a hidden-def embedding's sibling self-ref never deferred to
-- a closure and missed use-site narrowing (argocd `#OpaqueSecret` link 2). Pin each axis.
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

-- A `#Def: Self={…}` value alias: `Self.field` self-reference resolves within the
-- definition (the load-bearing prod9/infra pattern).
theorem parse_value_alias_self_reference :
    parseOutputMatches
      "#D: Self={\n\tx: 5\n\ty: Self.x\n}\n"
      "#D: {x: 5, y: 5}" = true := by
  native_decide

-- A `Self.#hidden` self-reference resolves the hidden field — the `#Secret`/`#ConfigMap`
-- shape that base64/encoding builtins wrap.
theorem parse_value_alias_hidden_self_reference :
    parseOutputMatches
      "#S: Self={\n\t#name: \"tls\"\n\tdata: Self.#name\n}\n"
      "#S: {#name: \"tls\", data: \"tls\"}" = true := by
  native_decide

-- A non-`Self` value alias whose name is referenced inside its own value. The alias is
-- visible within the value it labels (not to siblings, per CUE scoping).
theorem parse_value_alias_named :
    parseOutputMatches
      "a: X={\n\tg: \"hi\"\n\te: X.g\n}\n"
      "a: {g: \"hi\", e: \"hi\"}" = true := by
  native_decide

-- The alias is visible from arbitrarily deep nested fields within its value.
theorem parse_value_alias_deep_nested :
    parseOutputMatches
      "a: Self={\n\tx: 1\n\tinner: {q: Self.x}\n}\n"
      "a: {x: 1, inner: {q: 1}}" = true := by
  native_decide

-- Value alias composes with B1 colon-shorthand: `b: c: Self.a` desugars under the alias.
theorem parse_value_alias_with_colon_shorthand :
    parseOutputMatches
      "f: Self={\n\ta: 7\n\tb: c: Self.a\n}\n"
      "f: {a: 7, b: {c: 7}}" = true := by
  native_decide

-- A self-reference cycle through the alias terminates at top (bounded), never loops.
theorem parse_value_alias_cycle_bounded :
    parseOutputMatches
      "a: Self={\n\tx: Self.y\n\ty: Self.x\n}\n"
      "a: {x: _, y: _}" = true := by
  native_decide

-- Regression: `a == b` stays an equality expression, NOT a `X=`-style alias. Asserted at
-- the Value level — the evaluated result is the concrete boolean.
theorem parse_equality_not_alias :
    parseOutputMatches
      "r: 1 == 1\ns: 1 == 2\n"
      "r: true\ns: false" = true := by
  native_decide

-- A malformed `X=` with no value expression reports a sensible line:col.
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

-- ## Qualified import-path parsing (F-3)
--
-- `ImportPath = '"' ImportLocation [ ":" identifier ] '"'`: the `:identifier` qualifier is
-- split out of the location at parse time into `Import.packageName`, leaving `path` the
-- bare location. `isPackageIdentifier`/`splitImportPath` enforce the identifier rule.

-- A bare location parses with no qualifier; `path` is the whole location.
theorem parse_import_bare_location :
    (parseImportSpec "\"example.com/defs\"".toList
      == .ok ({ path := "example.com/defs" }, [])) = true := by
  native_decide

-- An explicit `:identifier` qualifier is split out: `path` is the location, `packageName`
-- the qualifier.
theorem parse_import_qualified_location :
    (parseImportSpec "\"example.com/defs:foo\"".toList
      == .ok ({ path := "example.com/defs", packageName := some "foo" }, [])) = true := by
  native_decide

-- The qualifier names the package even when the last path element is not itself a valid
-- identifier (the case the suffix exists for — `pkg-with-dash:pkg`).
theorem parse_import_qualifier_for_dashed_last_element :
    (parseImportSpec "\"domain.com/pkg-with-dash:pkg\"".toList
      == .ok ({ path := "domain.com/pkg-with-dash", packageName := some "pkg" }, [])) = true := by
  native_decide

-- A `PackageName` alias prefix coexists with a `:identifier` qualifier; both are recorded.
theorem parse_import_alias_and_qualifier :
    (parseImportSpec "bar \"example.com/defs:foo\"".toList
      == .ok ({ path := "example.com/defs", packageName := some "foo", alias := some "bar" }, [])) = true := by
  native_decide

-- An underscore-led qualifier is a legal (non-definition) identifier.
theorem parse_import_underscore_qualifier :
    (parseImportSpec "\"example.com/defs:_foo\"".toList
      == .ok ({ path := "example.com/defs", packageName := some "_foo" }, [])) = true := by
  native_decide

-- A qualifier with a leading digit is not an identifier → parse error.
theorem parse_import_invalid_digit_qualifier_errors :
    (parseImportSpec "\"example.com/defs:2bad\"".toList).isOk = false := by
  native_decide

-- A definition-identifier qualifier (`#foo`) is rejected — a PackageName may not be a
-- definition identifier.
theorem parse_import_definition_qualifier_errors :
    (parseImportSpec "\"example.com/defs:#foo\"".toList).isOk = false := by
  native_decide

-- An empty qualifier (`location:`) is rejected.
theorem parse_import_empty_qualifier_errors :
    (parseImportSpec "\"example.com/defs:\"".toList).isOk = false := by
  native_decide

-- An empty location (`":foo"`, no ImportLocation) is rejected — cue errors `invalid
-- import path: ":foo"`.
theorem parse_import_empty_location_errors :
    (parseImportSpec "\":foo\"".toList).isOk = false := by
  native_decide

-- `isPackageIdentifier` accepts a plain identifier, accepts an underscore lead and a
-- double-underscore, and rejects empty / digit-led / definition forms / the lone blank
-- identifier `_` (cue: `_ is not a valid import path qualifier`).
theorem parse_is_package_identifier_cases :
    (isPackageIdentifier "foo" && isPackageIdentifier "_foo" && isPackageIdentifier "a1"
      && isPackageIdentifier "__"
      && !isPackageIdentifier "" && !isPackageIdentifier "1a" && !isPackageIdentifier "#foo"
      && !isPackageIdentifier "_#foo" && !isPackageIdentifier "_") = true := by
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

-- Two sources parse to the same pre-resolution `Value` AST. The colon-shorthand
-- contract: `a: b: 1` must build exactly what `a: {b: 1}` builds.
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

-- The `a: b` reference form is unchanged: a bare label NOT followed by `:` stays an
-- ordinary value, never a shorthand field.
theorem reference_value_not_treated_as_shorthand :
    parseOutputMatches "b: 2\na: b\n" "b: 2\na: 2" = true := by
  native_decide

-- A multiline `"""…"""` literal parses to the same `Value` AST as the single-line string
-- with the dedented content: the closing-line indentation is stripped from every content
-- line, the leading/trailing newlines are dropped, and the lines join with `\n`.
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

-- Interpolation `\(expr)` works inside a multiline literal, building the same
-- `.interpolation` AST as the single-line form.
theorem multiline_interpolation_equals_single_line :
    parseSameValue
      "n: \"bob\"\nx: \"\"\"\n\thi \\(n)\n\tbye\n\t\"\"\"\n"
      "n: \"bob\"\nx: \"hi \\(n)\\nbye\"\n" = true := by
  native_decide

-- A `'''…'''` literal is the multiline bytes form, parsing to the same dedented bytes
-- value as the single-line bytes literal.
theorem multiline_bytes_equals_single_line :
    parseSameValue "x: '''\n\tabc\n\tdef\n\t'''\n" "x: 'abc\\ndef'\n" = true := by
  native_decide

-- A content line lacking the closing-line indentation prefix is rejected, matching CUE's
-- "invalid whitespace". The bad line `bad` is line 4 here.
theorem multiline_under_indented_line_fails :
    parseFails "x: \"\"\"\n\tok\nbad\n\t\"\"\"\n" = true := by
  native_decide

-- Content on the opening-delimiter line is rejected: the delimiter must be followed by a
-- newline.
theorem multiline_content_on_opening_line_fails :
    parseFailsAt "x: \"\"\"hi\n\t\"\"\"\n" 1 7 = true := by
  native_decide

-- Interpolation inside multiline bytes is a documented deferral, rejected at parse.
theorem multiline_bytes_interpolation_deferred :
    parseFails "n: 5\nx: '''\n\tv\\(n)\n\t'''\n" = true := by
  native_decide

-- SC-1d: a pattern def with a `...` tail stays OPEN — the parser must PRESERVE the `...` when
-- patterns are present (it dropped it before, building a `.regularOpen`/`none`-tail node). With
-- the tail kept the def is open-via-tail, so meeting `{extra: 5}` admits `extra` despite it
-- matching no pattern. The output echoes the retained `...`.
theorem parse_pattern_tail_stays_open :
    parseOutputMatches
      "#A: {x: int, [=~\"^a\"]: int, ...}\nout: #A & {x: 1, extra: 5}\n"
      "#A: {x: int, [=~\"^a\"]: int, ...}\nout: {x: 1, extra: 5, [=~\"^a\"]: int, ...}" = true := by
  native_decide

-- SC-1d regression guard: the SAME pattern def WITHOUT `...` still CLOSES (SC-1c). `z` neither
-- declared nor matching `[=~"^a"]` bottoms. The fix preserves the tail without re-opening the
-- no-`...` case.
theorem parse_pattern_notail_closes :
    parseOutputMatches
      "#A: {x: int, [=~\"^a\"]: int}\nout: #A & {x: 1, z: 9}\n"
      "#A: {x: int, [=~\"^a\"]: int}\nout: {x: 1, z: _|_, [=~\"^a\"]: int}" = true := by
  native_decide

-- SC-1d: `...` opens the label-set but the pattern still value-constrains a MATCHING field —
-- `abc` matches `[=~"^a"]: int` so the string `"no"` bottoms. Orthogonal axes: `...` admits the
-- label, the pattern constrains the value.
theorem parse_pattern_tail_value_constrains :
    parseOutputMatches
      "#A: {x: int, [=~\"^a\"]: int, ...}\nout: #A & {x: 1, abc: \"no\"}\n"
      "#A: {x: int, [=~\"^a\"]: int, ...}\nout: {x: 1, abc: _|_, [=~\"^a\"]: int, ...}" = true := by
  native_decide

-- SC-1d coherence (ILL-1): a parsed pattern+`...` struct is OPEN-via-tail with `closedClauses
-- = []` (open ⇒ closes nothing). Inspect the parsed node directly: the tail is preserved AND the
-- openness is `defOpenViaTail` AND no closed clauses leak in.
theorem parse_pattern_tail_node_is_open_via_tail :
    (match parseSource "x: {a: int, [=~\"^a\"]: int, ...}\n" with
     | .ok (.struct [⟨"x", .regular, .struct _ openness tail _ closing⟩] _ _ _ _) =>
         openness == .defOpenViaTail && tail.isSome && closing == ([] : List ClosedClause)
     | _ => false) = true := by
  native_decide

-- Parser strictness: `__`-prefixed identifiers are spec-reserved keywords.
-- The CUE spec reserves every identifier whose raw spelling begins with `__` (two
-- underscores) as a language keyword, so a user identifier `__x` is invalid in EVERY
-- identifier position — field label, reference, alias. A single leading `_` (`_x`) is the
-- VALID hidden-field form; `#__x`/`_#__x` begin with `#`/`_#` (definition prefixes), not
-- `__`, so they stay valid; a quoted `"__x"` is a string label, not an identifier.

-- A `__`-prefixed reference is rejected (spec: identifiers starting with `__` are reserved).
-- `cue` likewise rejects `b: __x` as `identifiers starting with '__' are reserved`.
theorem parse_double_underscore_reference_reserved :
    parseFails "__x: 1\nb: __x\n" = true := by
  native_decide

-- A `__`-prefixed FIELD LABEL is rejected at parse — the reservation is on the identifier
-- spelling, regardless of position. (`cue` accepts the inline `a: __x: 1` shorthand but
-- rejects the brace form `a: { __x: 1 }`; Kue rejects both, conforming to the spec — see
-- cue-divergences.)
theorem parse_double_underscore_field_label_reserved :
    parseFails "__x: 1\n" = true := by
  native_decide

-- The inline nested form `a: __x: 1` is ALSO rejected — `cue` accepts it (a parser
-- inconsistency); the spec reserves `__x` everywhere.
theorem parse_double_underscore_inline_nested_reserved :
    parseFails "a: __x: 1\n" = true := by
  native_decide

-- The bare two-underscore `__` and the triple `___x` both begin with `__` → reserved.
theorem parse_bare_and_triple_underscore_reserved :
    (parseFails "__: 1\n" && parseFails "___x: 1\nb: ___x\n") = true := by
  native_decide

-- The reservation diagnostic anchors at the identifier (`b: __x` → the `__x` at col 4).
theorem parse_double_underscore_position :
    parseFailsAt "a: 1\nb: __x\n" 2 4 = true := by
  native_decide

-- BOUNDARY: a SINGLE leading underscore `_x` is the valid hidden-field identifier — it
-- must still parse and resolve.
theorem parse_single_underscore_hidden_still_parses :
    parseSucceeds "_x: 1\nb: _x\n" = true := by
  native_decide

-- BOUNDARY: the blank identifier `_` (top) still parses.
theorem parse_blank_underscore_still_parses :
    parseSucceeds "a: _\n" = true := by
  native_decide

-- BOUNDARY: `#__x` (definition prefix `#`) and `_#__x` (hidden-definition prefix `_#`)
-- begin with `#`/`_#`, NOT `__`, so they are NOT reserved — both still parse.
theorem parse_definition_prefixed_double_underscore_still_parses :
    (parseSucceeds "#__x: 5\nb: #__x\n" && parseSucceeds "_#__x: 5\nb: _#__x\n") = true := by
  native_decide

-- BOUNDARY: a QUOTED label `"__x"` is a string, not an identifier — not reserved.
theorem parse_quoted_double_underscore_label_still_parses :
    parseSucceeds "\"__x\": 1\n" = true := by
  native_decide

-- Parser strictness: the `*` default mark is valid only on a disjunct that has siblings.
-- The spec marks an ELEMENT OF a multi-term disjunction (`*1 | 2`), so a sole marked
-- operand — `*(1|2)` (mark on a parenthesized group), `*1` (single disjunct) — has no
-- alternatives to prefer and `cue` rejects it at parse with `preference mark not allowed at
-- this position`. A marked disjunct WITH siblings stays valid.

-- `*(1|2)` is rejected: the mark is on a parenthesized group that is the SOLE disjunct, not
-- an element of a disjunction. `cue`: `preference mark not allowed at this position`.
theorem parse_default_mark_on_sole_paren_group_rejected :
    parseFails "x: *(1|2)\n" = true := by
  native_decide

-- `*("a"|"b")` (string variant) and `*({a:1}|{b:2})` (struct variant) are rejected the same
-- way — the mark sits on a sole parenthesized-group disjunct.
theorem parse_default_mark_on_paren_group_variants_rejected :
    (parseFails "x: *(\"a\"|\"b\")\n" && parseFails "x: *({a:1}|{b:2})\n") = true := by
  native_decide

-- `*1` (a single disjunct marked, no `|` sibling) is rejected — there is nothing to prefer
-- it over.
theorem parse_default_mark_on_single_disjunct_rejected :
    (parseFails "x: *1\n" && parseFails "x: *(1)\n") = true := by
  native_decide

-- The rejection anchors at the leading `*` (`x: *(1|2)` → col 4).
theorem parse_default_mark_rejected_position :
    parseFailsAt "x: *(1|2)\n" 1 4 = true := by
  native_decide

-- BOUNDARY: `*1 | 2` (mark on a disjunct WITH a sibling) parses to the marked disjunction
-- AST intact — the canonical valid default. (Eval-collapse to `1` is pinned in the
-- disjunction-default suites; here the parse-level round-trip preserves the mark.)
theorem parse_default_mark_valid_two_disjuncts :
    parseOutputMatches "x: *1 | 2\n" "x: *1 | 2" = true := by
  native_decide

-- BOUNDARY: a valid string default `*"a" | "b"` and a list default `*[1] | [2]` both parse,
-- preserving the mark.
theorem parse_default_mark_valid_string_and_list :
    (parseOutputMatches "x: *\"a\" | \"b\"\n" "x: *\"a\" | \"b\""
      && parseOutputMatches "x: *[1] | [2]\n" "x: *[1] | [2]") = true := by
  native_decide

-- BOUNDARY: a parenthesized whole disjunction `(*1 | 2)` is valid — the `*` marks the inner
-- disjunct `1`, which has the sibling `2`. The parens dissolve, leaving the marked
-- disjunction.
theorem parse_default_mark_valid_inside_parens :
    parseOutputMatches "x: (*1 | 2)\n" "x: *1 | 2" = true := by
  native_decide

-- BOUNDARY: `*(1|2) | 3` PARSES (the mark is on a disjunct that has the sibling `3`); the
-- `*(1|2)` default being itself an unresolved disjunction is an EVAL concern, not a parse
-- error — matching `cue`, which parse-accepts and reports an incomplete value downstream.
theorem parse_default_mark_group_with_sibling_parses :
    parseSucceeds "x: *(1|2) | 3\n" = true := by
  native_decide

-- Aliased builtin-call canonicalization: an `import j "encoding/json"` aliases the package
-- locally, so `j.Marshal` must dispatch identically to the unaliased `json.Marshal`. The parser
-- lowers the call off the LITERAL head `j`, so a post-parse pass rewrites the alias head back to
-- the canonical family name BEFORE the alias-blind `BuiltinFamily.ofName?` dispatch. These pin
-- the unit pieces (the alias map + the head rewrite) and the end-to-end resolution per family.

-- The alias map records `(asWritten, canonical)` ONLY for a builtin import aliased to a
-- non-canonical head; an unaliased builtin (head == canonical) and a user import (non-builtin
-- path) contribute nothing — the boundary that keeps a user package from being misdispatched.
theorem builtin_import_local_names_maps_only_aliased_builtins :
    (builtinImportLocalNames [⟨"encoding/json", none, some "j"⟩]
        == [("j", "json")])
      && (builtinImportLocalNames [⟨"encoding/json", none, none⟩] == [])
      && (builtinImportLocalNames [⟨"strings", none, some "s"⟩] == [("s", "strings")])
      && (builtinImportLocalNames [⟨"ex.com/foo", none, some "f"⟩] == [])
      -- BINDING, not spelling: an alias whose text equals ANOTHER builtin's canonical name
      -- still maps to the family its PATH names (`import json "strings"` ⇒ `json` → `strings`).
      && (builtinImportLocalNames [⟨"strings", none, some "json"⟩] == [("json", "strings")])
      && (builtinImportLocalNames [⟨"encoding/json", none, some "strings"⟩]
          == [("strings", "json")]) = true := by
  native_decide

-- The head rewrite swaps the alias for its canonical package, keeps the leaf, and leaves an
-- unmapped head or a name with no `.` untouched.
theorem canonicalize_builtin_call_name_rewrites_only_mapped_head :
    (canonicalizeBuiltinCallName [("j", "json")] "j.Marshal" == "json.Marshal")
      && (canonicalizeBuiltinCallName [("j", "json")] "json.Marshal" == "json.Marshal")
      && (canonicalizeBuiltinCallName [("j", "json")] "f.Bar" == "f.Bar")
      && (canonicalizeBuiltinCallName [("j", "json")] "len" == "len") = true := by
  native_decide

-- End-to-end: an aliased builtin call resolves identically to the unaliased form, across every
-- package family (`json`/`strings`/`math`/`list`/`base64`/`yaml`).
theorem parse_aliased_builtin_call_resolves_like_unaliased :
    (parseOutputMatches "import j \"encoding/json\"\nout: j.Marshal({a: 1})\n"
        "out: \"{\\\"a\\\":1}\"")
      && parseOutputMatches "import s \"strings\"\nout: s.ToUpper(\"hi\")\n" "out: \"HI\""
      && parseOutputMatches "import m \"math\"\nout: m.Pow(2, 10)\n" "out: 1024"
      && parseOutputMatches "import l \"list\"\nout: l.Sum([1, 2, 3])\n" "out: 6"
      && parseOutputMatches "import b \"encoding/base64\"\nout: b.Encode(null, \"hi\")\n"
        "out: \"aGk=\""
      && parseOutputMatches "import y \"encoding/yaml\"\nout: y.Marshal({a: 1})\n"
        "out: \"a: 1\\n\""
      && parseOutputMatches "import r \"regexp\"\nout: r.Match(\"^a\", \"abc\")\n" "out: true"
        = true := by
  native_decide

-- BINDING, not spelling: when an alias's text collides with ANOTHER builtin's canonical name,
-- the call dispatches by the import's PATH, not the spelling. `import json "strings"` binds
-- `json` to the `strings` package, so `json.ToUpper` is `strings.ToUpper`, NOT a json call; and
-- the inverse `import strings "encoding/json"` makes `strings.Marshal` a json marshal. The single
-- highest wrong-dispatch risk — pinned end-to-end.
theorem parse_aliased_builtin_call_dispatches_by_binding_not_spelling :
    (parseOutputMatches "import json \"strings\"\nout: json.ToUpper(\"hi\")\n" "out: \"HI\"")
      && parseOutputMatches "import strings \"encoding/json\"\nout: strings.Marshal({a: 1})\n"
        "out: \"{\\\"a\\\":1}\"" = true := by
  native_decide

-- BOUNDARY: the unaliased builtin is unchanged, and an aliased USER import is NOT rewritten to a
-- builtin — `f.Bar` stays a deferred selector (here `f` is unbound, so it resolves to `_|_`,
-- never a marshaled string).
theorem parse_unaliased_builtin_and_aliased_user_import_unchanged :
    (parseOutputMatches "import \"encoding/json\"\nout: json.Marshal({a: 1})\n"
        "out: \"{\\\"a\\\":1}\"")
      && parseOutputMatches "import f \"ex.com/foo\"\nout: f.Bar\n" "out: _|_" = true := by
  native_decide

-- Aliased stdlib CONSTANT canonicalization (the no-call analog of the call canonicalization
-- above). A stdlib CONSTANT (`list.Ascending`/`Descending`/`Comparer`) resolves inline at parse
-- off the LITERAL head, so an aliased import (`import l "list"` ⇒ `l.Ascending`) keys
-- `stdlibPackageValue? "l" …` → `none` and survives as a deferred `.selector (.ref "l")
-- "Ascending"`. The post-parse pass maps the alias head back to the canonical package and
-- re-resolves, so an aliased constant yields the same comparator struct as the unaliased form.

-- The constant re-resolution maps a builtin-alias head to its canonical package and looks up
-- the stdlib constant; a non-builtin alias (absent from the map) and an unmapped/non-constant
-- label return `none` — the boundary that leaves a user import's `f.Ascending` untouched.
theorem canonicalize_builtin_const_resolves_only_aliased_stdlib :
    (canonicalizeBuiltinConst? [("l", "list")] "l" "Ascending"
        == stdlibPackageValue? "list" "Ascending")
      && (canonicalizeBuiltinConst? [("l", "list")] "l" "Descending"
        == stdlibPackageValue? "list" "Descending")
      && (canonicalizeBuiltinConst? [("l", "list")] "l" "Comparer"
        == stdlibPackageValue? "list" "Comparer")
      && (canonicalizeBuiltinConst? [("l", "list")] "l" "Nope" == none)
      && (canonicalizeBuiltinConst? [("f", "list")] "g" "Ascending" == none)
      && (canonicalizeBuiltinConst? [] "l" "Ascending" == none) = true := by
  native_decide

-- End-to-end: an aliased stdlib constant resolves identically to the unaliased form — driving
-- `Sort` with `l.Ascending`/`l.Descending`, and a standalone `l.Comparer` (the bare comparator
-- struct, byte-identical to the unaliased `list.Comparer` rendering).
theorem parse_aliased_stdlib_const_resolves_like_unaliased :
    (parseOutputMatches "import l \"list\"\nout: l.Sort([3, 1, 2], l.Ascending)\n"
        "out: [1, 2, 3]")
      && parseOutputMatches "import l \"list\"\nout: l.Sort([3, 1, 2], l.Descending)\n"
        "out: [3, 2, 1]"
      && (parseOutputMatches "import l \"list\"\nout: l.Comparer\n"
        "out: {T: number | string, x: number | string, y: number | string, less: bool}")
      && (parseOutputMatches "import \"list\"\nout: list.Comparer\n"
        "out: {T: number | string, x: number | string, y: number | string, less: bool}")
        = true := by
  native_decide

-- BOUNDARY: unaliased constants are unchanged, and an aliased USER import's const-shaped member
-- (`f.Ascending`) is NOT rewritten to the stdlib comparator — `f` is absent from the builtin
-- alias map, so the selector stays deferred (resolves to `_|_`, never the comparator struct).
theorem parse_unaliased_const_and_aliased_user_member_unchanged :
    (parseOutputMatches "import \"list\"\nout: list.Sort([3, 1, 2], list.Ascending)\n"
        "out: [1, 2, 3]")
      && parseOutputMatches "import f \"ex.com/foo\"\nout: f.Ascending\n" "out: _|_" = true := by
  native_decide

-- Coverage tripwire: a swallowed section (e.g. an unterminated `/-- -/`) would drop these
-- from elaboration. Each `#check` forces the last theorem of every section above to compile.
#check @parse_pattern_tail_node_is_open_via_tail
#check @parse_quoted_double_underscore_label_still_parses
#check @parse_default_mark_group_with_sibling_parses
#check @parse_unaliased_builtin_and_aliased_user_import_unchanged
#check @parse_unaliased_const_and_aliased_user_member_unchanged

end Kue
