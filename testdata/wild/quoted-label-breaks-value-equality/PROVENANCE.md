# quoted-label-breaks-value-equality

**Source:** audit-caught 2026-07-04 during the Phase A code-quality audit of `f128600`
(the `Field.quoted` model for the `let`/alias no-shadow REVERSE direction).

**Adjudication:** CUE treats a quoted label `"x":` and a bare label `x:` as the SAME
field — `{"x": 1}` and `{x: 1}` are the identical value. `f128600` added `quoted : Bool`
to `Field` and included it in the derived `BEq` for `Value`/`Field`/`ClosedClause`. That
makes two spec-equal structs compare UNEQUAL whenever their label quoting differs, and the
bit is not inert to evaluation: it leaks into every `Value`-`BEq` site.

Observed divergences (kue vs cue v0.16.1):
- `d: {x: 1} | {"x": 1}` — cue collapses the two equal arms to `{x:1}`; kue errors
  `ambiguous value: multiple non-default disjuncts remain` (`dedupAlternatives` fails to
  dedup the arms). THIS fixture.
- `({x: 1}) == ({"x": 1})` — cue → `true`; kue → `incomplete value` (the `==` operator
  compares structs by `Value` BEq).
- `[{x: 1}] | [{"x": 1}]` — same disjunction-dedup failure nested in a list.

Spec-adjudicated: kue is WRONG (`quoted` is parse-time provenance for the load-time
no-shadow check only; it must not participate in semantic value-equality). Expected value
is the spec-correct `{"d":{"x":1}}`, matched by cue and by the all-bare equivalent
`d: {x:1} | {x:1}`.

**Status:** RED (quarantined `.known-red`, captured not fixed). Fix is non-trivial
(exclude `quoted` from `Value`/`Field` `BEq`, or strip it post-parse) — filed as a fix-slice
in `docs/spec/plan.md`. Graduate this seed (delete `.known-red`) in the slice that fixes it.
