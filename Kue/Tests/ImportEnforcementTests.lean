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

-- ## Unused-import enforcement (UNUSED-IMPORT) — the mirror of the USE gate above

-- Pin the REASON, not merely "some bottom": the document root is a `.bottomWith` carrying an
-- `importedNotUsed` for the offending import (path + optional alias), matching cue's build error.
def topBottomHasUnusedImport (source path : String) (alias : Option String) : Bool :=
  match parseSource source with
  | .ok (.bottomWith reasons) => reasons.contains (.importedNotUsed path alias)
  | _ => false

-- An `import` never referenced in the body is a build error (`imported and not used`), so the
-- file bottoms — reproducing RED against the prior lenient (silently-accepted) behavior.
theorem unused_import_bottoms :
    exportJsonBottoms "import \"strings\"\nx: 1\n" = true := by native_decide

-- The bottom carries the cue-shaped reason: the import PATH, no alias.
theorem unused_import_reason_pinned :
    topBottomHasUnusedImport "import \"strings\"\nx: 1\n" "strings" none = true := by native_decide

-- A file whose import IS used (a qualified call) still parses and exports — no false positive.
theorem used_import_not_flagged :
    exportJsonMatches "import \"strings\"\nx: strings.ToUpper(\"a\")\n"
      "{\n    \"x\": \"A\"\n}\n" = true := by native_decide

-- An aliased import that is used under its alias is not flagged.
theorem aliased_used_import_not_flagged :
    exportJsonMatches "import s \"strings\"\nx: s.ToUpper(\"a\")\n"
      "{\n    \"x\": \"A\"\n}\n" = true := by native_decide

-- An aliased import left unused bottoms, and cue names it `"strings" as s` — the reason keeps
-- both path and alias so the message can render the `as` form.
theorem aliased_unused_import_bottoms :
    exportJsonBottoms "import s \"strings\"\nx: 1\n" = true := by native_decide

theorem aliased_unused_import_reason_pinned :
    topBottomHasUnusedImport "import s \"strings\"\nx: 1\n" "strings" (some "s") = true := by
  native_decide

-- The CLI RENDERS the unused-import bottom as cue's `imported and not used: "<path>"` message,
-- not the generic `conflicting values (bottom)` — the STDLIB-E render fix. Pins the exact wording.
theorem unused_import_render_message :
    exportErrorMessage "import \"strings\"\nx: 1\n" = "imported and not used: \"strings\"" := by
  native_decide

-- The aliased form renders the `as <alias>` suffix cue emits.
theorem aliased_unused_import_render_message :
    exportErrorMessage "import s \"strings\"\nx: 1\n"
      = "imported and not used: \"strings\" as s" := by native_decide

-- Two unused imports render one cue-shaped line each, in declaration order.
theorem two_unused_imports_render_message :
    exportErrorMessage "import (\n\t\"list\"\n\t\"strings\"\n)\nx: 1\n"
      = "imported and not used: \"list\"\nimported and not used: \"strings\"" := by native_decide

-- Multiple imports where only some are used: the unused one flags, exactly (the used `strings`
-- does not save the unused `list`).
theorem multiple_imports_only_unused_flagged :
    exportJsonBottoms "import (\n\t\"strings\"\n\t\"list\"\n)\nx: strings.ToUpper(\"a\")\n"
      = true := by native_decide

theorem multiple_imports_only_unused_reason_pinned :
    topBottomHasUnusedImport "import (\n\t\"strings\"\n\t\"list\"\n)\nx: strings.ToUpper(\"a\")\n"
      "list" none = true := by native_decide

-- All imports used: no flag even with several packages in scope.
theorem multiple_imports_all_used_ok :
    exportJsonMatches
        "import (\n\t\"strings\"\n\t\"math\"\n)\nx: {u: strings.ToUpper(\"a\"), p: math.Pow(2.0, 3.0)}\n"
      "{\n    \"x\": {\n        \"u\": \"A\",\n        \"p\": 8\n    }\n}\n" = true := by native_decide

-- ## Use sites the detector must reach (else a real use is mis-flagged unused)

-- Used only inside a NESTED struct.
theorem import_used_in_nested_struct_ok :
    exportJsonMatches "import \"strings\"\nx: {y: strings.ToUpper(\"a\")}\n"
      "{\n    \"x\": {\n        \"y\": \"A\"\n    }\n}\n" = true := by native_decide

-- Used only inside a STRING INTERPOLATION hole.
theorem import_used_in_interpolation_ok :
    exportJsonMatches "import \"strings\"\nx: \"[\\(strings.ToUpper(\"a\"))]\"\n"
      "{\n    \"x\": \"[A]\"\n}\n" = true := by native_decide

-- Used only inside a LIST COMPREHENSION body.
theorem import_used_in_comprehension_ok :
    exportJsonMatches "import \"strings\"\nx: [for a in [\"b\"] {v: strings.ToUpper(a)}]\n"
      "{\n    \"x\": [\n        {\n            \"v\": \"B\"\n        }\n    ]\n}\n" = true := by
  native_decide

-- Used only inside a DEFINITION (hidden `#D`), referenced by a regular field.
theorem import_used_in_definition_ok :
    exportJsonMatches "import \"strings\"\n#D: strings.ToUpper(\"a\")\nout: #D\n"
      "{\n    \"out\": \"A\"\n}\n" = true := by native_decide

-- Used only via the no-call CONSTANT form (`list.Ascending`), which parses as a deferred
-- selector on a `.ref` head — the detector must count that head as a use.
theorem import_used_in_const_form_ok :
    exportJsonMatches "import \"list\"\nout: list.Sort([2, 1], list.Ascending)\n"
      "{\n    \"out\": [\n        1,\n        2\n    ]\n}\n" = true := by native_decide

-- ## Two encodings of the builtin-package set stay in sync

-- `builtinPackageNames` (Value.lean, the import-gate set) and `BuiltinFamily.ofName?`
-- (Builtin.lean, the dispatch classifier) independently enumerate the qualified stdlib
-- packages. Pin them together at build time: every declared package name must classify to a
-- family, so a future package added to one list but not the other fails the gate. The probe
-- appends a leaf (`ofName?` prefix-matches on `<pkg>.`), and the names key off the last path
-- element (`encoding/base64` → `base64`), which is exactly the family prefix `ofName?` uses.
theorem every_builtin_package_resolves_to_family :
    builtinPackageNames.all (fun n => (BuiltinFamily.ofName? (n ++ ".SomeFn")).isSome) = true := by
  native_decide

-- COVERAGE TRIPWIRE (test-health): anchors the last theorem so a swallowed section fails
-- `#check` elaboration.
#check @every_builtin_package_resolves_to_family

end Kue
