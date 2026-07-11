import Kue.Builtin

namespace Kue

open TextTemplate

-- STDLIB-TEXTTEMPLATE-T1: the `text/template` package's minimal green core + escapers, pinned
-- against cue v0.16.1. The pure engine (`runTemplate` over `TemplateData`) carries the bulk of
-- behavior; `manifestToTemplateData` pins the Value→data bridge (float defer + key sort); a few
-- `evalBuiltinCall` theorems pin the dispatch verdicts (escapers, unsupported, nonexistent leaf).
-- DEFERRED constructs (funcs/pipelines/vars/define, float data, non-ASCII JSEscape) resolve to
-- `unsupportedBuiltin`; malformed templates and field-access-on-scalar bottom.

private def run (tmpl : String) (data : TemplateData) : Except TemplateError String :=
  runTemplate tmpl data

private def st (fields : List (String × TemplateData)) : TemplateData := .struct fields

-- ### Rendering — scalars, structs (Go `map[…]`), lists (Go `[…]`)

theorem tt_basic :
    (run "Hello {{ .name }}" (st [("name", .str "World")]) == .ok "Hello World") = true := by
  native_decide
theorem tt_nested_field :
    (run "{{.A.B}}" (st [("A", st [("B", .str "deep")])]) == .ok "deep") = true := by native_decide
theorem tt_dot_scalar :
    (run "{{.}}" (.str "hi") == .ok "hi") = true := by native_decide
theorem tt_dot_struct :
    (run "{{.}}" (st [("a", .int 1), ("b", .int 2)]) == .ok "map[a:1 b:2]") = true := by
  native_decide
theorem tt_dot_list :
    (run "{{.}}" (.list [.int 1, .int 2, .int 3]) == .ok "[1 2 3]") = true := by native_decide
theorem tt_missing_field :
    (run "{{.missing}}" (st [("a", .int 1)]) == .ok "<no value>") = true := by native_decide
theorem tt_null_field :
    (run "{{.x}}" (st [("x", .null)]) == .ok "<no value>") = true := by native_decide
theorem tt_bool_int :
    (run "{{.b}} {{.i}}" (st [("b", .bool true), ("i", .int 42)]) == .ok "true 42") = true := by
  native_decide
theorem tt_negative_int :
    (run "{{.}}" (.int (-7)) == .ok "-7") = true := by native_decide

-- Nested Go-fmt rendering: nested structs, list-in-struct, null nested ⇒ `<nil>` (not `<no value>`).
theorem tt_nested_map :
    (run "{{.}}" (st [("a", st [("b", .int 1)]), ("c", .list [.int 1, .int 2])])
      == .ok "map[a:map[b:1] c:[1 2]]") = true := by native_decide
theorem tt_map_str_vals :
    (run "{{.}}" (st [("a", .str "x"), ("b", .str "y")]) == .ok "map[a:x b:y]") = true := by
  native_decide
theorem tt_list_nested :
    (run "{{.}}" (.list [.list [.int 1, .int 2], .list [.int 3]]) == .ok "[[1 2] [3]]") = true := by
  native_decide
theorem tt_map_null_nested :
    (run "{{.}}" (st [("a", .null), ("b", .bool true)]) == .ok "map[a:<nil> b:true]") = true := by
  native_decide
theorem tt_list_null_nested :
    (run "{{.}}" (.list [.null, .int 1, .str "x"]) == .ok "[<nil> 1 x]") = true := by native_decide
theorem tt_empty_map :
    (run "{{.}}" (st []) == .ok "map[]") = true := by native_decide
theorem tt_empty_list :
    (run "{{.}}" (.list []) == .ok "[]") = true := by native_decide

-- ### `if` / `else` — Go truthiness

theorem tt_if_true :
    (run "{{if .x}}yes{{else}}no{{end}}" (st [("x", .bool true)]) == .ok "yes") = true := by
  native_decide
theorem tt_if_empty_string :
    (run "{{if .x}}yes{{else}}no{{end}}" (st [("x", .str "")]) == .ok "no") = true := by native_decide
theorem tt_if_zero :
    (run "{{if .x}}yes{{else}}no{{end}}" (st [("x", .int 0)]) == .ok "no") = true := by native_decide
theorem tt_if_empty_list :
    (run "{{if .x}}yes{{else}}no{{end}}" (st [("x", .list [])]) == .ok "no") = true := by
  native_decide
theorem tt_if_empty_struct :
    (run "{{if .x}}yes{{else}}no{{end}}" (st [("x", st [])]) == .ok "no") = true := by native_decide
theorem tt_if_missing :
    (run "{{if .missing}}Y{{else}}N{{end}}" (st [("a", .int 1)]) == .ok "N") = true := by
  native_decide
theorem tt_if_no_else :
    (run "{{if .x}}Y{{end}}" (st [("x", .bool false)]) == .ok "") = true := by native_decide

-- ### `range` — over list, over struct (KEY order preserved by builder), empty, null

theorem tt_range_list :
    (run "{{range .}}[{{.}}]{{end}}" (.list [.int 1, .int 2, .int 3]) == .ok "[1][2][3]") = true := by
  native_decide
theorem tt_range_struct :
    (run "{{range .}}[{{.}}]{{end}}" (st [("a", .int 1), ("b", .int 2), ("c", .int 3)])
      == .ok "[1][2][3]") = true := by native_decide
theorem tt_range_empty_else :
    (run "{{range .}}x{{else}}none{{end}}" (.list []) == .ok "none") = true := by native_decide
theorem tt_range_null_else :
    (run "{{range .x}}a{{else}}E{{end}}" (st [("x", .null)]) == .ok "E") = true := by native_decide
theorem tt_range_nested_field :
    (run "{{range .items}}{{.name}},{{end}}"
      (st [("items", .list [st [("name", .str "a")], st [("name", .str "b")]])])
      == .ok "a,b,") = true := by native_decide
theorem tt_range_scalar_unsupported :
    (run "{{range .x}}a{{end}}" (st [("x", .int 5)]) == .error .unsupported) = true := by
  native_decide

-- ### `with`

theorem tt_with :
    (run "{{with .x}}{{.y}}{{end}}" (st [("x", st [("y", .str "hi")])]) == .ok "hi") = true := by
  native_decide
theorem tt_with_else :
    (run "{{with .x}}has{{else}}empty{{end}}" (st [("x", .str "")]) == .ok "empty") = true := by
  native_decide

-- ### Comments and whitespace trimming

theorem tt_comment :
    (run "a{{/* c */}}b" (st []) == .ok "ab") = true := by native_decide
theorem tt_ws_trim_both :
    (run "a  {{- .x -}}  b" (st [("x", .str "X")]) == .ok "aXb") = true := by native_decide
theorem tt_ws_trim_newline :
    (run "a\n{{- .x}}" (st [("x", .str "X")]) == .ok "aX") = true := by native_decide
theorem tt_ws_trim_start :
    (run "{{- .x}}" (st [("x", .str "S")]) == .ok "S") = true := by native_decide

-- ### Nested control

theorem tt_nested_if_range :
    (run "{{range .}}{{if .}}[{{.}}]{{end}}{{end}}" (.list [.int 1, .int 0, .int 2])
      == .ok "[1][2]") = true := by native_decide

-- ### Parse / eval errors ⇒ bottom

theorem tt_parse_unclosed :
    (run "{{.n" (st [("n", .int 1)]) == .error .bottom) = true := by native_decide
theorem tt_parse_stray_end :
    (run "{{end}}" (st []) == .error .bottom) = true := by native_decide
theorem tt_parse_stray_else :
    (run "{{else}}" (st []) == .error .bottom) = true := by native_decide
theorem tt_parse_empty_action :
    (run "{{}}" (st []) == .error .bottom) = true := by native_decide
theorem tt_field_on_scalar :
    (run "{{.x}}" (.str "hello") == .error .bottom) = true := by native_decide
theorem tt_field_on_int :
    (run "{{.a.b}}" (st [("a", .int 5)]) == .error .bottom) = true := by native_decide

-- ### Deferred constructs ⇒ unsupported

theorem tt_func_unsupported :
    (run "{{len .x}}" (st [("x", .list [.int 1])]) == .error .unsupported) = true := by native_decide
theorem tt_pipeline_unsupported :
    (run "{{.x | html}}" (st [("x", .str "a")]) == .error .unsupported) = true := by native_decide
theorem tt_variable_unsupported :
    (run "{{$y := .x}}" (st [("x", .str "a")]) == .error .unsupported) = true := by native_decide
theorem tt_define_unsupported :
    (run "{{define \"T\"}}x{{end}}" (st []) == .error .unsupported) = true := by native_decide
theorem tt_template_unsupported :
    (run "{{template \"T\"}}" (st []) == .error .unsupported) = true := by native_decide

-- ### Chained-missing renders `<no value>`, not an error

theorem tt_chain_missing :
    (run "[{{.a.b}}]" (st [("x", .int 1)]) == .ok "[<no value>]") = true := by native_decide

-- ### Escapers (pure)

theorem tt_html_specials :
    (htmlEscape "a<b>&\"c' x" == "a&lt;b&gt;&amp;&#34;c&#39; x") = true := by native_decide
theorem tt_html_slash_plain :
    (htmlEscape "</script>" == "&lt;/script&gt;") = true := by native_decide
theorem tt_html_passthrough :
    (htmlEscape "hello 123" == "hello 123") = true := by native_decide
theorem tt_html_nul :
    (htmlEscape (String.singleton (Char.ofNat 0)) == String.singleton (Char.ofNat 0xFFFD))
      = true := by native_decide
theorem tt_js_specials :
    (jsEscape "a<b>&=\"c' x" == some "a\\u003Cb\\u003E\\u0026\\u003D\\\"c\\' x") = true := by
  native_decide
theorem tt_js_backslash_tab :
    (jsEscape "\\\t" == some "\\\\\\u0009") = true := by native_decide
theorem tt_js_passthrough :
    (jsEscape "hello world 123" == some "hello world 123") = true := by native_decide
-- Non-ASCII ⇒ deferred (needs unicode.IsPrint; see cue-spec-gaps.md).
theorem tt_js_nonascii_deferred :
    (jsEscape "café" == none) = true := by native_decide

-- ### Bridge: `manifestToTemplateData` (float defer + key sort)

theorem tt_bridge_float_defer :
    (manifestToTemplateData (.prim (.float { numerator := 3, scale := 1 } "0.3")) == none)
      = true := by native_decide
theorem tt_bridge_float_in_struct_defer :
    (manifestToTemplateData (.struct [("x", .prim (.float { numerator := 3, scale := 1 } "0.3"))])
      == none) = true := by native_decide
theorem tt_bridge_key_sort :
    (manifestToTemplateData (.struct [("b", .prim (.int 2)), ("a", .prim (.int 1))])
      == some (.struct [("a", .int 1), ("b", .int 2)])) = true := by native_decide
theorem tt_bridge_scalars :
    (manifestToTemplateData (.prim (.string "s")) == some (.str "s")) = true := by native_decide

-- ### Dispatch verdicts through `evalBuiltinCall`

private def call (name : String) (args : List Value) : Value := evalBuiltinCall name args

theorem tt_call_htmlescape :
    (call "template.HTMLEscape" [.prim (.string "<x>")] == .prim (.string "&lt;x&gt;")) = true := by
  native_decide
theorem tt_call_jsescape :
    (call "template.JSEscape" [.prim (.string "<x>")] == .prim (.string "\\u003Cx\\u003E"))
      = true := by native_decide
theorem tt_call_jsescape_nonascii :
    (call "template.JSEscape" [.prim (.string "é")]
      == .bottomWith [.unsupportedBuiltin "text/template.JSEscape"]) = true := by native_decide
-- Nonexistent leaf (`template.Parse`) ⇒ bare bottom (cue: cannot call non-function).
theorem tt_call_nonexistent_leaf :
    (call "template.Parse" [.prim (.string "x")] == .bottom) = true := by native_decide
theorem tt_call_execute_string_scalar :
    (call "template.Execute" [.prim (.string "{{.}}"), .prim (.string "hi")]
      == .prim (.string "hi")) = true := by native_decide
theorem tt_call_execute_float_defer :
    (call "template.Execute"
      [.prim (.string "{{.}}"), .prim (.float { numerator := 15, scale := 1 } "1.5")]
      == .bottomWith [.unsupportedBuiltin "text/template.Execute"]) = true := by native_decide

-- Coverage tripwire: one `#check @` per section so an editing slip that swallows a whole
-- section fails the test-health gate instead of silently dropping the theorems.
#check @tt_empty_list                  -- scalar/struct/list Go-fmt rendering
#check @tt_if_no_else                  -- if / else truthiness
#check @tt_range_scalar_unsupported    -- range over list/struct/null + scalar defer
#check @tt_with_else                   -- with / with-else
#check @tt_ws_trim_start               -- comments + whitespace trimming
#check @tt_nested_if_range             -- nested control
#check @tt_field_on_int                -- parse / eval errors ⇒ bottom
#check @tt_template_unsupported        -- deferred constructs ⇒ unsupported
#check @tt_js_nonascii_deferred        -- escapers (html/js) incl. non-ASCII defer
#check @tt_bridge_scalars              -- manifestToTemplateData bridge (float defer + sort)
#check @tt_call_execute_float_defer    -- evalBuiltinCall dispatch verdicts

end Kue
