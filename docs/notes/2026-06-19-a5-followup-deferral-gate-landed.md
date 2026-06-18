# RESUME HERE — A5-followup deferral-gate fix LANDED (2026-06-19)

Supersedes the prior START-HERE pointer
(`2026-06-18-a5-comprehension-body-frame-depth-landed.md`). Standing grant in effect
(autonomy / Lean-into-Lean-4 / commit-push freely / specs as restore point). Full record:
`docs/reference/implementation-log.md` ("A5-followup" entry); ranked work:
`docs/spec/plan.md` (Live Backlog).

## What landed — `e00c3de` (pushed to gh:main)

A5-followup: the OBSERVABLE wrong value A5 surfaced now flips correctly.
```
#H: {#t: string | *"def"}
#R: Self={#H, out: [for x in [1] {v: Self.#t}]}
v: #R & {#t: "y"}   # cue 0.16.1 → v.out[0].v: "y"; now kue too (was string | *"def")
```

**The plan's diagnosis was the symptom, not the cause.** It was filed as a "Pass-2 re-eval
gap" (Pass-2 not refreshing a comprehension-valued field's body). Tracing (dbg_trace on the
selector arm + the eager/force `.structComp` arms) showed `#R & {narrow}` never reached the
Pass-2 arms at all — it took the eager-then-meet path. The real defect is one layer earlier,
in the DEFERRAL GATE:

`hasSelfRefAtDepth` (used by `defBodyHasSiblingSelfRef`/`bodyNeedsDefer` and the `.conj` fold
to decide whether a self-ref def defers to a closure) scanned a comprehension BODY at the
comprehension node's own `depth`, ignoring the loop frame each `for` pushes. A body `Self.#t`
resolves to `refId ⟨depth + #forClauses, _⟩`; scanned at `depth` it compared unequal and was
MISSED. So `#R` was judged to have no sibling self-ref → eager standalone eval (embedding
default `string | *"def"`) then meet with `{#t: "y"}` (narrows the scalar but can't re-expand
the comprehension). The closure-FORCE path (fires when the gate detects the self-ref) splices
the narrowing into the frame BEFORE the body evaluates — the already-correct, already-perf
arm. Routing the conj to it is the whole fix; Pass-2 selective re-eval untouched, no perf
regression.

This is the **FOURTH A5-family walker** (after `remapConj*`, `selfReferencedLabels`,
`refsSelfEmbeddedLabel`). The old arm comment claimed body-at-`depth` "over-detects only,
never misses" — false: too-shallow UNDER-detects every loop-deep self-ref.

Fix: `hasSelfRefAtDepth` made `mutual` with `hasSelfRefAtDepthClauses`, threading frame depth
like `resolveClausesWithFuel` (+1 per `for`, +0 per `guard`). Pins: end-to-end fixture
`comprehension_embed_self_narrow_body` (parse-driven FixturePort, oracle 0.16.1) +
native_decide gate pins (body-detected, loopvar boundary = no over-detect, multi-`for`,
guard-no-frame, struct clause helper). Edge cases (guard / multi-for / nested comprehension /
different-source embedded label) oracle-confirmed during dev.

## Verify (all green at commit)

`lake build` 86 jobs (native_decide pins build-checked); `scripts/check-fixtures.sh` →
`fixture pairs ok` (zero byte-drift; A5 module fixtures `open_embed_selfref_guard`,
`structcomp_lazymerge_guard`, `listcomp_embed_selfref`, `list_embed_self_narrowing`
byte-identical = the no-regression gate; spot-checked byte-equal to the live `cue` oracle). No
shell changed. cert-manager/argocd hit the documented perf wall (timeout) regardless —
module fixtures are the completing correctness signal.

## Next step — TWO-PHASE AUDIT IS DUE FIRST

Two slices have landed since the last audit (A5 `c3d0089` + A5-followup `e00c3de`). Per the
slice-loop cadence, run the two-phase audit NEXT (sequential, per `docs/guides/slice-loop.md`
— do NOT invoke `/ace-audit`): **(A) code-quality audit** over A5 + A5-followup (correctness,
totality, illegal-states, DRY, test strength, skill compliance), then **(B) architecture /
refactor audit** over the whole module graph. Fold findings into the plan as fix-slices.

Then, ranked:

1. **B7** (MEDIUM-HIGH) — typed frame coordinate. Now FIVE hand-coded `*Clauses` walkers all
   repeat +1-per-`for` (`resolveClausesWithFuel`, `remapConjClauses`,
   `selfReferencedLabelsClauses`, `refsSelfEmbeddedLabelClauses`, `hasSelfRefAtDepthClauses`).
   A typed `Depth` obtainable only via a `forIn`-descent makes the whole A5 family a compile
   error. `clauseFrameShift` is the seed; factor the shift into ONE authority. Design-spike first.
2. **B2** headline struct refactor (design-spike then migrate) / **B6** design-spike /
   **A2-followup** import-binding marker / **item 1** follow-up.

Releases: ~1 datestamped alpha/day via `scripts/release.sh` (local only — CI banned).
