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
| A. Disjunctions/narrowing | batch 1 | DONE | 1 KUE-VIOLATES (disj display); **Gap-2b/Bug2-3 FIXED 2026-06-19** (cue correct; structural list-vs-struct arm prune); 2 spec gaps; rest CONFORMS |
| B. Closedness/definitions | batch 1 | DONE | SC-1/1c/1d + SC-2 (nested def-body closedness) all FIXED 2026-06-19 — closedness cluster drained; import-laziness recorded as a deliberate gap; rest CONFORMS |
| C. Structs/lists          | batch 1 | DONE | 1 KUE-VIOLATES (pattern-meet closedness); 1 spec gap (field order); rest CONFORMS |
| D. Comprehensions/scoping | batch 2 | DONE | 3 KUE-VIOLATES (guard catch-all swallows bottom/incomplete; no structural-cycle detection; `let` clauses unparseable); frame-model + read-splice CONFORM |
| E. Scalars/bounds/builtins| batch 2 | DONE | 1 KUE-VIOLATES HIGH (regex not RE2); 2 MED builtin (ASCII case-fold; deferred builtins bottom); numeric/bounds/division/decimal core CONFORMS |
| F. Manifest/modules       | batch 2 | DONE | 3 KUE-VIOLATES (`regexp` import missing — **F-1 FIXED 2026-06-19**; self `@vN` not stripped — **F-2 FIXED 2026-06-19**; qualified `path:id` unparsed); export + module-resolution core CONFORM |

## Findings (ranked; filled as auditors return)

### Bug2-3 / Gap-2b — DONE (2026-06-19, `d9f66ca`)

Structural list-arm-vs-struct-host disjunction pruning. **Landed; cue is correct (spec-grounded:
unification distributes over disjunction + a list meets a struct with regular fields = ⊥); Kue was
under-pruning.** A def embedding a STRUCTURAL disjunction (`listShape | structShape`, discriminated
by list-vs-struct SHAPE, not a regular label), embedded one layer down (`#U: {#M}`) and
force-narrowed by a sibling regular OUTPUT field the arms lack: the host's regular fields reached
the arms only as a SIBLING of the embedded disjunction, never met INTO the list arm as a value, so
the sound `list & {regular fields} = ⊥` prune never fired and BOTH arms survived (ambiguous bottom).

- **Fix (the design's lever, gated):** `embedBodyEmbedsDisj` detects a disjunction-embedding body (a
  `.disj` in `cs`, or a depth-0 `.refId` to a let slot holding a `.disj`). When it fires,
  `spliceOperandForEmbed` routes ALL the host's regular OUTPUT fields into the embedded arms (not
  just the narrow comprehension-read/discriminator labels). The EXISTING `meet`-over-`.disj`
  distribution then prunes a list-shaped arm against the struct host via the SOUND type-conflict
  primitive; a struct-compatible arm survives untouched (meet is idempotent on a field it already
  carries). **The prune is the meet primitive, NOT a shape heuristic** — so two struct-compatible
  arms stay ambiguous (cue-exact), no over-eager shape discrimination.
- **GATE (cert-manager byte-identity):** the all-regular splice fires ONLY for a
  disjunction-embedding body; every other body keeps the narrow splice byte-identical. cert-manager
  re-probed vs cue v0.16.1: **content-identical** (jq -S, exit 0). All existing fixtures green (zero
  byte-drift). 6 `native_decide` pins (incl. gate-off `embed_body_embeds_disj_gate_no_disj`).
- **Soundness (all four obligations verified vs cue):** (1) struct-compatible arm survives; (2) real
  conflict (host matches neither arm) bottoms; (3) directly-narrowed disjunction unchanged (both
  compatible arms survive); (4) `struct | struct` ambiguous stays ambiguous, NOT falsely pruned.
- **argocd: STILL bottoms — a SEPARATE pre-existing blocker surfaced (NOT a regression).** The
  structural disjunction now prunes correctly (the guard-free repro
  `testdata/modules/disj_embed_struct_disc` exports content-identical to cue), but
  `kue export apps/argocd.cue` still bottoms (~104s) on a DISTINCT bug: a **two-level-embedded
  `let _patch` comprehension guard does not see the host narrowing**. With `#U: {#M}` and `#M`
  embedding `let _patch = { kind: string, for _, add in Self.#additions { if kind == add.#kind {
  add.#patch } } }`, the host's narrowed `kind` reaches `#U` but `embedComprehensionReadLabels`
  follows let-comprehension reads only ONE level, so `kind` is stripped before reaching `_patch`'s
  frame and the guard sees `string` → never fires → the matched `#patch` (`meta:"yes"`) is dropped.
  **Reproduces with NO disjunction at all** (`/tmp/kue-patch4.cue`: `#U: {#M}`, `#M` embeds `_patch`,
  `#U & {kind, #additions}` → cue `{kind, meta}`, Kue `{kind}` only) — confirmed identical on clean
  HEAD (`2ab5c84`). This is a comprehension-read-splice depth gap (Bug2-4 below), NOT Gap-2b. So
  argocd is NOT yet unblocked; cert-manager remains the one fully-correct probed real app.
- `Kue/Eval.lean` (`embedBodyEmbedsDisj`, `spliceOperandForEmbed`), `Kue/Tests/TwoPassTests.lean`,
  `testdata/modules/disj_embed_struct_disc`.

**Bug2-4 (DONE, `3f7a761`) — let-LOCAL declare-and-read narrowing.** The blocker was NOT a
transitive comprehension-read (Bug2-1 already followed lets transitively). It was the shape where
the read sibling is DECLARED INSIDE the same let that buries the comprehension: `let _patch = {
kind: string; for … { if kind == add.#kind {…} } }` (literally `defs/parts.#Mixin`'s `_patch`).
The guard's `kind` resolves to `_patch`'s OWN frame, where `kind` is also declared, so NO embed-def
index names it — `closeDefFrameReadIndices` (which collects def-frame reads) finds nothing, and a
host narrowing spliced at the def frame lands as a SIBLING the guard never reads. Two helpers, both
total (visited-set + structural fuel, cycle-safe) and sound (only meets the host narrowing into a
field the host narrows anyway — never invents a value, never over-splices, same envelope as
Bug2-1):
- `letPromotedReadLabels` (fixpoint over followed lets): surfaces the regular labels a let's OWN
  comprehension reads from its OWN frame — labels the let promotes to the embed on embedding, so the
  host's narrowing splices toward the def.
- `injectLetLocalNarrowings` (in `forceClosureWithConjunctCore`): meets the use-operand's regular
  narrowings INTO any let-local that declares-and-reads the label, before the comprehension expands.

Fixes the minimal Mixin repro (def-host `#Use & {kind:"ListenerSet"}`, with the structural
`listShape | structShape | error` disjunction): matched patch `meta:"yes"` surfaces,
content-identical to cue v0.16.1. Verify green (build · `fixture pairs ok` zero drift · shellcheck ·
cert-manager content-identical). 7 `native_decide` pins + `testdata/modules/mixin_let_local_narrowing`.

**argocd STILL bottoms — Bug2-5, a DISTINCT residual blocker (pre-existing, NOT a regression).**
`kue export apps/argocd.cue` still bottoms (~153s). The remaining shape, faithfully reproduced
(`/tmp/kue-ls-shape.cue`), is `defaults.#ListenerSet = defs.#ListenerSet & parts.#UseCertManager &
{…}`: `defs.#ListenerSet` declares `kind: "ListenerSet"` at ITS def frame and CO-EMBEDS
`#UseCertManager` (→ `#Mixin`). The Mixin's `_patch.kind` must be narrowed by the SIBLING def's
`kind`, NOT by a use-operand. Because `#Mixin`'s body is the `listShape | structShape | error`
DISJUNCTION, the embed resolves on the `.disj` arm of `meetEmbeddingsWithFuel` (each arm `meet`s the
host AFTER the arm — and `_patch`'s comprehension — has evaluated), so the narrowing arrives too late
and `injectLetLocalNarrowings` (which fires only on the `forceClosureWithConjunctCore` `.structComp`
arm) never runs. Minimal repro: `#ListenerSet: { #UseCertManager; kind: "ListenerSet" }`, `out:
#ListenerSet & {#name:"x"}` → cue emits `meta:"yes"`, Kue drops it. This is narrowing-injection into
a DISJUNCTION-arm-referenced let-local on the eager/disj path — a deeper mechanism than read-label
following, filed as Bug2-5 below. (Note: CLI `kue export` and the in-Lean `exportJsonMatches`
harness take DIFFERENT embed paths for the same source — the def-host Mixin reaches the force
`.structComp` arm in the harness but not in the CLI; both produce correct output, but the path
divergence is a latent concern flagged for the architecture audit.)

**NEW fix-slice — Bug2-5 (HIGH, the residual argocd blocker, undesigned):** narrowing-injection into
a disjunction-arm-referenced let-local. When an embedded disjunction's surviving arm (`structShape`)
references a sibling let (`_patch`) that declares-and-reads a label narrowed by a CO-EMBEDDING
sibling def's static field (`kind`), the `.disj`-distribution path of `meetEmbeddingsWithFuel` must
inject that narrowing into `_patch` BEFORE the arm's comprehension expands — the disjunction analogue
of Bug2-4's `injectLetLocalNarrowings` on the force path. Pinned repro `/tmp/kue-ls-shape.cue`. This
is now the single real-app export blocker for argocd.

### Phase-A audit of the RX-2b + RX-1c batch (`5d884af..e4922c9`, 2026-06-19)

Pressure-tested the regex trilogy's final two slices (invalid-pattern bottom contract +
submatch/`Find*`/`ReplaceAll` engine surface) against `cue` v0.16.1 and the RE2 spec.
**Verdict: both slices spec-correct; nothing reverted. ONE recategorization (low-risk doc)
+ ONE test-strength fix applied inline; no code/behavior change.**

- **RX-1c newline-prefix fix (`ac354ab`) — CORRECT, both halves verified.** The unanchored
  search prefix `.star false (.cls [] true)` (negated-empty = any-char-incl-`\n`) lets the
  search CROSS newlines (`"two" =~ "one\ntwo"` → true; `"a\nb" =~ "b"` → true), WITHOUT
  making a bare `.` match `\n`: `.any` still compiles to `Inst.any`, gated by `c != '\n'`
  in `stepThreads`. Oracle-matched all four: `"a\nb" =~ "a.b"` → false, `"a\nb" =~ "a.*b"`
  → false, `"a\nc" =~ "a.c"` → false, `"abc" =~ "a.c"` → true. No `(?s)`-style dotall
  leakage. **The complement (`.` excludes `\n`) was UNTESTED** — added 3 regression-guard
  pins (`rx_dot_excludes_newline`, `rx_dotstar_excludes_newline`, `rx_dot_matches_nonnewline`).
- **Go `Expand` template — CORRECT across all edge cases.** Oracle-matched the longest-name
  rule and the subtle cases: `$10` → group 10 (nonexistent) → empty (`"--"`); `${1}0` →
  group 1 + `"0"`; `$0` → whole match; `$$1` → literal `$` then `"1"`; trailing `$` →
  literal; `$$` → `$`. `expandTemplate` is fuel-bounded by template length, total.
- **Totality / axioms — clean.** `#print axioms` for `matchRegex`/`findSubmatch`/`find`/
  `findAll`/`findAllSubmatch`/`replaceAll`/`replaceAllLiteral` = `{propext, Quot.sound,
  Classical.choice}` only. No `partial`, no `sorry`. The empty-match advance (`allMatches`
  `next := if e ≤ pos then pos + 1 else e`) guarantees progress so the fuel
  (`chars.length + 2`) is exact and never spuriously hit — `regexp.ReplaceAll("x*","abc","-")`
  → `-a-b-c-` (one rune/step, no loop, oracle-matched).
- **Submatch / leftmost — CORRECT (RE2, not POSIX-longest).** `find "a|ab" "ab"` → `"a"`
  (first arm, leftmost — NOT longest `"ab"`); nested `(a(b)c)` spans, optional
  non-participating `(x)?y` → `""`, alternation untaken arm `(a)|(b)` → `""` — all
  oracle-matched. No-match → `none` → `.bottom` at the dispatch site; cue raises `no match`
  (confirmed), so the bottom is the correct categorization (not Go's nil).
- **Kept-unsupported — HONEST.** `FindString`/`Split` → `unsupportedBuiltin` bottom;
  confirmed cue v0.16.1 genuinely lacks them (`cannot call non-function regexp.FindString`).
  `FindAll(..., n)` truncation matches cue (`n<0` all, `n≥0` first n, `n=0` → no-match
  bottom). Abstract args (`regexp.Match "a" string`) stay `.builtinCall` — incomplete, not
  bottom.
- **RX-2b 5-site contract — CONSISTENT.** All 5 sites verified: `=~`/`!~`
  (`evalRegexMatch`/`evalRegexNotMatch`) bottom a concrete invalid pattern (`!~` bottoms,
  NOT flips to true) and DEFER an abstract one (`.binary` residual); `regexp.Match`,
  `meetStringRegexPrim`, `subsumesWithFuel` (boolean site — conservative-false, can't
  bottom), and the pattern-label path (`patternsRegexError?` — `some` on a concrete invalid
  `.stringRegex`/`.conj`, `none` on an abstract `.kind` predicate). Oracle-matched.
- **Divergence-entry recategorization (APPLIED inline, low-risk doc).** The RX-2b field-less
  invalid-label entry (`{[=~"a("]: int}` → cue `{}`, Kue `_|_`) was in `cue-divergences.md`
  as CUE-BUG/KUE-CORRECT. It is actually a **SPEC-SILENT / operational-laziness spec gap** —
  the same family as the import-laziness gap (B#2/F-5) and SC-2b: the spec mandates RE2
  SYNTAX but is SILENT on WHEN an UNEXERCISED pattern constraint is validated (parse-time vs
  lazy-on-match), and cue's tolerance is reference-location-dependent (field present ⇒ both
  error and AGREE; field-less ⇒ cue tolerates, Kue bottoms eagerly). Moved to
  `cue-spec-gaps.md`; Kue's eager-bottom basis (illegal-states: a struct carrying a malformed
  constraint is ill-formed regardless of later meet) recorded. The `(?i)` deferred-construct
  entry is correctly ABSENT from both divergence docs — cue/RE2 SUPPORT `(?i)` (`"ABC" =~
  "(?i)abc"` → true), Kue defers it as `.unsupportedRegex`; that is Kue-incomplete (RX-2a
  territory), NOT cue-wrong.
- **Illegal-states / DRY / skill — clean.** No new `partial`, no catch-all `_` swallowing
  future `Inst`/`Regex` constructors. `Captures` is a clean `abbrev`; the 6 `evalRegexpBuiltin`
  arms each guard on `regexParseError?` first (DRY via the shared helper); the `| none =>
  .bottom -- unreachable` arms after a checked parse are provably dead but total (ε-safe, not
  a crash). `bumpGroups`/`findFrom`'s wrapper-group trick (reserve group 1 for the true
  whole-match span behind the prefix-pinned slots 0/1) is the one piece of real subtlety —
  verified correct via the leftmost/nested span probes.

**No new fix-slices.** The batch is spec-correct as landed; the two inline fixes (doc
recategorization + 3 regression-guard pins) carry no behavior change. Note: RX-2c
(repeat-count cap at 1000) appears ALREADY DONE — `maxRepeat = 1000` is enforced in
`parseRepeatSuffix` and pinned by `rx_repeat_over_cap_*` in RegexTests (landed with RX-1a);
the backlog still lists it as open. Mark RX-2c DONE in the next plan-hygiene pass. Remaining
genuine regex work: RX-2a (in-class `\D\W\S`, the lone corpus divergence).

### Phase-A audit of the SC-2 + RX-1a + RX-1b batch (`a5862df..04eb7de`, 2026-06-19)

Pressure-tested the new RE2 regex engine (RX-1a/b) against `cue` v0.16.1 with a broad
~96-case pattern×input corpus, plus a 12-case SC-2 over-close hunt. **Engine verdict:
RE2-correct beyond the 7 repros — exactly ONE corpus divergence, and it is a known deferred
feature surfaced as a parse error (not silent-wrong).** SC-2 verdict: **no over-close found.**
Four findings folded into the backlog (none high enough to block; all NEW fix-slices):

- **Regex corpus diff (Kue vs cue, ~96 cases): 1 divergence.** `[\D]` (negated perl class
  INSIDE a `[…]`) → Kue `unsupportedRegex` parse-error, cue/RE2 matches. This is the
  RX-1a-documented deferred construct (`\D \W \S` inside a class need set-complement folding),
  correctly stubbed not silent-wrong. → **RX-2a** below. Everything else byte-agrees with cue,
  including all the named hazards:
  - Alternation precedence `a|ab` (leftmost, not longest); `(a|ab)(c|bcd)` on `abcd` picks
    g1=`a` g2=`bcd` (RE2 leftmost, NOT POSIX-longest) — confirmed via capture spans.
  - Empty/nested-loop quantifiers `(a*)*`, `(a?)*`, `(|a)*`, `(a*)*b` all **terminate AND
    match correctly** — the `visited`-by-pc dedup in `addThread` cuts the ε-loop (not fuel).
  - `{0,0}`, `a{0}`, `{2,}` shapes; mid-pattern anchors `a^b`/`a$b` (correctly never match);
    `^$` on empty (match) + non-empty (no); `.` does NOT match `\n` (RE2 default); char-class
    edges `[]`/`[^]`/`[a-]`/`[-a]`/`[z-a]`(error)/ranges; `\d`/`\D`/`[\d]`; `\b`/`\B` at all
    boundaries; greedy-vs-lazy spans; UTF-8 (`α`, `日本`, `café`, `[α-γ]` — the VM iterates
    `Char` (runes), matching cue's rune semantics on `=~`); the unsound old-engine
    `(foo|bar)+` substring case.
- **Totality: axiom-clean.** `#print axioms` for `compile`/`NFA.run`/`matchRegex`/`parseRegex`/
  `Compile.desugar` = `{propext, Quot.sound, Classical.choice}` only — no `sorryAx`, no
  `partial`. The Pike-VM ε-closure fuel (`insts.size`) is genuinely exact; the empty-loop case
  terminates by `visited`, not fuel-exhaustion (verified by the corpus above).
- **Capture slots correct for RX-1c.** Dumped `run`'s slots for the flagged shapes: `((a)(b))`
  (nested), `(a)?b` (non-participating group → none/none, RE2-correct), `(a)|(b)` (untaken
  branch unset), `(a+)(b+)`, `(a|ab)(c|bcd)` (leftmost). All correct — RX-1c can expose them
  as-is.
- **4 dispatch sites consistent.** `Eval.evalRegexMatch`, `Order.subsumesWithFuel`,
  `Lattice.meetStringRegexPrim`, `Builtin.regexp.Match` ALL route through the single
  `matchRegex` unanchored entrypoint → agree by construction. `!~` = `evalRegexNotMatch`
  negates the bool, correct for VALID patterns.
- **RX-bug — invalid pattern silently swallowed to `false` at ALL 4 sites (NEW finding,
  pre-existing).** `matchRegex` returns `false` on `parseRegex` error, so `=~` with an invalid/
  deferred pattern yields `false` (and `!~` yields `true`; the Lattice site bottoms a VALID
  string). cue/RE2 raise `invalid regexp` (an error/bottom), confirmed on `(`, `a(`,
  `regexp.Match("(", "x")`. The old engine had the same swallow (carried forward, NOT introduced
  by RX-1b), BUT RX-1b added the unused `regexParseError?` helper, so the fix is now cheap. →
  **RX-2b** below.
- **RX-bug — no repeat-count cap (NEW finding).** Kue accepts `a{0,5000}` and would `desugar`
  it to 5000 nested optionals (linear AST/program blowup; `a{0,100000000}` is a compile/memory
  DoS). RE2/cue cap repeat counts at 1000 (`invalid repeat count` on `a{0,2000}`). Both a
  conformance gap and a resource bound. → **RX-2c** below.
- **SC-2 over-close hunt (12 cases): clean — NO over-close.** Plain nested (`c1`), deep nested
  (`c3`), def-embed (`c6`), comprehension-in-def (`c7`), nested-optional (`c10`), disj-nested
  (`c12`) all close in BOTH Kue and cue (Kue renders `extra: _|_`, cue errors — the known #3
  field-order/error-render gap, not a closedness divergence). Nested `...` tail (`c2`) and plain
  non-def struct (`c5`) correctly STAY OPEN in both. SC-2b (`c9`) is the recorded intentional
  divergence (correct: closedness monotone through meet; cue re-opens on no-op `& {}` — an
  eval-strategy artifact). Fixtures green (cert-manager/argocd no new closedness bottom).
- **SC-2 under-close (NEW, LOW / suspect-artifact).** TWO direct-unification paths where Kue
  stays OPEN but cue CLOSES: `#A:{_h:{b:int}}; #A & {_h:{b,extra}}` (hidden field, `c4`) and
  `#A:{let z={b:int}, a:z}; #A & {a:{b,extra}}` (let-bound PLAIN struct as a def field value,
  `c8`). The SC-2 design deliberately routes `letBinding`/hidden through the SPINE (not the
  closing twin), correct for a let/hidden bound to a DEF (`c8b`/`c4b` selection paths, where
  Kue==cue==OPEN). But cue itself is INCONSISTENT — `c4` (direct `&`) closes while `c4b`
  (select-then-`&`) does not — so this is likely a cue eval-strategy artifact, not a spec
  mandate. Needs a spec check before any fix; NOT confirmed a Kue bug. → **SC-4** below (LOW,
  spec-gap-first).
- **Illegal-states / DRY / skill:** RX-1a/b are exemplary — greediness as a `Bool` field (no
  lazy-constructor duplication), `repeat.max : Option Nat` (no sentinel), group `index : Option
  Nat` (none = non-capturing), typed `RegexParseError` (genuine vs deferred distinguished),
  no catch-all `_` swallowing future `Inst`/`Regex` constructors, the `.«repeat»` arm in
  `compileFrag` is provably dead (desugar runs first) and returns ε rather than crashing. SC-2's
  twin-function (not a `closing : Bool` flag) keeps intent in WHICH function is called —
  illegal-states philosophy. No new partiality.

### Phase-B whole-graph sweep (2026-06-19, post regex-trilogy, `4358a7e`)

Whole-graph sweep after the regex family (RX-1a/b/c, RX-2b/2c) landed complete. **No new
high finding; module graph healthy. Bug2-3 + D#2 designs RE-VERIFIED against current code
(post-SC-2, post-regex) — both GO, no drift. No inline code fix (build green, 100 jobs);
audit folds the re-rank + readiness verdicts + plan-hygiene rec into this doc.**

**JOB 1 — whole-graph sweep.**
- **`Kue/Regex.lean` (929 lines) — clean, well-encapsulated leaf.** Imports NOTHING from
  Kue (line-5 "import" is a doc comment; confirmed `grep '^import'` is empty). Consumed by
  exactly the 4 dispatch sites + `Value` (BottomReason via RX-2b) + `Order` + `RegexTests`.
  Internal layering textbook: `RegexParseError`/`Regex` AST → `parseRegex` (recursive
  descent) → `Inst`/`AssertKind`/`NFA` → `Compile` (Thompson + desugar) → `Vm` (Pike) →
  `matchRegex`/`regexParseError?` entrypoints → engine layer (`findSubmatch`/`find`/
  `findAll`/`replaceAll` + Go `Expand`). **Size: 929 lines is the second-largest leaf but
  NOT split-warranting** — it is one cohesive responsibility (RE2 subset), the layers are a
  clean pipeline (AST→VM→replace), and splitting (AST+parser vs NFA+VM vs replace/find)
  would scatter shared types (`Regex`/`Inst`/`Captures`) across files for no boundary
  benefit. Revisit only if RX-2a (set-complement folding) pushes it past ~1100. **Verdict:
  exemplary leaf; no action.**
- **Import graph acyclic (re-verified whole-graph).** `Value → Regex` (RX-2b's addition)
  adds NO cycle — Regex is a true leaf (imports nothing from Kue), so `Value → Regex` is a
  DAG edge to a sink. Full chain confirmed: `Regex` (sink) ← `Value`/`Order`/`Lattice`/
  `Builtin`/`Eval`; `Value` ← `Decimal`/`Normalize`/`Resolve`/`Order`/`Format`/`Lattice`/
  `Parse`; `Lattice` ← `Builtin`/`Manifest`/`Eval`; `Eval` ← `Runtime`/`Examples`; no
  back-edge. One clear responsibility per module holds.
- **`Eval.lean` (3159 lines, was ~3135) — comprehension-expansion sublayer stays a
  preference-not-defect.** +24 lines since last sweep (RX-2b dispatch wiring at
  `evalRegexMatch`/`evalRegexNotMatch`, not new structure). Still the one oversized module;
  still no extractable seam that wouldn't fracture the mutual-recursion block (`evalValue`/
  `force`/`meetEmbeddings`/`expandComprehensions` are one `mutual`). Not a fix-slice.
- **`kue-performance.md` (at `docs/guides/`, NOT `docs/reference/`) — CURRENT.** The
  linear-Pike-VM entry (L154-160, "Regex matching is linear (RX-1a/b LANDED)") already
  replaced the stale backtracking known-limitation. No drift. The regex perf cliff +
  fuel-out soundness hole are both recorded RESOLVED. No edit.

**JOB 2 — Bug2-3 + D#2 implementation-readiness (RE-VERIFIED against current `Eval.lean`).**

**Bug2-3 / Gap-2b — GO, no drift.** SC-2 was Normalize-only (`normalizeDefinitionFieldWithFuel`
twin), touched NOTHING on the disjunction/embedding eval path Bug2-3 targets — confirmed by
re-locating every cited anchor in the post-SC-2 tree:
- The standalone raw `.disj` arm (design "~2406/2449") is now `Eval.lean:2445-2449`
  (`.disj alternatives => … normalizeEvaluatedDisj evaluated`). Intact.
- The `meetEmbeddingsWithFuel` `.disj`-distribution helper the fix proposes REUSING (design
  "~2708") is now `Eval.lean:2705-2710` (`conjDisjArms? → arms.mapM … meetEmbeddingsWithFuel
  … [arm.snd]`). Intact — the existing arm-distribution lever Bug2-3 builds on is unchanged.
- The no-tail-no-pattern force arm (design "~2875") is within `forceClosureWithConjunctCore`
  (`Eval.lean:2836`), using `mergeConjOperands` + `evalFieldRefsListWithFuel`. Intact.
- **Repro RE-CONFIRMED LIVE (`/tmp/kprobe/struct_disc.cue`):** Kue → `conflicting values
  (bottom)`, cue v0.16.1 → `{kind:"ListenerSet", meta:"yes"}`. cue is CORRECT (spec: `list &
  {regular fields} = ⊥`); Kue under-prunes the list arm. Still the LAST real-app export
  blocker. Line-refs in the design are stale by ±40 lines but the STRUCTURES and the reuse
  target are all present and unchanged. **Still ≤1-2-slice; design accurate; GO.**

**D#2 (structural cycles) — GO, no drift, still 2 slices.** The ancestor-force-stack design
re-verified against the current force path:
- `ForceKey = ⟨fuel, capturedEnv.ids, body, useOperands⟩` (`Eval.lean:2818`) — EXACTLY the
  design's "ancestor identity is ForceKey minus fuel". Unchanged.
- The `forceClosureWithConjunct` (entry, memo-gated, `Eval.lean:2809`) /
  `forceClosureWithConjunctCore` (`Eval.lean:2836`) split the design places the cycle check
  at is intact; `termination_by (fuel, 5, 0)` (L2834) matches obligation-3.
- `refDefClosureBody? → forceClosureWithConjunct fuel (frame :: outer) defBody []`
  (design "2331") is now `Eval.lean:2354-2355`. The depth-0 `visited`-slot check
  (`Eval.lean:36-44`, threaded as the `visited : List Nat` parameter) is the disjoint
  reference-cycle mechanism the design says NOT to touch — intact.
- D#2b dependency confirmed: `liveAlternatives`/`resolveDisjDefault?` (`Lattice.lean:269/288`)
  + the A#6 `containsBottomFuel = 100` cap (`Lattice.lean:146`) all present. The
  `structuralCycle` arm-bottom sits at an arm's top level, well within the 100-cap, so the
  design's ⚠ (cap hiding a deep cycle bottom) is low-risk and already folded into D#2b.
- `BottomReason` (`Value.lean:500`) currently has `invalidRegex` (RX-2b) but NOT yet
  `structuralCycle` — D#2a adds it (additive, no conflict; RX-2b already proved the pattern).
- **2 slices (D#2a detection + D#2b terminating-disjunct); design accurate; GO.**

**JOB 3 — re-ranked next 3-4** (see "Re-ranked next slices — Phase-B audit #4" in the
consolidated backlog below). Top: Bug2-3 (last real-app export blocker, designed) → D#2a/b
(designed) → RX-2a (regex feature, both touch the same module — sequence after the engine
is quiet).

**JOB 4 — plan-hygiene: DUE, schedule it (LOW urgency, not blocking).** `plan.md` (1756+
lines) and this audit doc (1221 lines) have accumulated ~9 superseded re-rank sections, 4
completed Phase-A audit write-ups, and resolved fix-slice diagnoses (SC-1/1c/1d, F-1/F-2,
D#1a, RX-2b/RX-1c all DONE inline in the trackers). A hygiene pass would: (a) distill the
backlog to the LIVE open set (Bug2-3, D#2, RX-2a, SC-4, the MED tail, 4 spec-gap
ratifications, A#6) + North Star + standing capabilities; (b) move the DONE entries + the
superseded re-ranks to `implementation-log.md` (history) / git; (c) mark RX-2c DONE (the
backlog still lists it open — `maxRepeat=1000` landed with RX-1a, flagged in the prior
Phase-A audit). `docs/www/index.html` is CURRENT (just refreshed) — leave it. Schedule as
ONE non-code slice AFTER Bug2-3 lands (so the next argocd-unblock milestone is captured in
the same distillation), not before (it would churn the trackers Bug2-3's slice must update).

### Phase-B whole-graph sweep (2026-06-19, D#2-spike audit, `659cf70`)

Brief architectural state alongside the D#2 design spike. No NEW high finding; the module
graph is healthy post-RX-1b.

- **`Kue/Regex.lean` is a clean, well-encapsulated leaf.** Imports NOTHING from the engine
  (the line-5 "import" is a doc comment; no `import Kue.*`) — it is a pure `String → String →
  Bool`/submatch module. Imported by exactly Builtin/Eval/Lattice/Order (the 4 dispatch sites).
  Internal layering is textbook: `RegexParseError`/`Regex` (AST) → `parseRegex` (recursive
  descent) → `AssertKind`/`Inst`/`NFA` → `Compile` (Thompson + `desugar`) → `Vm` (Pike) →
  `matchRegex`/`regexParseError?` (entrypoints). The no-`DecidableEq` `Value` perf carve-out
  correctly does NOT apply here. **Verdict: exemplary leaf; no action.**
- **RX-2b soundness hole — blast radius was 4 sites + 1 (RESOLVED 2026-06-19).** `matchRegex`
  (`Regex.lean`) swallowed `parseRegex .error → false`. The 4 named callers (`evalRegexMatch`,
  `subsumesWithFuel`, `meetStringRegexPrim`, `regexp.Match`) routed through it, AND a FIFTH the
  4-site sweep missed: the pattern-LABEL application (`labelMatchesPatternWith` wraps the meet in
  `!containsBottom`, swallowing the parse bottom into a non-match). All five now guard on
  `regexParseError?` (the 5th at the `applyEvaluatedStructN` chokepoint via `patternsRegexError?`).
  `BottomReason.invalidRegex pattern err` added (carries the typed `RegexParseError`; `Value.lean`
  imports the Regex leaf). DONE — see the consolidated-backlog entry.
- **SC-2 closing-walker twin vs the D#2 structural-cycle walker — NO shared abstraction
  warranted (DRY check).** The SC-2 twin (`normalizeDefinitionFieldWithFuel`, `Normalize.lean`)
  is a STATIC normalization pass that closes nested def-body field values at capture time; the
  D#2 detection is a DYNAMIC runtime ancestor-check on the `Eval.lean` force path. They walk
  different structures (normalized-body fields vs in-progress force frames) at different times
  (capture vs eval) for different purposes (closedness vs cycle). Forcing them to share would
  couple normalize and eval — a layering violation. Keep separate. The ONE real reuse D#2
  exploits is the EXISTING `ForceKey` triple (frame identity) and the EXISTING
  `liveAlternatives`/`resolveDisjDefault?` algebra (terminating arm) — D#2 adds almost no new
  abstraction, which is the right amount.
- **Perf-guide currency — FIXED INLINE this audit.** `kue-performance.md`'s "Regex matching is
  backtracking (RX-1 pending)" known-limitation was STALE (RX-1a/b landed; the backtracking
  engine is deleted, the Pike-VM is live and linear). Rewrote it to "Regex matching is linear
  (RX-1a/b LANDED)" — the regex perf cliff + the fuel-out-soundness hole are both RESOLVED;
  remaining regex work is feature coverage (RX-1c/RX-2a), not perf. Committed with this audit.
- **No new architecture finding.** Module boundaries sane, no import cycles, no dead code
  surfaced in the sweep. The `BottomReason` enum is the one place two designed slices (RX-2b
  `invalidRegex`, D#2 `structuralCycle`) both add arms — additive, no conflict.

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

### Re-ranked next slices (2026-06-19 Phase-B audit #4 — regex trilogy COMPLETE; SC-2 landed)

Re-rank after the full regex family (RX-1a/b/c, RX-2b/2c) + SC-2 landed and were
Phase-A-verified clean (`4358a7e`). The two designed HIGH levers (Bug2-3, D#2) RE-VERIFIED
GO against the post-SC-2 tree this audit (line-refs drifted ±40 but structures + reuse
targets intact). Principle (slice-loop): contained-soundness before larger features;
cue-AGREEING correctness before divergence; designed levers before undesigned;
real-app-unblock weighted. **Recommended next 3-4:**

1. **Bug2-3 / Gap-2b — DONE (2026-06-19, `d9f66ca`).** Structural list-arm-vs-struct-host
   disjunction pruning landed (gated, cert-manager byte-identical, 4 soundness obligations
   verified). See the DONE writeup above. argocd did NOT unblock — a SEPARATE pre-existing
   bug surfaced (Bug2-4 below).
1b. **Bug2-4 (HIGH — the NEW last argocd export blocker, undesigned).** Transitive
   comprehension-read-splice: `embedComprehensionReadLabels` follows an embedded let's
   comprehension reads only ONE level, so the two-level `#U:{#M}` shape where `#M` embeds a
   `let _patch` whose `if kind == add.#kind` guard reads a host-narrowed `kind` never sees the
   narrowing → the guard drops the matched `#patch`. Reproduces with NO disjunction (pinned in
   the Bug2-3 DONE writeup). Now the single real-app export blocker for argocd → TOP of the next
   slices.
2. **D#2a (HIGH — structural-cycle DETECTION, DESIGNED, slice 1 of 2).** Ancestor-force-stack
   on the `forceClosureWithConjunct` path (reusing the `ForceKey` triple). Lands oracle
   #1/#3/#4/#5 (error + finite-control + reference-control). Spec-mandated, currently MISSING.
   Design GO, no drift. Cannot regress real apps (zero self-ref defs in prod9).
3. **D#2b (HIGH — terminating-disjunct, DESIGNED, slice 2 of 2).** `#List | *null` takes the
   default arm once the cyclic arm bottoms (existing `liveAlternatives`/`resolveDisjDefault?`
   algebra). Folds in the A#6 `containsBottom` fuel-cap fix if it hides a deep cycle bottom.
4. **RX-2a (MED — in-class `\D`/`\W`/`\S`, the lone regex-corpus divergence).** Needs
   class-level set-complement folding in `parseClassEscape`. Sequence AFTER D#2 if D#2 runs
   in a worktree — RX-2a and any future regex work both touch the Regex leaf, so serialize
   regex-module edits to avoid worktree contention. Lower than Bug2-3/D#2 (feature, not a
   real-app blocker; current behavior is an honest stub, not silent-wrong).

Then the MED tail (D#1b/D#1c, D#3 `let`-clauses, SC-3 disj-display, BI-1 Unicode case-fold,
BI-2 `math.Pow`/`list.Sort`, F-3 qualified import), SC-4 (LOW, spec-gap-first), the 4
spec-gap ratifications in `cue-spec-gaps.md`, low/hardening (A#6 standalone if not folded
into D#2b), and the **plan-hygiene slice (schedule AFTER Bug2-3)**. RX-2c is DONE (mark it
in the hygiene pass — `maxRepeat=1000` landed with RX-1a).

### Re-ranked next slices (2026-06-19 Phase-B audit #3 — regex engine LIVE; D#2 now designed)

Re-rank with the RE2 regex engine landed (RX-1a/b) and D#2 designed (this audit). Principle
(slice-loop): contained-soundness before larger features; cue-AGREEING correctness before
divergence; designed levers before undesigned. **Recommended next 3-4:**

1. **RX-2b — DONE (2026-06-19).** Invalid/deferred regex pattern now bottoms with
   `BottomReason.invalidRegex pattern err` (carries the offending pattern + the structured
   `RegexParseError`), not a silent `false`/`true`/valid-string-bottom. The already-defined-and-
   unused `regexParseError? : String → Option RegexParseError` (`Regex.lean`) became the shared
   decision; each of the 4 `matchRegex` dispatch sites guards on it before matching:
   `Eval.evalRegexMatch` (concrete-string arm → `.bottomWith [.invalidRegex …]`, abstract operand
   still defers via the `.binary` residual arm — NOT bottom); `evalRegexNotMatch` delegates to
   `evalRegexMatch` so its `.bottomWith` flows through the `value => value` arm — `!~` bottoms,
   NOT silently `true`; `Lattice.meetStringRegexPrim` (invalid pattern bottoms BEFORE the prim
   match — was: a VALID string bottomed); `Order.subsumesWithFuel` `.stringRegex`-vs-string arm
   (`(regexParseError? pattern).isNone && matchRegex …` — an invalid constraint subsumes nothing);
   `Builtin.regexp.Match`. A FIFTH consumer surfaced and was fixed: the pattern-LABEL application
   path (`[=~"a("]:` predicate) — `Eval.applyEvaluatedStructN` now bottoms the struct via a new
   `patternsRegexError?` scan of the label predicates (a `.stringRegex`/`.conj`-wrapped invalid
   concrete pattern; an ABSTRACT predicate does not trip), because `Lattice.labelMatchesPatternWith`
   wraps the meet in `!containsBottom` and so would have swallowed the parse bottom into a
   non-match. `Value.lean` gained `import Kue.Regex` to carry the typed error in `BottomReason`
   (Regex stays an import-less leaf; no cycle). **`BottomReason.invalidRegex` added.** Pins: 4
   `regexParseError?` helper pins in RegexTests; 9 dispatch-site pins in LatticeTests (eval +
   meet + label, valid-unchanged, abstract-stays-residual); 2 in OrderTests; 1 in BuiltinTests
   (+ the F-1 valid pins stay green) + 2 fixtures (`numeric/regex_invalid_patterns`,
   `definitions/regex_invalid_pattern_label`). Verified vs cue v0.16.1: `=~`/`!~`/`regexp.Match`/
   `[=~…]` all error on `a(`; **two intentional divergences** recorded (`cue-divergences.md`): cue
   tolerates an invalid pattern with NO field-to-match (`{[=~"a("]: int}` → `{}`); Kue bottoms
   eagerly (RE2 says the literal is ill-formed regardless of application). Deferred constructs
   (`(?i)`) bottom in Kue but cue/RE2 support them — this is the RX-2a not-yet-implemented feature
   surfaced honestly, not a "Kue-correct" divergence. cert-manager content-identical to cue
   (`jq -S`, exit 0, ~32s) — valid-pattern apps unaffected. Axiom-clean (`{propext, Quot.sound,
   Classical.choice}`). **Sequenced before RX-1c so its `Find*`/`ReplaceAll` arms inherit the
   invalid→bottom contract correct-by-construction.** `Value.lean`, `Eval.lean`, `Lattice.lean`,
   `Order.lean`, `Builtin.lean`.
2. **RX-1c — DONE (2026-06-19).** Submatch + `regexp.ReplaceAll`/`ReplaceAllLiteral`/`Find`/
   `FindSubmatch`/`FindAll`/`FindAllSubmatch` wired through the Pike-VM capture array; the
   `unsupportedBuiltin` deferral arms for the implemented forms removed. The regex family is
   now COMPLETE except RX-2a (in-class `\D\W\S`). See the as-built record in the consolidated
   backlog (HIGH #2 below) — engine layer in the Regex leaf (`findSubmatch`/`find`/`findAll`/
   `findAllSubmatch`/`replaceAll`/`replaceAllLiteral` + Go `Expand` template), dispatch in
   `evalRegexpBuiltin`. Surfaced + FIXED a pre-existing RX-1b bug: the unanchored-search prefix
   was `.any` (RE2 `.` excludes `\n`), so `=~`/`Match`/`Find*` could not cross a newline — now
   a negated-empty class (`unanchoredPrefix`). prod9: the `#Regexp` filter (`regexp.ReplaceAll`)
   exports cue-identical (simple + multiline `${0}${1}` cases); the `filters` PACKAGE still does
   NOT export — its sibling `#Template` filter needs `text/template` (`template.Execute`), still
   unimplemented (honest: NOT a full prod9 unblock). Lands on RX-2b's error contract.
3. **Bug2-3 / Gap-2b (HIGH — the LAST argocd export blocker).** Structural disjunction-arm
   pruning. Design landed (`plan.md` "Slice Bug2-3 — Gap-2b"); contained primitive (list-meet-
   to-bottom keying, NOT a shape heuristic), well-diagnosed. A whole app exports. Ranks with
   RX-1c (both HIGH, both designed) — sequence by whichever worktree is freer; RX-1c is the
   broad regex/prod9 lever, Bug2-3 the single-app unblock.
4. **D#2 (HIGH, LARGE — structural-cycle detection — NOW DESIGNED, this audit).** `#L:{n,next:#L}`
   errors `structural cycle`; `#List | *null` terminates on the default arm. Spec-mandated,
   currently MISSING (unrolls fuel-deep to garbage). Detection = an ancestor force-stack
   (reusing the `ForceKey` triple as frame identity); terminating-arm = the EXISTING
   `liveAlternatives`/`resolveDisjDefault?` algebra once the cyclic arm bottoms. 2 slices (D#2a
   detection + D#2b terminating-disjunct). Cannot regress real apps (prod9 has ZERO recursive
   defs). See the "D#2 design (implementable)" section below.

**NEW fix-slices from the SC-2/RX-1a/RX-1b Phase-A audit (`a5862df..04eb7de`, 2026-06-19),
ranked into the MED/LOW tail:**

- **RX-2b — DONE (2026-06-19).** See the ranked-#1 entry above for the as-built record. Wired
  `regexParseError?` into all 4 `matchRegex` dispatch sites + a 5th (the pattern-LABEL path via
  `applyEvaluatedStructN`/`patternsRegexError?`); added `BottomReason.invalidRegex`; `!~` bottoms;
  abstract operands/labels stay unresolved. Fixtures shipped; cert-manager content-identical;
  two cue divergences recorded.
- **RX-2c (LOW-MED, tiny).** Cap repeat counts at 1000 (RE2 limit). In `parseRepeatSuffix`,
  reject `m`/`n` > 1000 as `.invalid` (→ `.malformed "invalid repeat count"`), matching cue's
  `invalid repeat count`. Closes both a conformance gap (Kue accepts `a{0,5000}`) and a
  `desugar` blowup/DoS surface (`a{0,100000000}` → giant AST). Pin: `a{0,1001}` errors,
  `a{0,1000}` parses.
- **RX-2a (MED, needs set-complement).** Support `\D`/`\W`/`\S` INSIDE a `[…]` class (the lone
  corpus divergence). Needs class-level set complement (fold the negated perl ranges into the
  class, or carry per-class negation of a sub-set) — `parseClassEscape`'s current `.error`
  arms become real folds. RE2 feature; currently a correct stub. Sequence after RX-1c (the
  capture work) since both touch the regex module.
- **SC-4 (LOW, spec-gap-first).** Hidden-field / let-bound-PLAIN-struct nested values do not
  close on DIRECT def unification (`#A:{_h:{b:int}}; #A & {_h:{b,extra}}` and the let analog)
  where cue closes. cue is INTERNALLY INCONSISTENT (direct-`&` closes, select-then-`&` does
  not), so this is probably a cue eval-strategy artifact, not a spec mandate. **Spec-check
  FIRST** (record in `cue-spec-gaps.md`); only then decide whether to route these through the
  closing twin. Do NOT reflexively match cue. Lowest priority.

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
- **RX-1b — Thompson compile + Pike-VM + re-wire boolean `=~`/`Match`. DONE (2026-06-19).**
  Added to `Kue/Regex.lean`: `Inst` (flat `char`/`any`/`split`/`jmp`/`save`/`assert`/`accept`
  program), `AssertKind`, `NFA`, `compile` (Thompson; `{m,n}` desugared to concat-of-opt via a
  `desugar` pass so the VM has no counters), `NFA.run` (total Pike-VM — ε-closure deduped by pc
  over the fixed program, fuel = `insts.size` exact, no backtracking; carries capture slots for
  RX-1c), `matchRegex` (unanchored RE2 `Match`/`=~` via an implicit lazy `.*?` prefix). Rewired
  FOUR dispatch sites (the audit said 3; `Order.subsumesWithFuel`'s `.stringRegex` arm was the
  4th): `Eval.evalRegexMatch`, `Order.subsumesWithFuel`, `Lattice.meetStringRegexPrim`,
  `Builtin.regexp.Match`. Deleted the old `Value.lean` backtracking block (~L771-1011,
  `stringRegexMatches`/`parseRegexAtom`/`regexMatchHereWithFuel`/`expandFirstRegexGroup` et al.)
  and dropped the now-unused `Init.Data.String.Search` import from `Value.lean`. Gate met: 7
  repros match cue v0.16.1; all existing regex fixtures byte-identical (zero drift); new fixture
  `numeric/regex_re2_repros`; cert-manager content-identical, argocd unchanged (still its
  pre-existing Bug2-3 bottom). Totality: `compile`/`run` total, axioms = only the standard
  Lean foundational set (no `sorryAx`).
- **RX-1c — DONE (2026-06-19).** Exposed the Pike-VM capture array through a pure
  `String → … → Option` engine layer in the Regex leaf — `findSubmatch`/`find`/`findAll`/
  `findAllSubmatch` (leftmost RE2 group spans, rune-indexed) + `replaceAll`/`replaceAllLiteral`
  (Go `Expand` template: `$n`/`${n}`/`$$`, longest-name rule for `$1suffix` vs `${1}suffix`,
  unknown group → empty; zero-width match ADVANCES one rune per Go so it cannot stall). The
  leftmost match START is read off an explicit whole-match wrapper group (the program's own
  slots 0/1 are pinned to offset 0 by the lazy prefix). Wired into `evalRegexpBuiltin`
  (Builtin.lean), removing the `unsupportedBuiltin` arms for the implemented forms; KEPT
  `FindString*`/`FindAllString*`/`Split`/named-submatch as `unsupportedBuiltin` (cue v0.16.1
  exposes NO such function — calling them is a non-function error there — and named captures
  `(?P<…>)` are an RX-1a-deferred parse). The `Find*` family BOTTOMS on no-match (cue raises
  `no match`, NOT Go's nil); invalid pattern → `.invalidRegex` (RX-2b); abstract arg stays a
  `.builtinCall`. **Fixed a pre-existing RX-1b bug** surfaced by the prod9 multiline filter:
  the unanchored-search prefix was `.star false .any`, but RE2 `.` excludes `\n` so the search
  could not cross newlines — replaced with a shared `unanchoredPrefix = .star false (.cls []
  true)` (any char incl `\n`) in both `matchRegex` and `findFrom`. Pins: 27 `native_decide`
  RegexTests (engine layer + cross-newline regressions) + 19 BuiltinTests (dispatch) + fixture
  `builtins/regexp_submatch` (.cue/.expected + FixturePorts) byte-identical to cue across all
  14 fields incl. nested-list `FindAllSubmatch`. Axiom-clean. cert-manager content-identical
  (jq -S, ~32s); argocd unchanged (pre-existing Bug2-3). prod9 HONEST: `#Regexp` filter exports
  cue-exact, but the `filters` package still blocks on `#Template`/`text/template`.

**Worktree: yes.** RX-1b deletes a large block from `Value.lean` (a hot, widely-imported
module) and adds a leaf module — a worktree isolates the multi-file churn (new module +
3 dispatch rewrites + Value deletion) from concurrent slices and keeps `main` shippable
between the three sub-slices. Each sub-slice commits independently (checkpoint discipline).

## D#2 design (implementable) — structural-cycle detection

**Status (2026-06-19, Phase-B spike):** designed, ready to slice. Oracle ground truth built;
the detection lever, the terminating-disjunct handling, the soundness/totality argument, and
the slice plan follow. This is the remaining large structural gap (D#2, HIGH, spec-mandated,
currently MISSING).

### Spec basis (the gate — RE2-style, quote the spec)

The CUE spec mandates dynamic detection: *"Implementations should be able to detect such
structural cycles dynamically."* The validity rule it sets up: *"a node is valid if any of
its conjuncts is not cyclic"* — i.e. a structural cycle is an error UNLESS a conjunct/arm
provides a non-cyclic (terminating) value. So `#L: {n:int, next:#L}` (the sole conjunct is
cyclic) is a `structural cycle` error, while `#List: {head:_, tail: #List | *null}` is valid
— the disjunction's `*null` arm is a non-cyclic conjunct, so the node terminates by taking it.
This is NOT a perf concern routed through the fuel backstop; it is a spec-mandated *value*
(error vs terminated-struct), and the fuel bound must NOT be the thing that fires.

### Oracle ground truth (cue v0.16.1, all probes run; `/Users/chakrit/go/bin/cue`)

| # | Input | `cue` | Kue (current) | Verdict |
|---|-------|-------|---------------|---------|
| 1 | `#L:{n:int, next:#L}` ; `x:#L` | `#L.next: structural cycle` (error) | unrolls fuel-deep to truncated tree | D#2 — Kue wrong (missing detection) |
| 2 | `#List:{head:_, tail:#List \| *null}` ; `y:#List & {head:1}` | `tail` collapses to `null` (terminates) | unrolls fuel-deep, `tail` never collapses | D#2 — Kue wrong (default arm not taken) |
| 3 | `#A:{b:#B}` `#B:{a:#A}` ; `z:#A` | `#B.a: structural cycle` (error) | unrolls fuel-deep (mutual) | D#2 — mutual recursion must also detect |
| 4 | `#D:{a:{b:{c:{d:int}}}}` ; `w:#D` | finite struct (no error) | finite struct (correct) | control — finite-deep must NOT false-positive |
| 5 | `x: x` | `x: _` (reference cycle → `_`) | `x: _` (correct, via `visited` set) | control — reference cycle already handled, do NOT touch |

The differentiator between #1 (error) and #5 (`_`): #5 is a REFERENCE cycle (`x` resolves to
itself with no struct between) handled by the depth-0 `visited`-slot check
(`Eval.lean:2342-2347`, returns `.top`); #1 is a STRUCTURAL cycle (a def body whose field
re-enters the same def through a struct layer) handled by the def-closure FORCE path
(`refDefClosureBody?` → `forceClosureWithConjunct`), which currently has NO cycle tracking. The
two are distinct mechanisms; D#2 adds the second without disturbing the first.

### Root cause (single, in the def-body force path)

A `#Def` whose body needs deferral (`refDefClosureBody?` fires for a nested `depth>0` self-ref
`.struct`, oracle #1's `next: #L`) forces via `forceClosureWithConjunct fuel (frame::outer)
defBody []` (`Eval.lean:2331`). Forcing evaluates the body's fields
(`evalFieldRefsListWithFuel`, the `.struct` arm at `Eval.lean:2898-2905`); the field `next:#L`
is a `.refId` back to `#L`, re-enters the `.refId` arm (`Eval.lean:2314`), hits
`refDefClosureBody?` AGAIN, and re-forces the SAME `(capturedEnv.ids, body)` one fuel tier
down — recursing until `fuel = 0` truncates to `{..., ...}`. The depth-0 `visited`-slot check
(line 2342) is structurally BYPASSED: the closure-force fork at line 2330 returns before the
`visited` branch is ever reached. So there is no ancestor memory on the force path at all.

### The ancestor identity is ALREADY computed — `ForceKey` minus fuel

The sound ancestor identity falls out of existing machinery. `forceClosureWithConjunct` already
keys its memo on `ForceKey = ⟨fuel, capturedEnv.ids, body, useOperands⟩` (`Eval.lean:1418`).
The fuel-free triple `(capturedEnv.ids, body, useOperands)` is EXACTLY "this def-frame being
expanded": `capturedEnv.ids` is the canonical frame-id stack (frame-sharing canonicalizes it —
`pushFrame`/`FrameKey`), `body` is the normalized def body (closed-vs-open already baked in),
`useOperands` is the narrowing. Two forces with the same triple ARE the same def-frame
expansion at different fuel — a structural cycle is precisely a re-entry of an in-progress
triple. So "ancestor" is identified soundly as **the set of `(envIds, body, useOperands)`
triples currently on the force stack** — no new identity scheme, reusing the proven `ForceKey`
soundness argument (the id stack is a canonical proxy for frame contents).

### Detection lever — an ancestor-frame stack threaded through the force path

Add an ancestor stack to `EvalM` state (or thread it as a parameter — see "Representation"
below): `forceStack : List ForceFrameId` where `ForceFrameId = (List Nat × Value × List (List
Field × Bool))` is the fuel-free force triple. `forceClosureWithConjunct`:

1. Compute `frameId := (capturedEnv.ids, body, useOperands)`.
2. **If `frameId ∈ forceStack`** → this force re-enters an in-progress ancestor = a structural
   cycle. Return `.bottomWith [.structuralCycle]` (new `BottomReason` arm) for THIS expansion
   — do NOT recurse. (The "any conjunct not cyclic" rule is handled at the disjunction layer,
   below; a bare cyclic conjunct with no terminating arm surfaces this bottom.)
3. **Else** push `frameId`, recurse (`forceClosureWithConjunctCore`), pop on return.

This fires BEFORE fuel exhaustion: the second re-entry of `#L` (depth-2) is already an ancestor
hit, so detection happens at recursion depth ~2, not at `fuel = 0`. The fuel bound stays as the
backstop for genuinely-unbounded NON-cyclic growth (which a finite spec program never has), but
a true structural cycle NEVER reaches it. Place the check at the single `forceClosureWithConjunct`
entry (not `…Core`) so the memo-hit fast-path and the cycle check share one gate; the memo and
the cycle stack are orthogonal (a memo hit is a *completed* force, never an in-progress one — a
completed force has been popped, so a memo hit can never be a false cycle positive).

**Why the force triple and not the slot index** (contrast with `visited`): the `visited` set is
slot indices within ONE frame — correct for same-frame reference cycles (#5), useless across
def-body expansions (each force pushes a fresh frame). The force triple spans frames, which is
what a structural cycle needs (#1's re-entry is a NEW frame with the same canonical id-stack +
body). Mutual recursion (#3, `#A`→`#B`→`#A`) works for free: `#A`'s force triple re-enters the
stack two hops down, same mechanism — no special mutual-cycle code.

### The terminating-disjunct case (#2 — `#List | *null`)

`tail: #List | *null` must take the `*null` arm rather than unroll the cyclic `#List` arm. The
spec rule — *"a node is valid if any of its conjuncts is not cyclic"* — means: when forcing a
disjunction arm that turns out structurally-cyclic, that arm becomes `.bottomWith
[.structuralCycle]`, and the EXISTING disjunction algebra prunes it. The mechanism already
exists and needs only the cyclic arm to bottom:

- `liveAlternatives` (`Lattice.lean:266`) filters arms via `containsBottom` — a
  `.structuralCycle` bottom arm is dropped exactly like any other bottom arm.
- `resolveDisjDefault?` (`Lattice.lean:285`) then resolves: with the cyclic `#List` arm
  pruned, the surviving `*null` default wins → `tail: null`. The default-mark algebra is
  UNTOUCHED; the cyclic arm simply never survives to compete.

The ORDER subtlety the spike flags: the arms must be evaluated such that the cyclic arm's
re-entry bottoms it BEFORE `resolveDisjDefault?` runs — which is automatic, because forcing
each arm is what triggers the ancestor-stack hit, and `liveAlternatives`/`resolveDisjDefault?`
run on the already-forced arm values. The disjunction-distribution path (`splitDisjConjunct`,
`Eval.lean:2361`) and the `.disj`-arm force already evaluate arms independently; the cyclic arm
under the SAME force-stack ancestor bottoms, the default arm does not. **No new
default-resolution code** — D#2's terminating-arm handling IS the existing default algebra,
once the cyclic arm carries a `structuralCycle` bottom. This is the same shape as D#1a (a
bottom that must PROPAGATE through the comprehension/disjunction algebra rather than vanish).

⚠ One probe the slice MUST run: confirm `*null` is reached. The current code force-recurses the
`#List` arm via `refDefClosureBody?` on `next`/`tail` — once that arm bottoms on the ancestor
hit, verify `liveAlternatives` sees the bottom (it calls `containsBottom`, which must reach a
nested `.structuralCycle` — check `containsBottom`'s fuel cap A#6, the 100-level limit, does not
hide a deep structural-cycle bottom; if it can, raise it or special-case `.structuralCycle`).

### Soundness + totality (gate)

Three obligations, each discharged by the lever's structure:

1. **No false-positive on finite-deep non-recursive nesting** (oracle #4, `#D:{a:{b:{c:{d}}}}`).
   Each nested struct `a`/`b`/`c` has a DISTINCT force triple (different `body`, different
   `envIds`) — none re-enters an ancestor, so no `structuralCycle` fires. The depth is bounded
   by the program's finite AST; the force stack grows to AST depth and pops cleanly. ✓
2. **No interference with reference cycles** (oracle #5, `x:x`). The `visited`-slot check
   (line 2342) is on the NON-closure `.refId` path; `x:x` never reaches `refDefClosureBody?`
   (a bare self-ref with no struct body to defer → `none` from `refDefClosureBody?`, falls to
   the `visited` branch). The force stack is only pushed on the closure path. The two
   mechanisms are disjoint by construction. ✓ (Pin a `native_decide`: `x:x` still → `.top`/`_`.)
3. **Totality** — the force stack is a `List` that grows by one push per force-recursion and is
   bounded: either a triple repeats (→ cycle bottom, no further recursion) or every triple is
   distinct (→ bounded by the finite set of `(envIds, body, useOperands)` reachable from the
   program, which is finite since the AST is finite and `envIds` are drawn from the finite
   frame table). So the recursion terminates BY the cycle check, independent of fuel — fuel
   becomes a pure backstop, never the deciding bound for a cyclic program. No new `partial`; the
   `termination_by (fuel, 5, 0)` measure is unchanged (the check is a `List.contains` guard
   before the recursive call, not a new recursion). ✓

**Representation choice (illegal-states / repo philosophy):** thread the ancestor stack as an
EXPLICIT parameter to `forceClosureWithConjunct`/`…Core` (and the few force call sites), NOT as
mutable `EvalState`. A parameter is lexically scoped to the live recursion — it cannot leak a
stale ancestor across sibling forces (a mutable field would need careful push/pop discipline
that a future edit could break; the parameter makes the scope structural). This mirrors the
`visited : List Nat` parameter already threaded through `evalValueWithFuel` — same pattern, same
rationale (the slice loop's "encode intent in the type/scope, not a flag"). The force-memo
(`ForceKey`) is independent and unchanged: a memo hit serves a COMPLETED (popped) force, never
an in-progress ancestor, so the cycle stack and the memo never alias. ⚠ Memo interaction to
verify in the slice: a `structuralCycle` bottom result must be keyed/cached correctly — it is a
genuine saturated value (not a fuel truncation), so it caches in `satCache` like any bottom;
confirm the bottom is not re-derived per fuel level (it should be `saturated`).

### New `BottomReason` arm + gate

Add `BottomReason.structuralCycle` (parameterize with the def label/path if cheap, for a
spec-shaped message like `#L.next: structural cycle`; a bare arm is acceptable for v1). Wire
its display in `Format`/`Manifest` (the standard bottom-reason rendering path). **Gate:**
byte-identical on ALL existing fixtures EXCEPT the new D#2 repros (which now error/terminate
correctly); cert-manager/argocd content-identical (re-probe READ-ONLY) — and they CANNOT
regress: a read-only sweep of `prod9/infra` (27 `.cue` files) found ZERO self-referential
definitions, so no real-app shape reaches the ancestor-hit path. Detection fires only on a true
ancestor re-entry, which the apps never trigger.

### Fixtures + pins

- **NEW (error cases):** `comprehensions/structural_cycle_struct` (#1, `#L:{n,next:#L}` →
  `next: _|_ structuralCycle`), `…/structural_cycle_mutual` (#3, `#A`/`#B` mutual). Each with a
  `FixturePorts` entry. (Note: the `.expected` records Kue's spec-correct ERROR, matching cue's
  `structural cycle` — record as CONFORMS, both error.)
- **NEW (terminating case):** `comprehensions/structural_cycle_terminating_default` (#2,
  `#List | *null` → `tail: null`), the spec's headline "valid if any conjunct not cyclic" case.
- **Controls (keep green):** a finite-deep struct fixture (#4 — must NOT bottom; add
  `…/deep_finite_struct_no_cycle` if not already covered), and `x:x` (#5 — reference cycle still
  `_`, an existing fixture).
- **`native_decide` pins:** `#L` self-ref → `structuralCycle` bottom at `next`; `#List | *null`
  → `tail` resolves to `null`; finite-deep → no bottom; `x:x` → `.top` (reference path
  untouched); mutual `#A`/`#B` → bottom.

### Slice plan (2 slices; worktree optional)

Splittable at a clean internal seam:

- **D#2a — detection (the error case).** Add `BottomReason.structuralCycle`; thread the
  ancestor force-stack parameter through `forceClosureWithConjunct`/`…Core` + its call sites;
  fire the cycle bottom on an ancestor hit. Wire bottom-reason display. Lands oracle #1/#3/#4/#5
  (error + finite-control + reference-control). Gate: the two error fixtures + the two controls.
  Checkpoint-commit when green.
- **D#2b — the terminating-disjunct case.** Verify `liveAlternatives`/`resolveDisjDefault?`
  prune the cyclic arm and take `*null` (oracle #2); fix `containsBottom`'s fuel cap (A#6) if it
  hides a deep `structuralCycle` bottom (this couples D#2 with the A#6 hardening item — fold it
  in here if it blocks #2). Lands the `#List | *null` terminating fixture + pin.

**Couples with D#1b** (incomplete-guard deferral) only loosely — both touch bottom-propagation
through the disjunction/comprehension algebra, but D#2's bottom is a CONCRETE structural-cycle
error (propagate), not an incomplete deferral. Do D#2 standalone; D#1b can follow.

**Worktree: optional.** D#2a touches `Eval.lean` (the hot module) + `Value.lean`
(`BottomReason`) + `Format`/`Manifest` (display) — a focused multi-file change but not the
large churn RX-1b had. A worktree is reasonable if RX-1c/Bug2-3 are running concurrently;
otherwise `main` is fine (the change is additive — a new bottom arm + a guard, no deletion of a
hot block). Estimate: **2 slices**, contained.

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
