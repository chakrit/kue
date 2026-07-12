package repro

// A pattern-constraint label alias `[Name=string]: …` binds `Name` to the
// concrete label of each matched field, in scope within the constraint body.
// cue v0.16.1: `foo: {}` matches the pattern, so `foo.n` unifies to the label
// string "foo" ⇒ {"foo": {"n": "foo"}}.
// kue cannot PARSE the `[Name=string]` alias form (the label position rejects
// the `ident=` prefix) — a missing feature: pattern label aliases (parse +
// per-matched-label eval binding) are unimplemented.
// Spec-adjudicated value: {"foo": {"n": "foo"}}.
[Name=string]: {n: Name}
foo: {}
