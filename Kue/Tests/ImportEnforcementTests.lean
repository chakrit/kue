import Kue.Tests.EvalTestHelpers

namespace Kue

-- BUILTIN-IMPORT-LENIENCY enforcement: a package-qualified stdlib builtin reference resolves
-- ONLY when its package is imported, matching cue v0.16.1 (an un-imported reference errors
-- `reference "<pkg>" not found`). Covers the call form (`strings.ToUpper(...)`), the no-call
-- CONSTANT form (`list.Ascending`), aliased imports, wrong/missing imports, and the slice
-- operator's exemption (`x[lo:hi]` is a language operator, not the public `list.Slice`).

-- ## Call form — gated on the import

-- WITHOUT `import "strings"`, a qualified builtin call is an unresolved reference (bottom).
theorem call_without_import_bottoms :
    exportJsonBottoms "out: strings.ToUpper(\"hi\")\n" = true := by native_decide

-- WITH the import it resolves to the builtin's value.
theorem call_with_import_resolves :
    exportJsonMatches "import \"strings\"\nout: strings.ToUpper(\"hi\")\n"
      "{\n    \"out\": \"HI\"\n}\n" = true := by native_decide

-- An aliased import binds the package under the alias; the aliased call resolves identically.
theorem aliased_call_resolves :
    exportJsonMatches "import s \"strings\"\nout: s.ToUpper(\"hi\")\n"
      "{\n    \"out\": \"HI\"\n}\n" = true := by native_decide

-- Importing a DIFFERENT builtin package does not license an un-imported one: `list` in scope,
-- `strings.ToUpper` still errors.
theorem wrong_package_import_bottoms :
    exportJsonBottoms "import \"list\"\nout: strings.ToUpper(\"hi\")\n" = true := by native_decide

-- Encoding packages carry the last path element as their local name (`encoding/json` → `json`).
theorem encoding_json_without_import_bottoms :
    exportJsonBottoms "out: json.Marshal({a: 1})\n" = true := by native_decide

theorem encoding_json_with_import_resolves :
    exportJsonMatches "import \"encoding/json\"\nout: json.Marshal({a: 1})\n"
      "{\n    \"out\": \"{\\\"a\\\":1}\"\n}\n" = true := by native_decide

-- Multiple imports: each qualified reference resolves against its own package.
theorem multiple_imports_each_resolve :
    exportJsonMatches
        "import (\n\t\"strings\"\n\t\"math\"\n)\nout: {u: strings.ToUpper(\"a\"), p: math.Pow(2.0, 3.0)}\n"
      "{\n    \"out\": {\n        \"u\": \"A\",\n        \"p\": 8\n    }\n}\n" = true := by native_decide

-- A nested/embedded builtin call is gated the same as a top-level one.
theorem nested_call_without_import_bottoms :
    exportJsonBottoms "out: {inner: {v: math.Pow(2.0, 3.0)}}\n" = true := by native_decide

-- ## Constant form — gated on the import

-- `list.Ascending` (a stdlib VALUE, no call) also requires `import "list"`.
theorem const_without_import_bottoms :
    exportJsonBottoms "out: list.Sort([3, 1, 2], list.Ascending)\n" = true := by native_decide

theorem const_with_import_resolves :
    exportJsonMatches "import \"list\"\nout: list.Sort([3, 1, 2], list.Ascending)\n"
      "{\n    \"out\": [\n        1,\n        2,\n        3\n    ]\n}\n" = true := by native_decide

-- An aliased import resolves the constant form identically to the unaliased.
theorem aliased_const_resolves :
    exportJsonMatches "import l \"list\"\nout: l.Sort([3, 1, 2], l.Ascending)\n"
      "{\n    \"out\": [\n        1,\n        2,\n        3\n    ]\n}\n" = true := by native_decide

-- ## Slice operator exemption

-- Slice SYNTAX `x[lo:hi]` is a language operator (desugars to the core `slice` builtin), so it
-- needs no `import "list"` — matching cue, which slices without the import.
theorem slice_syntax_without_import_ok :
    exportJsonMatches "out: [1, 2, 3][0:2]\n"
      "{\n    \"out\": [\n        1,\n        2\n    ]\n}\n" = true := by native_decide

-- The PUBLIC `list.Slice(...)` function, by contrast, IS gated — cue requires `import "list"`
-- for the package function even though the slice operator is exempt.
theorem public_list_slice_without_import_bottoms :
    exportJsonBottoms "out: list.Slice([1, 2, 3], 0, 2)\n" = true := by native_decide

theorem public_list_slice_with_import_resolves :
    exportJsonMatches "import \"list\"\nout: list.Slice([1, 2, 3], 0, 2)\n"
      "{\n    \"out\": [\n        1,\n        2\n    ]\n}\n" = true := by native_decide

-- ## Shadowing — a local field named like a builtin package

-- A local field `strings` shadows the builtin; `strings.ToUpper` (no import) is ordinary field
-- access into the local struct, NOT the builtin — so it resolves to the local value, not bottom.
theorem local_field_shadows_builtin_const_form :
    exportJsonMatches "strings: {ToUpper: \"local\"}\nout: strings.ToUpper\n"
      "{\n    \"strings\": {\n        \"ToUpper\": \"local\"\n    },\n    \"out\": \"local\"\n}\n"
        = true := by native_decide

-- COVERAGE TRIPWIRE (test-health): anchors the last theorem so a swallowed section fails
-- `#check` elaboration.
#check @local_field_shadows_builtin_const_form

end Kue
