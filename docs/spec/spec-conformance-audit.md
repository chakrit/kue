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

| Area                       | Auditor | Status     | Findings (V/CUE-BUG/SUSPECT)                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------- | ------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A. Disjunctions/narrowing  | batch 1 | DONE       | 1 KUE-VIOLATES (disj display); **Gap-2b/Bug2-3 FIXED 2026-06-19** (cue correct; structural list-vs-struct arm prune); 2 spec gaps; rest CONFORMS                                                                                                                                                                                                                                                                                   |
| B. Closedness/definitions  | batch 1 | DONE       | SC-1/1c/1d + SC-2 FIXED 2026-06-19; **SC-1b FIXED 2026-06-21** via `closedClauses` provenance; **SC-1e (closed×open-`...`) FIXED 2026-06-21** (`closeTailResult`, monotonicity) + **EMBED-CLOSE-1 PINNED**; **import-eager-closedness FIXED 2026-06-22** (`selectedFieldValue` closes a SELECTED def body — eager + force share one closing decision; was a silent-admit on the eager selector path) → closedness family FULLY CLOSED; unreferenced-import LAZINESS remains a deliberate ratified gap                                                                                          |
| C. Structs/lists           | batch 1 | DONE       | pattern-meet closedness FIXED (SC-1b, 2026-06-21); field order RATIFIED as a spec gap (Kue keeps source order); rest CONFORMS                                                                                                                                                                                                                                                                                                      |
| D. Comprehensions/scoping  | batch 2 | **CLOSED** | guard catch-all DRAINED (**D#1a/D#1b/D#1c all FIXED**: bottom→propagate, incomplete→defer, concrete-non-bool→type-error; 2026-06-20); structural cycles **D#2 COMPLETE 2026-06-20** (D#2a detection + D#2b terminating-disjunct); **`let`-clauses D#3 FIXED 2026-06-20** (parse + `Clause.letClause` + `let` = +1 frame; the LAST open D-item); frame-model + read-splice CONFORM — **D-area now fully closed**                    |
| E. Scalars/bounds/builtins | batch 2 | DONE       | regex→RE2 COMPLETE (RX-1 trilogy + RX-2a/b/c all FIXED — corpus divergence-free 2026-06-20); **BI-2 math.Pow exact + list.Sort/SortStable FIXED 2026-06-20**, **BI-1 Unicode case-fold FIXED 2026-06-20** (oracle-generated BMP table); E#4 arithmetic-operator domain FIXED 2026-06-20; numeric/bounds/division/decimal core CONFORMS. **BI-2 family COMPLETE 2026-06-21**: math.Sqrt + math.Pow(·,½) (EXACT DECIMAL `decimalSqrt` — fixed-iteration integer-Newton, total; self-consistent `Sqrt=Pow(·,½)`), **+ BI-2-§3 (`cd2f0a9`): neg-int `x^-n=1/x^n` (exact rational) + general non-½ fractional `x^y=exp(y·ln x)` via `decimalExpScaled`/`decimalLnScaled` (fixed 40/60-term Taylor + binary range reduction, total, axiom-clean; mantissa byte-identical to cue apd)**. Full real domain, Float correctly AVOIDED; domain edges (`Pow(neg,non-int)`/`Pow(0,0)`/`Pow(0,neg)`) bottom not `NaN`/`Infinity` — divergences recorded. Nothing open. |
| F. Manifest/modules        | batch 2 | DONE       | 3 KUE-VIOLATES (`regexp` import missing — **F-1 FIXED 2026-06-19**; self `@vN` not stripped — **F-2 FIXED 2026-06-19**; qualified `path:id` unparsed — **F-3 FIXED 2026-06-20**); export + module-resolution core CONFORM                                                                                                                                                                                                          |

## Audit history (archived — full detail in implementation-log.md + git)

Completed findings and shipped design specs, compressed to pointers. Each cites the
landing commit; the as-built detail lives in `docs/reference/implementation-log.md` and
git history.

- 2026-06-20 — **D#3** `let` clauses in comprehensions — the LAST open D-area item, now
  CLOSED. `Clause.letClause (name, value)` added to the comprehension clause sum
  (`Value.lean`, total, no catch-all); `descendClauses` `.letClause` arm routes the value
  through `onSource` + pushes +1, so `clauseChainDepth` + all 4 walkers handle it for
  free. Frame model: `let` = +1 (spec: *"`for` and `let` clauses each define a new
  scope"*; `if` = +0). Parse: `parseLetClause` (`dropWord?`-bounded), wired into
  `parseClause` after `for` /`if`; reached only inside a clause chain, so a
  struct-field-head `let` stays a struct-body binding (spec `StartClause` excludes `let`).
  Eval: bind the EVALUATED value into a one-slot frame like a `for` element (`loopFrame
  none.top name`), alignment-correct; an unreferenced binding's bottom sits unread
  (matches cue for value-level bottoms). All 8 clause-match sites updated explicitly. 9
  `native_decide` pins (incl. the `for` -after-`let` frame-accounting + shadowing cases) +
  6 fixtures (list + struct forms); cert-manager content-identical. 1 cue-divergence
  (unreferenced unresolved-ref `let` — cue errors, Kue tolerates) + 1 spec-gap
  (eval-order/eager-into-frame). See implementation-log 2026-06-20.
- 2026-06-20 — **D#1b + D#1c** comprehension-guard classification (`Eval.lean`: new total
  `classifyGuard` over a `GuardVerdict` sum, enumerating every `Value` — no catch-all —
  read by both clause-walkers; `Value.lean`: `NonBoolGuardType` +
  `BottomReason.nonBoolGuard`). D#1c concrete-non-bool→type-error (CONFORMS); D#1b
  incomplete→defer (keeps the comprehension residual via the new `ClauseExpansion`
  /`ListClauseExpansion` `deferred` outcome + `withDeferredComprehensions` re-wrap;
  spec-gap + display divergence recorded). The residual presence-test shape `X !=/== _|_`
  is carved out (stays a drop). Guard catch-all fully drained (D#1a/b/c all DONE). 17
  `native_decide` pins + 4 fixtures; 3 bug-replicating drop-pins corrected to the held
  form; cert-manager content-identical. See implementation-log 2026-06-20.
- 2026-06-20 — **RX-2a** in-class negated shorthand classes (`Regex.lean`
  `parseClassEscape` 's `\D` /`\W`/`\S` `.error` arms → `complementRanges` folds; new
  total `Regex.complementRanges` + `maxCodePoint` over the `[0, U+10FFFF]` `Char` domain).
  The lone regex-corpus divergence; CONFORMS (RE2-mandated, cue-agreeing). Representation:
  NO new AST state — `cls ranges negated` already precise, the complement is a range union
  that composes through the ordinary union and is flipped by the whole-class `negated`
  flag for `[^…]`. 26 `native_decide` pins + the `numeric/regex_in_class_negated` `=~`
  /`!~` fixture. The regex corpus is now divergence-free (RX-1 trilogy + RX-2a/b/c all
  DONE).
- 2026-06-20 — **D#2b** terminating-disjunct (`Eval.lean` `normalizeEvaluatedDisj` now
  applies `liveAlternatives` on the has-default branch). Completes D#2: `#List | *null`
  terminates on `*null` (`tail: null`, cue-byte-identical). Re-diagnosis: VALUE resolution
  was already correct after D#2a (`export` via `resolveDisjDefault?`); the A#6 fuel cap
  was never implicated (detection at depth ~2 ⇒ shallow bottom); the gap was the EVAL
  value path emitting defaulted disjunctions raw (SC-3 root). The fix prunes the
  `.structuralCycle` arm WITHOUT collapsing the default into the value (collapse is
  unsound — `b: a & 2` needs the live non-default arm; cue's display-collapse is a
  projection). Folds in SC-3 dedup (`*1|*1|2` → `*1 | 2`). Eval-display divergence
  recorded (Kue shows `{…} | *null`, cue collapses — same convention as
  `default_disjunction`). 8 pins + 3 `export/` fixtures; cert-manager content-identical.
- 2026-06-20 — **D#2a** structural-cycle DETECTION (`Value.lean`
  `BottomReason.structuralCycle`; `Eval.lean` `structStack` /`isStructLikeBody` + `.refId`
  re-eval cycle bracket). The DESIGNED force-stack lever was wrong as built (the force
  triple never repeats — fresh frame ids); redesigned to a struct-body re-entrancy stack
  on the `.refId` path, keyed on the body `Value`. Detects def + regular + mutual struct
  cycles (class-agnostic), preserves `x: x` → `_`, no false-positive on finite-deep or
  list-tail recursion; cert-manager content-identical (zero false-fire). Value verdict
  CONFORMS to cue; eval-display differs (spec-gap recorded). 8 `native_decide` pins + 2
  `refs/` fixtures.
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

### Genuinely-open ranked backlog (current — 2026-06-21)

Ranking principle (slice-loop, reaffirmed): **spec-correctness and clean design
evolution** — contained-soundness before larger features; cue-AGREEING correctness before
divergence; designed levers before undesigned. Real-app compilation (argocd, cert-manager)
is a STRESS TEST, not a ranking driver: a blocker needing app-specific narrowing is PARKED
(Bug2-5), never promoted to the critical path.

**Everything spec-conformance-HIGH is DONE.** The large designed levers all landed —
Bug2-3/Gap-2b, D#2 (structural cycles, complete), the regex trilogy + RX-2a/b/c (corpus
divergence-free), BI-1 (Unicode case-fold), BI-2 (math.Pow exact + list.Sort/SortStable),
F-1/F-2/F-3, E#4-fix (arithmetic domain), the D-area (D#1a-d, D#2, D#3 — CLOSED), the
dyn-field correctness family (A-EN3-DYN, DYN-DEF-1, D#1d, default-label), the MEET-RESID-1
ripple family (MEET-RESID-1, RESID-MASK-1, A#6, RESID-MASK-2), and the closedness family
(SC-1/1b/1c/1d/1e + SC-2, EMBED-CLOSE-1 pinned). The 4 spec-gap ratifications are DONE (3
RATIFIED + test-pinned; gap-4/E#4 escalated → the E#4-fix slice). Detail for every one of
these is in Audit history (below) + the implementation-log + git.

**The open backlog is now small (AD2-1 + SC-3 resolved 2026-06-21):**

1. **AD2-1 — RESOLVED (2026-06-21, UNIFIED).** The lone-default lattice-marker was proven
   NON-load-bearing (vacuous: value-identical to the bare value in every onward meet, since
   `combineMark` is AND + `withDefaultConvention` only synthesizes defaults for an
   all-regular operand). `normalizeDisj`'s lone-arm collapse is now mark-agnostic, unifying
   the two normalizers' lone-arm rule; named pins renamed to the corrected behavior +
   adversarial non-load-bearing witnesses added; the change moves Kue's display TOWARD cue
   (which also collapses a lone `*v` → `v`). NOT user-gated after all — the gate was
   over-caution about a pin rename, not a real soundness fork. Detail: `plan.md`
   walker-dedup section (AD2-1 entry).
2. **SC-3 — narrowed to MULTI-arm defaults only (no longer open work).** The lone-default
   half collapsed under AD2-1 (now matches cue). What remains is purely cue's further
   display-collapse of a MULTI-arm default to its selected default, which Kue deliberately
   does NOT do (unsound — loses the live non-default arm a later meet needs). Recorded as a
   spec-gap (`cue-spec-gaps.md` D#2b/SC-3 row, scope note added). Not a gate, not a slice.
3. **BI-2 family** (MED — `math.Sqrt` + full-domain `math.Pow`). **COMPLETE 2026-06-21.** The
   "USER-GATED / needs a Float/NaN/Infinity model" framing was WRONG and is dropped: Float was
   correctly AVOIDED throughout. Kue is exact-rational, so the whole real domain is computed in
   EXACT DECIMAL. **BI-2-residual** (`cd…`/`0091aba`): `Sqrt`/`Pow(·,½)` via `decimalSqrt`
   (fixed-iteration integer-Newton, total), matching cue's OWN apd `Pow(2,½)` and making
   `Sqrt(x) = Pow(x, ½)` self-consistent. **BI-2-§3** (`cd2f0a9`): §1 negative-INTEGER exponent
   `x^(-n)=1/x^n` (exact rational); §2 general non-½ fractional `x^y = exp(y·ln x)` via
   `decimalExpScaled`/`decimalLnScaled` (fixed 40/60-term Taylor + binary range reduction,
   working scale 50, structurally total, axiom-clean). Mantissa byte-identical to cue's apd
   across 40 random + extreme cases; integral results collapse. Domain errors (`Sqrt(neg)`,
   `Pow(neg, non-int)`, `Pow(0,0)`, `Pow(0,neg)`) BOTTOM, never `NaN`/`Infinity`. The family is
   now fully closed — nothing open. See the BI-2-§3 SHIPPED block below.
4. **EvalOps extraction** (mechanical, AUTONOMOUS but NOT urgent — `plan.md` item 2). ~256
   lines of pure scalar algebra carved to `Kue/EvalOps.lean`; `Eval.lean` is under the
   re-split threshold, so hygiene not pressure. The one remaining autonomous slice.
5. **SC-4** (LOW, spec-gap-first — nested hidden/let-bound closedness on direct def-meet).
   Spec-check first; do not reflexively match cue (it is internally inconsistent here).
   See the SC-4 entry below.

**PARKED (off the critical path):** **Bug2-9** (the NEXT argocd residual — use-site narrowing of a
REFERENCED multi-conjunct def whose conjuncts include the cert-manager mixin; surfaced after Bug2-8
landed) — see Live-slice detail. **Bug2-8 RESOLVED** (2026-06-23): same-def multi-decl close-once
ACROSS AN EMBED boundary via a `DeclProvenance` sum threaded on a named `ConjOperand` — see Live-slice
detail. **Bug2-7 RESOLVED** (`3361699`, 2026-06-23): def multi-decl close-once on
the reference / force-fold path via per-operand `canonicalizeFields` in `mergeConjOperands` —
see Live-slice detail. **Bug2-6 RESOLVED** (`ef824cb`, 2026-06-23): definition
multi-declaration close-once via `mergeDefinitionDecls` — see Live-slice detail.
**Bug2-5 RESOLVED** (`5fca57e`, 2026-06-22): the transitive-embed disj-path
narrowing-injection mechanism is fixed; it was NOT the final argocd blocker. Plus the LOW
cosmetic/latent corners tracked in `plan.md` item 6.

Audit cadence + the non-spec-conformance plan roadmap live in `plan.md` / the breadcrumb,
not here.

### Live-slice detail (folded from prior re-ranks; DONE entries dropped to Audit history)

**Bug2-5 — RESOLVED (`5fca57e`, 2026-06-22). The mechanism was real but NOT the final
argocd blocker.** The diagnosed shape: `defaults.#ListenerSet = defs.#ListenerSet &
parts.#UseCertManager & {…}` — `defs.#ListenerSet` declares `kind: "ListenerSet"` and
CO-EMBEDS `#UseCertManager` (→ `#Mixin`, body `listShape | structShape | error`). The
Mixin's `_patch.kind` must be narrowed by the sibling def's `kind`. **The actual break (one
level deeper than the original sketch):** `kind` is declared on the OUTER def and `#Mixin`
is embedded TRANSITIVELY (`#ListenerSet` → `#UseCertManager` → `#Mixin`). The host's
`spliceOperandForEmbed` into the MIDDLE def (`#UseCertManager`) dropped `kind` because
`embedBodyEmbedsDisj` is a ONE-level check and the middle def neither reads `kind` nor
DIRECTLY embeds a disjunction (the disjunction is one more level down). So the Gap-2b
"splice ALL regular fields" gate never fired and `kind` never reached the disjunction-arm
path. **Fix:** `embedBodyEmbedsDisjDeep` follows the embed chain (via `resolveEmbedDefBody?`,
mirroring `bodyNeedsDefer`'s transitive recursion) so a transitively-embedded disjunction
triggers the same sound Gap-2b splice. NOT the `.disj`-distribution-injection the sketch
predicted — the narrowing already flows correctly ONCE `kind` reaches the splice; the bug
was purely the GATE missing the transitive disjunction. Self-contained repro
`testdata/export/bug25_disj_arm_let_local_narrowing.{cue,json,args}` (cue emits `meta:"yes"`,
pre-fix kue dropped it; now identical). 8 `native_decide` pins (`TwoPassTests` Bug2-5
section). cert-manager content-identical.

**Bug2-6 — RESOLVED (`ef824cb`, 2026-06-23). Definition multi-declaration close-once via
`mergeDefinitionDecls`.** Two SEPARATE declarations of one definition path (`#Foo: {a:1}` +
`#Foo: {c:3}`) now UNIFY their field-sets and close ONCE over the union (cue v0.16.1:
`{a:1,c:3}`) — the standard union-not-intersect CUE definition-merge rule. Kue formerly
`.conj`-ed two SEPARATELY-closed bodies, so the meet mutually rejected → `{a:_|_, c:_|_}`.

**Mechanism (provenance carrier — illegal-states-unrepresentable):** the carrier is
STRUCTURAL, not a flag. `canonicalizeFields` (the one seam that knows two bodies are
repeated decls of the SAME def-path label — `Eval.lean`, via the new
`mergeUnevaluatedFieldInto`) routes a merged DEFINITION-class slot through
`mergeDefinitionDecls` — which UNIONS the two decl bodies into ONE def body (union fields via
`mergeFieldListWith joinUnevaluated` so a shared label's values still `.conj`-meet; union
patterns; `unionDefOpenness` with OPEN dominating) so the eval close closes it ONCE via the
EXISTING single-`closedClauses`-clause path (`mkStruct` defaults the union clause). Non-def
duplicate labels keep the deferred `.conj` (`joinUnevaluated`), which `meet`s lazily. The
same-decl-vs-use-site distinction is a merged-body vs a `.conj`, never a `Bool` on `.conj`.

**Soundness preserved (the guards stay green):** `#A & #B` (distinct closed defs) STILL
rejects — the use-site `meet` CONCATENATES `closedClauses` (conjunction → reject extras) and
NEVER routes through `mergeDefinitionDecls`; the two paths are disjoint in code.
`mergeConjFields` (the conj-of-EMBEDS path) deliberately keeps plain `joinUnevaluated`: a
host's `#data` meeting an embedded mixin's `#data` is a genuine cross-conjunct meet that must
`.conj` (unioning there wrongly re-opened a closed pattern def, `#data: [string]: string`
gaining a stray `...`). 13 pins (TwoPassTests Bug2-6): target close-once + 3-decl + nested;
close-once rejects use-site extra, admits a union field; same-def CONFLICT still bottoms;
one-decl open-via-`...` opens the union; 4 distinct-closed-def soundness guards. 3 fixture
pairs + FixturePorts. All oracle-confirmed vs cue v0.16.1. Axiom-clean (propext only), total.
cert-manager content-identical (jq-normalized diff empty; field-order #3 only).

**argocd status: STILL bottoms (~61s) — Bug2-6 was NOT the final blocker.** `kue export
apps/argocd.cue` localized to `route.yaml`/`listener.yaml` (the
`defaults.#ListenerSet = defs.#ListenerSet & parts.#UseCertManager & {…}` composition, whose
`#UseCertManager` declares `#additions` THREE times). It now hits **Bug2-7** (below).

**Bug2-7 — RESOLVED (`3361699`, 2026-06-23). Def multi-decl close-once on the reference /
force-fold path via per-operand `canonicalizeFields`.** Bug2-6's close-once was correct on
DIRECT selection but LOST when the merged def lives inside a DEFINITION wrapper
selected/referenced through a sibling (`#Use: {#additions:…; #additions:…; vis: #additions}`
then `#Use.vis`): the wrapper defers to a `.closure`, and the force-fold reconstruction
(`forceClosureWithConjunctCore`'s three struct arms) rebuilds the body via `mergeConjOperands`,
which ran `mergeConjFields` (plain `.conj`) over each operand's fields BEFORE the downstream
`canonicalizeFields` could union them — so the two `#additions` decls were `.conj`-collapsed and
re-closed SEPARATELY → `{cert_gw:_|_, cert_ing:_|_}` (cue: `{cert_gw:{}, cert_ing:{}}`).

**Mechanism (within-operand vs cross-operand — the soundness boundary):** `mergeConjOperands`
now `canonicalizeFields`-es each operand's OWN fields up-front (`operands.map (canonicalizeFields
op.fst, op.snd)`), so two repeated DEFINITION-class decls of one path declared WITHIN a single
struct body (one operand) UNION via `mergeDefinitionDecls` (the Bug2-6 close-once lever, reused
unchanged). The CROSS-operand merge (`mergeConjFields`, plain `.conj`) is UNTOUCHED, so a host's
`#data` meeting an EMBED's `#data` (DISTINCT operands) still `.conj`-MEETs — never unions. The
within-operand-vs-cross-operand split IS the disjointness: the union fires only for decls inside
one operand; a genuine cross-conjunct meet is never reached by the canonicalize. Per-operand
canonicalization preserves first-occurrence layout for every slot at-or-before a collapsed
duplicate (the `vis` ref `refId ⟨0,0⟩` still lands on the merged `#additions` slot 0), so the
`mergedMap` (rebuilt from the canonicalized operands) + rebased refs stay coherent — exactly the
direct-eval `.struct` arm's treatment, now applied per-operand on the force path too.
Axiom-clean (propext/Quot.sound), total.

**Soundness guards stay green (pinned via a reference):** `#A & #B` (distinct closed defs,
distinct operands) still rejects; same-def CONFLICT on a shared label still bottoms; close-once
still rejects a use-site extra. cert-manager content-identical (jq -S diff = 0; raw diff = 15 =
ratified field-order #3 only — the closed `#data` pattern is NOT re-opened). 8 pins (TwoPassTests
Bug2-7): target close-once via ref (FLIPPED witness) + 3-decl argocd shape + ref-and-direct-both
+ nested ref + def-ref-after-meet; 3 soundness guards. 3 fixture pairs (`bug27_*`) + FixturePorts.

**argocd status: STILL bottoms (~58s) — Bug2-7 was NOT the final blocker.** It now hits
**Bug2-8** (below): `#UseCertManager` EMBEDS `#Mixin` and adds its OWN `#additions` decls, so the
`#additions` decls span the embed boundary (cross-operand) yet must still union.

**Bug2-8 — RESOLVED (2026-06-23). Same-def multi-decl close-once ACROSS AN EMBED boundary via a
`DeclProvenance` sum on a named `ConjOperand`.** When a def declares `#m` once and EMBEDS another
def that also declares `#m` (`#A: {#m:{a}}` then `#Use: {#A; #m:{c}; vis:#m}`), the two `#m` decls
are repeated declarations of the ONE def path `#m` spanning the embed — cue close-once-UNIONS them
(`{a:1, c:3}`). kue formerly `.conj`-met them across the embed → each clause re-closed separately →
mutual reject → bottom (and the `-e out` projection dropped `a`).

**Mechanism (provenance carried in the TYPE, not a Bool — illegal-states-unrepresentable).** New
`inductive DeclProvenance := ownDecl | embeddedDecl` (`Value.lean`) on a named `structure
ConjOperand (fields, open_, provenance)` replacing the old `(List Field × Bool)` operand tuple that
`mergeConjOperands` threads. A SUM, not a Bool: the discriminator is not "did this come from an
embed" but "do two same-label decls name the ONE def path" — `ownDecl × embeddedDecl` is exactly
that pair, and only it close-once-UNIONs; a Bool admits the nonsense "own-and-embedded" and says
nothing about which path. Two threading points:
- **Static fold (eager + force `.structComp` arms).** A PLAIN embedding's same-def-path decls
  (`embedSameDefPathDecls`, resolving each embed body via `resolveEmbedDefBody?`, gated to labels
  the host ALSO declares as DEFINITIONS) are folded into the static frame as an `embeddedDecl`
  operand BEFORE static eval. `mergeConjOperands`'s provenance-aware cross-operand merge
  (`mergeConjOperandFields`) then close-once-UNIONS the host `ownDecl #m` × embed `embeddedDecl #m`
  pair via `mergeDefinitionDecls` (the Bug2-6 lever) — so the `#m` SLOT holds the union AND a
  sibling `vis: #m` (evaluated on the static frame) resolves against it (fixes the `-e out` drop).
- **Embed meet-fold (`meetEmbeddingsWithFuel`).** Since the static fold already unioned `#m` into
  the host, the meet-fold STRIPS the embed's matching same-def-path `#m` (`meetEmbedUnioningDefDecls`)
  so the generic `meet` does not re-meet the union against the embed's narrower arm (which would
  re-close-REJECT the host's other labels, or double an equal shared field to `1 & 1`).

**Soundness boundary (the discriminator that keeps the canary a MEET).** The union fires ONLY for a
same-label DEFINITION-class decl pair of differing provenance whose BOTH values are field/pattern-
bearing STRUCTS (`isUnionableDefValue` — a scalar/kind def value `#x: string` stays a meet, else its
`.conj` doubles the display). A deferral/disjunction-bearing embed (`bodyNeedsDefer` /
`embedBodyEmbedsDisjDeep`) is EXCLUDED from the static fold — it keeps its existing narrowing
machinery (Bug2-4/2-5 splice, disj distribution). The cert-manager `data: [string]: string` is a
REGULAR field, so it never enters the DEFINITION decl-union and stays a closed-pattern MEET. A
DEFINITION pattern field (`#data: [string]:string`) DOES union — but `mergeDefinitionDecls` unions
patterns alongside fields, so an int host field still bottoms against `string` (pattern preserved).

**Guards green (all pinned + oracle-confirmed vs cue v0.16.1).** Witness close-once-unions (whole-file
AND `-e out` both `{a:1,c:3}`); 3-decl host+two-embeds; two-mixin same path; DEFINITION pattern
across embed admits string + rejects int; same-def CONFLICT across embed still bottoms; two DISTINCT
closed defs `#A.#m & #B.#m` still reject; the cert-manager REGULAR closed-pattern canary stays a MEET
(`{extra:"x"}`). 8 `native_decide` pins (TwoPassTests Bug2-8) + 3 fixture pairs (`bug28_*`) +
FixturePorts. cert-manager FULL export content-identical (jq -S diff = 0; raw diff = 15 = ratified
field-order #3 only — the closed pattern is NOT re-opened). Axiom-clean (`propext`/`Quot.sound`/
`Classical.choice`), total. The 599 `disj_default_embed_sibling_narrows` near-regression (a scalar
`#x: string` def value double-displaying as `string & string`) was fixed by the `isUnionableDefValue`
struct-value gate.

**argocd status: STILL bottoms (~55s) — Bug2-8 was NOT the final blocker.** It now hits **Bug2-9**
(below). The Bug2-8 union mechanism itself handles the cert-manager `#additions` shape correctly
(a comprehension over the pattern+field-unioned `#additions` across the embed matches cue).

**Bug2-9 (HIGH — the NEXT residual argocd export blocker; PARKED, distinct mechanism).** Use-site
narrowing of a REFERENCED multi-conjunct def whose conjuncts include the cert-manager mixin. The
argocd `ls = defaults.#ListenerSet & {#name, #ns, #passthrough_hosts}` where `defaults.#ListenerSet`
is itself a def equal to `defs.#ListenerSet & parts.#UseCertManager & {#gateway_name, …}` (a 3-way
def-meet, the second conjunct being the `#UseCertManager` → `#Mixin` mixin). **Minimal repro (in the
prod9 module):** `defaults.#ListenerSet & {#name:"argocd-ls", #ns:"argocd", #passthrough_hosts:[…]}`
→ cue: full ListenerSet manifest with the cert-manager annotation; kue: bottoms. **Localized:** the
INLINED 3-way meet with all use fields supplied directly (`defs.#ListenerSet & parts.#UseCertManager
& {all #fields}`) WORKS in kue — the bottom is specific to REFERENCING `defaults.#ListenerSet` (a
NAMED multi-conjunct def) and narrowing it at the use site, where `#name`/`#ns` must flow through the
multi-conjunct def to the mixin's `_patch`/`#additions` machinery. Distinct from Bug2-8 (decl-union):
this is narrowing-through-a-referenced-multi-conjunct-def. ~11s to repro in isolation (`defaults.
#ListenerSet & {…}` via a probe in the apps package). PARKED for a dedicated slice; correctness-first.

**HIGH — soundness / real-app correctness (the LARGE designed levers):**

- **Bug2-3 / Gap-2b — DONE (2026-06-19, `d9f66ca`).** See Audit history.
- **D#2 — COMPLETE (2026-06-20).** Detection (D#2a) + terminating-disjunct (D#2b) both
  landed. `#L:{n,next:#L}` errors (cyclic re-entry bottoms with `.structuralCycle`);
  `#List | *null` terminates on `*null` (`tail: null`, byte-identical to cue). Detection =
  struct-body re-entrancy stack (`structStack`) on the `.refId` re-eval path (NOT the
  designed force-stack — see the SUPERSEDED banner below). Termination =
  `normalizeEvaluatedDisj` now applies `liveAlternatives` (prune-bottom/dedup) on the
  has-default branch, pruning the `.structuralCycle` arm WITHOUT collapsing the default
  into the value (unsound — see implementation-log). A#6 fuel cap was NOT implicated
  (detection at depth ~2 ⇒ shallow bottom). SC-3 dedup folded in. cert-manager
  content-identical (zero false-fire; prod9 has ZERO recursive defs). See Audit history +
  implementation-log 2026-06-20.

**BI-2-residual (MED — SPLIT; sqrt + Pow-½ DONE 2026-06-21, exp/ln increment filed).** The
prior framing ("needs a Float/NaN/Infinity model; no sub-domain carve-out-able") was WRONG
and is corrected here: **Float was never needed and is correctly avoided.** Kue is
exact-rational by design, so the sound move is to compute in EXACT DECIMAL and record the
divergence from cue's fallible float artifacts — not to import IEEE.

**SHIPPED (2026-06-21).** **(a) `math.Sqrt` + `Pow(·, ½)`** via `Decimal.sqrt`
(`decimalSqrt`): a FIXED-iteration integer-Newton square root (`isqrtNewton`/`isqrtNat` —
`x' = (x + N/x)/2` on `Nat`, budget `2·digits + 8`, min-tracked so it lands EXACTLY on
`⌊√N⌋`; structurally recursive on the budget, hence total — `#print axioms` shows no
`sorryAx`/`partial`). For `a = num/10^s`, `√a = ⌊√(num·10^(2P−s))⌋/10^P` with `P ≥ 40`;
perfect squares collapse to int (`Sqrt(144)=12`, `Sqrt(100)=10` — NOT cue's `1e+1`), exact
non-integer roots trim (`Sqrt(2.25)=1.5`), irrationals render to 34 sig digits via the
shared division renderer (`Sqrt(2)=1.414…209698`, BYTE-IDENTICAL to cue's OWN apd
`Pow(2,½)`). `math.Sqrt` and `math.Pow(·,½)` route through the SAME function, so
`Sqrt(x)=Pow(x,½)` (cue's float64 `Sqrt` ≠ apd `Pow` — cue is internally inconsistent; Kue
is more precise + self-consistent — recorded as a kue-more-correct divergence). Domain
errors BOTTOM: `Sqrt(neg)`, `Pow(neg,½)` (real-domain / complex), NEVER `NaN`. Files:
`Kue/Decimal.lean` (`isqrtNewton`/`isqrtNat`/`decimalSqrt`), `Kue/Builtin.lean`
(`decimalSqrtSigned`/`mathSqrt?`/`isHalfExponent`, `mathPow?` ½-route, `math.Sqrt` arm),
17 `BuiltinTests` pins, `builtins/math_sqrt` fixture (14 cases).

**SHIPPED — BI-2-§3 (2026-06-21, `cd2f0a9`).** The residual-of-the-residual is DONE; the
**BI-2 family is now COMPLETE** — `math.Pow`/`math.Sqrt` cover their full real domain in
EXACT DECIMAL, no Float, axiom-clean. **§1 negative-INTEGER exponent**: `x^(-n) = 1/x^n` via
`reciprocalDecimalToValue` over the existing exact int-pow + the division renderer — an
EXACT rational (`Pow(2,-3)=0.125`, `Pow(10,-2)=0.01`, `Pow(1,-5)=1` collapses,
`Pow(3,-1)=0.333…333` at 34 sig digits). **§2 general non-½ fractional exponent** (`x > 0`):
`x^y = exp(y·ln x)` via `decimalExpScaled`/`decimalLnScaled` in `Decimal.lean`.
`decimalLnScaled`: range-reduce `x = m·2^k`, `m ∈ [⅔,4/3)`, `ln x = k·ln2 + ln m`, `ln m =
2·artanh((m−1)/(m+1))` as a FIXED 40-odd-term series (`|t| ≤ ⅕` on the reduced range ⇒ tail
`< 10⁻⁵⁵`). `decimalExpScaled`: range-reduce `z = n·ln2 + r`, `|r| ≤ ln2/2`, `exp z =
2ⁿ·exp r`, `exp r = Σ rᵏ/k!` as a FIXED 60-term series (running factorial threaded). Working
scale 50 (16 guard digits past the 34-sig render context); every intermediate is a scaled
`Int` (`mulScaled`/`divScaled` truncate back), so all arithmetic is exact. Both series + both
binary range-reduction loops run a FIXED budget ⇒ structurally total, no `partial`/`sorry`
(`decimalExpScaled`/`decimalLnScaled` depend on ZERO axioms; the `Pow` path only on
`propext`/`Quot.sound`/`Classical.choice`). Results round to 34 sig digits and collapse to
`int` when integral (`Pow(4,1.5)=8`, `Pow(8,⅓)=2`); the MANTISSA is byte-identical to cue's
apd `Pow` across the corpus (40 random + extreme-magnitude cases verified, plus
`Pow(2,0.5)=Sqrt(2)` cross-check — the ½ case still routes through `decimalSqrt` for
exactness). **Domain edges → bottom**: `Pow(neg, non-integer)` (complex — cue errors),
`Pow(0,0)`, `Pow(0,neg)` (cue → `Infinity`); `Pow(0,positive)=0`. Divergences (display only,
value-identical, same family as Sqrt): cue pads terminating expansions to fixed width / uses
scientific notation; Kue trims + renders plain — recorded in `cue-divergences.md`. Files:
`Kue/Decimal.lean` (`lnExpScale`/`lnExpUnit`/`ln2Scaled`/`mulScaled`/`divScaled`/`lnArtanhSeries`
/`lnMantissa`/`lnRangeReduce{Up,Down}`/`decimalLnScaled`/`expTaylorSeries`/`applyPow2Scaled`
/`decimalExpScaled`/`intSigDigits`/`roundScaledToSigDigits`/`decimalPowGeneral`),
`Kue/Builtin.lean` (`reciprocalDecimalToValue`, rewired `mathPow?`), 13 `BuiltinTests` pins,
11 new `builtins/math_pow` fixture cases.

**SC-1b — DONE (2026-06-21).** Closed×closed-pattern intersection. The old
`closingPatterns : List Value` was a FLAT UNION across conjuncts — it could only express
"matches ANY stored predicate," so a meet of two closed structs admitted a field matching
EITHER conjunct's pattern. The correct closed allowed-set is the INTERSECTION: a field
survives iff EVERY closed conjunct admits it. A flat list of label-predicates cannot
represent this (you cannot intersect "matches `^x` " and "matches `^y` " into one regex).
**Fix: provenance-carrying representation** — replaced `closingPatterns` with
`closedClauses : List ClosedClause`, where each clause `{fieldLabels, patterns}` is ONE
closed conjunct's allowed-set; a field is admitted iff EVERY clause admits it
(`ignoresClosedness` escapes; empty clause list = open). A self-closed struct carries one
clause; a meet CONCATENATES clauses (conjunction). This is exactly the provenance the
closedness guide mandates ("which conjuncts introduced which patterns and closedness
constraints"). The original audit witness (same-pattern `^x`, disjoint *explicit* fields)
was MASKED — the disjoint required fields materialize and poison, so the union-store's
lossiness wasn't observable there. The REAL witnesses use DIFFERENT patterns:
`#A:{[=~"^x"]} & #B:{[=~"^y"]}` then `& {x1}` — `x1` matches `^x` not `^y`, must be
rejected (cue rejects; pre-fix Kue admitted). Field-side too (CRUX): a field-only closed
clause `#A:{a?}` must reject a later `x1` that matches `#B` 's `^x` (the merged `fields`
over-approximates each clause's field-set, so per-clause field-labels are needed). 17
pins: 12 source-level (`exportJson{Bottoms,Matches}` in `StructTests` `### SC-1b` —
disjoint/overlapping/narrower patterns, field-only-clause, broad-then-narrow, 3-way assoc,
nested, direct-meet, `close()` -idempotence, closed-empty) + 5 clause-logic units
(`fieldAllowedByClausesWith` = `all` /conjunction, in `LatticeTests`) + a fixture pair
(`definitions/sc1b_closed_pattern_intersection`). cert-manager export still semantically =
cue (def-meet hot path clean). All oracle-confirmed vs cue v0.16.1.

**SC-1e — DONE (2026-06-21).** Closed × OPEN-via-`...`: a CLOSED struct met with an
open-tail struct must STAY closed — the `...` does NOT re-open the closed conjunct
(closedness is monotone under meet). cue (CORRECT): `#A:{[=~"^x"]} & {b:1, ...}` rejects
`b`; `#C:{a} & {b, ...}` rejects `b`. Kue admitted all (PRE-EXISTING, confirmed on the
`f0613e5` baseline).

**Diagnosis was WIDER than the phase-B sketch.** The breadcrumb named only the
tail×patterns CATCH-ALL arm (`Lattice.lean:1009`), because the pattern-closed witness
routed there. Instrumenting found a FIELD-closed def (`#C:{a:int}`, no patterns) routes
through the `struct × structTail` arm (`none, [], some tail, []`) and ALSO dropped the
clause. **All four tail-bearing arms** hardcoded
`mkStruct … .defOpenViaTail (some tail) []`: arms 2, 3, and the catch-all are vulnerable
(a closed operand has no tail, so it sits on the plain side); arm 4 (tail×tail) is safe
(both operands open ⇒ `bothClauses = []`).

**Fix:** a single local `closeTailResult` in `mergeStructN` that all four tail arms route
through, branching on `closedOpenness.isOpen` (= `StructOpenness.meet`, which already
makes `defClosed` dominate `defOpenViaTail`). Open ⇒ keep the tail, `[]` clauses. Closed ⇒
collapse to a no-tail `defClosed` result carrying `bothClauses`, `applyBothClosedness`
over the merged fields (forbidden extras → `_|_`, exactly as the no-`...` control). The
`[] ↔ open` invariant holds. cert-manager byte-identical to the pre-fix baseline (pure
no-op there). 9 `native_decide` pins (`StructTests ### SC-1e` + `### EMBED-CLOSE-1`) + 4
fixture pairs, all oracle-confirmed.

**RX-2a — DONE (2026-06-20).** In-class `\D` /`\W`/`\S` set-complement folding. See Audit
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

9. **D#1b — DONE (2026-06-20).** Incomplete-guard deferral. A genuinely-abstract guard (a
   `.kind`, bound, unresolved disjunction, or non-presence comparison) now DEFERS — the
   comprehension stays a residual `.structComp` /`.comprehension`/`.listComprehension`
   node (cue eval-holds; `kue export` errors `incomplete value`), instead of dropping to
   `{}` /`[]`. Result protocol gained `ClauseExpansion` /`ListClauseExpansion`
   (`fields`/`bottom`/`deferred`); `withDeferredComprehensions` re-wraps. The residual
   PRESENCE test `X !=/== _|_` is CARVED OUT (stays a drop — cue eval drops it). Spec-gap
   recorded (defer mechanism); display divergence recorded (Kue renders the held ref as
   `@d.i`). See Audit history + implementation-log 2026-06-20.
10. **D#1c — DONE (2026-06-20).** Concrete non-bool guard → TYPE ERROR. A fully-concrete
    present value of non-`bool` type (`if "x"`/`if 3`/`if {…}`/`if [..]`/`if null`) is now
    a `.bottomWith [.nonBoolGuard ty]` that propagates (cue: `cannot use … as type bool`),
    NOT a `{}` drop. New `BottomReason.nonBoolGuard` + precise `NonBoolGuardType` (`scalar
    Kind`/`struct`/`list`). CONFORMS (cue+Kue agree, both modes). Split from D#1b in the
    SAME `classifyGuard` enumeration (no catch-all). See Audit history +
    implementation-log 2026-06-20.
11. **D#3 — DONE (2026-06-20).** `let` clauses in comprehensions. `Clause.letClause`
    added; `descendClauses` `.letClause` arm wires `let` = +1 (via `onSource` + frame
    push), so all 5 frame-walkers + `clauseChainDepth` handle it. Parse (`parseLetClause`,
    clause-chain-only so a field-head `let` stays a struct-body binding — spec
    `StartClause` excludes `let`); eval binds the evaluated value into a `for`
    -element-style frame (alignment-correct). The for=+1/if=+0 model is spec-CORRECT
    (B7-vindicated); `let` joined as +1. 9 pins + 6 fixtures; cert-manager
    content-identical. The D-area is now CLOSED. See Audit history + implementation-log
    2026-06-20.
12. **SC-3 — flatten/dedup half DONE (2026-06-20, folded into D#2b); display-collapse
    residual is LOW/spec-gap.** `normalizeEvaluatedDisj` now applies `liveAlternatives`
    (flatten/drop-bottom/dedup) on the non-all-regular branch — `*1|*1|2` eval → `*1 | 2`
    (deduped), `.structuralCycle` arms pruned. The prescribed fix is landed. What REMAINS
    is purely cue's further DISPLAY-collapse to the default (`*1|2` → `1`, `{…} | *null` →
    `null`), which Kue deliberately does NOT do — collapsing into the value is unsound
    (loses the live non-default arm a later meet needs; cf. `default_disjunction.expected`
    Kue `*"prod"|"dev"` vs cue `"prod"`). That cosmetic display projection (a Format-layer
    change rewriting ~7 fixtures) is recorded as a spec-gap (`cue-spec-gaps.md` D#2b/SC-3
    row), not a value bug — close it only if the eval-display convention is ever
    revisited.
13. **F-3 — DONE (2026-06-20).** Qualified import path `"location:identifier"` now parses.
    The spec grammar `ImportPath = '"' ImportLocation [ ":" identifier ] '"'` puts the
    qualifier INSIDE the string; `splitImportPath` splits it out at parse time into a new
    `Import.packageName : Option String` (location-only `path` + explicit qualifier), so
    every path consumer (`isBuiltinImport`/`resolveImportTarget`/`lastPathElement`) sees
    the bare location — the previous bug fed the unstripped `:id` into directory
    resolution (`package directory not found: …/math-utils:math`). `isPackageIdentifier`
    validates the qualifier (identifier-start + parts, not `#` /`_#`) at PARSE, rejecting
    junk cue defers to a load error (F-3 divergence). `importBindName` precedence is alias
    > qualifier > declared-name > last-element. SCOPE = parse + bind-name; the stricter
    suffix-vs-loaded-declared-name MISMATCH gate (cue's `package name "other"`) is a
    recorded resolution residual (needs the loaded name). 8 parse pins + 4
    `importBindName` /`isPackageIdentifier` pins + 4 module fixtures
    (`qualified_import{,_bare,_mixed,_invalid_id}`, all byte-identical to cue on the
    success cases). 1 cue-divergence (junk-qualifier parse-reject) + 1 spec-gap (validity
    boundary + parse-only scope). See implementation-log 2026-06-20.
14. **BI-2 — DONE (2026-06-20), with residual.** `math.Pow` (EXACT
    non-negative-integer-exponent domain — repeated exact decimal multiply, byte-identical
    to cue; `Pow(0,0)` bottoms, CONFORMS)
    + `list.Sort` /`list.SortStable` (comparator `{x,y,less}` evaluated per pair at the
      EVAL layer via
    a total stable monadic merge sort; `list.Ascending` /`Descending` emitted by
    `stdlibPackageValue?`) all FIXED. **BI-2-residual — `math.Sqrt` + `Pow(·,½)` DONE
    2026-06-21:** EXACT DECIMAL (`decimalSqrt` — fixed-iteration integer-Newton, total; Float
    correctly AVOIDED). Perfect squares collapse to int, irrationals → 34 sig digits;
    `Sqrt(x) = Pow(x,½)` (kue-more-correct divergence); `Sqrt(neg)`/`Pow(neg,½)` BOTTOM (no
    `NaN`). **BI-2-§3 — DONE 2026-06-21 (`cd2f0a9`), BI-2 family now COMPLETE:** §1 negative-INT
    exponent `x^(-n)=1/x^n` (exact rational); §2 general non-½ fractional `x^y = exp(y·ln x)`
    via `decimalExpScaled`/`decimalLnScaled` (fixed 40/60-term Taylor + binary range reduction,
    working scale 50, structurally total, axiom-clean). Mantissa byte-identical to cue's apd
    across 40 random + extreme cases; integral results collapse (`Pow(4,1.5)=8`, `Pow(8,⅓)=2`);
    `Pow(neg,non-int)`/`Pow(0,0)`/`Pow(0,neg)` BOTTOM (no `NaN`/`Infinity`). `math.Pow`/`Sqrt`
    now cover the full real domain — nothing open. See the BI-2-§3 SHIPPED block above +
    implementation-log 2026-06-21; spec gaps in `cue-spec-gaps.md` (BI-2 Pow/Sqrt + Sort rows);
    divergences in `cue-divergences.md` (Sqrt-vs-float64, NaN/Inf→bottom, general-Pow rendering).
15. **BI-1 (MED) — DONE 2026-06-20 (CONFORMS across the BMP).** Unicode case mapping for
    `strings.ToUpper/ToLower` shipped via an oracle-generated BMP simple-mapping table
    (`Kue/CaseTable.lean`, generated by `scripts/gen-case-table.py` from the local oracle,
    READ-ONLY no network; total binary-search lookup + Unicode char maps in `Builtin.lean`;
    ASCII maps deleted — the table is the single authority). `ToUpper("café")=="CAFÉ"`,
    `ToLower("ΑΒΓ")=="αβγ"`, byte-identical to cue across the BMP incl. irregular
    singletons (`µ`→`Μ`, `ÿ` →`Ÿ`) and the `ß` -no-expand simple-mapping boundary. New
    `StringsTests` module (case pins moved out of BuiltinTests + Unicode
    round-trips/singletons/boundaries/mixed + lookup unit pins) + `strings_case_unicode`
    fixture. **Residual (documented, deferred — NOT this slice):** (i) `ToTitle` stays
    ASCII-bounded — its Unicode TITLE-case mapping (`ǆ`→`ǅ`, ≠ upper) + `unicode.IsSpace`
    word boundary need their own table+predicate (the ONE remaining case-builtin
    divergence: `ToTitle("über alles")` Kue `"über Alles"` vs cue `"Über Alles"`); (ii)
    full case folding (`ß`→`SS`), locale (Turkish `ı` /`İ`), Greek final sigma,
    astral-plane letters — all recorded in `cue-spec-gaps.md` + `compat-assumptions.md`.
    See implementation-log 2026-06-20. Spike findings (for the record): (a) UNAVAILABLE —
    `lake-manifest` has ZERO external deps (no Std/Batteries/Mathlib); Lean core
    `Char.toUpper/toLower` are ASCII-only, no Unicode tables in core. (b) algorithmic
    ranges REJECTED as a clean slice — local oracle (`cue export` over the whole BMP)
    shows the mapping is overwhelmingly IRREGULAR: 1190 ToUpper / 1173 ToLower BMP code
    points collapse to only 674/658 offset-runs, of which **632/617 are SINGLETONS**; just
    ~13 contiguous regular runs (ASCII, Latin-1 supplement, Greek, Cyrillic, Armenian,
    fullwidth…). A (b) covering only the regular runs would leave all of Latin
    Extended-A/B (the even/odd ±1 letter pairs + hundreds of one-offs like µ→Μ +743, ÿ→Ÿ
    +121) WRONG — a weak partial on very common European text; covering the full set
    algorithmically = hand-transcribing ~650 rules as code (strictly worse than a table).
    (c) CHOSEN: generate a BMP **simple 1:1** case-mapping table from the local `cue`
    oracle (READ-ONLY, no network), embed as a Lean source file, commit the generator +
    table + provenance. cue's `strings.ToUpper/ToLower` are confirmed pure rune-wise
    SIMPLE mapping (length-in-code-points preserved across the BMP; NO ß→SS expansion —
    `ToUpper("ß")=="ß"`), so a 1:1 table is faithful; full-case-folding special-casing
    (ß→SS, locale ı/İ, final sigma) stays a documented spec-gap.

**Spec-gap decisions (the 4 ratifications) — DONE 2026-06-20.** All four were re-derived
from the spec + first principles and closed; see `cue-spec-gaps.md` for the full bases.
Verdicts:
- **Import-binding laziness** (B#2/F-5) — **RATIFIED.** Spec genuinely silent; keep
  tolerating on an operational-laziness basis (demand-driven value model; the
  `importBinding` marker keeps the package shallow). Includes the recategorized RX-2b
  field-less-invalid-label entry. Pinned by the `unreferenced_import_conflict` fixture +
  `rx2b_label_pattern_invalid_bottoms`.
- **`A|B` un-narrowed struct disjunction** (A) — **RATIFIED.** Spec silent; keep open — a
  join with no unique default IS the join (verified meet-identity vs `.top`). Corrected
  the prior "`incomplete`" mischaracterization (it is the open disjunction value, not an
  error). New pins `StructTests` `disj_struct_arms_no_default_*`.
- **Field order #3** (C/F-4) — **RATIFIED.** Spec silent (structs unordered, order
  implementation-defined); keep Kue's declaration/source order. Corrected the cue-behavior
  description (cue's cross-conjunct order is an undocumented internal-graph artifact, not
  the "first-introduced" rule once claimed — often sorts, sometimes interleaves).
  Supersedes plan item #4: parity DECLINED. New pin
  `meet_struct_field_order_is_declaration_order`.
- **list `+` /`*`** (E#4) — ✅ **DONE (E#4-fix, 2026-06-20).** Was MIS-FILED as a gap; the
  spec MANDATES the operator domain, so a concrete out-of-domain operand is a type error.
  cue is spec-correct; Kue was WRONG (held residual). FIXED — Kue now conforms. See the
  DONE entry below
  + `cue-spec-gaps.md` (RESOLVED row, NOT a `cue-divergence` — cue was right).

**E#4-fix — ✅ DONE (2026-06-20).** A concrete operand outside an arithmetic op's domain is
now a type-error bottom, not a held residual (the spec closes `+ - * /` over int/decimal,
plus `+` /`*` over string/bytes). `classifyArithOperand` (`Eval.lean`) classifies each
operand `prim` / `concreteNonArith` (`.struct`/`.list`/`.listTail`/`.embeddedList`) /
`incomplete`; `arithmeticDomainResult` type-errors (`.bottomWith [.nonArithmeticOperand op
ty]`) ONLY a concrete-nonarith operand paired with a CONCRETE partner, and DEFERS
(`.binary` residual) whenever either operand is incomplete — so `[1] + x` holds while
`x: int` is abstract and errors only after `x` resolves (matches cue; the
concrete-vs-incomplete discipline mirrors D#1b/c `classifyGuard`). The `prim,prim`
mismatches (`1+"x"`, `"a"-"b"`) were already `.bottom` and unchanged. Sibling fix:
`evalMul` gained the string/bytes `*` int **repetition** arms (`"ab"*2="abab"`, either
order, zero→ empty, negative→`negativeRepeatCount` error) — cue's documented behavior
superseding strings/bytes.Repeat, previously a silent wrong-bottom. Pins: 3 `numeric/*`
fixtures + ~19 `native_decide` theorems (`EvalTests`). Verify: `lake build` green,
`check-fixtures.sh` → `fixture pairs ok` (zero drift), cert-manager content-identical to
cue (modulo field-order #3).

**Low / hardening:** `containsBottom` fuel cap 100 (**A#6 — ✅ DONE 2026-06-21, made
TOTAL/structural**; `Lattice.lean:160`). Was: a bottom >100 levels deep escaped pruning →
wrong value (a dead disjunction arm survived `liveAlternatives`); a partiality hole.
**STANDALONE — D#2b confirmed it was NOT implicated by structural cycles** (D#2a detection
fires at recursion depth ~2, so a `.structuralCycle` bottom is always shallow); the hole
was for genuinely-deep NON-cyclic nested bottoms. **Fix:** removed the fuel entirely —
rewrote `containsBottom` as a mutual block (`containsBottom` + 4 list-helpers) elaborated
via `termination_by structural`, so it is TOTAL (no depth bound: a `.bottom` at ANY depth
is found) AND `rfl` /`decide`-reducible (structural recursion reduces in the kernel; a
`sizeOf` WF measure would have broken the existing `meet` /manifest `rfl` proofs).
`fieldBottomCounts` folded inline into `containsBottomFields` (optional-skip rule
preserved). Axiom-clean (`propext` only). Cert-manager byte-identical to pre-fix HEAD;
fixtures zero-drift; 8 adversarial `native_decide` pins (deep-150/-500 bottom detected,
deep no-bottom false, deep `.bottomWith`, deep optional-skip, `liveAlternatives`
/`normalizeDisj` end-to-end) in `LatticeTests.lean`. Also: `{#a:1,5}`
scalar-embed-with-definitions coverage gap; D#1b incomplete-guard deferral (couples with
D#2).

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

**Plan-hygiene / docs-reconciliation (recurring, non-code).** `plan.md` and this audit doc
re-accrete superseded re-ranks, completed Phase-A/B write-ups, and resolved fix-slice
diagnoses; a hygiene pass periodically distills the backlog to the LIVE open set + North
Star
+ standing capabilities and moves DONE detail to `implementation-log.md` /git. Last run
2026-06-21 (distilled the ~9 accreted audit blocks + the shipped D#2 design out of both
docs; RX-2c marked DONE — `maxRepeat=1000` landed with RX-1a). `docs/README.md` +
`www/index.html` routing/refresh is owned by the orchestrator — not touched here.

**Spec-doc errors (cosmetic, no code action):** the CUE spec's disjunction worked-example
comments contradict its own U2 rule (cue + Kue both follow the rule); the
`2 & >=1.0 & <3.0` example is stale. No action.

## D#2 design (structural-cycle detection) — SHIPPED, archived

The full D#2 design spike (oracle ground truth, the superseded `ForceKey` -triple
ancestor-scheme, the as-built `structStack` redesign, the terminating-disjunct algebra,
the soundness/totality argument, and the 2-slice plan) is HISTORY: D#2a + D#2b both landed
2026-06-20 and D#2 (structural cycles) is COMPLETE. The as-built detail lives in
[`../reference/implementation-log.md`](../reference/implementation-log.md) (D#2a/D#2b
entries) and git; the spec-gap on the eval-display of the cycle bottom is in
[`../reference/cue-spec-gaps.md`](../reference/cue-spec-gaps.md) (D#2a row). The design
prose is no longer carried here — the slice shipped and the behavior is pinned.
