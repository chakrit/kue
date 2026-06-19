# Spec-conformance re-audit

A full re-examination of every `cue`-grounded behavioral decision in Kue against the **CUE
language spec** and **lattice first principles**, triggered by the 2026-06-19 reframe
(`docs/guides/slice-loop.md` → "The CUE spec is the authority"). The slice loop had drifted
into byte-identical-to-`cue`-v0.16.1 as the correctness gate — structurally bug-replicating.
This audit reclassifies what is actually correct vs. what merely matches a fallible binary.

Feature slices are PAUSED until the high-risk areas are reclassified; findings here become
the spec-first fix-slice backlog in `plan.md`.

## Authority hierarchy (the gate)

1. **CUE language spec** — authoritative where it speaks; match it even against the binary.
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

- **A. Disjunctions, defaults, narrowing** — default-mark algebra, resolution order, nested
  precedence, dedup, embedded-default narrowing, disjunction-arm pruning + structural
  discrimination (the argocd Gap-1/2/2b territory). HIGHEST risk — most `cue`-grounded.
- **B. Closedness & definitions** — open/closed, `...`, `#Def`, def-body closedness, the B6
  cluster, `importBinding`/hidden-field laziness, closed-meet.
- **C. Structs & lists** — meet, patterns, tail (the B2 `mergeStructN` matrix + B2.5
  cross-combinations), list meet, embeddings, scalar-embed collapse.
- **D. Comprehensions, references, scoping** — comprehension guards/sources/scoping, frame
  resolution, closures, cross-package def-meet.
- **E. Scalars, bounds, kinds, regex, arithmetic, builtins** — the "basic" lattice (likely
  CONFORMS, but verify cue-correctness, esp. bounds intersection + numeric/decimal).
- **F. Manifest/export & module/import semantics** — what errors vs. tolerates, hidden-field
  bottom propagation, field ordering (#3), incomplete-vs-error, cross-module resolution.

## Status

| Area | Auditor | Status | Findings (V/CUE-BUG/SUSPECT) |
|------|---------|--------|------------------------------|
| A. Disjunctions/narrowing | batch 1 | DONE | 1 KUE-VIOLATES (disj display); Gap-2b = real bug (cue correct); 2 spec gaps; rest CONFORMS |
| B. Closedness/definitions | batch 1 | DONE | 2 SUSPECT-ARTIFACT (instantiation re-open; import laziness); rest CONFORMS |
| C. Structs/lists          | batch 1 | DONE | 1 KUE-VIOLATES (pattern-meet closedness); 1 spec gap (field order); rest CONFORMS |
| D. Comprehensions/scoping | batch 2 | DONE | 3 KUE-VIOLATES (guard catch-all swallows bottom/incomplete; no structural-cycle detection; `let` clauses unparseable); frame-model + read-splice CONFORM |
| E. Scalars/bounds/builtins| batch 2 | DONE | 1 KUE-VIOLATES HIGH (regex not RE2); 2 MED builtin (ASCII case-fold; deferred builtins bottom); numeric/bounds/division/decimal core CONFORMS |
| F. Manifest/modules       | batch 2 | DONE | 3 KUE-VIOLATES (`regexp` import missing; self `@vN` not stripped; qualified `path:id` unparsed); export + module-resolution core CONFORM |

## Findings (ranked; filled as auditors return)

### Batch 1 (areas A, B, C) — complete 2026-06-19

**Fix-slices (KUE-VIOLATES — spec-first, ranked):**

1. **SC-1 (HIGH — closedness soundness; Kue wrong vs spec AND cue).** `mergeStructN` arms 5/6
   (`Lattice.lean:846-862`, pattern × plain) drop the *other* side's closedness/openness, so a
   closed `#Def` is silently re-opened when met with a pattern struct: `#C & P & {z:9}` admits
   `z`; spec ("closing = adding `..._|_`", conjunctive/monotone) and cue both reject. Fix:
   `StructOpenness.meet leftOpenness rightOpenness` + apply closedness from BOTH sides (each
   side's allowed set = own fields + own patterns). Contained; byte-identical gate + new
   spec-correct fixture.

2. **SC-2 (HIGH — closedness; requires DIVERGING from cue).** Closing-vs-instantiation. Spec:
   referencing a def recursively closes it "anywhere within the definition"; closedness
   persists through meet (monotone — meet cannot remove a constraint). cue RE-OPENS on
   instantiation (`(#D & {}).r & {b}` admits `b`) — an eval-strategy artifact, not
   lattice-derivable. Kue currently copies it. Fix = DIVERGE: preserve nested closedness on
   instantiation (reject `b`), record in `cue-divergences.md`. ⚠ This RE-SCOPES the B6-deferred
   sub-gap, which wrongly proposed *implementing* the artifact (a flag cleared on
   instantiation) — that direction is spec-wrong. ⚠ Real-app impact: verify cert-manager/argocd
   don't depend on the re-open before landing.

3. **SC-3 (LOW-MED — disjunction eval display/normalization).** `normalizeEvaluatedDisj`
   (`Eval.lean:648`) only flattens/dedups the all-regular case; a marked-default or nested
   `.disj` arm is emitted raw → `eval` display + structural `.disj` equality diverge (`*1|*1|2`
   shows raw, cue → `1`). Values stay correct (`export`/arithmetic force `resolveDisjDefault?`).
   Fix: apply `liveAlternatives` (flatten/drop-bottom/dedup) in the non-all-regular branch.

**Gap-2b / Bug2-3 — REAL bug, cue correct → PROCEED (was suspected artifact, now cleared).**
Structural arm pruning is spec-grounded ("unification distributes over disjunction" +
`list & {regular fields} = ⊥`). Kue under-prunes a list-shaped arm carrying a force-tier
spliced `_patch` against a struct host (`Eval.lean ~2661/2704`). ⚠ The fix MUST key on the
actual `.embeddedList`/list-meet-to-bottom, NOT a shape heuristic — cue does NOT prune two
*struct*-shaped arms (stays ambiguous `incomplete`), so over-eager shape discrimination would
itself be a divergence. Continue Bug2-3 as a correctness fix; record the basis as spec-grounded.

**Spec gaps (→ `cue-spec-gaps.md`):** import-binding laziness tolerating a bottom unreferenced
def (B#2 — flip basis from "match cue" to a deliberate operational gap; smell:
reference-location-dependent); the `incomplete value A | B` ambiguity form for un-narrowed
struct-arm disjunctions (A — lattice-defensible: a join with no unique default); struct-meet
output field ORDER (#3 — spec mandates none; Kue ≠ cue; re-derive a principled order, do NOT
inherit cue-pins).

**Vindicated CORRECT (cleared — were potential artifacts, proven lattice/spec-correct, keep):**
B2.5 pattern×tail unify; pattern dedup; scalar-embed `{5}`→`5`; list meet; hidden-field
deep-bottom propagation (deep IS spec-correct — recursive bottom rule); `StructOpenness`
lattice + meet; B6 direct-def-path close; default-mark cross-product algebra;
resolve-operand-first; embedded-default narrowing + the 4 argocd narrowing fixtures.

**Low / hardening:** `containsBottom` fuel cap 100 (`Lattice.lean:142` — a bottom >100 levels
deep escapes pruning → wrong value, not just slow; partiality hole); `{#a:1, 5}`
scalar-embed-with-definitions coverage gap.

**Spec-doc errors (cosmetic, no code action):** the CUE spec's disjunction worked-example
comments contradict its own U2 rule; cue + Kue both follow the rule.

### Batch 2 (areas D, E, F) — complete 2026-06-19

**D — comprehensions/scoping:** D#1 guard `_ => []` catch-all conflated false/incomplete/error
→ a bottom guard (`if 1/0 > 0`) silently vanished (SOUNDNESS) and an incomplete guard drops
the field instead of deferring. **D#1a (bottom half) FIXED 2026-06-19** — bottom now propagates
(see fix backlog). D#1b (incomplete-deferral half) still open. D#2 NO structural-cycle detection — `#L:{n:int,next:#L}`
unrolls to garbage; spec mandates detection (wrong value, missing feature). D#3 `let` clauses
in comprehensions unparseable (`Clause` has only for/if). D#4 the for=+1/if=+0 frame model is
spec-CORRECT (B7 vindicated); `let` must wire as +1 when D#3 lands. D#5 the
comprehension-read-splice (Bug2-1/2) is LATTICE-DERIVED/correct (meet idempotent → early
splice recovers a result naive order drops) — KEEP; its gates are a perf-fence smell, not
correctness. D#6/D#7 minor cycle-display / iteration divergences (doc).

**E — scalars/bounds/builtins:** RX-1 (HIGH) the regex engine is NOT RE2 — expands only the
first group, no `\b`, no lazy quantifiers, unsound anchoring-dependent substring fallback;
silently mis-validates grouped/multi-group/semver/DNS patterns real apps use (invisible to
fixtures). BI-1 (MED) `strings.ToUpper/ToLower` ASCII-only (cue full-Unicode → wrong answers).
BI-2 (MED) deferred builtins (`math.Pow/Sqrt`, `list.Sort`) bottom on concrete input. E#4 (LOW)
list `+`/`*` removed in cue v0.11 (Kue leaves residual). Numeric/int-float-lattice/bounds/
division(Euclidean div-mod, truncated quo-rem)/decimal(34-digit) all CONFORMS (re-derived).

**F — manifest/modules:** F-1 (HIGH) `regexp` not in the builtin import allowlist → real apps
`import "regexp"` fail (engine exists, wiring missing). F-2 (HIGH) self-module `@vN` suffix not
stripped (deps are; asymmetry) → in-module imports fail. F-3 (MED) qualified import `"path:id"`
unparsed (latent). F-4/F-5 confirm spec gaps (export field order — keep Kue's principled
source-order; import laziness reference-location-dependence — keep, record). Export
concreteness, incomplete-vs-error, required/optional/definition/null emission, module
resolution core all CONFORMS.

## Consolidated fix backlog (re-audit COMPLETE — spec-first, ranked)

Feature work resumes here, spec-first. Ranked by severity; contained high-confidence fixes
front-loaded before the large rewrites.

**HIGH — soundness / real-app correctness:**
1. **SC-1 — DONE (2026-06-19).** mergeStructN pattern-meet dropped the other-side closedness,
   re-opening a closed def met with a pattern struct. Fixed: arms 5/6 (and arm 1/7) now set
   result openness = `StructOpenness.meet leftOpenness rightOpenness` and apply closedness from
   BOTH sides. The KEY subtlety required a representation refinement: a pattern only CLOSES (widens
   the allowed set) if it belongs to a CLOSED struct, so `.struct` gained a `closingPatterns :
   List Value` field (subset of `patterns`' label-predicates) threaded through `mkStruct`/meet. An
   OPEN conjunct's pattern (e.g. `P`'s `[string]`) is retained as a value-constraint but NOT as a
   closing pattern, so `#C & P & {z:9}` rejects `z` (spec + cue agree), while `#C & P & {a:1}`
   admits `a`, a closed def's OWN pattern (`#D:{a,[string]}`) still admits matching fields, and an
   OPEN struct met with a pattern stays open (no over-close). Pins: 4 `native_decide` theorems in
   `LatticeTests` + fixture `definitions/sc1_closed_meets_pattern_stays_closed`. cert-manager
   re-probed: exports clean, no regression. `Lattice.lean` `mergeStructN`, `Value.lean`
   `mkStruct`/`Value.struct`.
   - **SC-1b (follow-up, MED — soundness, pre-existing & broader than SC-1).** The
     `closingPatterns` carry-forward is a UNION across conjuncts; for two CLOSED defs with DISJOINT
     explicit fields but overlapping patterns (`#A:{a,[=~"^x"]} & #B:{b,[=~"^x"]}`), the correct
     forward allowed-set is the INTERSECTION of the two (`out.a`/`out.b` rejected, `x1` admitted).
     The union-store admits `a`/`b` on a LATER meet against the result (the at-this-meet marking is
     correct via sequential closedness application; only the stored forward set is lossy). cue
     rejects `a`/`b`; current Kue (both before and after SC-1) admits them. Needs an
     intersection-aware closed allowed-set representation. Not introduced by SC-1 — SC-1 made the
     pattern-vs-plain case correct; this is the closed×closed-pattern case.
2. **D#1a — DONE (2026-06-19).** Comprehension guard: a BOTTOM guard now PROPAGATES instead of
   being swallowed. Mechanism: the six expansion helpers
   (`expandClauses`/`expandForPairs`/`expandComprehension`/`expandComprehensions` + the two list
   twins) return `EvalM (Except Value (List …))` — `.error b` carries the bottom value (preserving
   `.bottomWith reasons`) and short-circuits every concat in the for-pairs/clause recursion; the
   three call sites (`.comprehension` eval arm, the eager + forced `.structComp` arms, and
   `evalListItemsWithFuel`) re-surface it as the result bottom. The guard match is now ENUMERATED,
   no catch-all swallow: `.bool true` → continue, `.bool false` → drop (`[]`, the spec drop),
   `.bottom`/`.bottomWith` → propagate, residual `_` → still `[]` (D#1b makes the incomplete case
   DEFER). A SECOND swallow was found and fixed: the clauses-exhausted `[] =>` arm's body-eval
   catch-all (`| _ => pure []`) also dropped a `.bottom` body (the case where a bottom guard sits
   one level deeper, inside a `for`-body struct) — now `.bottom`/`.bottomWith` body propagates.
   `{if (1/0>0){b:1}}` → `_|_`; `false`/`true` guards unchanged; the list twin positions the bottom
   in the element slot (`[if(1/0>0){1}]` → `[_|_]`, Kue's existing `[1/0]` → `[_|_]` convention —
   the soundness fix is that it is PRESERVED, not swallowed). Pins: 4 `native_decide` theorems in
   `PresenceTests` + 3 fixtures (`comprehensions/guard_bottom_propagates`,
   `list_guard_bottom_propagates`, `guard_bottom_from_sibling`). cert-manager re-probed: exports
   clean (~34s), no regression. `Eval.lean` expansion-helper cluster + call sites. (D#1b
   incomplete-deferral still OPEN — larger, couples with D#2 structural cycles.)
3. **F-1** add `regexp` builtin import + wire `regexp.Match/…` to the existing engine. Contained;
   real-app blocker.
4. **F-2** strip self-module `@vN` in `readModuleInfo`. Contained. `Module.lean:221-236`.
5. **RX-1** replace the regex engine with a real AST→NFA→Thompson (RE2-equivalent, total).
   LARGE; own planned slice. Highest real-app correctness impact.
6. **D#2** structural-cycle detection (ancestor-chain; default-arm-terminates). LARGE; own slice.
7. **Bug2-3 / Gap-2b** argocd disjunction under-pruning (REAL bug, cue correct) — key on
   `.embeddedList`/list-meet-to-bottom, NOT a shape heuristic. The argocd unblock.

**HIGH — DIVERGE from cue (spec says so):**
8. **SC-2** closing-vs-instantiation: preserve nested closedness on instantiation; record
   `cue-divergences.md`. RE-SCOPES B6-deferred (which wrongly proposed implementing the cue
   artifact). Verify cert-manager/argocd no-regress.

**MED:**
9. **D#3** `let` clauses in comprehensions (parse + `Clause.letClause` + wire `let`=+1 in
   `descendClauses`).
10. **SC-3** disjunction eval display: flatten/dedup the non-all-regular branch
    (`normalizeEvaluatedDisj`).
11. **BI-1** Unicode case folding for `strings.ToUpper/ToLower`.
12. **BI-2** implement `math.Pow/Sqrt`, `list.Sort/SortStable`.
13. **F-3** parse qualified import path `"location:identifier"`.

**Spec-gap decisions (record + ratify, mostly doc):** import-binding laziness (B#2/F-5 — keep,
operational basis); incomplete `A|B` form (A — keep open); field order #3 (C/F-4 — keep Kue's
principled source-order, stop gating on cue's order); list `+`/`*` (E#4 — decide hard-error vs
residual). All three current gaps already in `cue-spec-gaps.md`.

**Low / hardening:** `containsBottom` fuel cap 100 (A#6 — deep bottom escapes pruning);
`{#a:1,5}` scalar-embed-with-defs coverage; D#1b incomplete-guard deferral (couples with D#2).

**Spec-doc errors (cosmetic):** CUE spec's disjunction worked-example comments contradict its
own U2 rule (cue + Kue follow the rule); the `2 & >=1.0 & <3.0` example is stale. No action.
