# pattern-label-alias

- **Source:** SCOPING-PROBE (2026-07-12).
- **Defect:** kue cannot parse the pattern-constraint label alias `[Name=string]: …`,
  which binds `Name` to each matched field's concrete label in scope within the
  constraint body. The label position rejects the `ident=` prefix (`missing ',' in list
  literal`). Missing feature: parse support + per-matched-label eval binding.
- **Spec basis:** CUE `LabelExpr` grammar admits `"[" [ identifier "=" ] AliasExpr "]"`;
  the alias binds the matched label string.
- **cue:** v0.16.1 ⇒ `{"foo": {"n": "foo"}}`. kue ⇒ parse error.
- **Status:** QUARANTINED (`.known-red`). Filed as fix-slice PATTERN-LABEL-ALIAS
  (parse the `[X=expr]` alias + bind the label value per matched field at eval).
