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
| B. Closedness/definitions | batch 1 | DONE | SC-1/1c/1d + SC-2 (nested def-body closedness) all FIXED 2026-06-19 — closedness cluster drained; import-laziness recorded as a deliberate gap; rest CONFORMS |
| C. Structs/lists          | batch 1 | DONE | 1 KUE-VIOLATES (pattern-meet closedness); 1 spec gap (field order); rest CONFORMS |
| D. Comprehensions/scoping | batch 2 | DONE | 3 KUE-VIOLATES (guard catch-all swallows bottom/incomplete; no structural-cycle detection; `let` clauses unparseable); frame-model + read-splice CONFORM |
| E. Scalars/bounds/builtins| batch 2 | DONE | 1 KUE-VIOLATES HIGH (regex not RE2); 2 MED builtin (ASCII case-fold; deferred builtins bottom); numeric/bounds/division/decimal core CONFORMS |
| F. Manifest/modules       | batch 2 | DONE | 3 KUE-VIOLATES (`regexp` import missing — **F-1 FIXED 2026-06-19**; self `@vN` not stripped — **F-2 FIXED 2026-06-19**; qualified `path:id` unparsed); export + module-resolution core CONFORM |

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
   - **SC-2 is BROADER than the re-open-on-instantiation framing (Phase-A SC-1d/F-2 probe,
     2026-06-19).** Nested closedness fails on a SINGLE meet, no instantiation needed: `#A: {a:
     {b: int}}` meet `{a: {b: 1, extra: 5}}` — `cue` and the spec REJECT `extra` (the inner
     `{b: int}` is "within the definition" ⇒ closed), but Kue ADMITS `extra: 5`. The TOP-level
     def field closes correctly (`#A: {b: int} & {b: 1, extra: 5}` → `extra: _|_`, oracle-matched)
     — only the NESTED struct-field value fails to close. Same root cause (closedness not
     propagated into nested def-body field values) but the differentiator is DEPTH, not
     instantiation; the SC-2 fix must close nested field values at the FIRST meet, not only
     defend against a later re-open. Probes: `{a:{b:int}}` over-opens (Kue admits extra); the
     pattern variant `{a:{b,[=~"^x"]}}` likewise over-opens nested while the top-level pattern
     def closes (SC-1c). Cue agrees with the spec on all of these → NOT a divergence; Kue is
     wrong. No fixture shipped (an `.expected` recording Kue's current wrong output would lie
     about correctness); the SC-2 fix-slice owns adding the spec-correct fixture once it closes
     nested. Repro for that slice: `#A:{a:{b:int}}` / `out: #A & {a:{b:1,extra:5}}` ⇒ expect
     `out.a.extra` rejected.

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

### Phase-A audit of the SC-1d + F-2 batch (`df10043..ae63b8a`, 2026-06-19)

Both slices verified spec-correct; nothing in either was reverted or refixed.

- **SC-1d (parser preserves `...` when patterns present).** All four `declared` arms route the
  tail: plain+pattern via `baseValue = mkStruct … .defOpenViaTail (some tail) patterns`;
  comprehension-only via `structCompOpenness = .defOpenViaTail` (`structComp` carries no tail
  VALUE by design — bare `...` flag); comprehension+pattern via `.conj [baseValue, structComp]`
  (typed tail + patterns live in `baseValue`, openness in `structComp`). ILL-1 coherence triple
  (`openness=.defOpenViaTail ∧ tail.isSome ∧ closingPatterns=[]`) is enforced structurally by
  `mkStruct`/`coherentTail` — incoherent triples are unconstructable through the only sanctioned
  constructor. Oracle probes (all Kue==cue==spec): nested `{a:{b,[pat],...}}` admits extra
  (open); multi-pattern+`...` admits non-matching, value-constrains matching; plain (non-def)
  struct+pattern+`...` stays open; comprehension+pattern+`...` (arm 3) splices comprehension
  field, admits extra, value-constrains matching. SC-1c regression guard holds at top level
  (pattern+no-`...` def closes). The 4 native_decide pins are real (one directly inspects the
  parsed node's coherence triple). **Verdict: CORRECT, complete, coherent.**
- **SC-1d surfaced a SEPARATE pre-existing bug (NOT introduced by SC-1d):** nested closedness is
  not propagated — see the SC-2 finding above (`#A:{a:{b:int}}` over-opens on a single meet). It
  lives in the no-tail path SC-1d never touched; folded as a broadening of SC-2.
- **F-2 (strip self-module `@vN` in `readModuleInfo`).** DRY: reuses `depKeyModulePath` (the
  same strip deps already use) on the `module:` field — no duplicated strip logic. The bare
  `modPath` reaches ALL consumers: it populates `ctx.modPath` at every `readModuleInfo` call
  site (self-context `loadFileBound`/`loadPackageDir`, dep-context hop in `resolveImportTarget`),
  feeding `resolveImportSubpath`/`importUnderModule`/`resolveCrossModule`. `depKeyModulePath` is
  total (`splitOn "@"` always returns ≥1 element; the `[] => key` arm is dead but harmless) and
  identity on a no-`@` path (no-suffix case unchanged). Edges: empty string → `""` (total);
  multi-`@` malformed path (`a@v1/b@v2`) → strips at FIRST `@` (`a`), but CUE module paths cannot
  legally embed `@` except the trailing major, so this is a non-case — acceptable, noted as a
  latent assumption rather than a gap. Fixture is end-to-end and oracle-matched; 4 pins pin the
  exact bug composition. **Verdict: CORRECT, DRY, all consumers covered.**
- **Illegal-states/totality:** no new partiality, no new catch-all `_`, no incoherent
  constructor reachable. SC-1d's coherence is type-enforced via `mkStruct`; F-2 adds no new state.

## Consolidated fix backlog (re-audit COMPLETE — spec-first, ranked)

Feature work resumes here, spec-first. Ranked by severity; contained high-confidence fixes
front-loaded before the large rewrites.

### Re-ranked next slices (2026-06-19 Phase-B audit #2 — DONE: SC-1, SC-1c, SC-1d, SC-2, D#1a, F-1, F-2)

Contained-high-confidence before large rewrites; cue-AGREEING correctness before divergence;
contained-correctness before large rewrites (slice-loop principle). **Recommended next 3-4:**

1. **SC-2 — DONE (2026-06-19).** Nested def-body closedness via a closing field-walker twin
   (`normalizeDefinitionFieldWithFuel` in `Normalize.lean`). SC-2a (cue+spec agree) and SC-2b
   (the spec-correct divergence) landed as ONE change. Closedness cluster drained to zero.
   See the "SC-2 design (implementable)" section below (now the as-built record) and the
   HIGH-backlog item for the full fix description.
2. **RX-1 (HIGH, LARGE — 3 slices, worktree).** Highest real-app-correctness lever; 7
   demonstrated silent mis-validations + unblocks F-1's `ReplaceAll` (prod9 exports). Design
   ready below ("RX-1 design (implementable)"). **RX-1a (AST+parser) — DONE (2026-06-19).**
   → **RX-1b (NFA+Pike-VM+rewire the 3 dispatch sites + delete old engine) — NEXT** →
   RX-1c (submatch+`ReplaceAll`).
3. **Bug2-3 / Gap-2b (HIGH).** The LAST argocd export blocker — structural disjunction-arm
   pruning. Design landed (`plan.md` "Slice Bug2-3 — Gap-2b"). High payoff (a whole app
   exports), contained primitive (list-meet-to-bottom keying), well-diagnosed. Ranks with RX-1
   (both HIGH, both designed) — sequence by whichever worktree is freer; RX-1 is the broader
   correctness lever, Bug2-3 the single-app unblock.
4. **D#2 (HIGH-MED, LARGE — structural-cycle detection).** `#L:{n:int,next:#L}` unrolls to
   garbage (wrong value + missing feature); spec mandates detection. Own slice; needs the
   design-spike treatment (ancestor-chain; default-arm-terminates) before launch. Couples with
   D#1b (incomplete-guard deferral).

Then the **MED tail** (D#1c non-bool guard → type error; D#1b incomplete-deferral, couples
with D#2; D#3 `let`-clauses; SC-3 disj display; BI-1 Unicode case-fold; BI-2
`math.Pow`/`Sqrt`/`list.Sort`; F-3 qualified import), spec-gap ratifications, then
low/hardening (`containsBottom` fuel cap; `{#a:1,5}` coverage). SC-1b (MED soundness,
closed×closed-pattern intersection) sits with the MED tail — pre-existing, narrower than SC-1.

Rationale for SC-2 → RX-1/Bug2-3 → D#2: SC-2 is the only contained HIGH correctness fix left
(one file, full soundness argument, fixes a live over-open) — it lands first to drain the
closedness cluster to zero before opening the RX-1 worktree. RX-1 and Bug2-3 are the two large
designed levers (broad regex correctness vs single-app unblock); D#2 is the remaining large
structural gap and needs its own spike. Divergence (SC-2b) rides in with SC-2a because the
representation entangles them — there is no cue-agreeing-only slice to do first.

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
   - **SC-1c — DONE (2026-06-19, Phase-A audit of the SC-1 batch).** A closed pattern-def did
     NOT close over its own SELECTIVE pattern: `#A: {x:int, [=~"^a"]:int} & {b:1}` admitted `b`
     (cue rejects). SC-1's headline constraint C1 used `[string]` (matches everything) and so
     MASKED this — the def was never actually closing; it stayed open with `closingPatterns=[]`.
     Two root causes, both fixed: (1) `Normalize.normalizeDefinitionValueWithFuel`'s
     pattern-bearing def arm passed the parser's open-by-default `openness` straight to
     `mkStruct` (so the default `closingPatterns = if openness.isOpen then [] else …` resolved to
     `[]` AND the openness stayed `regularOpen`) — now `openness.closeDefBody` closes a no-`...`
     pattern def exactly like the no-pattern arm; (2) `Eval.applyEvaluatedStructN`'s pattern
     branch split the fields onto a SEPARATE open struct for the pattern-application meet, so the
     closedness check's `declaredFields` was `[]` and the def's OWN declared `x` bottomed; fields
     (and the tail) now stay on the pattern-bearing struct. Verified: `#A & {b:1}` rejects `b`,
     `#A & {a1:1}` admits `a1`, standalone `#A` keeps `x`, and all SC-1 C1/C2/C2b constraints
     still hold (cue-cross-checked). `lake build` + `check-fixtures` (`fixture pairs ok`) +
     `shellcheck` green. `Normalize.lean` def-pattern arm, `Eval.lean` `applyEvaluatedStructN`.
   - **SC-1d — DONE (2026-06-19).** A struct with BOTH patterns AND a `...` tail dropped the tail
     at PARSE time: `Parse.parsedFieldsValue`'s `some tail` branch returned `declared`
     (= `parsedFieldsBaseValue`, `.regularOpen` + `none` tail) whenever patterns were present (the
     `| _, _ => declared` arm), losing the `...`. Harmless while pattern-defs never closed; once
     SC-1c made them close, an open-via-tail pattern def `#A: {x, [=~"^a"], ...} & {extra}` wrongly
     REJECTED `extra` (cue admits — the `...` opens it). Fix: co-represent tail+patterns at parse
     time. Introduced a single tail-aware `baseValue` (`match parts.tail | some tail => mkStruct
     parts.fields .defOpenViaTail (some tail) parts.patterns | none => parsedFieldsBaseValue …`)
     used by every `declared` arm (plain, comprehension-only, comprehension+pattern conj base), so
     the `...` + patterns now CO-REPRESENT in all four combinations. `mkStruct` with
     `.defOpenViaTail` enforces ILL-1: tail present, patterns retained as value-constraints,
     `closingPatterns = []` (open ⇒ closes nothing). The whole trailing `match parts.tail` dispatch
     collapsed to `declared` (now redundant — `baseValue` already encodes the tail). Verified vs
     cue v0.16.1: pattern+`...` admits a non-matching `extra` (OPEN); pattern+no-`...` still rejects
     a non-matching `z` (SC-1c CLOSING intact); pattern+`...` still value-constrains a matching
     `abc` (`"no"` vs `int` → bottom). Pins: 4 `native_decide` theorems in `ParseTests`
     (`parse_pattern_tail_stays_open`, `parse_pattern_notail_closes`,
     `parse_pattern_tail_value_constrains`, `parse_pattern_tail_node_is_open_via_tail` — the last
     inspects the parsed node: `openness = .defOpenViaTail` ∧ `tail.isSome` ∧ `closingPatterns = []`)
     + 3 fixtures (`definitions/sc1d_pattern_tail_stays_open`, `…_notail_closes`,
     `…_tail_value_constrains`) with `FixturePorts` ports. **Real-app:** cert-manager re-probed
     READ-ONLY — exports clean (exit 0, ~32s), no regression (diff vs cue is the known field-ORDER
     gap #3 only, same keys/values). argocd still bottoms on the PRE-EXISTING Bug2-3/perf wall, NOT
     an SC-1d/SC-1c over-close — and **no prod9 file combines a `[pattern]:` with `...` in one
     struct**, so SC-1c had NOT over-closed any real-app `{patterns, ...}` shape: SC-1d is the
     forward-looking fix for the regression SC-1c could cause, not a recovery of a live regression.
     SC-1d cannot regress the real apps — it is purely additive to openness (preserves `...`), so it
     can only make a struct MORE open, never more closed. `Parse.lean` `parsedFieldsValue`.
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
   - **D#1c (follow-up, MED — found in the SC-1-batch Phase-A audit).** The guard's residual
     `_ => pure (.ok [])` arm still SWALLOWS a CONCRETE non-bool guard, which the spec treats as a
     type error, not a drop: `if "x" {…}` / `if 3 {…}` yield `{}` in Kue but `cue` errors
     (`cannot use "x" (type string) as type bool`). D#1a fixed the bottom case and D#1b owns the
     INCOMPLETE (abstract) case (legitimately defers), but the residual arm conflates "incomplete
     abstract → defer" with "concrete non-bool → error". The fix splits them: a concrete value
     whose kind is not `bool` is a `.bottomWith` type error (propagate, like the bottom case);
     only a genuinely incomplete/abstract guard defers (D#1b). Couples with D#1b's deferral
     classification. `Eval.lean` `expandClausesWithFuel` guard match.
3. **F-1 — DONE (2026-06-19).** Added `"regexp"` to `builtinImportPaths` (`Module.lean`) so
   `import "regexp"` resolves, and wired a `regexp.*` call-form dispatcher (`evalRegexpBuiltin`,
   `Builtin.lean`). `regexp.Match(pattern, string) -> bool` dispatches to `stringRegexMatches`
   — the SAME engine entrypoint `=~` uses, an UNANCHORED search (matches anywhere), confirmed
   against the Go/CUE stdlib contract and cross-checked vs `cue` v0.16.1 (`^x`/`y`/`b`/`q`/`z$`/
   `[0-9]` all byte-identical). **Deferred (engine cannot do submatch/replace yet — RX-1):**
   `ReplaceAll`, `ReplaceAllLiteral`, `Find`/`FindSubmatch`/`FindAll*`, and any other capture- or
   substitution-form. These surface a CLEAR signal — a new `BottomReason.unsupportedBuiltin name`
   on concrete args (NOT a silent wrong answer); an abstract arg stays an unresolved `.builtinCall`
   for a later pass. ⚠ prod9 (honda-obs/lemonsure/ssw `defs/filters/regexp.cue`) uses ONLY
   `regexp.ReplaceAll` with `${n}` backrefs, so F-1 unblocks the *import* but NOT those apps'
   exports — they need RX-1. Probe confirmed: the prod9 filters package no longer errors on
   `import "regexp"`; it now advances to a *different* unimplemented builtin (`text/template`).
   **F-1's dispatch inherits RX-1's pending engine limitations** (grouped quantifiers, `\b`, lazy
   quantifiers, multi-group, invalid-pattern-as-literal); RX-1 fixes both `=~` and `regexp.*`
   together. Pins: 7 `native_decide` theorems in `BuiltinTests` + fixture
   `builtins/regexp_match` + module fixture `modules/regexp_import` (end-to-end loader). cert-manager
   re-probed: exports clean (~34s), no regression.
4. **F-2 — DONE (2026-06-19).** Self-module `@vN` suffix was read VERBATIM into
   `ModuleContext.modPath` (`Module.lean` `readModuleInfo`), so a module declared
   `module: "ex.com/m@v0"` got `modPath = "ex.com/m@v0"` and an in-module import `"ex.com/m/sub"`
   prefix-matched against `"ex.com/m@v0/"` → NO match → "unresolved import". The `@major` strip
   already applied to dependency KEYS (`depKeyModulePath`) but NOT to the importing module's own
   path — that asymmetry was the bug. CUE modules contract: the `@vN` in `module:` is the major
   version, not part of the addressable path; imports address the BARE module path. Fix (DRY):
   reuse the existing `depKeyModulePath` on the `module:` field in `readModuleInfo` so the returned
   `modPath` is bare. Both `readModuleInfo` callers (`loadFileBound`/`loadPackageDir` self-resolution
   and `resolveImportTarget`'s cross-module dep-context hop) flow through this one function, so the
   bare form propagates to every `modPath` consumer (`resolveImportSubpath`/`importUnderModule`).
   The dep-strip path is untouched (deps already stripped their own keys). Pins: 4 `native_decide`
   theorems in `ModuleTests` (verbatim `@v0` modPath → `none`; stripped → `some "sub"`; stripped
   module-root → `some ""`; no-suffix regression guard → unchanged) + module fixture
   `modules/self_major_version_strip` (`module: "ex.com/m@v0"`, in-module `import "ex.com/m/defs"`,
   end-to-end loader, oracle-matched vs cue v0.16.1). **Real-app:** no prod9/hatari self-module
   declares an `@vN` suffix today (swept all `cue.mod/module.cue` read-only — all bare paths), so
   F-2 changes NO current real-app resolution; it is forward-looking and can only HELP (a future
   `@vN` module's in-module imports resolve instead of erroring), never regress — the no-suffix
   case is the `depKeyModulePath` identity, and the no-suffix self (`export_subdir`) + dep
   (`crossmod*`) fixtures stayed green.
5. **RX-1** replace the regex engine with a real AST→NFA→Thompson (RE2-equivalent, total).
   LARGE; own planned slice. Highest real-app correctness impact.
6. **D#2** structural-cycle detection (ancestor-chain; default-arm-terminates). LARGE; own slice.
7. **Bug2-3 / Gap-2b** argocd disjunction under-pruning (REAL bug, cue correct) — key on
   `.embeddedList`/list-meet-to-bottom, NOT a shape heuristic. The argocd unblock.

**HIGH — nested def-body closedness (SC-2a cue-AGREES + SC-2b DIVERGES; ONE slice):**
8. **SC-2 — DONE (2026-06-19).** Closed nested def-body field VALUES at the FIRST meet via a
   CLOSING field-walker twin `normalizeDefinitionFieldWithFuel` (`Normalize.lean`): identical to
   `normalizeFieldWithFuel` except the regular/optional/required arm recurses the CLOSING walker
   `normalizeDefinitionValueWithFuel` (not the spine), so a referenced def's nested PLAIN-struct
   field values close recursively. The CLOSING walker's `.struct`/`.structComp`/pattern-bearing
   arms now map this twin over their fields. **SC-2a (cue+spec AGREE):** `#A:{a:{b:int}} &
   {a:{b:1,extra:5}}` rejects `extra` (oracle #1/#2/#3 + #6 direct-selector); a nested `...`
   keeps the nested struct OPEN (#4). **SC-2b (DIVERGES — recorded):** `(#D & {}).r & {b}` now
   REJECTS `b` (closedness monotone through meet; cue re-opens on `& {}` — eval-strategy
   artifact). Fell out for free: Kue stores closedness on the value, meet is monotone, no
   shed-on-`&` code exists, so closing the nested value once preserves it through instantiation.
   Trap defence (UNCHANGED arms): `importBinding` SKIP (bound packages stay lazy — no
   cert-manager/argocd re-bottom), `letBinding`/hidden `_x` SPINE (a def's hidden-field nested
   struct admits extras, #8); a plain non-def struct never reaches the twin (#5 stays open).
   Normalize-only; no `Lattice`/`Eval` edit (`mergeStructN` enforces + preserves the closure).
   Pins: 4 `native_decide` soundness theorems + flipped SC-2b theorem + 5 `sc2a_*` fixtures +
   the renamed `sc2b_instantiated_def_field_stays_closed`; updated `eval_meet_lazy_hidden_def`
   (nested def-body `out` now `.defClosed`). Gate: all existing fixtures byte-identical except
   the one flipped SC-2b fixture; cert-manager content-identical (field-order gap #3 only, exit
   0 ~32s), argocd still bottoms on the pre-existing Bug2-3 (`conflicting values`, NOT a
   closedness `field not allowed` bottom, ~91s). The "SC-2 design (implementable)" section below
   is now the as-built record.

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

## RX-1 design (implementable) — replace the regex engine with an RE2-equivalent NFA

**Status (2026-06-19, Phase-B spike):** designed, ready to slice. The current matcher
(`Value.lean` `stringRegexMatches`/`parseRegexAtom`/`regexMatchHereWithFuel`/
`expandFirstRegexGroup`, ~L771-1012) is a backtracking literal/class matcher that
**silently mis-validates** real-app patterns. The CUE spec mandates RE2: *"the regular
expression syntax is that accepted by RE2 … except for `\C`."* So the gate is RE2/Go
`regexp` semantics, not the binary. Oracle-confirmed (cue v0.16.1) the 7 demonstrated
constructs all `=~ true`; the current engine returns wrong/unsound results on all 7:

| Construct                | Pattern (example)                         | Current engine fault |
|--------------------------|-------------------------------------------|----------------------|
| grouped quantifier       | `^(ab)+$`                                 | `+` re-binds to `b`, not the group (only group *alternatives* expanded) |
| nested group             | `^((a\|b)c)+$`                            | only FIRST group expanded; outer `(` `)` fall through as literals |
| multi-group semver       | `^(\d+)\.(\d+)\.(\d+)$`                    | 2nd/3rd `( )` become literal `(`/`)` → never matches |
| word boundary `\b`       | `\bcat\b`                                  | `\b` parsed as literal `b` (no `\b`/`\B` atom) |
| lazy quantifier          | `a.*?b`                                    | `?` after `*` parsed as a fresh optional atom; no laziness |
| DNS-1123                 | `^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.…)*$`    | nested optional groups + group-`*` mis-expanded |
| anchoring fallback       | any unanchored pattern with a group       | UNSOUND substring fallback can admit non-matches |

### Architecture — parse → compile → Pike-VM (total, linear)

Three stages, a new module `Kue/Regex.lean` (regex is a pure `String → String → Bool`/
submatch function with NO `Value` dependency — it imports nothing from the engine and is
imported by `Eval`/`Lattice`/`Builtin`, a clean leaf in the import graph; the `Value`
no-`DecidableEq` perf carve-out does NOT apply here).

1. **AST** (`inductive Regex`). Total, illegal-states-unrepresentable:

   ```
   inductive Regex where
     | empty                                        -- ε
     | lit       (c : Char)
     | class     (ranges : List (Char × Char)) (negated : Bool)
     | any                                          -- . (no newline, RE2 default)
     | anchorStart | anchorEnd                      -- ^ $
     | wordBoundary (negated : Bool)                -- \b \B
     | concat    (parts : List Regex)
     | alt       (branches : List Regex)            -- a|b|c
     | star      (greedy : Bool) (body : Regex)     -- *  *?
     | plus      (greedy : Bool) (body : Regex)     -- +  +?
     | opt       (greedy : Bool) (body : Regex)     -- ?  ??
     | repeat    (greedy : Bool) (min : Nat) (max : Option Nat) (body : Regex)  -- {m},{m,},{m,n}
     | group     (index : Option Nat) (body : Regex) -- capturing (some i) / non-capturing (none)
   ```

   Greediness is a `Bool` FIELD on each quantifier, not a separate lazy constructor — keeps
   the match-priority logic in one place. `{m,n}` carries `max : Option Nat` so `{m,}` is
   representable without a sentinel. `group`'s `index` is `none` for `(?:…)`, `some i` for a
   capturing group (i assigned left-to-right at parse time). The repeat-with-bounded-max is
   **desugared to concat of opt/exact copies at compile time** (RE2 does this; keeps the VM
   free of counters), so the VM never sees `repeat`.

2. **Parser** (`parseRegex : String → Except RegexParseError Regex`). Recursive-descent over
   `List Char`, total via a structural-position fuel = input length (each step consumes ≥1
   char or descends a balanced bracket). Grammar: alt → concat → quantified → atom, with
   atom = group | class | escape | `.` | anchor | literal. This REPLACES the four ad-hoc
   splitter functions (`splitRegexAlternatives*`, `parseRegexGroupBody*`, `findFirstRegexGroup*`,
   `expandFirstRegexGroup`) with ONE real parser — the "expand only the first group" hack
   disappears by construction. **Invalid pattern → `Except.error`**, NOT a silent
   literal-fallback (the current `parseRegexAtom`'s `['\\'] => .literal '\\'` and
   group-not-found → literal `(` are unsound). RE2/cue treat an invalid pattern in `=~` as a
   build error (`.bottomWith [.invalidRegex …]`); pin that.

3. **Compile to NFA** (`compile : Regex → NFA`). Thompson construction. NFA =
   `Array Inst` (a flat program, RE2/Pike style) with instructions:

   ```
   inductive Inst where
     | char  (ranges : List (Char × Char)) (negated : Bool) (next : Nat)  -- consume one matching char
     | any   (next : Nat)
     | split (a : Nat) (b : Nat)            -- ε-fork; ORDER encodes greediness (a before b = prefer a)
     | jmp   (next : Nat)
     | save  (slot : Nat) (next : Nat)      -- record input pos into capture slot (Pike submatch)
     | assert (kind : AssertKind) (next : Nat) -- ^ $ \b \B (zero-width)
     | accept
   ```

   Greedy `*` compiles to `split(body, exit)`; lazy `*?` to `split(exit, body)` — the split
   ARM ORDER is the entire laziness mechanism, and the Pike-VM's "first thread to reach
   accept wins" gives RE2 leftmost-greedy/lazy semantics for free. `save 2i`/`save 2i+1`
   bracket each capturing group i → submatch spans (slot 0/1 = whole match).

4. **Pike-VM** (`run : NFA → List Char → Option (Array (Option Nat)))`). Thompson/Pike
   simulation: step the input one char at a time carrying a SET of threads (dedup by pc →
   each instruction visited ≤ once per input position), each thread a pc + capture array.
   `split`/`jmp`/`save`/`assert` are followed in the ε-closure within a position; `char`/`any`
   advance to the next position. **No backtracking → linear in `input.length × NFA.size`**,
   no catastrophic blowup. Returns the capture array of the first thread to `accept` (NONE on
   no match). Boolean `=~`/`Match` = `(run …).isSome`; submatch = the array.

### Totality argument (replaces the current fuel-bounded *partiality*)

The current engine is `partial`-in-spirit: `regexMatchHereWithFuel` returns `false` on fuel
exhaustion — a fuel-out is INDISTINGUISHABLE from a genuine non-match (a soundness hole on
adversarial patterns). The Pike-VM is **structurally total**: the outer loop is structural
recursion on the input `List Char` (decreasing); the inner ε-closure terminates because the
thread set is deduped by pc over a FIXED-SIZE `Array Inst` (≤ `NFA.size` distinct pcs, so the
closure worklist drains in ≤ `NFA.size` steps — a `Nat` fuel = `NFA.size` is provably
sufficient AND never reached spuriously, unlike the input×pattern×4 backtracking budget).
Total decidable function, no `partial def`, no fuel-as-truncation. Compile + desugar are
structural recursion on the finite AST. The parser is the one fuel-bounded step (input-length
fuel), consistent with the standing parser exception, but here the bound is exact (one char
consumed per step). **This removes a real soundness hole, not just a perf concern.**

### RE2 subset — implement now vs. defer (stub-not-silent-wrong)

**MANDATORY (covers prod9 corpus + spec examples; unblocks all 7 repros + F-1):** concat,
alternation `|`, capturing `( )` + non-capturing `(?:…)`, repetition `* + ? {m} {m,} {m,n}`
GREEDY and LAZY, char classes `[…]`/`[^…]` with ranges, perl classes `\d \D \w \W \s \S`,
`.`, anchors `^ $`, word boundaries `\b \B`, escapes. Submatch capture (slot array) — needed
for F-1's `ReplaceAll`/`FindSubmatch`.

**DEFERRED — explicit `.bottomWith [.unsupportedRegex feature]`, never silent-wrong:** named
captures `(?P<name>…)`, flags `(?i)`/`(?m)`/`(?s)`, `\A \z \Q…\E`, POSIX classes
`[[:alpha:]]`, Unicode property classes `\p{…}`/`\pL`. **RE2 has NO backreferences by
design** — `\1` in the pattern is a parse error in RE2/cue, so Kue's parser rejects it too
(this is the `${n}` in `ReplaceAll`'s *replacement template*, a different grammar — see
below, that IS supported). Each deferred feature is detected in the parser and surfaced as a
clear unsupported signal; the policy mirrors F-1's `unsupportedBuiltin`.

### Submatch → unblocks F-1's `ReplaceAll`/`Find*`

The Pike-VM's capture array is exactly what F-1's deferred forms need. With submatch:

- `regexp.Match(p,s) → bool` = `(run …).isSome` (re-wire the existing `regexp.Match` arm).
- `regexp.FindSubmatch`/`Find`/`FindAll*` = expose the capture spans as the documented
  CUE/Go return shapes.
- `regexp.ReplaceAll(p, s, template)` — the prod9 lever. Parse the REPLACEMENT template's
  `${n}`/`$n` backrefs (Go `Regexp.Expand` grammar, NOT regex backrefs), substitute capture
  group n's span. This is what honda-obs/lemonsure/ssw `defs/filters/regexp.cue` need to
  export. Remove the `unsupportedBuiltin` deferral arms in `evalRegexpBuiltin` as each lands.

### Migration + soundness gate

This is a behavior **CHANGE, not byte-identical** — the old engine mis-validates, so the new
one will return DIFFERENT (correct) results on the 7 repros. The gate is therefore NOT
"byte-identical to old Kue"; it is **conformance to RE2/spec**, cross-checked against cue:

1. All 7 RX-1 repros now match cue (add as fixtures with `=~`).
2. **Existing regex fixtures stay correct** — `regex_match_expressions`,
   `regex_group_alternation_pattern`, `regex_bounded_repetition_pattern`,
   `regex_label_pattern`, `regex_wildcard_pattern`, `regexp_match`, `modules/regexp_import`
   all use the simple anchored/class/single-group patterns the OLD engine got right, so they
   must stay green (a regression here = a real bug).
3. Cross-check a corpus of real patterns vs cue: semver, DNS-1123 (label + subdomain),
   docker image-ref, k8s name, and the prod9 `regexp.ReplaceAll` filter patterns.
4. `native_decide` theorems pinning: greedy-vs-lazy priority, group submatch spans, `\b` at
   word edges, invalid-pattern → error, deferred-feature → unsupported.

Record in `cue-divergences.md` any case where the new engine matches the spec but cue (rare
for regex — cue delegates to Go's RE2, so it's usually correct here) differs.

### Slice plan (3 slices; worktree recommended)

RX-1 is large and touches a NEW module + three dispatch sites. Split at clean seams:

- **RX-1a — AST + parser + invalid-pattern errors. DONE (2026-06-19).** New leaf
  `Kue/Regex.lean` (imports only `Char`/`String`): `Regex` inductive (greediness a `Bool`
  field on each quantifier; `repeat.max : Option Nat`; `group.index : Option Nat`) +
  `parseRegex : String → Except RegexParseError Regex` (recursive-descent, TOTAL via
  input-length fuel, no `partial`/`sorry`). Invalid → `.error` (typed: `.malformed` /
  `.backreference` / `.unsupportedRegex`), NEVER a silent literal-fallback. `\1` rejected
  (RE2 has no backrefs); deferred constructs (`(?i)`, `(?P<…>)`, `\A`/`\z`/`\Q`, POSIX
  `[[:…:]]`, `\p{…}`, in-class `\D`/`\W`/`\S`) → `.unsupportedRegex`. Pins: 7 repro ASTs +
  greedy/lazy + `{m,n}` shapes + non-capturing-index + class/dot + invalid (incl. `a{5,2}`
  → error, matching RE2 vs a literal) + `\1` + 4 deferred, all `native_decide`. Additive /
  byte-identical: NOT wired to any dispatch site; `lake build` green (96+ jobs),
  `check-fixtures` zero drift, `shellcheck` clean.
- **RX-1b — Thompson compile + Pike-VM + re-wire boolean `=~`/`Match`.** `compile`, `Inst`,
  `run`, then point `stringRegexMatches` (or its replacement) at the VM and re-wire the three
  call sites (`Eval.evalRegexMatch`, `Lattice.meetStringRegexPrim`, `Builtin.regexp.Match`).
  Delete the old `Value.lean` regex block (~L771-1012). Gate: 7 repros + all existing
  fixtures green vs cue.
- **RX-1c — submatch wiring: `ReplaceAll`/`Find*`.** Expose the capture array; implement
  `regexp.ReplaceAll` (+ `Expand` template grammar) and `Find*`/`FindSubmatch`; remove the
  matching `unsupportedBuiltin` deferral arms. Gate: prod9 filter patterns export, cue-exact.

**Worktree: yes.** RX-1b deletes a large block from `Value.lean` (a hot, widely-imported
module) and adds a leaf module — a worktree isolates the multi-file churn (new module +
3 dispatch rewrites + Value deletion) from concurrent slices and keeps `main` shippable
between the three sub-slices. Each sub-slice commits independently (checkpoint discipline).

## SC-2 design (implementable) — nested def-body closedness

**Status (2026-06-19, Phase-B spike):** designed, ready to slice. The spike oracle-confirmed
the two halves AND uncovered that they are NOT independently sliceable in Kue's
representation — see "Entanglement" below. Lever, soundness, and the trap argument follow.

### Oracle ground truth (cue v0.16.1, all probes run)

| # | Input | `cue` | Kue (current) | Verdict |
|---|-------|-------|---------------|---------|
| 1 | `#A:{a:{b:int}}` `& {a:{b:1,extra:5}}` | REJECT `extra` | **ADMIT** | SC-2a — Kue wrong, cue+spec agree |
| 2 | `#A:{a:{b:int\|*0}}` `& {a:{b:1,extra:5}}` (concrete) | REJECT `extra` | **ADMIT** | SC-2a — cleanest repro (fully concrete) |
| 3 | `#A:{a:{b:{c:int}}}` `& {a:{b:{c:1,deep:9}}}` | REJECT `deep` | (ADMIT) | SC-2a — closes RECURSIVELY at any depth |
| 4 | `#A:{a:{b:int,...}}` `& {a:{b:1,extra:5}}` | ADMIT `extra` | ADMIT | control — nested `...` keeps nested struct OPEN |
| 5 | `A:{a:{b}}` (plain, no `#`) `& {a:{b:1,extra:5}}` | ADMIT `extra` | ADMIT | control — plain nested struct stays OPEN (the A2 trap) |
| 6 | `#D:{r:{a:int}}` ; `#D.r & {b:2}` (direct selector) | REJECT `b` | **ADMIT** | SC-2a — same root cause; cue closes the direct path |
| 7 | `#D:{r:{a:int}}` ; `(#D & {}).r & {b:2}` (instantiated) | ADMIT `b` | ADMIT | SC-2b — cue RE-OPENS on instantiation; spec says close |
| 8 | `#A:{_h:{x:int}}` ; `out._h & {extra}` | ADMIT `extra` | ADMIT | control — hidden-field nested struct does NOT close |

Note cue's **internal inconsistency** between #6 and #7: `#D.r` closes but `(#D & {}).r`
re-opens. The differentiator is the `& {}` instantiation step, not anything lattice-derivable
— strong evidence #7 is an eval-strategy artifact (closedness shed by `&`), not spec behavior.
The spec says closedness is monotone through meet, so the closed `r` must STAY closed → #7's
admit is the bug, #6's reject is correct.

### Root cause (single, in the no-tail path)

Closedness is stored on the struct VALUE (`StructOpenness`); meet preserves it (monotone — a
single-side field carries through `mergeFieldIntoWith` verbatim). A `#Def` is closed lazily by
`Normalize.normalizeDefinitionValueWithFuel` (the CLOSING walker) when referenced/captured.
That walker's no-pattern `.struct` arm (`Normalize.lean:27-28`) DOES set the struct's own
openness to `defClosed`, but it descends its fields via the SHARED `normalizeFieldWithFuel`,
whose regular/optional/required arm (`Normalize.lean:121-122`) recurses the **SPINE** walker
`normalizeDefinitionsWithFuel` — which preserves openness and only closes nested `#Def`s, NOT
nested PLAIN struct VALUES. So `#A:{a:{b:int}}` closes the top struct but leaves `a`'s value
`{b:int}` at `regularOpen`. B6 deliberately chose the spine here (its sub-gap note's "STOP")
precisely because the closing walker risked the A2/cert-manager trap — but that risk is now
GONE (see Soundness), so the choice can be revisited.

### Lever — a CLOSING field-walker variant (Normalize, no-tail path only)

Give `normalizeFieldWithFuel` a closing-context twin (`normalizeDefinitionFieldWithFuel`)
whose ONLY difference is the regular/optional/required arm recurses
`normalizeDefinitionValueWithFuel` (CLOSING) instead of `normalizeDefinitionsWithFuel`
(spine). The CLOSING walker's `.struct` arms call this twin (not the shared walker). The
other three arms are UNCHANGED — and that is the entire trap defence:

- **`importBinding` → skip (untouched).** Bound packages are never recursed (closing OR
  spine) → no cert-manager/argocd re-bottom (control #5/A2 trap structurally dodged; the
  `FieldClass.importBinding` marker, post-ILL-1, makes this LOCAL by construction).
- **`letBinding` / in-file hidden `_x` → spine (untouched).** Their nested struct VALUES do
  NOT close (oracle #8: a def's hidden-field nested struct admits extras) — keep them on the
  spine, preserving their own openness exactly as today.
- **regular/optional/required → CLOSING.** Their nested struct VALUES close recursively
  (oracle #1/#2/#3). The CLOSING walker already returns a `defOpenViaTail` struct UNCHANGED
  (`Normalize.lean:25-26`), so a nested `...` struct stays OPEN (control #4) — depth-recursion
  respects nested `...` for free.

Prefer a separate function (a closing twin) over a `closing : Bool` param — the repo's
illegal-states philosophy: the call site's intent (closing vs spine) is encoded in WHICH
function it calls, not in a flag a future edit can mis-thread. The spine walker keeps the
existing shared field walker; only the closing path forks.

This is a **Normalize-only change** (no meet-time propagation needed): once the def's nested
field values carry `defClosed`, the existing `mergeStructN`/`applyStructClosedness` enforces
it at every meet, AND preserves it through instantiation (monotone). No `Lattice`/`Eval` edit.

### Entanglement — SC-2a and SC-2b are ONE fix, not two slices

Because Kue stores closedness on the value and meet is monotone (no re-open code exists —
verified: there is NO instantiation-shed path in `Lattice`/`Eval`; `openStructValue` at
`Eval.lean:1527` is the embedding-UNION path, orthogonal), closing the nested field value
(SC-2a) AUTOMATICALLY makes `(#D & {}).r` retain `defClosed` → reject `b` (SC-2b). There is
no separate code for SC-2b. Sequencing:

- **Before the fix:** Kue under-closes everywhere → admits `b` on BOTH #6 and #7 (matches
  cue on #7 by accident, DIVERGES from cue on #6).
- **After the fix:** Kue closes nested values → rejects `b` on BOTH → matches cue on #6
  (SC-2a, cue-agrees), DIVERGES from cue on #7 (SC-2b, the spec-correct divergence).

So SC-2b is not separable work — it is the same code change. Achieving cue's #7 admit would
require ADDING a shed-on-`&` artifact (the OLD B6-deferred plan: a "closed on this selection
path" flag the meet clears) — which is spec-WRONG and re-introduces partiality. Do NOT do it.
The fix's only SC-2b-specific deliverables are docs+fixture (below).

### Soundness + the trap argument (gate)

Closedness is the most regression-prone class (links 3/4/5, SC-1c). The three obligations:

1. **A referenced closed def's nested field rejects extras** — oracle #1/#2/#3/#6; the lever
   sets `defClosed` on the nested value; `mergeStructN` rejects. ✓
2. **A plain (non-def) nested struct stays open** — oracle #5; the CLOSING walker runs ONLY
   inside a referenced `#Def` body, never on a plain `A:{a:{b}}` (plain structs go through the
   SPINE walker / no normalization-close at all). The lever cannot touch control #5. ✓
3. **An unreferenced import binding stays lazy** — oracle/control: the `importBinding` arm is
   UNCHANGED (skip). The closing twin only forks the regular arm. cert-manager/argocd cannot
   re-bottom. ✓ (re-verify READ-ONLY on prod9 before landing — exit 0, no key/value drift.)

**Gate:** byte-identical on ALL existing fixtures EXCEPT `b6_instantiated_def_field_reopens`
(the one SC-2b fixture, intentionally flipped — see below) + cert-manager/argocd no-regress
(read-only prod9) + new spec-correct SC-2a fixtures (cue+spec agree) + the flipped SC-2b
fixture (Kue-diverges, recorded). If control #5 (`b6_plain_struct_under_regular_open`) or the
import sentinels drift, the lever over-closed → STOP-and-report. The existing
`b6_depth2_nested_def_closes` (closes a nested `#Inner`) must stay green — the spine already
closes nested defs; the lever ADDS nested plain-struct closing on top, orthogonal.

### Fixture impact (precise)

- **Keep green (controls):** `b6_plain_struct_under_regular_open` (#5 — plain stays OPEN),
  `b6_depth2_nested_def_closes` (#3-shape via `#Inner`), `b6a1_infile_hidden_def_*`,
  `nested_def_*_under_regular_field`, all import/module fixtures, SC-1/1c/1d fixtures.
- **NEW (SC-2a, cue+spec agree):** `definitions/sc2a_nested_def_field_closes`
  (`#A:{a:{b:int}}` / `out: #A & {a:{b:1,extra:5}}` ⇒ `out.a.extra: _|_`),
  `…/sc2a_nested_def_field_closes_concrete` (#2, fully concrete),
  `…/sc2a_nested_def_field_depth2` (#3), `…/sc2a_nested_def_field_tail_stays_open` (#4
  regression guard), `…/sc2a_direct_selector_closes` (#6, `#D.r & {b}` rejects). Each with a
  `FixturePorts` entry. Add `native_decide` pins: nested closes, plain-control admits, `...`
  nested admits, hidden-control admits.
- **FLIP (SC-2b divergence):** `b6_instantiated_def_field_reopens.expected` currently records
  cue's re-open (`out: {x:1, extra:2}`). After the fix Kue REJECTS — rewrite the `.expected`
  to `out: {x:1, extra: _|_}` (the spec-correct value) and RENAME to
  `sc2b_instantiated_def_field_stays_closed` so the name no longer asserts the artifact.
  Record the cue-divergence entry (below). This is the ONE intentional drift in the gate.

### `cue-divergences.md` entry (SC-2b)

| Topic | `cue` ver | Claim / input | `cue` output | Kue output | Why Kue is right | Fixture |
|-------|-----------|---------------|--------------|------------|------------------|---------|
| nested closedness shed on instantiation | v0.16.1 | `#D:{r:{x:int}}` ; `(#D & {}).r & {x:1,extra:2}` | `{x:1, extra:2}` — `extra` ADMITTED (re-opened) | `{x:1, extra: _|_}` — `extra` REJECTED | Spec: referencing a def recursively closes it "anywhere within the definition"; closedness is MONOTONE through meet (`&` cannot remove a constraint). cue is internally inconsistent — the direct path `#D.r & {x,extra}` REJECTS `extra` (cue+Kue agree), but inserting a no-op `& {}` instantiation re-opens it. The `& {}` cannot lattice-logically add openness (meeting with the top struct is identity on closedness), so cue's re-open is an eval-strategy artifact. Kue preserves closedness on both paths. | `definitions/sc2b_instantiated_def_field_stays_closed` |

### Slice plan (1 slice; NO worktree)

**One slice, not two.** SC-2a and SC-2b are the same Normalize-only code change (entanglement
above); splitting them is impossible without adding the spec-wrong shed-on-`&` artifact. The
slice lands SC-2a's correctness AND SC-2b's divergence together, gated as one. No worktree —
it is a single-file change (`Normalize.lean`: add the closing field-walker twin, point the
CLOSING walker's `.struct` arms at it) plus fixtures/divergence-doc. Estimate: contained, ~1
slice. Internal checkpoint commit after the code is green (before the fixture/doc churn) per
checkpoint discipline. Real-app re-probe (cert-manager + argocd, read-only) is part of the
gate, not a follow-up.

**Caveat (pattern-bearing def arm):** the CLOSING walker's pattern-bearing `.struct` arm
(`Normalize.lean:35-41`) also maps `normalizeFieldWithFuel` over its fields — point it at the
closing twin too, so a closed pattern def's nested plain-struct field values close as well
(`#A:{a:{b:int},[=~"^x"]:int}`). Probe this against cue in the slice; if cue treats the
pattern-def's nested field differently, narrow the twin to the no-pattern arm only. The
`defOpenViaTail` arm (line 25-26) is untouched (already returns unchanged → SC-1d intact).
