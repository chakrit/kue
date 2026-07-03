# Breadcrumb — 2026-07-04 — INTERP-OPERAND-TYPING landed (conformance probe)

## Where things stand

Conformance probe of **string interpolation / regexp / encoding** builtins (AFK slice).
Found + FIXED one real bug cluster; red-seeded + filed two adjacent parser bugs; the rest
of the swept area is conformant.

### Landed (this slice)

- **INTERP-OPERAND-TYPING** — concrete `null`/list/struct in `"\(x)"` now bottom (`_|_`),
  were passthrough-rendered. Spec: operand must be `bool|string|bytes|number`. Fix in
  `EvalBase.lean` (`classifyInterpolationPart` total classifier + `combineInterpVerdict` fold;
  new `BottomReason.nonInterpolatable`). Unresolved operands still DEFER (canary EMPTY).
  Fixture `numeric/interpolation_type_error` + 8 `native_decide` (`Tests.lean`).

### Filed / red-seeded (next probes / slices pick up)

- **BYTE-LITERAL-LEXING** (red-seeded, `.known-red`): `testdata/wild/byte-literal-interpolation`
  (`'\(1)'` interpolation unevaluated) + `testdata/wild/byte-literal-hex-escape` (`'\x01ab'`
  escape undecoded). Parser-level byte-literal lexer defects, both kue-wrong. Also fold in
  bytes-operand render into a STRING interpolation (`"\(bytesval)"`, currently deferred).
- **BUILTIN-IMPORT-LENIENCY** (observation): kue resolves `regexp.*`/`strings.*`/`list.*`/`math.*`
  without the `import` clause cue requires. Broad; separate import-enforcement slice.

### Swept CLEAN (conformant — skip next time)

- Interpolation: int/float/bool/string render, nested, multi-part, dynamic field label,
  escaped `\\(`, incomplete-DEFER (rendering cosmetically differs — kue shows evaluated parts
  `"\(string)"`, cue shows source `"\(b)"` — both incomplete, not a semantic divergence).
- Regexp: `=~`/`!~` true/false, invalid-pattern → bottom (both), `=~` on non-string → bottom
  (both), `regexp.Match`/`ReplaceAll` match cue (WITH import).
- encoding: `json.Marshal` field order + number formatting match cue.

## Next step

Continue the slice loop. A natural follow-on is the **BYTE-LITERAL-LEXING** slice (graduates
the two red seeds); or pick a fresh un-probed builtin area. Two-phase audit is due (last full
audit 2026-07-02; several slices have landed since — list-slice, strings.Runes, struct-eq
ruling, this one).
