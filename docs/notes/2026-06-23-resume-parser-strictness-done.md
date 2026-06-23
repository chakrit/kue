# RESUME — parser-strictness DONE; spec-conformance backlog still EMPTY (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-spec-conformance-backlog-empty.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).
Served status page: [`../../www/index.html`](../../www/index.html).

## Just landed — parser-strictness (plan item-6 LOW)

Two SPEC-MANDATED parse rejections Kue was missing (both spec-verified, not cue-quirks):

- **`__`-prefixed identifiers reserved.** Spec reserves all `__`-prefix identifiers as
  keywords → `reservedDoubleUnderscore` at the `parseIdentifier` chokepoint rejects `__x` on
  every spelling (field label / ref / alias). BOUNDARY held: `_x` hidden, `_` blank,
  `#__x`/`_#__x` defs, quoted `"__x"` all still parse.
- **`*(1|2)` sole-marked default.** The `*` mark is valid only on a disjunct WITH siblings
  (`*1 | 2`); a sole marked operand (`*(1|2)`, `*1`) is rejected via a single-`.default`
  guard in `parseDisjunctionRest`, diagnostic anchored at the `*`. BOUNDARY held: `*1 | 2`,
  `(*1 | 2)`, `*(1|2) | 3` (marked group WITH a sibling — parse-accepts) all still parse.

18 `ParseTests` parse pins (reject + valid boundary, two new `--` sections + 3 `#check`
tripwires). 1 cue-divergence recorded (cue accepts the inline `a: __x: 1` shorthand — a cue
parser inconsistency) + 1 spec-gap (the murky package-name / import-qualifier `__` corner,
deliberately out-of-scope — `isPackageIdentifier` unchanged). Verify: `lake build` clean
(112 jobs), `check-fixtures.sh` ZERO drift, both canaries jq -S = 0 (cert-manager ~11.4s,
argocd ~54s — UNAFFECTED, real configs use no `__`/`*(…)` invalid syntax).

## State — audit counter = 1.

Spec-conformance backlog still EMPTY (every correctness item RESOLVED; argocd + cert-manager
content-identical drop-ins, jq -S = 0). This slice was a plan-only item-6 LOW (parser
laxity), not a correctness fix. Module graph unchanged (parser-only edit, no new edge).

## NEXT — pick the next leader (resolve by philosophy; none soundness-bearing)

Ranked candidates (item-6 LOW tail is shrinking):

1. **item-6 LOW tail** in `plan.md` — remaining: A2-x/y (importBinding merge-asymmetry +
   import-name redeclaration check), B2-A1/A2 (typed-ellipsis `tail` thread + test-gap fill),
   `module-file-scoped-imports` (arch-sized per-file import scoping), the concurrent-release
   tap-clone race + `release-linux.sh` dirty-tree guard (release-script LOW), the
   `resolveEmbeddedDisjDefault` distribution check, DRY `selectEvaluatedField .disj`. None
   soundness-bearing.
2. **per-eval-CONSTANT perf frontier** (argocd ~50s residual). Big levers EXHAUSTED
   (frame-sharing WON'T-FIX ~0.05% ceiling, safe-wins + flatten-bound SHIPPED); a deeper
   hot-path micro-opt is incremental/hard — flag diminishing returns honestly.
3. **SC-3** display-gap (multi-arm-default display-collapse — cosmetic Format-layer
   projection; close only if the eval-display convention is revisited).

## Release

`v0.1.0-alpha.20260623` CUT; Homebrew formula live-correct on all 3 platforms. (This
parser-strictness slice is a candidate to ride the next datestamped alpha.)

## Audit

Counter = **1** (this slice). Next two-phase audit DUE after 2–3 slices, per
[`../guides/slice-loop.md`](../guides/slice-loop.md).

## Live state end
