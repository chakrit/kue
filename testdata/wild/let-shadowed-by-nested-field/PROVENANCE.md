# let-shadowed-by-nested-field

**Source:** wild-caught 2026-07-04 while building the probe matrix for the `let`/alias
no-shadow validation (graduating `let-alias-shadow-not-rejected`).

**Adjudication:** cue v0.16.1 REJECTS `let x` (enclosing scope) shadowed by a field `x`
in a NESTED scope (`cannot have both alias and field with name "x" in same scope`). This
is the REVERSE direction (the offending `let` is an ANCESTOR of the field). Kue enforces
only the FORWARD direction (field ancestor-or-self of the `let`) — the reverse needs
parse-time ancestor-`let` context threaded into nested field parsing, which the current
quoted-accurate `parsedFieldsValue` hook does not carry. Spec-adjudicated UNDER-rejection.

**Status:** RED (`.known-red`). Graduate when the reverse direction lands. See
`docs/reference/cue-spec-gaps.md` (let/alias no-shadow, reverse direction).
