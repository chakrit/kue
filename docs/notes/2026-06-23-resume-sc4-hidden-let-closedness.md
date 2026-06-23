# RESUME — SC-4 nested HIDDEN/LET closedness RESOLVED; audit counter = 2 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-multiref-flatten-bound.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).
Served status page: [`../../www/index.html`](../../www/index.html).

## State — audit counter = 2. Last slice: SC-4 nested HIDDEN/LET closedness (SHIPPED).

**SC-4 RESOLVED (case (b): kue under-closed → fixed; conforms to cue on the direct
paths).** A def's nested PLAIN-struct value carried by a HIDDEN field (`#A: {_h: {x: int}}`)
or read from a LET binding (`#A: {let _t={x:int}, v:_t}`) did NOT close on a direct def-meet
— `#A & {_h: {x: 1, extra: 2}}` ADMITTED `extra`, while a nested REGULAR value already
closed (SC-2). Principled answer = REJECT: closedness is a property of the definition and is
MONOTONE; the carrying field's visibility/carrier does not change whether the nested value
is closed.

- **The stale framing was WRONG for cue v0.16.1.** cue is NOT internally inconsistent on
  direct-`&`-vs-direct-select — it CONSISTENTLY closes the nested hidden value on direct-meet
  AND direct-select (`#A._h & {extra}`); the old "oracle #8" admit was the BOUND-then-select
  path (`y: #A; y._h & {extra}`), where cue re-opens (the SC-2b-family eval artifact). Pinned
  cue + adjacent shapes to locate the seam precisely.
- **FIX** (`Normalize.lean`, `normalizeDefinitionFieldWithFuel`): the `_x`-hidden and
  `letBinding` arms of the CLOSING field-walker twin now recurse the CLOSING walker
  (`normalizeDefinitionValueWithFuel`), like the regular arm, so a def's nested hidden/let
  plain-struct value closes recursively. `importBinding` SKIP untouched (A2 trap defence);
  the SPINE twin untouched (a plain non-def struct stays open). Nested `...` stays open; a
  NEW use-site hidden field is still admitted (`ignoresClosedness` axis, orthogonal).
- **Gate GREEN:** `lake build` clean (112 jobs, no warning/`sorry`/axiom), `check-fixtures.sh`
  ZERO drift. Canaries from `prod9/infra`: cert-manager jq -S = 0 (~11.7s), argocd jq -S = 0
  (~50s) — UNCHANGED (the shape is off the real-app path). Closedness family + D#2 all match
  cue.
- **7 `EvalTests` `eval_sc4_*` pins** (`### SC-4` section; the former obligation-4 pin FLIPPED
  from stays-open to closes) + **4 `sc4_*` fixtures** (hidden direct/tail/depth2 + let-read).
- **1 cue-divergence** recorded (`cue-divergences.md` SC-4 row: cue re-opens via a bound
  selection `y._h`, same SC-2b family; Kue monotone on every path). No spec-gap (spec speaks,
  cue agrees on the direct paths).

## NEXT — pick the next leader (resolve by philosophy; none soundness-bearing)

Spec-conformance backlog is now EMPTY (SC-4 was the last open item; SC-3 is a recorded
display-only spec-gap). Ranked candidates:

1. **per-eval-CONSTANT perf frontier** (the live lever) — lower the per-eval CONSTANT / eval
   COUNT over the genuinely-large DISTINCT population on the real apps (cert-manager ~11.7s,
   argocd ~50s; the ~50s is the residual, NOT the fan-out — fixed — and NOT cross-env sharing
   — closed at ~0.05% ceiling). Profile the SETUP/import closure + the `.struct`/`.refId`/
   `.conj` re-eval under divergent frames. Detail: `kue-performance.md` § Known limitations
   (Absolute per-eval cost on deep apps).
2. **item-6 LOW tail** in `plan.md` (parser strictness `*(1|2)`/`__x`, A2-x/y, B2,
   `module-file-scoped-imports`, the concurrent-release tap-clone race — none
   soundness-bearing).

**Audit:** counter = 2 → **two-phase audit DUE after the next slice** (per
`docs/guides/slice-loop.md`). Spawn (A) code-quality then (B) architecture/refactor/cleanup
once the next slice lands.

## Live state end
