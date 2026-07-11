import "text/template"

// text/template package: the T1 green core + escapers (STDLIB-TEXTTEMPLATE-T1). Only success
// cases live here — deferred constructs (funcs/pipelines/float data) and malformed templates are
// pinned by native_decide (they export as errors, no json). The real prod9 shape is `greeting`.
greeting: template.Execute("Hello {{ .name }}", {name: "World"})
nested: template.Execute("{{.A.B}}", {A: {B: "deep"}})
dot_scalar: template.Execute("{{.}}", "hi")
dot_struct: template.Execute("{{.}}", {b: 2, a: 1})
dot_list: template.Execute("{{.}}", [1, 2, 3])
missing: template.Execute("{{.missing}}", {a: 1})
null_field: template.Execute("{{.x}}", {x: null})
bool_int: template.Execute("{{.b}} {{.i}}", {b: true, i: 42})
if_branch: template.Execute("{{if .x}}yes{{else}}no{{end}}", {x: ""})
range_list: template.Execute("{{range .}}[{{.}}]{{end}}", [1, 2, 3])
range_map: template.Execute("{{range .}}[{{.}}]{{end}}", {b: 2, a: 1, c: 3})
with_block: template.Execute("{{with .x}}{{.y}}{{end}}", {x: {y: "hi"}})
comment: template.Execute("a{{/* c */}}b", {})
ws_trim: template.Execute("a  {{- .x -}}  b", {x: "X"})
nested_map: template.Execute("{{.}}", {a: {b: 1}, c: [1, 2]})
html_esc: template.HTMLEscape("a<b>&\"c' </x>")
js_esc:   template.JSEscape("a<b>&=\"c' x")
