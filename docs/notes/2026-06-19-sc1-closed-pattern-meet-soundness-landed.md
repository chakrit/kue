# SC-1 landed — closed struct no longer re-opened by a pattern-struct meet

Supersedes `2026-06-19-bug2-2-gap2-disj-arm-narrowing-landed-gap2b-remains.md` as the live
pointer. First spec-first fix-slice from the consolidated backlog in
`docs/spec/spec-conformance-audit.md`.

## What landed

`mergeStructN` (`Lattice.lean`) arms 5/6 (pattern-on-one-side × plain-other-side) dropped the
plain side's openness AND closedness, silently re-opening a closed `#Def` met with an open
pattern struct: `#C & P & {z:9}` admitted `z`. Spec (closedness conjunctive/monotone) + cue both
reject. Fixed:

- **Result openness** = `StructOpenness.meet leftOpenness rightOpenness` (closed dominates).
- **Closedness from BOTH sides**, each side's allowed set = its fields + its CLOSING patterns
  (open side admits everything) via the new `applyClosingPatternsWith`.
- **Representation refinement (the crux):** `Value.struct` gained `closingPatterns : List Value`
  — the label-predicates that CLOSE (widen the allowed set), distinct from `patterns` (value
  constraints). A pattern closes iff its declaring struct is closed; an OPEN conjunct's pattern
  is kept as a value-constraint but is NON-closing, so it can't re-open a closed result. Built
  through `mkStruct` (default: own pattern predicates when closed, `[]` when open) and threaded
  through every struct rebuild/eval/resolve/normalize site. `closeValue` + def-body normalize
  keep all-patterns-closing (own patterns).

Confirmed on the binary: `#C & P & {z:9}` → `z: _|_` (rejected); `#C & P & {a:1}` admits `a`;
`#D:{a,[string]} & {z:9}` admits `z` (own pattern); open `C & P & {z:9}` admits `z` (no
over-close); value-constraint persists (`(#C & P) & {a:50}` with `<10` rejects).

## Verify (gate passed)

`lake build` green (96 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok` (ALL existing
fixtures held — cue agrees with the stricter behavior, nothing relied on the bug; no pin/fixture
encoded the re-open); `shellcheck` clean. cert-manager re-probed READ-ONLY: exports clean (exit
0), no regression. Tests: 4 `native_decide` pins in `LatticeTests` + fixture
`definitions/sc1_closed_meets_pattern_stays_closed` (+ `FixturePorts` port).

## Follow-up found (SC-1b — MED, pre-existing, broader)

The `closingPatterns` carry-forward is a UNION; for two CLOSED defs with disjoint explicit fields
but overlapping patterns (`#A:{a,[=~"^x"]} & #B:{b,[=~"^x"]}`) the correct forward allowed-set is
the INTERSECTION (cue rejects `a`/`b` on a later meet, admits `x1`; current Kue admits `a`/`b`).
At-this-meet marking is correct (sequential closedness); only the stored forward set over-admits.
NOT introduced by SC-1 (the closed×plain case is now correct; this is closed×closed-pattern).
Needs an intersection-aware closed allowed-set. Recorded in `spec-conformance-audit.md`.

## Next step

**Audit cadence — DUE.** Bug2-1 + Bug2-2 + SC-1 = **3 code slices** since the last two-phase
audit. Run the two-phase audit (per `docs/guides/slice-loop.md` — do NOT invoke `/ace-audit`)
BEFORE the next feature slice: (A) code-quality over the recent batch (incl. SC-1's
`closingPatterns` threading — correctness, totality, illegal-states, DRY, test strength, skill
compliance; especially whether `closingPatterns` should be folded INTO the pattern type as an
intrinsic per-pattern role rather than a parallel list, which would also tee up SC-1b), then (B)
architecture/refactor/cleanup over the module graph.

**Then the backlog** (`docs/spec/spec-conformance-audit.md` consolidated backlog): next HIGH
spec-first fixes are **D#1a** (comprehension guard: propagate a BOTTOM guard, don't swallow —
`Eval.lean:2941-2953,2997-3007`) and **F-1** (`regexp` builtin import + wire `regexp.Match/…`).
Then SC-1b, F-2 (self-module `@vN` strip), the RX-1 regex rewrite (LARGE), D#2 cycle detection
(LARGE), Bug2-3/Gap-2b (the argocd unblock). SC-2 (closing-vs-instantiation, DIVERGE from cue) is
the closedness sibling of SC-1.

## Standing rules

- prod9 + cue caches READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard`. No
  env mutation outside the project tree.
