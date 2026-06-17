import Kue.Yaml

namespace Kue

/-! Serializer pins for `manifestToYaml` / `valueToYaml` and the pretty-JSON path.
    Every expected string was oracle-checked against `cue` v0.16.1 (`cue export --out
    yaml` / default JSON / `yaml.Marshal`) before being encoded here. -/

-- Scalars: numbers/bool/null render bare; `1.50` keeps exact spelling.
theorem yaml_scalar_int : manifestToYaml (.prim (.int 42)) = "42" := by native_decide
theorem yaml_scalar_float : manifestToYaml (.prim (.float "1.50")) = "1.50" := by native_decide
theorem yaml_scalar_true : manifestToYaml (.prim (.bool true)) = "true" := by native_decide
theorem yaml_scalar_null : manifestToYaml (.prim .null) = "null" := by native_decide

-- String quoting: bare when safe.
theorem yaml_string_bare : manifestToYaml (.prim (.string "hello")) = "hello" := by native_decide
theorem yaml_string_with_space : manifestToYaml (.prim (.string "with space")) = "with space" := by native_decide
theorem yaml_string_colon_slash_bare : manifestToYaml (.prim (.string "a:b")) = "a:b" := by native_decide

-- Double-quoted: resolver-ambiguous (numeric-looking, YAML 1.1 bool/null tokens).
theorem yaml_string_numeric_quoted : manifestToYaml (.prim (.string "123")) = "\"123\"" := by native_decide
theorem yaml_string_float_like_quoted : manifestToYaml (.prim (.string ".5")) = "\".5\"" := by native_decide
theorem yaml_string_bool_word_quoted : manifestToYaml (.prim (.string "true")) = "\"true\"" := by native_decide
theorem yaml_string_yes_quoted : manifestToYaml (.prim (.string "yes")) = "\"yes\"" := by native_decide
theorem yaml_string_single_y_quoted : manifestToYaml (.prim (.string "y")) = "\"y\"" := by native_decide
theorem yaml_string_single_f_quoted : manifestToYaml (.prim (.string "f")) = "\"f\"" := by native_decide
theorem yaml_string_empty_quoted : manifestToYaml (.prim (.string "")) = "\"\"" := by native_decide

-- Single-quoted: structurally unsafe plain but not resolver-ambiguous.
theorem yaml_string_leading_bracket : manifestToYaml (.prim (.string "[bracket")) = "'[bracket'" := by native_decide
theorem yaml_string_leading_hash : manifestToYaml (.prim (.string "#x")) = "'#x'" := by native_decide
theorem yaml_string_leading_star : manifestToYaml (.prim (.string "*star")) = "'*star'" := by native_decide
theorem yaml_string_colon_space : manifestToYaml (.prim (.string "a: b")) = "'a: b'" := by native_decide
theorem yaml_string_space_hash : manifestToYaml (.prim (.string "a # b")) = "'a # b'" := by native_decide
theorem yaml_string_trailing_colon : manifestToYaml (.prim (.string "x:")) = "'x:'" := by native_decide
theorem yaml_string_all_spaces : manifestToYaml (.prim (.string "  ")) = "'  '" := by native_decide
-- bare cases that look risky but are not: leading `-`/`?`/`:` without following space, comma.
theorem yaml_string_leading_dash_bare : manifestToYaml (.prim (.string "-x")) = "-x" := by native_decide
theorem yaml_string_trailing_comma_bare : manifestToYaml (.prim (.string "comma,")) = "comma," := by native_decide

-- Empty containers.
theorem yaml_empty_struct : manifestToYaml (.struct []) = "{}" := by native_decide
theorem yaml_empty_list : manifestToYaml (.list []) = "[]" := by native_decide

-- A nested map: children indent two spaces; YAML 1.1 key `f` is quoted.
theorem yaml_nested_map :
    manifestToYaml (.struct [("metadata", .struct [("name", .prim (.string "web")), ("f", .prim (.int 2))])])
      = "metadata:\n  name: web\n  \"f\": 2" := by native_decide

-- A list of scalars and a list of maps (sequence indentation).
theorem yaml_list_scalars :
    manifestToYaml (.struct [("nums", .list [.prim (.int 1), .prim (.int 2), .prim (.int 3)])])
      = "nums:\n  - 1\n  - 2\n  - 3" := by native_decide

theorem yaml_list_of_maps_multi :
    manifestToYaml (.list [.struct [("kind", .prim (.string "A")), ("x", .prim (.int 1))],
                           .struct [("kind", .prim (.string "B")), ("y", .prim (.int 2))]])
      = "- kind: A\n  x: 1\n- kind: B\n  \"y\": 2" := by native_decide

-- Nested list-in-list `- - 1`.
theorem yaml_list_in_list :
    manifestToYaml (.struct [("d", .list [.list [], .list [.prim (.int 1)]])])
      = "d:\n  - []\n  - - 1" := by native_decide

-- Block scalar `|-` for a string containing newlines (chomped, no trailing newline).
theorem yaml_block_scalar :
    manifestToYaml (.struct [("a", .prim (.string "line one\nline two"))])
      = "a: |-\n  line one\n  line two" := by native_decide

-- Chomping indicators encode trailing newlines so the string round-trips losslessly.
-- One trailing newline clips (`|`); two or more keep (`|+`) with explicit blank lines.
-- Oracle: `cue export --out yaml` v0.16.1.
theorem yaml_block_scalar_clip_one_trailing :
    manifestToYaml (.struct [("a", .prim (.string "x\ny\n"))])
      = "a: |\n  x\n  y" := by native_decide
theorem yaml_block_scalar_keep_two_trailing :
    manifestToYaml (.struct [("a", .prim (.string "x\ny\n\n"))])
      = "a: |+\n  x\n  y\n" := by native_decide
theorem yaml_block_scalar_keep_three_trailing :
    manifestToYaml (.struct [("a", .prim (.string "x\ny\n\n\n"))])
      = "a: |+\n  x\n  y\n\n" := by native_decide

-- Interior blank line stays blank (no chomp change, no indent on the empty line).
theorem yaml_block_scalar_interior_blank :
    manifestToYaml (.struct [("a", .prim (.string "x\n\ny"))])
      = "a: |-\n  x\n\n  y" := by native_decide

-- A leading-space first line forces the explicit indentation indicator (`|N-`), else the
-- block's indentation would be ambiguous to a reader/parser. Oracle: `cue` emits `|2-`.
theorem yaml_block_scalar_leading_space_indent_indicator :
    manifestToYaml (.struct [("a", .prim (.string " x\ny"))])
      = "a: |2-\n   x\n  y" := by native_decide

-- bytes → base64 string scalar (matches JSON's byte handling).
theorem yaml_bytes_base64 :
    manifestToYaml (.prim (.bytes "hi")) = "aGk=" := by native_decide

-- A k8s-Deployment-shaped value, oracle-matched byte-for-byte against `cue export --out yaml`.
theorem yaml_k8s_deployment :
    manifestToYaml
      (.struct [
        ("apiVersion", .prim (.string "apps/v1")),
        ("kind", .prim (.string "Deployment")),
        ("metadata", .struct [
          ("name", .prim (.string "web")),
          ("labels", .struct [("app", .prim (.string "web")), ("tier", .prim (.string "frontend"))])]),
        ("spec", .struct [
          ("replicas", .prim (.int 3)),
          ("selector", .struct [("matchLabels", .struct [("app", .prim (.string "web"))])]),
          ("template", .struct [
            ("metadata", .struct [("labels", .struct [("app", .prim (.string "web"))])]),
            ("spec", .struct [
              ("containers", .list [.struct [
                ("name", .prim (.string "web")),
                ("image", .prim (.string "nginx:1.25")),
                ("ports", .list [.struct [("containerPort", .prim (.int 80))]]),
                ("env", .list [.struct [("name", .prim (.string "FOO")), ("value", .prim (.string "bar"))]])]])])])])])
      =
        "apiVersion: apps/v1\n" ++
        "kind: Deployment\n" ++
        "metadata:\n" ++
        "  name: web\n" ++
        "  labels:\n" ++
        "    app: web\n" ++
        "    tier: frontend\n" ++
        "spec:\n" ++
        "  replicas: 3\n" ++
        "  selector:\n" ++
        "    matchLabels:\n" ++
        "      app: web\n" ++
        "  template:\n" ++
        "    metadata:\n" ++
        "      labels:\n" ++
        "        app: web\n" ++
        "    spec:\n" ++
        "      containers:\n" ++
        "        - name: web\n" ++
        "          image: nginx:1.25\n" ++
        "          ports:\n" ++
        "            - containerPort: 80\n" ++
        "          env:\n" ++
        "            - name: FOO\n" ++
        "              value: bar" := by native_decide

-- `yaml.Marshal` framing: a trailing newline (oracle: `yaml.Marshal({a:1,...})`).
theorem yaml_marshal_trailing_newline :
    (valueToYaml (.struct [("a", .regular, .prim (.int 1)),
                           ("b", .regular, .list [.prim (.int 1), .prim (.int 2)])] true)).toOption
      == some "a: 1\nb:\n  - 1\n  - 2\n" := by native_decide

theorem yaml_marshal_list :
    (valueToYaml (.list [.struct [("a", .regular, .prim (.int 1))] true,
                         .struct [("b", .regular, .prim (.int 2))] true])).toOption
      == some "- a: 1\n- b: 2\n" := by native_decide

-- Pretty JSON (the `cue export` default): 4-space indent, source-order keys, trailing nl.
theorem json_pretty_nested :
    (valueToJsonPretty (.struct [
      ("a", .regular, .prim (.int 1)),
      ("b", .regular, .struct [("c", .regular, .prim (.string "x")),
                               ("d", .regular, .list [.prim (.int 1), .prim (.int 2)])] true),
      ("e", .regular, .prim (.float "1.50")),
      ("f", .regular, .list [] ),
      ("g", .regular, .struct [] true)] true)).toOption
      ==
        some ("{\n" ++
          "    \"a\": 1,\n" ++
          "    \"b\": {\n" ++
          "        \"c\": \"x\",\n" ++
          "        \"d\": [\n" ++
          "            1,\n" ++
          "            2\n" ++
          "        ]\n" ++
          "    },\n" ++
          "    \"e\": 1.50,\n" ++
          "    \"f\": [],\n" ++
          "    \"g\": {}\n" ++
          "}\n") := by native_decide

end Kue
