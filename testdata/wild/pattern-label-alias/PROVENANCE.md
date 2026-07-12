# pattern-label-alias

- **Source:** SCOPING-PROBE (2026-07-12).
- **Defect:** kue cannot parse the pattern-constraint label alias `[Name=string]: …`,
  which binds `Name` to each matched field's concrete label in scope within the
  constraint body. The label position rejects the `ident=` prefix (`missing ',' in list
  literal`). Missing feature: parse support + per-matched-label eval binding.
- **Spec basis:** CUE `LabelExpr` grammar admits `"[" [ identifier "=" ] AliasExpr "]"`;
  the alias binds the matched label string.
- **cue:** v0.16.1 ⇒ `{"foo": {"n": "foo"}}`. kue ⇒ `{"foo": {"n": "foo"}}` (matches).
- **Status:** FIXED (PATTERN-LABEL-ALIAS, 2026-07-12). Parse reads the `ident=` alias
  (`patternAliasHead?`) and desugars it onto the constraint (`bindPatternAlias`) as a
  `letBinding` carrying the `Value.patternLabel` placeholder, substituted to the matched label at
  application (`applyPatternToFieldWith`). GREEN, quarantine removed.
