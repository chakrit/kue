# RESUME — Bug2-12 self-recursive-closedness leak RESOLVED; audit counter = 1 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-perf7-audit-closed-next-frontier.md`
(deleted). Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance
backlog: [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) §
Genuinely-open. Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Served status
page: [`../../www/index.html`](../../www/index.html).

## State — audit counter = 1. Pick the next forward slice.

One implementation slice landed (Bug2-12 self-recursive). Two more slices, then the
two-phase audit (A code-quality, then B architecture) per `slice-loop.md`. On resume:
verify HEAD == upstream (tree clean, pushed `main -> main`).

## What landed — Bug2-12 (SELF-recursive closed def closedness leak) RESOLVED

A closedness SOUNDNESS leak on the structural-cycle path. `#X: #X & {a:1}` then `out: #X &
{b:2}` ADMITTED `b`; cue rejects (`field not allowed`). **Spec-verified cue is CORRECT** —
closedness is a property of the definition; self-recursion does NOT re-open it
(cross-checked vs the consistent `#A & #B` distinct-meet + one-way `#A: #B & {a}`
rejects).

**Root cause:** the def body `#X & {a:1}` is a `.conj [#X, {a:1}]`; the structural-cycle
path bottomed the self-`#X` and left the surviving `{a:1}` OPEN — def-closedness was never
applied (`normalizeDefinitionValueWithFuel` has no `.conj` arm; `refDefClosureBody?` skips
a non-struct-like `.conj` body). **Fix** (`flattenConjDefRef`, `Eval.lean`): when
expanding a DEFINITION field whose `.conj` body is genuinely SELF-REFERENTIAL (a depth-0
conjunct refs the same slot), close each expanded conjunct via the def-body closer —
struct literals close, the self-ref `.refId` is left untouched so the cycle path bottoms
it identically. Self-ref guard is the soundness boundary: a non-self-recursive
multi-conjunct def (`#LS: #Base & {#extra}`, Bug2-6..9 — `#Base` ≠ self) stays OPEN,
close-once fold untouched. (A blanket `.conj` arm in the closer over-closed 6 Bug2-6..9
pins; reverted for the gated flatten fix.)

**Boundaries (all == cue v0.16.1):** REJECT — self extra / inlined / non-matching pattern
/ nested extra. ADMIT (no over-close) — declared field, pattern-MATCH, `...`-open-tail,
nested declared. D#2 detection UNCHANGED (`#L:{n,next:#L}` bottoms; `#List | *null`
terminates). Canaries jq -S = 0 (prod9 zero recursive defs → guard never fires).

**Tests:** 11 `native_decide` pins (`Bug2xTests` `### Bug2-12`) incl. 2 re-pinned D#2
guardrails; 4 fixtures (`bug212_selfrec_*`) + `FixturePorts` entries; tripwire sentinel.

**MUTUAL tail OPEN (NOT fixed):** `#A: #B & {a}`, `#B: #A & {b}` — kue admits, cue rejects
even the def's OWN field. cue's mutual reading is lattice-questionable → recorded as an
OPEN spec-gap (`cue-spec-gaps.md` Bug2-12 MUTUAL row), deferred as a future fix-slice
(guardrail #5: don't over-reach the cycle machinery to match a questionable semantics).

## Live state

- **TWO content-identical prod9 drop-ins:** cert-manager **~12s** (984 B), argocd **~50s**
  (37230 B), both jq -S diff = 0 vs `cue`. Bug2-5..2-14c chain CLOSED. perf #7
  frame-sharing WON'T-FIX. `Eval`+`Lattice` FULLY total; module graph ACYCLIC.
  axiom-clean.

## NEXT LEADER — pick one (none soundness-bearing, none block adoption)

Resolve by philosophy and drive — do NOT pause to ask "what next". Ranked:
- **Bug2-12 MUTUAL tail** (LOW, spec-gap-first) — the mutual-recursion closedness leak
  above; decide whether to match cue's lattice-questionable "reject the def's own field"
  or hold the principled admit; transitive back-ref detection in `flattenConjDefRef`.
- **per-eval-cost slice** (the live perf frontier now frame-sharing is WON'T-FIX) — lower
  the per-eval CONSTANT / eval COUNT over the genuinely-large distinct population (~50s
  argocd).
- **SC-4** (LOW, spec-gap-first — nested hidden/let closedness on direct def-meet; cue
  internally inconsistent, spec-check first).
- **missing-field-selection** (LOW — `x.a.missing != _|_` → kue `incomplete` vs cue
  `false`).
- **item-6 LOW tail** in `plan.md` (`module-file-scoped-imports`, parser strictness,
  `release-linux.sh` dirty-tree guard, A2-x/y, B2-A1/A2, concurrent-tap-race note, DRY
  `selectEvaluatedField .disj`).

After 2 more slices: two-phase audit (A then B) per `slice-loop.md` — do NOT invoke
`/ace-audit`; follow the guide.

## RELEASE STATUS

`v0.1.0-alpha.20260623` is **CUT** and the Homebrew formula is live-correct on all 3
platforms. Do NOT re-cut. Next alpha: ~daily via `scripts/release.sh` +
`scripts/release-linux.sh` (local only; CI/Actions banned; push/release attended-only).

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push/release on `main`
  (attended). Don't pause at milestones.
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue`) a fallible cross-check, never the
  gate. kue binary: `.lake/build/bin/kue`. Canary oracles: run from the prod9 infra root
  (`/Users/chakrit/Documents/prod9/infra`, READ-ONLY) so cue has its module context — `cue
  export apps/{argocd,cert-manager}.cue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main
  tree.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (`--` headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
