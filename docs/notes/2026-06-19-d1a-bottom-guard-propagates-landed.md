# D#1a landed — a bottom comprehension guard propagates instead of vanishing

Supersedes `2026-06-19-sc1-closed-pattern-meet-soundness-landed.md` as the live pointer.
Second spec-first fix-slice from the consolidated backlog in
`docs/spec/spec-conformance-audit.md`.

## What landed

`expandClausesWithFuel` / `expandListClausesWithFuel` (`Eval.lean`) matched a guard as
`.prim (.bool true) => continue | _ => pure []`. The catch-all swallowed EVERYTHING that
wasn't literally `true` — including a guard evaluating to BOTTOM. So `out: {if (1/0 > 0)
{b:1}}` silently produced `out: {}` (the div-by-zero vanished — a soundness hole). Spec: an
`if` guard "terminates the current iteration if it evaluates to false"; *false* is the only
drop. A bottom guard is an error; bottom propagates recursively. cue errors on a bottom guard.

**Mechanism.** The six expansion helpers in the mutual block
(`expandClauses`/`expandForPairs`/`expandComprehension`/`expandComprehensions` + the two list
twins) changed return type from `EvalM (List …)` to `EvalM (Except Value (List …))`.
`Except.error b` carries the actual bottom value (preserving `.bottomWith reasons` like
`divisionByZero`) and short-circuits every concat in the for-pairs / multi-comprehension
recursion via explicit `.error → propagate` / `.ok → continue` matches — total, no monad
transformer. The guard match is now ENUMERATED (no catch-all swallow): `.bool true` →
continue, `.bool false` → `[]` (the spec drop), `.bottom`/`.bottomWith` → `.error
testCondition`, residual `_` → still `[]` (with a comment that D#1b makes the incomplete case
DEFER). Three call sites re-surface the error as the result bottom: the `.comprehension` eval
arm, the eager + forced `.structComp` arms, and `evalListItemsWithFuel`.

**Second swallow found + fixed.** The clauses-exhausted `[] =>` arm evaluates the body struct
and had `| .struct fields _ none [] _ => pure fields | _ => pure []`. With a bottom guard one
level deeper (inside a `for`-body struct, `for k in … { if (1/0>0) {…} }`), the body evaluates
to `.bottom` and was dropped by that catch-all. Added `.bottom`/`.bottomWith` body → `.error`.
(The list twin's `[evaluatedBody]` already preserves a bottom body as an element — no swallow.)

## Confirmed on the binary

- `out: {if (1/0 > 0) {b:1}}` → `out: _|_` (was `out: {}`). cue errors (rc=1) — agrees.
- `out: {if false {b:1}}` → `out: {}` (unchanged spec drop).
- `out: {if true {b:1}}` → `out: {b: 1}` (unchanged).
- `out: [if (1/0 > 0) {1}]` → `out: [_|_]` (bottom positioned in the element slot, Kue's
  existing `[1/0]` → `[_|_]` convention; PRESERVED, not swallowed).
- `x: 1 & 2; out: {if x > 0 {b:1}}` → both `_|_` (sibling bottom flows through the guard).
- `for k in ["a","b"] { if (1/0>0) {…} }` → `_|_` (the deeper-swallow fix).

**Granularity note (not a value divergence).** Struct guard collapses the whole comprehension
to bottom (no field exists yet for the bottom to attach to); list guard positions the bottom
in the element slot — matching Kue's standing "bottoms are positioned, not collapsed at
eval/render" convention (`{a:1/0}` → `{a:_|_}`). cue addresses these as `out` vs `out.0`
errors; both are "error". No `cue-divergences.md` entry — the value (bottom) and the
positioning convention both predate this slice; only the SWALLOW was the bug.

## Verify (gate passed)

`lake build` green (96 jobs, no warnings); `scripts/check-fixtures.sh` → `fixture pairs ok`
(all existing fixtures held — none carries a bottom guard); `shellcheck` clean. cert-manager
re-probed READ-ONLY: exports clean (exit 0, ~34s), no regression. Tests: 4 `native_decide`
pins in `PresenceTests` (bottom propagates; bottom-from-sibling propagates; `false` drops;
`true` yields) + 3 fixtures (`comprehensions/guard_bottom_propagates`,
`list_guard_bottom_propagates`, `guard_bottom_from_sibling`) with `FixturePorts` ports.

## Still open

**D#1b (incomplete-guard deferral).** An INCOMPLETE guard still drops to `[]` (the residual
`_` arm) instead of DEFERRING. Larger; couples with D#2 structural-cycle detection. The arm is
explicitly carved out with a comment in both twins.

## Next step

**F-1 — `regexp` builtin import** (`docs/spec/spec-conformance-audit.md` HIGH backlog #3):
add `regexp` to the builtin import allowlist + wire `regexp.Match/…` to the EXISTING regex
engine (engine present, wiring missing). Contained; real-app blocker. NOTE: the existing
engine is NOT RE2 (RX-1) — F-1 only wires what exists; the RX-1 rewrite is a separate LARGE
slice.

**Two-phase audit DUE after F-1.** SC-1 + D#1a + F-1 = 3 spec-first fixes since the last
audit. Run the two-phase audit (per `docs/guides/slice-loop.md` — do NOT invoke `/ace-audit`)
BEFORE the next feature slice: (A) code-quality over the recent batch (incl. this slice's
`Except`-threading through the comprehension cluster — totality, the enumerated guard match,
test strength, DRY between the struct/list twins; and SC-1's `closingPatterns` threading),
then (B) architecture/refactor/cleanup over the module graph.

Then the rest of the backlog: SC-1b (intersection-aware closed allowed-set), F-2 (self-module
`@vN` strip), RX-1 (regex RE2 rewrite, LARGE), D#2 (cycle detection, LARGE), Bug2-3/Gap-2b
(the argocd unblock), SC-2 (closing-vs-instantiation, DIVERGE from cue).

## Standing rules

- prod9 + cue caches READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard`.
  No env mutation outside the project tree.
