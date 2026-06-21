# Spec-conformance re-audit

A full re-examination of every `cue` -grounded behavioral decision in Kue against the
**CUE language spec** and **lattice first principles**, triggered by the 2026-06-19
reframe (`docs/guides/slice-loop.md` → "The CUE spec is the authority"). The slice loop
had drifted into byte-identical-to-`cue`-v0.16.1 as the correctness gate — structurally
bug-replicating. This audit reclassifies what is actually correct vs. what merely matches
a fallible binary.

Feature slices are PAUSED until the high-risk areas are reclassified; findings here become
the spec-first fix-slice backlog in `plan.md`.

## Authority hierarchy (the gate)

1. **CUE language spec** — authoritative where it speaks; match it even against the
   binary.
2. **Lattice / first principles** — where the spec is silent (often): derive the
   mathematically-correct behavior (precise, total, illegal-states-unrepresentable).
3. **`cue` binary** — fallible cross-check ONLY. Never the gate.

## Classification taxonomy (every behavior gets one verdict)

- **CONFORMS** — spec speaks, Kue matches it (and `cue` does too). No action.
- **KUE-VIOLATES** — spec speaks, Kue is wrong (often because it matched a `cue` bug). FIX
  (spec-first fix-slice). Highest priority.
- **CUE-BUG / KUE-CORRECT** — spec speaks, `cue` is wrong, Kue follows the spec. Record in
  `cue-divergences.md`. No code action (already correct).
- **SPEC-SILENT / LATTICE-DERIVED** — spec silent, Kue's behavior is derivable as
  lattice-correct from first principles. Record the derivation; low risk.
- **SPEC-SILENT / SUSPECT-ARTIFACT** — spec silent, Kue's behavior only matches what the
  binary does and is NOT derivable (or contradicts) first principles. The danger zone:
  record in `cue-spec-gaps.md`, decide the principled behavior, FIX if it differs.

## Area decomposition (audited in risk order)

- **A. Disjunctions, defaults, narrowing** — default-mark algebra, resolution order,
  nested precedence, dedup, embedded-default narrowing, disjunction-arm pruning +
  structural discrimination (the argocd Gap-1/2/2b territory). HIGHEST risk — most `cue`
  -grounded.
- **B. Closedness & definitions** — open/closed, `...`, `#Def`, def-body closedness, the
  B6 cluster, `importBinding` /hidden-field laziness, closed-meet.
- **C. Structs & lists** — meet, patterns, tail (the B2 `mergeStructN` matrix + B2.5
  cross-combinations), list meet, embeddings, scalar-embed collapse.
- **D. Comprehensions, references, scoping** — comprehension guards/sources/scoping, frame
  resolution, closures, cross-package def-meet.
- **E. Scalars, bounds, kinds, regex, arithmetic, builtins** — the "basic" lattice (likely
  CONFORMS, but verify cue-correctness, esp. bounds intersection + numeric/decimal).
- **F. Manifest/export & module/import semantics** — what errors vs. tolerates,
  hidden-field bottom propagation, field ordering (#3), incomplete-vs-error, cross-module
  resolution.

## Status

| Area                       | Auditor | Status | Findings (V/CUE-BUG/SUSPECT)                                                                                                                                                                   |
| -------------------------- | ------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A. Disjunctions/narrowing  | batch 1 | DONE   | 1 KUE-VIOLATES (disj display); **Gap-2b/Bug2-3 FIXED 2026-06-19** (cue correct; structural list-vs-struct arm prune); 2 spec gaps; rest CONFORMS                                               |
| B. Closedness/definitions  | batch 1 | MOSTLY | SC-1/1c/1d + SC-2 FIXED 2026-06-19; **SC-1b (closed×closed-pattern intersection) FIXED 2026-06-21** via `closedClauses` provenance; **SC-1e (closed×open-tail) OPEN** (pre-existing, MED); import-laziness a deliberate gap |
| C. Structs/lists           | batch 1 | DONE   | 1 KUE-VIOLATES (pattern-meet closedness); 1 spec gap (field order); rest CONFORMS                                                                                                              |
| D. Comprehensions/scoping  | batch 2 | **CLOSED** | guard catch-all DRAINED (**D#1a/D#1b/D#1c all FIXED**: bottom→propagate, incomplete→defer, concrete-non-bool→type-error; 2026-06-20); structural cycles **D#2 COMPLETE 2026-06-20** (D#2a detection + D#2b terminating-disjunct); **`let`-clauses D#3 FIXED 2026-06-20** (parse + `Clause.letClause` + `let` = +1 frame; the LAST open D-item); frame-model + read-splice CONFORM — **D-area now fully closed** |
| E. Scalars/bounds/builtins | batch 2 | DONE   | regex→RE2 COMPLETE (RX-1 trilogy + RX-2a/b/c all FIXED — corpus divergence-free 2026-06-20); **BI-2 math.Pow exact + list.Sort/SortStable FIXED 2026-06-20** (residual: Sqrt + apd-Pow tail deferred = BI-2-residual); 1 MED builtin remains (BI-1 ASCII case-fold, reordered after F-3 — needs Unicode-table data decision); numeric/bounds/division/decimal core CONFORMS |
| F. Manifest/modules        | batch 2 | DONE   | 3 KUE-VIOLATES (`regexp` import missing — **F-1 FIXED 2026-06-19**; self `@vN` not stripped — **F-2 FIXED 2026-06-19**; qualified `path:id` unparsed — **F-3 FIXED 2026-06-20**); export + module-resolution core CONFORM |

## Audit history (archived — full detail in implementation-log.md + git)

Completed findings and shipped design specs, compressed to pointers. Each cites the
landing commit; the as-built detail lives in `docs/reference/implementation-log.md` and
git history.

- 2026-06-20 — **D#3** `let` clauses in comprehensions — the LAST open D-area item, now CLOSED.
  `Clause.letClause (name, value)` added to the comprehension clause sum (`Value.lean`, total, no
  catch-all); `descendClauses` `.letClause` arm routes the value through `onSource` + pushes +1, so
  `clauseChainDepth` + all 4 walkers handle it for free. Frame model: `let` = +1 (spec:
  *"`for` and `let` clauses each define a new scope"*; `if` = +0). Parse: `parseLetClause`
  (`dropWord?`-bounded), wired into `parseClause` after `for`/`if`; reached only inside a clause
  chain, so a struct-field-head `let` stays a struct-body binding (spec `StartClause` excludes
  `let`). Eval: bind the EVALUATED value into a one-slot frame like a `for` element
  (`loopFrame none .top name`), alignment-correct; an unreferenced binding's bottom sits unread
  (matches cue for value-level bottoms). All 8 clause-match sites updated explicitly. 9
  `native_decide` pins (incl. the `for`-after-`let` frame-accounting + shadowing cases) + 6 fixtures
  (list + struct forms); cert-manager content-identical. 1 cue-divergence (unreferenced unresolved-ref
  `let` — cue errors, Kue tolerates) + 1 spec-gap (eval-order/eager-into-frame). See implementation-log
  2026-06-20.
- 2026-06-20 — **D#1b + D#1c** comprehension-guard classification (`Eval.lean`: new total
  `classifyGuard` over a `GuardVerdict` sum, enumerating every `Value` — no catch-all — read by
  both clause-walkers; `Value.lean`: `NonBoolGuardType` + `BottomReason.nonBoolGuard`). D#1c
  concrete-non-bool→type-error (CONFORMS); D#1b incomplete→defer (keeps the comprehension residual
  via the new `ClauseExpansion`/`ListClauseExpansion` `deferred` outcome + `withDeferredComprehensions`
  re-wrap; spec-gap + display divergence recorded). The residual presence-test shape `X !=/== _|_`
  is carved out (stays a drop). Guard catch-all fully drained (D#1a/b/c all DONE). 17 `native_decide`
  pins + 4 fixtures; 3 bug-replicating drop-pins corrected to the held form; cert-manager
  content-identical. See implementation-log 2026-06-20.
- 2026-06-20 — **RX-2a** in-class negated shorthand classes (`Regex.lean` `parseClassEscape`'s
  `\D`/`\W`/`\S` `.error` arms → `complementRanges` folds; new total `Regex.complementRanges` +
  `maxCodePoint` over the `[0, U+10FFFF]` `Char` domain). The lone regex-corpus divergence;
  CONFORMS (RE2-mandated, cue-agreeing). Representation: NO new AST state — `cls ranges negated`
  already precise, the complement is a range union that composes through the ordinary union and is
  flipped by the whole-class `negated` flag for `[^…]`. 26 `native_decide` pins + the
  `numeric/regex_in_class_negated` `=~`/`!~` fixture. The regex corpus is now divergence-free
  (RX-1 trilogy + RX-2a/b/c all DONE).
- 2026-06-20 — **D#2b** terminating-disjunct (`Eval.lean` `normalizeEvaluatedDisj` now applies
  `liveAlternatives` on the has-default branch). Completes D#2: `#List | *null` terminates on
  `*null` (`tail: null`, cue-byte-identical). Re-diagnosis: VALUE resolution was already correct
  after D#2a (`export` via `resolveDisjDefault?`); the A#6 fuel cap was never implicated
  (detection at depth ~2 ⇒ shallow bottom); the gap was the EVAL value path emitting defaulted
  disjunctions raw (SC-3 root). The fix prunes the `.structuralCycle` arm WITHOUT collapsing the
  default into the value (collapse is unsound — `b: a & 2` needs the live non-default arm; cue's
  display-collapse is a projection). Folds in SC-3 dedup (`*1|*1|2` → `*1 | 2`). Eval-display
  divergence recorded (Kue shows `{…} | *null`, cue collapses — same convention as
  `default_disjunction`). 8 pins + 3 `export/` fixtures; cert-manager content-identical.
- 2026-06-20 — **D#2a** structural-cycle DETECTION (`Value.lean`
  `BottomReason.structuralCycle`; `Eval.lean` `structStack`/`isStructLikeBody` + `.refId`
  re-eval cycle bracket). The DESIGNED force-stack lever was wrong as built (the force triple
  never repeats — fresh frame ids); redesigned to a struct-body re-entrancy stack on the
  `.refId` path, keyed on the body `Value`. Detects def + regular + mutual struct cycles
  (class-agnostic), preserves `x: x` → `_`, no false-positive on finite-deep or list-tail
  recursion; cert-manager content-identical (zero false-fire). Value verdict CONFORMS to cue;
  eval-display differs (spec-gap recorded). 8 `native_decide` pins + 2 `refs/` fixtures.
- 2026-06-19 — `d9f66ca` — **Bug2-3 / Gap-2b** structural list-arm-vs-struct-host
  disjunction pruning (gated `embedBodyEmbedsDisj` /`spliceOperandForEmbed`; cert-manager
  byte-identical; 4 soundness obligations verified; cue correct, Kue was under-pruning).
- 2026-06-19 — `3f7a761` — **Bug2-4** let-LOCAL declare-and-read narrowing
  (`letPromotedReadLabels` + `injectLetLocalNarrowings`, both total + axiom-clean; minimal
  Mixin repro content-identical to cue; surfaced the residual Bug2-5 argocd blocker).
- 2026-06-19 — `2ab5c84..3725444` — Phase-A audit of the Bug2-3 + Bug2-4 batch (both
  spec-correct + sound; CLI-vs-harness divergence reconciled BENIGN; filed DRY-1 — see
  backlog).
- 2026-06-19 — `5d884af..e4922c9` — Phase-A audit of the RX-2b + RX-1c batch (both
  spec-correct; recategorized the RX-2b field-less invalid-label entry to a spec gap;
  added 3 newline regression pins; RX-2c noted already DONE).
- 2026-06-19 — `a5862df..04eb7de` — Phase-A audit of the SC-2 + RX-1a + RX-1b batch (RE2
  engine RE2-correct beyond the 7 repros, 1 corpus divergence = RX-2a; SC-2 no over-close;
  filed RX-2a/RX-2b/RX-2c/SC-4 — see backlog).
- 2026-06-19 — `4358a7e` — Phase-B whole-graph sweep (post regex-trilogy; module graph
  healthy; Bug2-3 + D#2 designs RE-VERIFIED GO no drift; produced the #4 re-rank below).
- 2026-06-19 — `659cf70` — Phase-B whole-graph sweep (D#2-spike audit; Regex leaf
  exemplary; RX-2b soundness hole resolved across 5 sites; perf-guide currency fixed
  inline).
- 2026-06-19 — Batch 1 (areas A, B, C) complete — SC-1/SC-2/SC-3 + Gap-2b +
  vindicated-correct catalog + spec gaps (import laziness, `A|B` form, field order #3).
- 2026-06-19 — Batch 2 (areas D, E, F) complete — D#1–D#7, RX-1, BI-1/BI-2, F-1–F-5
  findings; numeric/bounds/division/decimal CONFORMS.
- 2026-06-19 — `df10043..ae63b8a` — Phase-A audit of the SC-1d + F-2 batch (both
  spec-correct, DRY, all consumers covered; SC-1d surfaced the nested-closedness bug
  folded into SC-2).
- 2026-06-19 — RX-1a/RX-1b/RX-1c — regex trilogy SHIPPED (`Kue/Regex.lean` RE2-equivalent
  parse → Thompson compile → Pike-VM; submatch + `ReplaceAll` /`Find*` via the capture
  array; 4 dispatch sites rewired; old `Value.lean` backtracking block deleted; totality
  argument replaces the prior fuel-as-truncation soundness hole). Remaining regex work:
  RX-2a (below).
- 2026-06-19 — SC-2 SHIPPED — nested def-body closedness closed at the FIRST meet via the
  `normalizeDefinitionFieldWithFuel` CLOSING twin (Normalize-only; SC-2a cue-agrees, SC-2b
  diverges and is recorded in `cue-divergences.md`; `importBinding` /`letBinding`/hidden
  trap arms untouched). Was the last open closedness HIGH.

## Consolidated fix backlog (re-audit COMPLETE — spec-first, ranked)

Feature work resumes here, spec-first. Ranked by severity; contained high-confidence fixes
front-loaded before the large rewrites. **This section owns the single authoritative
ranked backlog.** The ranking is Phase-B audit #4 (below); the detailed live-slice entries
follow it.

### Re-ranked next slices (2026-06-19 Phase-B audit #4 — regex trilogy COMPLETE; SC-2 landed)

Re-rank after the full regex family (RX-1a/b/c, RX-2b/2c) + SC-2 landed and were
Phase-A-verified clean (`4358a7e`). The two designed HIGH levers (Bug2-3, D#2) RE-VERIFIED
GO against the post-SC-2 tree this audit (line-refs drifted ±40 but structures + reuse
targets intact). Principle (slice-loop, reaffirmed 2026-06-20): rank by **spec-correctness
and clean design evolution** — contained-soundness before larger features; cue-AGREEING
correctness before divergence; designed levers before undesigned. Real-app compilation
(argocd, cert-manager) is a STRESS TEST, not a ranking driver: a blocker that needs
app-specific narrowing is parked (see Bug2-5), never promoted to the critical path — it
resolves as the general semantics mature. **Recommended next 3-4:**

1. **D#2a — DONE (2026-06-20).** Structural-cycle DETECTION landed. The DESIGNED
   force-stack lever was WRONG as built (instrumentation falsified its premise: `#L` reaches
   `forceClosureWithConjunct` once, the unroll is on the `.refId` re-eval path with FRESH
   frame ids each level, so no force-triple identity can fire). Redesigned by first
   principles: a `structStack : List Value` on the `.refId` eval path detects struct-body
   RE-ENTRANCY (the body `Value` is the stable identity; frame ids are not). Lands oracle
   #1/#3/#4/#5 + the regular-field case (class-agnostic) + the list-tail control. cert-manager
   content-identical (zero false-fire on prod9). See Audit history + implementation-log.
2. **D#2b — DONE (2026-06-20).** Terminating-disjunct landed; **D#2 (structural cycles) is now
   COMPLETE** (detection + terminating-disjunct). Re-diagnosis vs the plan: VALUE resolution was
   ALREADY correct after D#2a (`export` gave `tail: null` via the existing `resolveDisjDefault?`
   → `liveAlternatives`); the A#6 fuel cap was NEVER implicated (detection fires at depth ~2, the
   bottom is shallow). The actual gap was the EVAL value path — `normalizeEvaluatedDisj` emitted
   defaulted disjunctions RAW (the SC-3 root), leaving the `.structuralCycle` arm in the eval
   value. Fix: apply `liveAlternatives` (prune-bottom/flatten/dedup) in its has-default branch,
   WITHOUT collapsing the default into the value (collapse would be unsound — `b: a & 2` needs the
   live non-default arm; cue's display-collapse is a projection, not a value rewrite). Folds in
   **SC-3**'s dedup (`*1|*1|2` → `*1 | 2`). 8 pins + 3 export fixtures. See Audit history +
   implementation-log 2026-06-20.
3. **RX-2a — DONE (2026-06-20).** In-class `\D`/`\W`/`\S` set-complement folding landed; the
   regex corpus is now divergence-free. `parseClassEscape`'s three `.error` arms became
   `complementRanges` folds (a new total `Regex.complementRanges` over the `[0, U+10FFFF]` `Char`
   domain) — NO new AST state (`cls ranges negated` already precise; the complement is itself a
   range union that composes through the ordinary union, flipped by the whole-class `negated`
   flag for `[^…]`). CONFORMS (RE2-mandated, cue-agreeing). 26 pins + 1 `=~`/`!~` fixture. See
   Audit history + implementation-log 2026-06-20.

(Recently landed, now in Audit history: Bug2-3/Gap-2b `d9f66ca`, Bug2-4 `3f7a761`. argocd
did not unblock — residual Bug2-5 is PARKED as a stress-test finding, see Live-slice
detail; it is not on the critical path.)

**Current state (2026-06-20):** the large designed levers are all DONE (Bug2-3, D#2, the regex
trilogy, BI-1, BI-2 Pow/Sort, F-3); **D-area CLOSED**. The **4 spec-gap ratifications are DONE**
(`47ff318` — 3 RATIFIED + test-pinned, gap-4/E#4 escalated to the **E#4-fix** slice `02b8b9d`,
also DONE). The only HIGH item left is **Bug2-5** (the argocd residual), **PARKED** as a
stress-test finding off the critical path. For the live ranked open backlog and the next-slice
leader, see `plan.md` § Live Backlog + the **Consolidated fix backlog** ranking above — this
section no longer carries a separate ranking (it drifted; the table + `plan.md` are the single
source). Audit cadence likewise lives in `plan.md` / the breadcrumb, not here.

### Live-slice detail (folded from prior re-ranks; DONE entries dropped to Audit history)

**Bug2-5 (HIGH — the single residual argocd export blocker, undesigned).**
`kue export apps/argocd.cue` still bottoms (~153s). Narrowing-injection into a
disjunction-arm-referenced let-local. The remaining shape, faithfully reproduced
(`/tmp/kue-ls-shape.cue`), is
`defaults.#ListenerSet = defs.#ListenerSet & parts.#UseCertManager & {…}`:
`defs.#ListenerSet` declares `kind: "ListenerSet"` at ITS def frame and CO-EMBEDS
`#UseCertManager` (→ `#Mixin`). The Mixin's `_patch.kind` must be narrowed by the SIBLING
def's `kind`, NOT by a use-operand. Because `#Mixin` 's body is the
`listShape | structShape | error` DISJUNCTION, the embed resolves on the `.disj` arm of
`meetEmbeddingsWithFuel` (each arm `meet` s the host AFTER the arm — and `_patch` 's
comprehension — has evaluated), so the narrowing arrives too late and
`injectLetLocalNarrowings` (which fires only on the `forceClosureWithConjunctCore`
`.structComp` arm) never runs. Minimal repro:
`#ListenerSet: { #UseCertManager; kind: "ListenerSet" }`,
`out: #ListenerSet & {#name:"x"}` → cue emits `meta:"yes"`, Kue drops it. **The fix:**
when an embedded disjunction's surviving arm (`structShape`) references a sibling let
(`_patch`) that declares-and-reads a label narrowed by a CO-EMBEDDING sibling def's static
field (`kind`), the `.disj` -distribution path of `meetEmbeddingsWithFuel` must inject
that narrowing into `_patch` BEFORE the arm's comprehension expands — the disjunction
analogue of Bug2-4's `injectLetLocalNarrowings` on the force path. A deeper mechanism than
read-label following. Pinned repro `/tmp/kue-ls-shape.cue`. (Note: CLI `kue export` and
the in-Lean `exportJsonMatches` harness reach DIFFERENT embed arms for the def-host Mixin
— both produce correct output, but the path divergence is a latent concern flagged for the
architecture audit. The Phase-A audit RECONCILED this as BENIGN for no-import single
sources — see Audit history `2ab5c84..3725444` — but the disj-arm path itself is the
Bug2-5 mechanism.)

**HIGH — soundness / real-app correctness (the LARGE designed levers):**

- **Bug2-3 / Gap-2b — DONE (2026-06-19, `d9f66ca`).** See Audit history.
- **D#2 — COMPLETE (2026-06-20).** Detection (D#2a) + terminating-disjunct (D#2b) both landed.
  `#L:{n,next:#L}` errors (cyclic re-entry bottoms with `.structuralCycle`); `#List | *null`
  terminates on `*null` (`tail: null`, byte-identical to cue). Detection = struct-body
  re-entrancy stack (`structStack`) on the `.refId` re-eval path (NOT the designed force-stack —
  see the SUPERSEDED banner below). Termination = `normalizeEvaluatedDisj` now applies
  `liveAlternatives` (prune-bottom/dedup) on the has-default branch, pruning the
  `.structuralCycle` arm WITHOUT collapsing the default into the value (unsound — see
  implementation-log). A#6 fuel cap was NOT implicated (detection at depth ~2 ⇒ shallow bottom).
  SC-3 dedup folded in. cert-manager content-identical (zero false-fire; prod9 has ZERO recursive
  defs). See Audit history + implementation-log 2026-06-20.

**BI-2-residual (MED — deferred builtins, undesigned numeric subproject).** The BI-2 slice
(2026-06-20) landed `math.Pow`'s EXACT domain + `list.Sort`/`SortStable` but DEFERRED two pieces
that need numeric/formatting machinery Kue does not have. Both BOTTOM today (honest "not computed",
never a wrong value — the grant): **(a) `math.Sqrt`** — cue computes it in IEEE-754 float64
(`Sqrt(2)=1.4142135623730951`) and renders with Go's float formatter incl. scientific notation
(`Sqrt(100)=1e+1`, `Sqrt(1000000)=1e+3`), with `Sqrt(-1)=NaN.0`, `Sqrt(0)=0.0`. Kue's numeric core
is EXACT base-10 rationals — no `Float`, no `NaN`/`Infinity`, no sci-notation formatter; even
perfect-square Sqrt needs the float-render path (`Sqrt(100)` must be `1e+1`, which Kue's decimal
formatter would render `10.0` — a wrong value), so NO sub-domain is cleanly carve-out-able. Needs:
a `Float` (or a decimal Newton/series sqrt to cue's precision) + `NaN`/`Infinity` value modeling +
a Go-style float formatter. **(b) `math.Pow` negative/fractional exponent + `Pow(0,neg)=Infinity`**
— cue uses an apd 34-significant-digit decimal Pow (`Pow(2,0.5)=1.414…209698`, `Pow(3,-1)=0.333…333`)
and emits `Infinity` for `Pow(0,neg)`. Needs an apd-equivalent decimal nth-root/exponentiation to
34 digits + an Infinity model. Design fork when sliced: introduce a real `Float`/IEEE bridge (broad,
risks colliding with the exact-decimal formatter) vs a decimal-precision numeric-methods module
(apd-style, keeps exactness philosophy). Lower priority than the feature tail; no real app needs it.

**SC-1b — DONE (2026-06-21).** Closed×closed-pattern intersection. The old `closingPatterns
: List Value` was a FLAT UNION across conjuncts — it could only express "matches ANY stored
predicate," so a meet of two closed structs admitted a field matching EITHER conjunct's
pattern. The correct closed allowed-set is the INTERSECTION: a field survives iff EVERY
closed conjunct admits it. A flat list of label-predicates cannot represent this (you cannot
intersect "matches `^x`" and "matches `^y`" into one regex). **Fix: provenance-carrying
representation** — replaced `closingPatterns` with `closedClauses : List ClosedClause`,
where each clause `{fieldLabels, patterns}` is ONE closed conjunct's allowed-set; a field is
admitted iff EVERY clause admits it (`ignoresClosedness` escapes; empty clause list = open).
A self-closed struct carries one clause; a meet CONCATENATES clauses (conjunction). This is
exactly the provenance the closedness guide mandates ("which conjuncts introduced which
patterns and closedness constraints"). The original audit witness (same-pattern `^x`,
disjoint *explicit* fields) was MASKED — the disjoint required fields materialize and
poison, so the union-store's lossiness wasn't observable there. The REAL witnesses use
DIFFERENT patterns: `#A:{[=~"^x"]} & #B:{[=~"^y"]}` then `& {x1}` — `x1` matches `^x` not
`^y`, must be rejected (cue rejects; pre-fix Kue admitted). Field-side too (CRUX): a
field-only closed clause `#A:{a?}` must reject a later `x1` that matches `#B`'s `^x` (the
merged `fields` over-approximates each clause's field-set, so per-clause field-labels are
needed). 17 pins: 12 source-level (`exportJson{Bottoms,Matches}` in `StructTests` `### SC-1b`
— disjoint/overlapping/narrower patterns, field-only-clause, broad-then-narrow, 3-way assoc,
nested, direct-meet, `close()`-idempotence, closed-empty) + 5 clause-logic units
(`fieldAllowedByClausesWith` = `all`/conjunction, in `LatticeTests`) + a fixture pair
(`definitions/sc1b_closed_pattern_intersection`). cert-manager export still semantically =
cue (def-meet hot path clean). All oracle-confirmed vs cue v0.16.1.

**SC-1e (MED — soundness, pre-existing, NEWLY DIAGNOSED during SC-1b; NOT yet fixed).**
Closed × OPEN-via-`...` interaction. A CLOSED struct met with an open-tail struct must STAY
closed — the `...` from the open operand does NOT re-open the closed conjunct (closedness is
monotone). cue: `#A:{[=~"^x"]} & {b:1, ...}` rejects `b` (`out.b: field not allowed`); `(#A &
{...}) & {y1}` rejects `y1`; `(#A:{a} & {...}) & {b}` rejects `b`. Kue ADMITS all (both before
and after SC-1b — confirmed against the `f0613e5` baseline, so PRE-EXISTING, not an SC-1b
regression). Root: the B2.5 tail×patterns composition arm in `mergeStructN` (the final
catch-all) produces a `defOpenViaTail` result with EMPTY `closedClauses`, dropping the closed
operand's clause. Two CLOSED structs never reach this arm (closed ⇒ no tail), so it is
strictly the closed×open-tail case, disjoint from SC-1b. **Fix sketch:** when either operand
is closed (`bothClauses` non-empty), the result is CLOSED — carry `bothClauses`, apply
`applyBothClosedness` to the merged fields, and DROP the tail (a closed struct admits no
extras, so the open operand's bare `...` is vacuous; cue confirms `...` acts as a no-op
constraint here). This needs the `closedClauses = [] ↔ open` invariant to admit a
closed-AND-tail-bearing intermediate, OR (cleaner) collapse to a no-tail `defClosed` result.
Its own slice with its own test sweep — do not fold into SC-1b. (MED tail.)

**RX-2a — DONE (2026-06-20).** In-class `\D`/`\W`/`\S` set-complement folding. See Audit
history + implementation-log. The regex corpus is now divergence-free (RX-1 trilogy +
RX-2a/b/c all DONE).

**SC-4 (LOW, spec-gap-first).** Hidden-field / let-bound-PLAIN-struct nested values do not
close on DIRECT def unification (`#A:{_h:{b:int}}; #A & {_h:{b,extra}}` and the let
analog) where cue closes. cue is INTERNALLY INCONSISTENT (direct-`&` closes,
select-then-`&` does not), so this is probably a cue eval-strategy artifact, not a spec
mandate. **Spec-check FIRST** (record in `cue-spec-gaps.md`); only then decide whether to
route these through the closing twin. Do NOT reflexively match cue. Lowest priority.
(Origin: SC-1-batch + SC-2 Phase-A under-close hunt; the SC-2 design deliberately routes
`letBinding` /hidden through the SPINE, correct for a let/hidden bound to a DEF — `c8b`
/`c4b` paths where Kue==cue==OPEN.)

**MED tail:**

9. **D#1b — DONE (2026-06-20).** Incomplete-guard deferral. A genuinely-abstract guard
   (a `.kind`, bound, unresolved disjunction, or non-presence comparison) now DEFERS —
   the comprehension stays a residual `.structComp`/`.comprehension`/`.listComprehension`
   node (cue eval-holds; `kue export` errors `incomplete value`), instead of dropping to
   `{}`/`[]`. Result protocol gained `ClauseExpansion`/`ListClauseExpansion`
   (`fields`/`bottom`/`deferred`); `withDeferredComprehensions` re-wraps. The residual
   PRESENCE test `X !=/== _|_` is CARVED OUT (stays a drop — cue eval drops it). Spec-gap
   recorded (defer mechanism); display divergence recorded (Kue renders the held ref as
   `@d.i`). See Audit history + implementation-log 2026-06-20.
10. **D#1c — DONE (2026-06-20).** Concrete non-bool guard → TYPE ERROR. A fully-concrete
    present value of non-`bool` type (`if "x"`/`if 3`/`if {…}`/`if [..]`/`if null`) is now a
    `.bottomWith [.nonBoolGuard ty]` that propagates (cue: `cannot use … as type bool`),
    NOT a `{}` drop. New `BottomReason.nonBoolGuard` + precise `NonBoolGuardType`
    (`scalar Kind`/`struct`/`list`). CONFORMS (cue+Kue agree, both modes). Split from D#1b
    in the SAME `classifyGuard` enumeration (no catch-all). See Audit history +
    implementation-log 2026-06-20.
11. **D#3 — DONE (2026-06-20).** `let` clauses in comprehensions. `Clause.letClause` added;
    `descendClauses` `.letClause` arm wires `let` = +1 (via `onSource` + frame push), so all 5
    frame-walkers + `clauseChainDepth` handle it. Parse (`parseLetClause`, clause-chain-only so a
    field-head `let` stays a struct-body binding — spec `StartClause` excludes `let`); eval binds
    the evaluated value into a `for`-element-style frame (alignment-correct). The for=+1/if=+0 model
    is spec-CORRECT (B7-vindicated); `let` joined as +1. 9 pins + 6 fixtures; cert-manager
    content-identical. The D-area is now CLOSED. See Audit history + implementation-log 2026-06-20.
12. **SC-3 — flatten/dedup half DONE (2026-06-20, folded into D#2b); display-collapse
    residual is LOW/spec-gap.** `normalizeEvaluatedDisj` now applies `liveAlternatives`
    (flatten/drop-bottom/dedup) on the non-all-regular branch — `*1|*1|2` eval → `*1 | 2`
    (deduped), `.structuralCycle` arms pruned. The prescribed fix is landed. What REMAINS is
    purely cue's further DISPLAY-collapse to the default (`*1|2` → `1`, `{…} | *null` → `null`),
    which Kue deliberately does NOT do — collapsing into the value is unsound (loses the live
    non-default arm a later meet needs; cf. `default_disjunction.expected` Kue `*"prod"|"dev"` vs
    cue `"prod"`). That cosmetic display projection (a Format-layer change rewriting ~7 fixtures)
    is recorded as a spec-gap (`cue-spec-gaps.md` D#2b/SC-3 row), not a value bug — close it only
    if the eval-display convention is ever revisited.
13. **F-3 — DONE (2026-06-20).** Qualified import path `"location:identifier"` now parses.
    The spec grammar `ImportPath = '"' ImportLocation [ ":" identifier ] '"'` puts the
    qualifier INSIDE the string; `splitImportPath` splits it out at parse time into a new
    `Import.packageName : Option String` (location-only `path` + explicit qualifier), so every
    path consumer (`isBuiltinImport`/`resolveImportTarget`/`lastPathElement`) sees the bare
    location — the previous bug fed the unstripped `:id` into directory resolution (`package
    directory not found: …/math-utils:math`). `isPackageIdentifier` validates the qualifier
    (identifier-start + parts, not `#`/`_#`) at PARSE, rejecting junk cue defers to a load error
    (F-3 divergence). `importBindName` precedence is alias > qualifier > declared-name >
    last-element. SCOPE = parse + bind-name; the stricter suffix-vs-loaded-declared-name MISMATCH
    gate (cue's `package name "other"`) is a recorded resolution residual (needs the loaded name).
    8 parse pins + 4 `importBindName`/`isPackageIdentifier` pins + 4 module fixtures
    (`qualified_import{,_bare,_mixed,_invalid_id}`, all byte-identical to cue on the success
    cases). 1 cue-divergence (junk-qualifier parse-reject) + 1 spec-gap (validity boundary +
    parse-only scope). See implementation-log 2026-06-20.
14. **BI-2 — DONE (2026-06-20), with residual.** `math.Pow` (EXACT non-negative-integer-exponent
    domain — repeated exact decimal multiply, byte-identical to cue; `Pow(0,0)` bottoms, CONFORMS)
    + `list.Sort`/`list.SortStable` (comparator `{x,y,less}` evaluated per pair at the EVAL layer via
    a total stable monadic merge sort; `list.Ascending`/`Descending` emitted by `stdlibPackageValue?`)
    all FIXED. **BI-2-residual (MED, deferred fix-slice):** `math.Sqrt` (IEEE-754 float64 — needs
    Float + `NaN`/`Infinity` + Go scientific-notation float formatting Kue lacks) and `math.Pow` with
    a negative/fractional exponent or `Pow(0,neg)=Infinity` (needs an apd-equivalent 34-sig-digit
    decimal Pow + Infinity model). Kue BOTTOMS on these inputs rather than shipping a wrong value
    (the grant). See Audit history + implementation-log 2026-06-20; spec gaps in `cue-spec-gaps.md`
    (BI-2 Pow + Sort rows).
15. **BI-1 (MED) — DONE 2026-06-20 (CONFORMS across the BMP).** Unicode case mapping for
    `strings.ToUpper/ToLower` shipped via an oracle-generated BMP simple-mapping table
    (`Kue/CaseTable.lean`, generated by `scripts/gen-case-table.py` from the local oracle,
    READ-ONLY no network; total binary-search lookup + Unicode char maps in `Builtin.lean`;
    ASCII maps deleted — the table is the single authority). `ToUpper("café")=="CAFÉ"`,
    `ToLower("ΑΒΓ")=="αβγ"`, byte-identical to cue across the BMP incl. irregular singletons
    (`µ`→`Μ`, `ÿ`→`Ÿ`) and the `ß`-no-expand simple-mapping boundary. New `StringsTests` module
    (case pins moved out of BuiltinTests + Unicode round-trips/singletons/boundaries/mixed +
    lookup unit pins) + `strings_case_unicode` fixture. **Residual (documented, deferred — NOT
    this slice):** (i) `ToTitle` stays ASCII-bounded — its Unicode TITLE-case mapping (`ǆ`→`ǅ`,
    ≠ upper) + `unicode.IsSpace` word boundary need their own table+predicate (the ONE remaining
    case-builtin divergence: `ToTitle("über alles")` Kue `"über Alles"` vs cue `"Über Alles"`);
    (ii) full case folding (`ß`→`SS`), locale (Turkish `ı`/`İ`), Greek final sigma, astral-plane
    letters — all recorded in `cue-spec-gaps.md` + `compat-assumptions.md`. See implementation-log
    2026-06-20. Spike findings (for the record):
    (a) UNAVAILABLE — `lake-manifest` has ZERO external deps (no Std/Batteries/Mathlib); Lean core
    `Char.toUpper/toLower` are ASCII-only, no Unicode tables in core. (b) algorithmic ranges REJECTED
    as a clean slice — local oracle (`cue export` over the whole BMP) shows the mapping is
    overwhelmingly IRREGULAR: 1190 ToUpper / 1173 ToLower BMP code points collapse to only 674/658
    offset-runs, of which **632/617 are SINGLETONS**; just ~13 contiguous regular runs (ASCII,
    Latin-1 supplement, Greek, Cyrillic, Armenian, fullwidth…). A (b) covering only the regular runs
    would leave all of Latin Extended-A/B (the even/odd ±1 letter pairs + hundreds of one-offs like
    µ→Μ +743, ÿ→Ÿ +121) WRONG — a weak partial on very common European text; covering the full set
    algorithmically = hand-transcribing ~650 rules as code (strictly worse than a table). (c) CHOSEN:
    generate a BMP **simple 1:1** case-mapping table from the local `cue` oracle (READ-ONLY, no
    network), embed as a Lean source file, commit the generator + table + provenance. cue's
    `strings.ToUpper/ToLower` are confirmed pure rune-wise SIMPLE mapping (length-in-code-points
    preserved across the BMP; NO ß→SS expansion — `ToUpper("ß")=="ß"`), so a 1:1 table is faithful;
    full-case-folding special-casing (ß→SS, locale ı/İ, final sigma) stays a documented spec-gap.

**Spec-gap decisions (the 4 ratifications) — DONE 2026-06-20.** All four were re-derived
from the spec + first principles and closed; see `cue-spec-gaps.md` for the full bases.
Verdicts:
- **Import-binding laziness** (B#2/F-5) — **RATIFIED.** Spec genuinely silent; keep tolerating
  on an operational-laziness basis (demand-driven value model; the `importBinding` marker keeps
  the package shallow). Includes the recategorized RX-2b field-less-invalid-label entry. Pinned
  by the `unreferenced_import_conflict` fixture + `rx2b_label_pattern_invalid_bottoms`.
- **`A|B` un-narrowed struct disjunction** (A) — **RATIFIED.** Spec silent; keep open — a join
  with no unique default IS the join (verified meet-identity vs `.top`). Corrected the prior
  "`incomplete`" mischaracterization (it is the open disjunction value, not an error). New pins
  `StructTests` `disj_struct_arms_no_default_*`.
- **Field order #3** (C/F-4) — **RATIFIED.** Spec silent (structs unordered, order
  implementation-defined); keep Kue's declaration/source order. Corrected the cue-behavior
  description (cue's cross-conjunct order is an undocumented internal-graph artifact, not the
  "first-introduced" rule once claimed — often sorts, sometimes interleaves). Supersedes plan
  item #4: parity DECLINED. New pin `meet_struct_field_order_is_declaration_order`.
- **list `+`/`*`** (E#4) — ✅ **DONE (E#4-fix, 2026-06-20).** Was MIS-FILED as a gap; the spec
  MANDATES the operator domain, so a concrete out-of-domain operand is a type error. cue is
  spec-correct; Kue was WRONG (held residual). FIXED — Kue now conforms. See the DONE entry below
  + `cue-spec-gaps.md` (RESOLVED row, NOT a `cue-divergence` — cue was right).

**E#4-fix — ✅ DONE (2026-06-20).** A concrete operand outside an arithmetic op's domain is now a
type-error bottom, not a held residual (the spec closes `+ - * /` over int/decimal, plus `+`/`*`
over string/bytes). `classifyArithOperand` (`Eval.lean`) classifies each operand `prim` /
`concreteNonArith` (`.struct`/`.list`/`.listTail`/`.embeddedList`) / `incomplete`;
`arithmeticDomainResult` type-errors (`.bottomWith [.nonArithmeticOperand op ty]`) ONLY a
concrete-nonarith operand paired with a CONCRETE partner, and DEFERS (`.binary` residual) whenever
either operand is incomplete — so `[1] + x` holds while `x: int` is abstract and errors only after
`x` resolves (matches cue; the concrete-vs-incomplete discipline mirrors D#1b/c `classifyGuard`).
The `prim,prim` mismatches (`1+"x"`, `"a"-"b"`) were already `.bottom` and unchanged. Sibling fix:
`evalMul` gained the string/bytes `*` int **repetition** arms (`"ab"*2="abab"`, either order, zero→
empty, negative→`negativeRepeatCount` error) — cue's documented behavior superseding
strings/bytes.Repeat, previously a silent wrong-bottom. Pins: 3 `numeric/*` fixtures + ~19
`native_decide` theorems (`EvalTests`). Verify: `lake build` green, `check-fixtures.sh` →
`fixture pairs ok` (zero drift), cert-manager content-identical to cue (modulo field-order #3).

**Low / hardening:** `containsBottom` fuel cap 100 (**A#6 — ✅ DONE 2026-06-21, made
TOTAL/structural**; `Lattice.lean:160`). Was: a bottom >100 levels deep escaped pruning →
wrong value (a dead disjunction arm survived `liveAlternatives`); a partiality hole.
**STANDALONE — D#2b confirmed it was NOT implicated by structural cycles** (D#2a detection
fires at recursion depth ~2, so a `.structuralCycle` bottom is always shallow); the hole was
for genuinely-deep NON-cyclic nested bottoms. **Fix:** removed the fuel entirely — rewrote
`containsBottom` as a mutual block (`containsBottom` + 4 list-helpers) elaborated via
`termination_by structural`, so it is TOTAL (no depth bound: a `.bottom` at ANY depth is
found) AND `rfl`/`decide`-reducible (structural recursion reduces in the kernel; a `sizeOf`
WF measure would have broken the existing `meet`/manifest `rfl` proofs). `fieldBottomCounts`
folded inline into `containsBottomFields` (optional-skip rule preserved). Axiom-clean
(`propext` only). Cert-manager byte-identical to pre-fix HEAD; fixtures zero-drift; 8
adversarial `native_decide` pins (deep-150/-500 bottom detected, deep no-bottom false, deep
`.bottomWith`, deep optional-skip, `liveAlternatives`/`normalizeDisj` end-to-end) in
`LatticeTests.lean`. Also: `{#a:1,5}` scalar-embed-with-definitions coverage gap; D#1b
incomplete-guard deferral (couples with D#2).

**DRY-1 (LOW Phase-B refactor, no behavior change).** Extract a shared `walkFollowedLets`
(visited-set + fuel + `.structComp` /`.struct` destructure) combinator and refactor
`closeDefFrameReadIndices` (collects `List Nat` indices), `letPromotedReadLabels`
(collects `List String` labels), `injectLetLocalNarrowings` (rewrites → `Value`) onto it —
the `seen.contains` /fuel-decrement/`.structComp`-vs-`.struct` destructure is copied ~3×.
The COMPOSERS (`embedComprehensionReadLabels`, `embedDisjArmDeclLabels`,
`embedBodyEmbedsDisj`, `spliceOperandForEmbed`) are NOT duplicative — each encodes a
distinct CUE rule. Pure cleanup; gate on byte-identical fixtures + axiom-clean. **Schedule
after Bug2-5** (which adds a 4th walker on the disj path — fold it into the same
combinator in one pass rather than refactoring twice).

**Plan-hygiene slice (non-code, schedule AFTER Bug2-3 lands).** `plan.md` and this audit
doc have accumulated superseded re-ranks, completed Phase-A write-ups, and resolved
fix-slice diagnoses. A hygiene pass distills the backlog to the LIVE open set + North Star
+ standing capabilities, moves DONE entries to `implementation-log.md` /git, and marks
RX-2c DONE (`maxRepeat=1000` landed with RX-1a). `docs/www/index.html` is CURRENT — leave
it.

**Spec-doc errors (cosmetic, no code action):** the CUE spec's disjunction worked-example
comments contradict its own U2 rule (cue + Kue both follow the rule); the
`2 & >=1.0 & <3.0` example is stale. No action.

## D#2 design (implementable) — structural-cycle detection

**Status (2026-06-19, Phase-B spike):** designed, ready to slice. Oracle ground truth
built; the detection lever, the terminating-disjunct handling, the soundness/totality
argument, and the slice plan follow. This is the remaining large structural gap (D#2,
HIGH, spec-mandated, currently MISSING).

### Spec basis (the gate — RE2-style, quote the spec)

The CUE spec mandates dynamic detection: *"Implementations should be able to detect such
structural cycles dynamically."* The validity rule it sets up: *"a node is valid if any of
its conjuncts is not cyclic"* — i.e. a structural cycle is an error UNLESS a conjunct/arm
provides a non-cyclic (terminating) value. So `#L: {n:int, next:#L}` (the sole conjunct is
cyclic) is a `structural cycle` error, while `#List: {head:_, tail: #List | *null}` is
valid — the disjunction's `*null` arm is a non-cyclic conjunct, so the node terminates by
taking it. This is NOT a perf concern routed through the fuel backstop; it is a
spec-mandated *value* (error vs terminated-struct), and the fuel bound must NOT be the
thing that fires.

### Oracle ground truth (cue v0.16.1, all probes run; `/Users/chakrit/go/bin/cue`)

| #   | Input                             | `cue`                               | Kue (current)                           | Verdict                                                 |                                         |
| --- | --------------------------------- | ----------------------------------- | --------------------------------------- | ------------------------------------------------------- | --------------------------------------- |
| 1   | `#L:{n:int, next:#L}` ; `x:#L`    | `#L.next: structural cycle` (error) | unrolls fuel-deep to truncated tree     | D#2 — Kue wrong (missing detection)                     |                                         |
| 2   | `#List:{head:_, tail:#List \      | *null}` ; `y:#List & {head:1}`      | `tail` collapses to `null` (terminates) | unrolls fuel-deep, `tail` never collapses               | D#2 — Kue wrong (default arm not taken) |
| 3   | `#A:{b:#B}` `#B:{a:#A}` ; `z:#A`  | `#B.a: structural cycle` (error)    | unrolls fuel-deep (mutual)              | D#2 — mutual recursion must also detect                 |                                         |
| 4   | `#D:{a:{b:{c:{d:int}}}}` ; `w:#D` | finite struct (no error)            | finite struct (correct)                 | control — finite-deep must NOT false-positive           |                                         |
| 5   | `x: x`                            | `x: _` (reference cycle → `_`)      | `x: _` (correct, via `visited` set)     | control — reference cycle already handled, do NOT touch |                                         |

The differentiator between #1 (error) and #5 (`_`): #5 is a REFERENCE cycle (`x` resolves
to itself with no struct between) handled by the depth-0 `visited` -slot check
(`Eval.lean:2342-2347`, returns `.top`); #1 is a STRUCTURAL cycle (a def body whose field
re-enters the same def through a struct layer) handled by the def-closure FORCE path
(`refDefClosureBody?` → `forceClosureWithConjunct`), which currently has NO cycle
tracking. The two are distinct mechanisms; D#2 adds the second without disturbing the
first.

### Root cause (single, in the def-body force path)

> ⚠ **SUPERSEDED by the D#2a as-built (2026-06-20).** This root-cause analysis and the
> `ForceKey`-triple ancestor scheme below were FALSIFIED by instrumentation during the D#2a
> slice. Reality: (1) `#L` reaches `forceClosureWithConjunct` EXACTLY ONCE — `refDefClosureBody?`
> returns `none` on every re-entry of `next: #L`, so the force branch is never re-taken; the
> unroll happens in `evalValueCoreWithFuel`'s `.refId` re-eval branches (depth-0-non-visited and
> depth>0), NOT the force path. (2) Those branches allocate FRESH frame ids each level
> (`[1,0]`→`[2,0]`→`[2,1,0]`→…), so `capturedEnv.ids` (hence the force triple) NEVER repeats — no
> force-triple identity can fire. The as-built lever is a `structStack : List Value` on the
> `.refId` path keyed on the body `Value` (the stable identity); see implementation-log
> 2026-06-20 + Audit history. Kept below as a record of the attempted design. **D#2b reads the
> "terminating-disjunct" subsection below as still valid** (it does not depend on the force-path
> premise — the cyclic arm bottoms via the as-built lever, and the pruning algebra is unchanged).

A `#Def` whose body needs deferral (`refDefClosureBody?` fires for a nested `depth>0`
self-ref `.struct`, oracle #1's `next: #L`) forces via
`forceClosureWithConjunct fuel (frame::outer) defBody []` (`Eval.lean:2331`). Forcing
evaluates the body's fields (`evalFieldRefsListWithFuel`, the `.struct` arm at
`Eval.lean:2898-2905`); the field `next:#L` is a `.refId` back to `#L`, re-enters the
`.refId` arm (`Eval.lean:2314`), hits `refDefClosureBody?` AGAIN, and re-forces the SAME
`(capturedEnv.ids, body)` one fuel tier down — recursing until `fuel = 0` truncates to
`{..., ...}`. The depth-0 `visited` -slot check (line 2342) is structurally BYPASSED: the
closure-force fork at line 2330 returns before the `visited` branch is ever reached. So
there is no ancestor memory on the force path at all.

### The ancestor identity is ALREADY computed — `ForceKey` minus fuel

The sound ancestor identity falls out of existing machinery. `forceClosureWithConjunct`
already keys its memo on `ForceKey = ⟨fuel, capturedEnv.ids, body, useOperands⟩`
(`Eval.lean:1418`). The fuel-free triple `(capturedEnv.ids, body, useOperands)` is EXACTLY
"this def-frame being expanded": `capturedEnv.ids` is the canonical frame-id stack
(frame-sharing canonicalizes it — `pushFrame` /`FrameKey`), `body` is the normalized def
body (closed-vs-open already baked in), `useOperands` is the narrowing. Two forces with
the same triple ARE the same def-frame expansion at different fuel — a structural cycle is
precisely a re-entry of an in-progress triple. So "ancestor" is identified soundly as
**the set of `(envIds, body, useOperands)` triples currently on the force stack** — no new
identity scheme, reusing the proven `ForceKey` soundness argument (the id stack is a
canonical proxy for frame contents).

### Detection lever — an ancestor-frame stack threaded through the force path

Add an ancestor stack to `EvalM` state (or thread it as a parameter — see "Representation"
below): `forceStack : List ForceFrameId` where
`ForceFrameId = (List Nat × Value × List (List Field × Bool))` is the fuel-free force
triple. `forceClosureWithConjunct`:

1. Compute `frameId := (capturedEnv.ids, body, useOperands)`.
2. **If `frameId ∈ forceStack` ** → this force re-enters an in-progress ancestor = a
   structural cycle. Return `.bottomWith [.structuralCycle]` (new `BottomReason` arm) for
   THIS expansion — do NOT recurse. (The "any conjunct not cyclic" rule is handled at the
   disjunction layer, below; a bare cyclic conjunct with no terminating arm surfaces this
   bottom.)
3. **Else** push `frameId`, recurse (`forceClosureWithConjunctCore`), pop on return.

This fires BEFORE fuel exhaustion: the second re-entry of `#L` (depth-2) is already an
ancestor hit, so detection happens at recursion depth ~2, not at `fuel = 0`. The fuel
bound stays as the backstop for genuinely-unbounded NON-cyclic growth (which a finite spec
program never has), but a true structural cycle NEVER reaches it. Place the check at the
single `forceClosureWithConjunct` entry (not `…Core`) so the memo-hit fast-path and the
cycle check share one gate; the memo and the cycle stack are orthogonal (a memo hit is a
*completed* force, never an in-progress one — a completed force has been popped, so a memo
hit can never be a false cycle positive).

**Why the force triple and not the slot index** (contrast with `visited`): the `visited`
set is slot indices within ONE frame — correct for same-frame reference cycles (#5),
useless across def-body expansions (each force pushes a fresh frame). The force triple
spans frames, which is what a structural cycle needs (#1's re-entry is a NEW frame with
the same canonical id-stack + body). Mutual recursion (#3, `#A` →`#B`→`#A`) works for
free: `#A` 's force triple re-enters the stack two hops down, same mechanism — no special
mutual-cycle code.

### The terminating-disjunct case (#2 — `#List | *null`)

`tail: #List | *null` must take the `*null` arm rather than unroll the cyclic `#List` arm.
The spec rule — *"a node is valid if any of its conjuncts is not cyclic"* — means: when
forcing a disjunction arm that turns out structurally-cyclic, that arm becomes
`.bottomWith [.structuralCycle]`, and the EXISTING disjunction algebra prunes it. The
mechanism already exists and needs only the cyclic arm to bottom:

- `liveAlternatives` (`Lattice.lean:266`) filters arms via `containsBottom` — a
  `.structuralCycle` bottom arm is dropped exactly like any other bottom arm.
- `resolveDisjDefault?` (`Lattice.lean:285`) then resolves: with the cyclic `#List` arm
  pruned, the surviving `*null` default wins → `tail: null`. The default-mark algebra is
  UNTOUCHED; the cyclic arm simply never survives to compete.

The ORDER subtlety the spike flags: the arms must be evaluated such that the cyclic arm's
re-entry bottoms it BEFORE `resolveDisjDefault?` runs — which is automatic, because
forcing each arm is what triggers the ancestor-stack hit, and `liveAlternatives`
/`resolveDisjDefault?` run on the already-forced arm values. The disjunction-distribution
path (`splitDisjConjunct`, `Eval.lean:2361`) and the `.disj` -arm force already evaluate
arms independently; the cyclic arm under the SAME force-stack ancestor bottoms, the
default arm does not. **No new default-resolution code** — D#2's terminating-arm handling
IS the existing default algebra, once the cyclic arm carries a `structuralCycle` bottom.
This is the same shape as D#1a (a bottom that must PROPAGATE through the
comprehension/disjunction algebra rather than vanish).

⚠ One probe the slice MUST run: confirm `*null` is reached. The current code
force-recurses the `#List` arm via `refDefClosureBody?` on `next` /`tail` — once that arm
bottoms on the ancestor hit, verify `liveAlternatives` sees the bottom (it calls
`containsBottom`, which must reach a nested `.structuralCycle` — check `containsBottom` 's
fuel cap A#6, the 100-level limit, does not hide a deep structural-cycle bottom; if it
can, raise it or special-case `.structuralCycle`).

### Soundness + totality (gate)

Three obligations, each discharged by the lever's structure:

1. **No false-positive on finite-deep non-recursive nesting** (oracle #4,
   `#D:{a:{b:{c:{d}}}}`). Each nested struct `a` /`b`/`c` has a DISTINCT force triple
   (different `body`, different `envIds`) — none re-enters an ancestor, so no
   `structuralCycle` fires. The depth is bounded by the program's finite AST; the force
   stack grows to AST depth and pops cleanly. ✓
2. **No interference with reference cycles** (oracle #5, `x:x`). The `visited` -slot check
   (line 2342) is on the NON-closure `.refId` path; `x:x` never reaches
   `refDefClosureBody?` (a bare self-ref with no struct body to defer → `none` from
   `refDefClosureBody?`, falls to the `visited` branch). The force stack is only pushed on
   the closure path. The two mechanisms are disjoint by construction. ✓ (Pin a
   `native_decide`: `x:x` still → `.top` /`_`.)
3. **Totality** — the force stack is a `List` that grows by one push per force-recursion
   and is bounded: either a triple repeats (→ cycle bottom, no further recursion) or every
   triple is distinct (→ bounded by the finite set of `(envIds, body, useOperands)`
   reachable from the program, which is finite since the AST is finite and `envIds` are
   drawn from the finite frame table). So the recursion terminates BY the cycle check,
   independent of fuel — fuel becomes a pure backstop, never the deciding bound for a
   cyclic program. No new `partial`; the `termination_by (fuel, 5, 0)` measure is
   unchanged (the check is a `List.contains` guard before the recursive call, not a new
   recursion). ✓

**Representation choice (illegal-states / repo philosophy):** thread the ancestor stack as
an EXPLICIT parameter to `forceClosureWithConjunct` /`…Core` (and the few force call
sites), NOT as mutable `EvalState`. A parameter is lexically scoped to the live recursion
— it cannot leak a stale ancestor across sibling forces (a mutable field would need
careful push/pop discipline that a future edit could break; the parameter makes the scope
structural). This mirrors the `visited : List Nat` parameter already threaded through
`evalValueWithFuel` — same pattern, same rationale (the slice loop's "encode intent in the
type/scope, not a flag"). The force-memo (`ForceKey`) is independent and unchanged: a memo
hit serves a COMPLETED (popped) force, never an in-progress ancestor, so the cycle stack
and the memo never alias. ⚠ Memo interaction to verify in the slice: a `structuralCycle`
bottom result must be keyed/cached correctly — it is a genuine saturated value (not a fuel
truncation), so it caches in `satCache` like any bottom; confirm the bottom is not
re-derived per fuel level (it should be `saturated`).

### New `BottomReason` arm + gate

Add `BottomReason.structuralCycle` (parameterize with the def label/path if cheap, for a
spec-shaped message like `#L.next: structural cycle`; a bare arm is acceptable for v1).
Wire its display in `Format` /`Manifest` (the standard bottom-reason rendering path).
**Gate:** byte-identical on ALL existing fixtures EXCEPT the new D#2 repros (which now
error/terminate correctly); cert-manager/argocd content-identical (re-probe READ-ONLY) —
and they CANNOT regress: a read-only sweep of `prod9/infra` (27 `.cue` files) found ZERO
self-referential definitions, so no real-app shape reaches the ancestor-hit path.
Detection fires only on a true ancestor re-entry, which the apps never trigger.

### Fixtures + pins

- **NEW (error cases):** `comprehensions/structural_cycle_struct` (#1, `#L:{n,next:#L}` →
  `next: _|_ structuralCycle`), `…/structural_cycle_mutual` (#3, `#A` /`#B` mutual). Each
  with a `FixturePorts` entry. (Note: the `.expected` records Kue's spec-correct ERROR,
  matching cue's `structural cycle` — record as CONFORMS, both error.)
- **NEW (terminating case):** `comprehensions/structural_cycle_terminating_default` (#2,
  `#List | *null` → `tail: null`), the spec's headline "valid if any conjunct not cyclic"
  case.
- **Controls (keep green):** a finite-deep struct fixture (#4 — must NOT bottom; add
  `…/deep_finite_struct_no_cycle` if not already covered), and `x:x` (#5 — reference cycle
  still `_`, an existing fixture).
- **`native_decide` pins:** `#L` self-ref → `structuralCycle` bottom at `next`;
  `#List | *null` → `tail` resolves to `null`; finite-deep → no bottom; `x:x` → `.top`
  (reference path untouched); mutual `#A` /`#B` → bottom.

### Slice plan (2 slices; worktree optional)

Splittable at a clean internal seam:

- **D#2a — detection (the error case).** Add `BottomReason.structuralCycle`; thread the
  ancestor force-stack parameter through `forceClosureWithConjunct` /`…Core` + its call
  sites; fire the cycle bottom on an ancestor hit. Wire bottom-reason display. Lands
  oracle #1/#3/#4/#5 (error + finite-control + reference-control). Gate: the two error
  fixtures + the two controls. Checkpoint-commit when green.
- **D#2b — the terminating-disjunct case.** Verify `liveAlternatives`
  /`resolveDisjDefault?` prune the cyclic arm and take `*null` (oracle #2); fix
  `containsBottom` 's fuel cap (A#6) if it hides a deep `structuralCycle` bottom (this
  couples D#2 with the A#6 hardening item — fold it in here if it blocks #2). Lands the
  `#List | *null` terminating fixture + pin.

**Couples with D#1b** (incomplete-guard deferral) only loosely — both touch
bottom-propagation through the disjunction/comprehension algebra, but D#2's bottom is a
CONCRETE structural-cycle error (propagate), not an incomplete deferral. Do D#2
standalone; D#1b can follow.

**Worktree: optional.** D#2a touches `Eval.lean` (the hot module) + `Value.lean`
(`BottomReason`) + `Format` /`Manifest` (display) — a focused multi-file change but not
the large churn RX-1b had. A worktree is reasonable if RX-1c/Bug2-3 are running
concurrently; otherwise `main` is fine (the change is additive — a new bottom arm + a
guard, no deletion of a hot block). Estimate: **2 slices**, contained.
