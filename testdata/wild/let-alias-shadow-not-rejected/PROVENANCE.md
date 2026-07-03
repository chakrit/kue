# let-alias-shadow-not-rejected

**Source:** wild-caught 2026-07-03 while verifying shadow detection for the
`module-file-scoped-imports` slice. Testing whether a `let x` / value-alias `x=`
in the importing file correctly shadows an imported `x`, cue instead REJECTED the
shadow outright: `cannot have both alias and field with name "x" in same scope`.

**Adjudication:** cue is spec-correct — a `let`/alias must not shadow an enclosing
binding (the rule is general, reproduced here with no import at all). Kue lacks this
load-time validation and silently accepts the shadow. Spec-adjudicated UNDER-rejection.

**Status:** RED (`.known-red`) — a separate load-time validation feature, out of the
import-scoping slice. Graduate when the `let`/alias no-shadow rule lands; then set the
`expected.err` substring to kue's actual diagnostic.
