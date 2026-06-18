# Kue Plan

The live implementation roadmap. Kept small, current, and actionable — one focused slice
at a time. The full record of completed slices lives in
[`../reference/implementation-log.md`](../reference/implementation-log.md), retained for
verification; this file holds only where we are and what's next. Distilled 2026-06-18 back
to the live roadmap (history moved to the log + git); a periodic plan-hygiene pass keeps it
lean (see [`../guides/slice-loop.md`](../guides/slice-loop.md)).

## North Star

Kue targets **CUE v0.15 semantics, done correctly**. Where the official `cue` v0.15
binary is buggy, Kue should implement the *correct* behavior, not replicate the bug. The
compatibility target is the language as specified, not bug-for-bug parity with the
reference implementation. See
[`../decisions/2026-06-14-cue-compatibility-target.md`](../decisions/2026-06-14-cue-compatibility-target.md).

## Working Principles

- Use TDD where behavior is testable: write theorem checks or executable examples
  before implementation.
- Keep the semantic model simple before optimizing representation.
- Prefer total functions and explicit semantic values over hidden host-language
  failure.
- Avoid dependencies until they clearly remove more complexity than they add.
- Keep each commit small enough to review, revert, or extend safely. One slice per
  commit; the commit subject mirrors the slice title.
- **Correctness over performance.** A latent unsound result is a Violation even with no
  failing fixture; a perf miss is acceptable. See
  [`../decisions/`](../decisions/).

## Standing Capabilities (what Kue does now)

The semantic core is broad and oracle-checked against `cue` v0.16.1
(`/Users/chakrit/go/bin/cue`). Currently working, cue-exact (modulo the tracked
field-ordering byte-parity gap, #3 in the backlog):

- **Evaluator + lattice.** Total `meet`/`join` over the full `Value` domain; primitives,
  kinds, bounds, regex, struct/list shapes. `Field` is a `structure`. Disjunctions with
  default-mark algebra (unification ANDs default sets; arithmetic/comparison/unary
  resolve-operand-first; nested two-level precedence; equal-default dedup).
  ```cue
  port: int & >0 & <=65535
  port: 8080  // 8080
  ```
- **Closures / cross-package def-meet.** `Value.closure (frame) (body)` carries the
  capture frame so an imported def's body unifies with the use-site *before* its
  cross-frame self/sibling refs resolve. Deep/nested self-ref detection
  (`hasSelfRefAtDepth`) defers `spec: acme: email: Self.#email` and comprehension guards;
  multi-level embed chains (`#ClusterIssuer → parts.#Metadata → attr.#Metadata`) resolve.
  Forcing tier closes imported def bodies at capture.
  ```cue
  import "ex.com/pkg"
  web: pkg.#Def & {name: "web"}
  ```
- **Comprehensions.** Struct (`for k,v in s {…}`) and list (`[for x in xs {x}]`, incl.
  `if` guards, nested/multi/zero-yield, plain+comp interleave). Scalar struct-embedding
  collapse (`{5}`→`5`) at embed-eval, so list-comp bodies and `{5}` shapes work; empty/
  decl-free struct ∩ scalar correctly conflicts.
  ```cue
  out: [for x in [1, 2, 3] {x * 2}]  // [2, 4, 6]
  ```
- **Disjunction defaults under embedding.** Use-site narrowing distributes into every arm
  of an embedded default disjunction, pruning dead arms (a dead default falls through to a
  surviving arm).
  ```cue
  x: (*"a" | "b") & ("b" | "c")  // "b"
  ```
- **Fuel-saturation perf.** Eval count is FLAT across fuel (bracketed monotonic
  truncation counter; truncated values stay fuel-keyed, saturated results go fuel-free).
  `evalFuel = 100`. Frame-id sharing + force-memo (partial).
- **Builtins.** `base64.Encode`, `json.Marshal` (`Kue/Json.lean`), `yaml.Marshal`
  (`Kue/Yaml.lean`), `strings.*`/`list.*`/`math.*` hardcoded namespaces. Multiline
  strings (`"""`/`'''`).
  ```cue
  import "encoding/json"
  out: json.Marshal({a: 1})  // "{\"a\":1}"
  ```
- **Imports / modules.** `cue.mod` discovery, in-module + cross-module (vendored or
  extract-cache) resolution by longest module-path prefix, multi-file package merge,
  transitive loads, package-dir entry (`kue export ./apps`). IO confined to
  `Kue/Module.lean`; `Eval`/`Resolve` stay pure. (Registry/OCI fetch — B3d — deferred; not
  needed for prod9, which is fully on-disk and resolves offline.)
  ```cue
  import "ex.com/pkg"
  out: pkg.#Def & {name: "x"}
  ```
- **CLI.** `kue eval`, `kue export [--out yaml|json] [file|dir]` (stdin or arg), clean
  missing-file diagnostics + exit codes.

**Real-app status** (prod9 infra, read-only oracle):
- **cert-manager: content-identical drop-in, ~92s.** Exports correctly at production fuel.
  (Was ~31s; the link-3/4 fixes route more shapes through the two-pass embed re-eval — SOUND,
  byte-identical fixtures, but slower; see item 7.)
- **argocd: `packs.#Argo` (link 5) UNBLOCKED — content-correct** (4-link chain, 2026-06-18; see
  backlog item 1 + the implementation-log "argocd-packs-argo" entry). `packs.#Argo` and all three
  components content-identical to cue (sorted-key, modulo field-order #3) in the scratch module,
  ~71s (perf-wall-adjacent — item 7). Full `apps/argocd.cue` end-to-end status in the latest
  breadcrumb. cert-manager byte-identical to baseline (no regression).

## Phase-A audit (2026-06-19, batch `24da14d..463f8e1` — B2 CP3-pre/flip + B2.5) — CLEAN

Audit of the B2 family-1 production flip (CP3-pre `b79af85..cf5b53c`, CP3-flip `ee7dfe5..4597dcd`,
B2.5 `b91b4fb`). Build green (96 jobs), zero fixture byte-drift across the whole batch. Focus was
the logic byte-identity cannot cover: the producer-flip openness mapping, the B2.5 unify arm, and
test-migration integrity. **No correctness defect found.** Two fix-slices folded below (one latent
guard, one end-to-end test-gap fill — both LOW).

VERDICTS:
- **Producer-flip mapping — all sites correct.** `parsedFieldsBaseValue`/`parsedFieldsValue`
  (`Parse.lean:508,532`): no-`...` ⇒ `.regularOpen`, explicit `...` ⇒ `.defOpenViaTail (some tail)`.
  `mergeSourceValues []` (`Runtime.lean:59`) and the comprehension/dynamicField re-emits
  (`Eval.lean:2127,2193`) ⇒ `.regularOpen none []` (open, correct). `bindImports`
  (`Module.lean:161`) preserves the existing coherent triple verbatim on the struct arm,
  `.defClosed` on the non-struct wrap. `evalConjStandard`/`closeEmbeddedOver`/the
  `forceClosureWithConjunct` arms thread `.ofBool open_`; `evaluatedStructOperand?`
  (`Eval.lean:1381`) maps `.defOpenViaTail → false` (no reopen on splice), all else
  `openness.isOpen`. All correct. `mkStruct`'s `coherentTail` is the safety net at every site:
  `tail = some _ ↔ .defOpenViaTail` is enforced post-construction, so a caller cannot build an
  incoherent openness/tail pair even if it passed the wrong openness.
- **B2.5 `mergeStructN` composition arm — correct.** Field order: tail-bearing side is the base
  (left when both have tails), matching cue (oracle-confirmed `{a:5,...}&{[string]:int}` and the
  reverse both give `{a:5}`-open). `leftPatterns ++ rightPatterns` without cross-side dedup is
  fine: `mkStruct` dedups the stored list via `dedupPatterns`, and `applyPatternsToFieldsWith`
  applying a duplicate pattern is idempotent (meet of a constraint with itself). The
  `mergedTail = none` trailing branch IS genuinely unreachable (the arm is entered only with ≥1
  tail; the no-tail combinations are arms 1/5/6/7) and bottoms defensively — total, justified.
  Pattern-violation edge (matched field bottoms, struct survives open) oracle-confirmed and pinned
  (`mergeStructN_pattern_tail_field_conflict`). Both orders + multi-pattern + both-tails-remeet are
  `native_decide`-pinned in LatticeTests.
- **Test-migration integrity — clean, no adapted-to-pass.** Sampled StructTests/EvalTests
  produced-output literals: every `true→.regularOpen none []`, `false→.defClosed none []`,
  `structTail fields t→.defOpenViaTail (some t)` migration preserves the exact field list; only the
  openness encoding changed. The one authorized divergence (pattern dedup, TwoPassTests) is
  oracle-confirmed cue-correct and recorded, not smuggled to the buggy legacy output.
- **`ManifestValue.struct` untouched.** The Manifest diff collapsed the 5 `Value.struct*` INPUT
  arms into one `.struct fields _ _ _`; the OUTPUT `.ok (.struct fields)` (= `ManifestValue.struct`)
  is byte-identical. Confirmed.
- **Illegal-states / totality — strong.** `StructOpenness` is a 3-state sum (no bool×bool nonsense);
  `mkStruct`+`coherentTail` make the incoherent `(tail, openness)` pairs unconstructable. The
  `.struct × .struct` meet routes entirely through `mergeStructN` (8 exhaustive tail/pattern arms,
  no catch-all `_` swallowing the struct). No `partial def`, no `sorry` introduced.

### Fix-slice B2-A1 — `applyEvaluatedStructN` pattern+tail tail-drop (LOW — latent, currently lossless)

`applyEvaluatedStructN` (`Eval.lean:330`) routes the patterns-present case through
`meet (mkStruct [] openness none patterns) (mkStruct fields .regularOpen none [])`, which DROPS the
`tail` argument. With B2.5, `mergeStructN` now PRODUCES structs carrying both patterns AND a tail,
so a re-evaluated pattern+tail struct (via `evalValueCoreWithFuel:2115` / `evalStructRefsM:2752`)
loses its real tail. **Currently lossless** because the only tail a parsed struct can carry is the
bare `...` = `.top` (cue v0.16.1's grammar REJECTS typed ellipsis `...T` — oracle-confirmed parse
error; kue's parser rejects it identically), and dropping a `.top` tail then re-supplying `some .top`
via `coherentTail` is a no-op. This is a GUARDED ASSUMPTION, not an active bug: it breaks the day
typed-ellipsis support lands. Fix: thread `tail` through the pattern arm —
`meet (mkStruct [] openness tail patterns) (mkStruct fields .regularOpen none [])` (the `mkStruct`
already coheres openness↔tail), and add a `native_decide` pin that a pattern+tail value round-trips
its tail through `applyEvaluatedStructN`. Pairs naturally with any future typed-ellipsis slice.

### Fix-slice B2-A2 — end-to-end fixture for the reverse-order B2.5 arm (LOW — test-gap fill)

The two B2.5 fixtures (`pattern_tail_unify`, `multi_pattern_tail_unify`) both exercise the SAME
orientation (patterns-on-LEFT × tail-on-RIGHT). The `leftHasTail` branch of the B2.5 arm
(tail-on-LEFT × patterns-on-RIGHT, baseFields = leftFields) and the both-tails+patterns path are
pinned only by `native_decide` LatticeTests, not end-to-end. Oracle-confirmed cue-correct:
`{a: 5, ...} & {[string]: int}` → `{a: 5}` (open), `{[string]: int, ...} & {a: 5, ...}` → `{a: 5}`.
Add two `testdata/cue/definitions/{tail_pattern_unify,both_tails_pattern_unify}` pairs +
FixturePorts entries so the reverse base-ordering is locked at the observable layer too.

## Phase-A audit (2026-06-18, slice `114eba8` argocd link 3/4) — VIOLATION found

Audit of the link-3/4 slice (`Eval.lean` two-pass gate depth/`.listComprehension`;
`Parse.lean` open-struct-with-embeds collapse). PART A correctness: ONE regression
(VIOLATION). PART B perf: regression is REDUNDANT-dominated (cheap fix exists).

- **VIOLATION (HIGH — fix-slice 0 below).** Fix 2's parser collapse silently CLOSES an
  open definition. `parsedFieldsValue` now drops the `...` tail for any def with
  comprehensions/embeds, returning the `.structComp open_=true`. But
  `normalizeDefinitionValueWithFuel` (`Normalize.lean:13-19`) hard-sets the `.structComp`
  arm to `open_ := false` — it IGNORES the incoming `open_` flag — so a def declared open
  via `...` is closed, and an extra field at the use site now bottoms. Bisected old/new/cue
  (`/tmp/kue-parent` @ `6667a7e`): `#D: {e, ...}` then `#D & {c}` → OLD `{a,c}` = cue;
  NEW bottoms. NOT embed-specific: `#D: {if true {b}, ...}` (comprehension + `...`, no
  embed) regresses identically. Non-def open structs unaffected (they stay open without
  normalize). The committed fixtures missed it because every use site only NARROWS existing
  fields, never ADDS an extra one past the `...`. This is real-app-relevant: prod9 `#Def`s
  are routinely `{embed; …; ...}` and consumers add fields. Soundness claim "byte-identical
  fixtures" held only because the fixtures didn't cover the open-accepts-extra shape.
- **Gate over-fire:** value-safe. Pass-2 re-eval is idempotent on already-resolved embedded
  fields; over-firing costs perf only, never a wrong value (probed deep/nested/multi-depth
  embed-label reads — all cue-exact). The `no-over-fire on nested unrelated label` pin tests
  the `labels.contains` guard, not the depth guard — sound but narrow; a depth-mismatch pin
  would strengthen it (LOW).
- **Dead-OR-branch: GONE.** Fix 1 removed the `… || refsSelfEmbeddedLabel … (.refId id)`
  recursion outright (the `.selector (.refId id) label` arm is now a plain conjunction). The
  backlog "Dead OR-branch `Eval.lean:97`" entry under item 8 is STALE — delete it.
- **Self-ref scanner consistency: OK.** All three scanners (`refsSelfEmbeddedLabel`,
  `hasSelfRefAtDepth`, `defBodyHasSiblingSelfRef`→`hasSelfRefAtDepth`, `bodyNeedsDefer`→
  former) now carry the `.listComprehension` arm transitively. No remaining gap.

### Fix-slice 0 — `def-open-tail-closedness` (HIGH — correctness regression) — DONE
LANDED. Chose neither (A) nor (B) literally — (A) "honor `open_`" alone over-opens a no-`...`
def because ONE bool cannot encode three states (regular-open, def-open-via-`...`, def-closed),
and (B)'s `.conj` split reintroduces the `#ListenerSet` bottom. Took the principled
illegal-states-unrepresentable route: added a SECOND flag `hasTail : Bool` to `.structComp`
(`Value.lean`). `open_` stays the regular-host openness (eager arm honors it); `hasTail` records
the explicit `...` and `normalizeDefinitionValueWithFuel` sets the def body's openness from it
(`open_ := hasTail`). Regular structs never pass normalize, so they stay open. Threaded the field
through all 42 `.structComp` sites + test literals. New module fixture
`testdata/modules/def_open_tail_addfield` (open-def-add-field accepted) + 3 EvalTests source pins
(open admits, closed-no-`...` REJECTS — no over-open, regular stays open). Verify: build 86 jobs,
`fixture pairs ok` (zero drift), shellcheck clean; cert-manager content-identical to cue (~88s);
argocd link 3 byte-identical pre-fix vs FIX-1 (worktree bisect) — no link-2/3/4 regression. See
implementation-log "def-open-tail-closedness".

## Phase-A audit (2026-06-18, batch `6ad6033..7898cff` — def-open-tail + Pass-2 + argocd link-5)

Audit of the 6-commit batch since slice `114eba8`: `6ad6033` (def-open-tail `hasTail`),
`2d87b8e` (Pass-2 selective re-eval), `8ce2462`/`6436d08`/`14994e6`/`7898cff` (argocd link-5
sub-fixes 1-4). Build green (86 jobs). Findings ranked; folded into the backlog as fix-slices
A1-A4.

- **A1 (HIGH — latent soundness hole, perf-change-induced).** The Pass-2 selective re-eval
  (`2d87b8e`) rests on a soundness claim — "the transitive closure is sound by construction" —
  that has a hole: both `selfReferencedLabels` (`Eval.lean:185`) and its boolean twin
  `refsSelfEmbeddedLabel` (`Eval.lean:99`) recurse through `selector/index/unary/binary/conj/
  disj/interpolation/struct/structTail/structComp/list/listTail/comprehension/listComprehension/
  dynamicField` but END in a catch-all (`_ => []` / `_ => false`) that SILENTLY SWALLOWS
  `builtinCall` (and `embeddedList`, `structPattern`, `structPatterns`). A `Self.<embedded-label>`
  read nested inside a builtin arg (`count: len(Self.#x)`, `[Self.#a] passed to a builtin`) is
  therefore INVISIBLE to both. Consequence: a static field whose only embedded-label dependency is
  builtin-wrapped is NOT in the closure → Pass-2 reuses its STALE Pass-1 value (wrong). The gate
  twin shares the blind spot (pre-existing), but `2d87b8e` is what makes the SELECTOR omission
  bite: pre-`2d87b8e`, once the gate fired (via any sibling) ALL static fields were re-evaluated,
  so the builtin-wrapped field got refreshed; now it is selectively skipped. This is exactly the
  "perf optimization that can return a wrong value" the correctness-over-perf decision forbids.
  Fix (cheap, but a behavior change → full verify, NOT inline): add the missing arms to BOTH
  functions — recurse into `builtinCall.args`, `embeddedList` (items/tail/decls), and
  `structPattern`/`structPatterns` field values. Add a `native_decide` pin: an embedded label read
  only via `len(Self.#x)` IS selected / DOES trip the gate. Confirmed reachable on the AST
  (`selfReferencedLabels` descends unevaluated `Field.value`, so `len(Self.#x)` is a live
  `.builtinCall` node at scan time).

- **A2 (MEDIUM — known correctness gap, documented in code).** Sub-fix 3 (`14994e6`) traded a
  cert-manager regression for a hidden-field-bottom gap: the hidden/definition regular-field arm in
  `manifestFieldsWithFuel` (`Manifest.lean:42-55`) uses a SHALLOW `isBottom (Field.value field)`.
  This catches `{#u: _|_}` but NOT `{#u: {x: _|_}}` — cue errors on BOTH (verified, cue v0.16.1).
  So Kue exports `{#u: {x: _|_}}` (drops the hidden field) where cue errors: a real divergence,
  Kue WRONG (not a cue bug → belongs here, not in cue-divergences.md). The shallow check was the
  pragmatic fix because the deep recurse spuriously bottomed unreferenced nested defs in imported
  package bindings. Proper fix: distinguish a hidden field REACHED in the selected value (bottom
  surfaces) from an unreferenced nested definition/package binding (cue is lazy, bottom tolerated) —
  i.e. recurse into the SELECTED value only, not blanket-shallow vs blanket-deep. Add a fixture
  pinning `{#u: {x: _|_}}` → error once fixed.

- **A3 (MEDIUM — soundness rests on an untyped runtime invariant).** Sub-fix 4 (`7898cff`)
  classifies `.disj _ => .defined` in `classifyDefinedness` (`Eval.lean:690`), justified by the
  invariant "an all-bottom disjunction never reaches here — `liveAlternatives` prunes bottom arms,
  so a surviving `.disj` has ≥1 live arm." This is correct under that invariant, but the invariant
  is NOT type-enforced: a `.disj []` or `.disj [all-bottom]` slipping past pruning into a presence
  test would misclassify an absent value as `.defined` (`X != _|_` → wrongly `true`). The operand
  is `evalValueWithFuel`'d before the test, so soundness depends on eval ALWAYS collapsing an
  all-bottom disj to `.bottom`. Tighten: either (a) a smart `mkDisj` that returns `.bottom` when no
  live arm remains (illegal-states-unrepresentable — no empty/all-bottom `.disj` representable
  post-eval), or (b) at minimum a defensive `match` in `classifyDefinedness` that checks for ≥1
  non-bottom arm rather than blanket `.defined`. Option (a) is the principled route. Add a pin: an
  all-bottom disj feeding a presence test classifies `.error`.

- **A4 (LOW — illegal-states / catch-all hygiene).** Two catch-alls flagged by the type-first
  checklist, both currently semantically defensible but each will silently swallow a future
  constructor:
  - `classifyDefinedness` `_ => .incomplete` (`Eval.lean:691`) — a new CONCRETE present-value
    constructor would wrongly classify incomplete. Enumerate the residual forms explicitly (kind,
    bound, ref, refId, selector, index, notPrim, stringRegex, thisStruct, conj, builtinCall, …) so
    a new present constructor forces a compile error here.
  - The shared `selfReferencedLabels`/`refsSelfEmbeddedLabel` catch-all is folded into A1 (its
    omission is a live bug there, not just hygiene).

- **`.structComp hasTail` design (`6ad6033`) — ACCEPTED, with a noted tightening (Phase B).** The
  two-bool encoding (`open_`, `hasTail`) was the right call to ship (it unblocked the HIGH
  regression and all 28 non-test sites were updated with NO catch-all swallowing the new field —
  exhaustiveness verified). But it admits a nonsense state: `open_=false, hasTail=true` (a CLOSED
  struct that has a `...` tail) is representable and never constructed. `hasTail` is a PARSE-TIME
  fact consumed at exactly ONE site (`normalizeDefinitionValueWithFuel`, which sets
  `open_ := hasTail` and thereafter `hasTail` is dead — every other site `_`-ignores it). This is a
  field that matters in only one phase. A tighter design (phase-indexed openness, or folding both
  into a 3-state `StructOpenness` sum: `regularOpen | defClosed | defOpenViaTail`) would erase the
  illegal state. NOT a Phase-A fix (large refactor across 28 sites, not low-risk) — filed as a
  Phase-B tightening candidate. The current code is CORRECT; this is representation hygiene.

- **Test strength — OK.** The four new module fixtures (`def_open_tail_addfield`,
  `list_embed_self_narrowing`, `disj_arm_kill_impossible_field`, `disj_presence_guard`) each ship a
  full multi-file dir + `expected` (auto-discovered by `check-fixtures.sh`; module fixtures need NO
  `FixturePorts` entry — that is only for inline single-file `.cue`/`.expected` pairs). Each is
  backed by `native_decide` EvalTests source pins, including no-over-prune / no-over-open negatives.
  Pass-2 has eval-count pins. Coverage gaps land as the A1-A3 pins above.

## Phase-A audit (2026-06-19 — B2 struct collapse in-progress, batch `4bdc602..6f73286`)

Code-quality audit of the IN-PROGRESS B2 collapse: `67b9596` (B2.1 `StructOpenness` + `Value.structN`
+ `mkStruct`), `b3881c6`+`eff5627` (B2.3 consumer arms + B2.4 single `mergeStructN` meet arm),
`6f73286` (docs). The `.structN` constructor has NO producer yet (B2.2 reverted), so every consumer
arm + `mergeStructN` is DEAD — `lake build` green (96 jobs) + zero fixture drift prove nothing about
their correctness. Validation was **by inspection against the legacy forms** (`4bdc602:Kue/Lattice.lean`
+ `4bdc602:Kue/Eval.lean`), the only check available pre-production. VERDICT: the collapse is CORRECT
— every arm reproduces its legacy form, field-merge order preserved, cross-combinations correctly held
as `.bottom`. NO inline fixes applied (a dead arm is trivially byte-identical; a "fix" risks baking
wrong behavior into the B2.2 test migration — left for B2.2 to own). Findings below are forward-looking
**must-fix-before-B2.2-flips-production** items (the live arms go LIVE in the very next slice).

**`mergeStructN` (highest-risk site) — reproduces all 12 legacy meet arms, arm-by-arm CORRECT.**
- Arm 1 plain×plain (`Lattice.lean:914`): `mergeStructFieldsWith left right` (left base), `applyStructClosedness`
  left-then-right, openness `StructOpenness.meet` ≡ legacy `leftOpen && rightOpen` (both ∈ {regularOpen,
  defClosed} so `meet` = `&&`). ✓
- Arm 2 tail-LEFT (923) ≡ legacy `structTail × struct` (`4bdc602` Lattice:978): leftFields base, `applyTailToExtrasWith
  leftFields tail merged`. ✓
- Arm 3 tail-RIGHT (928) ≡ legacy `struct × structTail` (980): **the flagged `rf++lf` reversal IS preserved** —
  merges `rightFields leftFields` (rightFields=structTail side as base), `applyTailToExtrasWith rightFields tail`,
  exactly as legacy `mergeStructTailWithStructWith` passed `tailFields`(=rightFields) first regardless of operand order. ✓
- Arm 4 tail×tail (933) ≡ legacy (982): tail = `meetValue leftT rightT`, isBottom-check, `applyTailToExtrasWith
  leftFields leftT (applyTailToExtrasWith rightFields rightT merged)` — RIGHT inner, LEFT outer, **identical nesting**;
  `applyTailToExtrasWith` runs on BOTH sides' extras. ✓
- Arms 5/6 single-side patterns (946/955) ≡ legacy `structPattern(s) × struct` (997/1001): patternFields base,
  `applyPatternsClosednessWith … (applyPatternsToFieldsWith leftPatterns merged)`, openness = the pattern side's own
  (the plain struct's openness IGNORED, matching legacy). Unifies single + multi (legacy `[(lp,c)]` vs `patterns`). ✓
- Arm 7 patterns×patterns (964) ≡ legacy `mergeStructPatternsWithStructPatternsWith` (850): left base, patterns
  `leftPatterns ++ rightPatterns`, apply LEFT-inner RIGHT-outer, closedness RIGHT-inner LEFT-outer — **identical**;
  openness `meet` = legacy `&&` (pattern structs never tail-bearing). ✓
- **Cross-combinations PRESERVED as `.bottom`** (the `| _, _, _, _ => .bottom` catch-all, `Lattice.lean:975`):
  `structPattern/structPatterns × structTail` (both orders) — `leftPatterns≠[] ∧ rightTail=some` (or mirror) — match
  no arm 1-7, fall to the catch-all = `.bottom`, exactly as legacy fell to `meetCore`→bottom. NOT accidentally fixed.
  B2.5 owns the flip. ✓
- `meetCore .structN .. → .bottom` (473/474) + the `.structN _ _ none [] × listLike` embed arms (1214/1235/1264/1271,
  restricted to plain-equivalent, tail/pattern → `meetCore`→bottom) reproduce the legacy `.struct × list` / `structTail
  × list`-had-no-arm behavior. The `meetCore (mkStruct …)` scalar-conflict fallbacks (1270/1277) bottom via 473 ≡ legacy
  `meetCore (.struct fields true) scalar` bottom. Same value either way. ✓

**`mkStruct` re-coercion in `mergeStructN` — one DELIBERATE divergence (improvement), flag for B2.2 fixtures.**
`mergeStructN` emits via `mkStruct`, which runs `dedupPatterns` on the result patterns. Legacy did NOT dedup. In arm 7,
`leftPatterns ++ rightPatterns` with a shared identical `(labelPattern, constraint)` pair: legacy stored BOTH, new
stores one. Value-equivalent for the MERGED FIELDS (applying a pattern twice is idempotent; `fieldAllowedBy*` uses
`.any` = set membership), but the OUTPUT struct's `patterns` list differs (deduped). This is the design's deliberate
confluence choice, NOT a legacy-reproduction bug — and cue dedups equal patterns. **B2.2 must add a pin:** `{[=~"a"]:int}
& {[=~"a"]:int}` stores ONE pattern (oracle-check the manifest/re-meet is cue-exact).

**Consumer arms (~30 sites across Eval/Lattice/Normalize/Builtin/Runtime/Resolve/Parse/Module/Format/Manifest) — ALL
reproduce legacy, NO catch-all swallows a live `.structN` on a reachable path.** Representative + highest-risk verified:
- `Normalize` both def-normalizers (`Normalize.lean:44-57, 144-155`, the flagged highest-risk site): `defOpenViaTail`
  left UNCHANGED (≡ legacy `structTail` had no arm → returned verbatim, keeps def OPEN); no-pattern struct-equiv CLOSES
  to `.defClosed` (≡ `.struct → false`); pattern-bearing keeps openness + normalizes patterns (≡ structPattern/s). ✓
- `Eval.classifyDefinedness` (840-841): split `patterns.isEmpty` — `[] → .defined` (≡ struct/structTail),
  `(_::_) → .incomplete` (≡ structPattern/s). ✓
- `Eval.forceClosureWithConjunctCore` (2790/2802): `defOpenViaTail+some+[]` ≡ legacy `.structTail` splice (open `true`,
  rebase tail); `openness+none+[]` ≡ legacy `.struct` splice (`openness.isOpen`); pattern-bearing → `_` catch-all ≡
  legacy `_`. ✓
- `Eval` eval-core (2308) + `evalStructRefsM` (3015): unify the four legacy eval arms (canonicalize → pushFrame →
  evalFields → eval tail/patterns), re-emit via `applyEvaluatedStructN` (`Eval.lean:384`), which for `patterns=[]`
  `mkStruct`s directly (≡ legacy `.struct`/`.structTail` re-emit) and for `patterns≠[]` `meet`s a pattern-only structN
  against a field-only open structN — routing through `mergeStructN` arm 5, byte-equivalent to legacy
  `applyEvaluatedStructPattern(s)`'s `meet (.structPattern [] …) (.struct fields true)`. ✓
- `remapConjRefs` (503-510): fields + tail (`tail.map`) + patterns all remapped at `frameDepth+1` ≡ legacy struct/
  structTail/pattern arms. ✓ `hasSelfRefAtDepth` (1633), `conjStructOperand?` (1410, plain-equiv only),
  `openStructValue`/`closeEmbeddedOver`/`evaluatedStructOperand?` (1455/1496/1511), the two `isStructLike` classifiers
  (1829/1917, `.structN _ _ _ []` covers struct+structTail, patterns→false ≡ legacy), `comprehensionPairs`/select/
  structPairs (661/692/749/1151, fields projection), `containsBottomWithFuel` (189, fields∪tail∪patterns union),
  `Builtin.closeValue`/`lenValue` (17/41), `Resolve` (120/187), `Parse.bindValueAlias` (666), `Module` (79/163),
  `Runtime` (19/91), `Format` (185), `Manifest` (109) — all reproduce legacy. NO finding.

**`StructOpenness.meet` / `mkStruct` / `coherentTail` — CORRECT, theorems REAL (not vacuous).**
- `StructOpenness.meet` (`Value.lean:464`) models legacy open/closed/tail meet: closed dominates (either order),
  `defOpenViaTail` preserved vs any open, two regularOpens → regularOpen. On the {regularOpen, defClosed} subset it
  reproduces `&&` (the legacy plain/pattern openness). `defOpenViaTail` only reachable with a tail (coherence). ✓
- `mkStruct` (`Value.lean:696`) in `Value.lean` (leaf) — clean layering, NO upward dep (`canonicalizeFields` left to
  callers, as B2.1 designed). `coherentTail` enforces `tail = some _ ↔ openness = .defOpenViaTail` (erases the
  `open_`/`hasTail` nonsense state); `dedupPatterns` canonicalizes for confluence.
- The 12 LatticeTests `native_decide` theorems exercise actual coercion/dedup with non-trivial expected `structN`
  literals (`mkStruct_some_tail_forces_defOpenViaTail`, `_some_tail_closed_coerced`, `_defOpenViaTail_no_tail_defaults_top`,
  `_dedups_patterns`, `_keeps_distinct_patterns`, `_always_coherent` over all 6 inputs; `openness_meet_*` full table).
  A regression flips `= true` to a build failure. ✓

### MUST-FIX before B2.2 flips production (fold into the B2.2/CP3 megaslice — these arms go LIVE)
1. **`Order.lean` `subsumes` (`Order.lean:223-262`) has NO `.structN` arm** — a live structN hits `_, _ => false`,
   breaking the test-only subsumption oracle (LatticeTests subsumption pins) the moment B2.2 produces structN. The
   `structN → struct` rename (arity 2→4) FORCES compile errors at Order's `.struct`/`.structTail`/`.structPattern(s)`
   arms, so it CANNOT be silently missed — but B2.2 must MERGE the four subsumption arms into one structN arm
   (dispatch on tail/pattern shape), not just mechanically fix the arity and drop structTail/pattern subsumption logic.
2. **Dedicated `mergeStructN` pins** — `mergeStructN` + every dead consumer arm is currently INSPECTION-ONLY
   (unreachable, so no fixture/theorem touches it). When B2.2 makes structN live, add `native_decide`/fixture pins for:
   the `struct×structTail` `rf++lf` field-order reversal (a `{b:_, a:_, ...} & {c:_}` shape where reversal is
   observable); the `applyTailToExtrasWith`-on-both-sides tail×tail merge; the arm-7 pattern dedup
   (`{[=~"a"]:int} & {[=~"a"]:int}` → one pattern, cue-exact); and the still-`.bottom` cross-combinations
   (`structPattern×structTail` etc.) BEFORE B2.5 flips them — so B2.5's behavior change is a visible diff, not a silent one.
3. **`applyEvaluatedStructN` pattern path** depends on `mergeStructN` arm-5 being correct (it `meet`s through it).
   Pin a pattern-struct eval (`{a: int, [=~"x"]: string}` value) end-to-end once live to confirm byte-parity with the
   legacy `applyEvaluatedStructPattern(s)` output.

These are NOT current bugs (the code is dead); they are the validation B2.2 must carry so a subtly-wrong arm cannot
bake wrong behavior into the ~940-site test-representation migration.

## Phase-A audit (2026-06-19 — B7 implementation + test-org reorg + B4 LatticeTests)

Code-quality audit of batch `7d73bb9..a03ff4a` (B7 impl `bbb00b2`/`c5cbb0e`/`aa5518c`/`969c187`;
test-org `ed314b7`; B4 LatticeTests `a03ff4a`). All four audit fronts pass; one LOW finding fixed
inline.

**B7 implementation — CORRECT, TOTAL, semantics-preserved, theorems REAL.**
- `descendClauses` matches `resolveClausesWithFuel` arm-by-arm: source/guard handled at current
  depth, `+1` per `forIn` for the remainder, `+0` per `guard`, body at accumulated depth. Total —
  structural on the clause list, no fuel, no `partial`. `Value`-non-recursive. Correct leaf
  placement in `Value.lean` (where `Clause Value` is defined); imports unchanged (still only
  `Init.Data.String.Search`), graph acyclic.
- The three migrated scanners (`refsSelfEmbeddedLabelClauses`, `selfReferencedLabelsClauses`,
  `hasSelfRefAtDepthClauses`) reproduce pre-B7 behavior EXACTLY — each instantiation maps the
  `[]`/`forIn`/`guard` arms identically to the hand-coded versions (`Bool` `||`, `List` `++`); the
  A5/A5-followup `native_decide` pins are the regression gate and stay green.
- The three agreement theorems are REAL, not vacuous: `descend_clauses_frame_count_matches_resolve`
  runs the ACTUAL `resolveClausesWithFuel` over 5 clause shapes (incl. mixed for/guard) and asserts
  `resolved refId.depth == clauseChainDepth` via `findInScopes`' genuine outward frame-walk — the
  `| _ => false` arm makes a wrong shape fail the `= true` build check;
  `descend_clauses_agrees_remapConjClauses` runs the real `remapConjRefs` and confirms the body
  refId is reindexed (`id.index == 0`) only when the body shift equals the rebuild's threaded depth;
  `descend_clauses_chain_depth_counts_only_for` pins the fold arithmetic against hand-computed
  literals (incl. `5 + for + guard + for == 7`). Drift becomes a build failure as designed.

**Test-org reorg — coverage TRULY preserved, all modules wired in.** Independently re-counted:
theorem 256→256 (exact NAME set-equality: zero dropped, zero added), `native_decide` 253→253. All
five split modules (`EvalTests`, `ClosureTests`, `EvalPerfTests`, `TwoPassTests`, `EvalTestHelpers`)
imported in `Kue/Tests.lean` — no compiles-but-unrun module. (`def` raw-grep 76→77 is a counting
artifact of `grep "def "`, not a lost test; theorem-name equality is the authoritative check.)

**B4 LatticeTests — all pins oracle-correct vs cue v0.16.1; A2 rule honored.** Re-ran all 6
struct-shape pins through `cue export`/`eval` — every expected value matches. The known-incomplete
arm (`#P:{[string]:int} & #T:{a:5,...}`) confirmed: cue → `{a:5}`, Kue → `_|_` (genuine Kue bug),
documented in the module header + B2 entry and correctly NOT pinned with a passing wrong-`.bottom`
test. The export-vs-constructor split is sound: B2-unstable struct RHS pinned via JSON `export`
(invariant under B2's constructor collapse); B2-stable scalar/kind/bound/regex/list/disj RHS pinned
at constructor level. `exportJsonMatches`/`evalSourceMatches` helpers fail closed.

**Finding (LOW — FIXED INLINE).** `descendClauses` carried a dead `empty : α` parameter: the `[]`
arm returns `onBody depth`, never `empty`, and `empty` is unreferenced in the body — the fold
terminates in `onBody`, so it needs no monoid unit despite the doc's "monoid-like `(empty, append)`"
claim. Removed the parameter, updated the 4 callsites (3 scanners + `clauseChainDepth`), and
corrected the docstring. Build + fixtures green; tightens the signature (general-coding: no dead
params) and removes a misleading doc.

**No other findings.** No catch-all `_` swallowing (B7 adds no `Value` constructor); no totality
gaps; no DRY violations (B7 is itself the de-dup); spec accurate (B7 / item-5 / B4 marked DONE, B2
entry refreshed, two-phase audit marked due — this is it). No CUE divergence (the one mismatch is
Kue-wrong, already tracked as a B2 fix-target, not a divergence).

## Phase-B audit (2026-06-19 #3 — B7 design finalized + light whole-graph sweep)

Third Phase-B pass (post A5 + A5-followup, batch `c3d0089..3a58b53`). PRIMARY: finalized the
B7 design spike — see "B7 design (implementable)" under the B7 backlog entry below. Verdict:
**option (b)** — a single shared `descendClauses` fold in `Value.lean` owning the
`+1-per-forIn`/`+0-per-guard`/body-at-end rule; the three scanners become one-line
instantiations; `clauseFrameShift` is deleted and `remapConjRefs`'s body shift re-derives from
the fold; `resolveClausesWithFuel` is tied to it by an agreement theorem rather than migrated
(it threads scopes, not `Nat`). NOT a `Depth` newtype (the recurring bug is the per-walker
*re-derivation*, not a raw `+1` — a newtype is ~24 sites of churn for no new guarantee, plus a
kernel-reduction cost on the hot resolve path). ONE slice, four fixture-gated commits; behavior-
preserving (existing A5/A5-followup pins are the full regression gate; the two new agreement
theorems are the structural pin).

SECONDARY (light sweep since `bb24953`): the A5/A5-followup changes touched ONLY `Eval.lean`
(the five walkers + new `mutual` blocks), `EvalTests`, `FixturePorts`, and two fixtures — exactly
B7's target surface, no new module, no eval-path change. **No NEW findings.** Confirmed: import
graph unchanged/acyclic; no new dead code, stray `TODO`/`FIXME`/`sorry`; `kue-performance.md`
CURRENT (A5-followup routed through the existing closure-FORCE path — no perf characteristic
changed). One observation, NOT re-filed (already item 5): `EvalTests.lean` is now 2976 lines
(+288 from A5/followup pins) — the test-org pass is increasingly overdue; if it lands before B7,
B7's agreement theorems go in a new `ClauseDepthTests` module.

## Phase-B audit (2026-06-18 #2, whole module graph — post A5 / B1 regression)

Second Phase-B pass, run after Phase A filed A5 (the B1 comprehension-body-remap depth
regression). Whole-graph re-scan with the type-system-first lens. Findings: ONE new
type-tightening fix-slice (**B7**, below — the highest-leverage type win in the graph, and
the root cause A5/B1 are symptoms of); everything else from the prior audits (B1-B6, A5,
item-7 perf, A2-followup) confirmed still-accurate and NOT re-filed. Verified this round:

- **Import graph** still acyclic and sane (`Value` leaf → `Lattice`/`Normalize`/`Resolve`/
  `Order`/`Format` → `Builtin`/`Decimal` → `Eval` → `Runtime` → `Cli`; `Module` over
  `Parse`+`Runtime`). No new module-boundary debt.
- **`remapConjRefs` catch-all** (post-B1, `Eval.lean:484`) — NOW complete. Residual
  `| _, value => value` swallows only scalars (`top`/`bottom`/`bottomWith`/`prim`/`kind`/
  `notPrim`/`stringRegex`/`boundConstraint`), `ref`, `thisStruct`, `closure` — all inert
  under conj-frame remap (no conjunction-frame `.refId` to rebase; `closure` deliberately
  excluded, its refs live in captured-env space). Not a finding.
- **Cleanup hygiene** — no `String.dropRight`/deprecated APIs; no stray `TODO`/`FIXME`/
  `HACK` in `Kue/*.lean`. `compat-assumptions.md` (543 lines) is a structured reference
  doc, not accumulated debt to promote. Nothing to clean inline.
- **Perf guide (`kue-performance.md`) — CURRENT.** Reflects item-7 frame-id divergence as
  THE perf wall, the 31s→92s cert-manager regression, Pass-2 selective re-eval, and the
  fuel-exhaustion-at-scale finding. No edit needed (re-confirmed, second pass).

- **B7 (MEDIUM-HIGH — type-system leverage; A5 + the item-7 frontier are both symptoms).**
  Frame coordinates are an untyped `Nat` (`BindingId.depth`, and the threaded `frameDepth`/
  `depth` parameters). The de Bruijn rule "a comprehension body lives `#forClauses` frames
  deeper than its enclosing scope; `for` pushes one frame, `guard` pushes none" is the
  SINGLE authority encoded in `resolveClausesWithFuel` (`Resolve.lean:52-67`,
  `clauseLoopFrame :: scopes` per `.forIn`), but it is RE-DERIVED BY HAND, independently,
  at every other walker that descends a comprehension body — with no type forcing agreement:
  - `remapConjRefs`/`remapConjClauses` (`Eval.lean:466-473, 534-547`) — recurse the body at
    flat `frameDepth`, ignoring the loop-frame push. This IS A5 (a value rewriter → WRONG
    VALUE). Also subtly wrong for multi-`for`: clause N's source is at `frameDepth+(N-1)`,
    but `remapConjClauses` remaps every clause source at flat `frameDepth` (folded into A5's
    "thread depth through the clause chain" fix).
  - `refsSelfEmbeddedLabel`/`hasSelfRefAtDepth` (`Eval.lean:138-161`) — recurse the body at
    flat `depth` TOO, but here it is DELIBERATELY conservative (a boolean two-pass gate:
    too-shallow over-fires the gate = perf only, never miss). The comment at `Eval.lean:139`
    documents the choice. SOUND by accident-of-direction.
  - `selfReferencedLabels` (`Eval.lean:249-266`) — recurse the body at flat `depth`, and
    here too-shallow can MISS: a `Self.<embedded>` read inside a `for` body sits at
    `depth+#for`, compared `== depth` (`:251`), so the label is not collected → the field is
    not selected for Pass-2 re-eval → reuses its stale Pass-1 value. Same A1-class hole as
    the original builtin-arg miss, reintroduced via comprehension-body depth. NARROW
    (`Self.<embedded-label>` literally inside a `for` body of a static field), but real and
    unsound. Add to A5's fix as a sibling pin, OR fix structurally via B7.
  This is the textbook illegal-states-unrepresentable case: the SAME structural pattern
  (comprehension body recursed at the parent's depth) is benign in one walker, a perf cost
  in a second, and a wrong-value bug in a third — the type gives ZERO signal which. **A
  type-level frame coordinate would have made A5 a compile error:** if the depth threaded to
  a comprehension body were a distinct type from the enclosing depth (or if descending a
  `for` clause were the ONLY way to obtain the deeper coordinate — a `descendForClause :
  Depth → Depth` the body-recursion must consume), then recursing the body at the
  un-descended `frameDepth` would not typecheck. **Fix (own slice, design-spike first):**
  factor the "descend a clause chain, accumulating frame depth" rule into ONE total function
  (`clauseDepthShift : List (Clause _) → Nat`, or a `Depth` newtype whose only `forIn`-
  descent constructor the walkers must route through) and have `resolveClausesWithFuel`,
  `remapConj*`, and the three scanners ALL consume it — so the rule lives once and a future
  walker physically cannot re-derive it wrong. This SUBSUMES A5 (A5 becomes "apply B7's
  shared shift in `remapConj*`") and closes the `selfReferencedLabels` miss above. Sequence:
  land A5's point-fix first (unblocks the wrong value now — never make the user wait), then
  B7 as the structural hardening so the third frame-depth bug cannot happen. NOT inline
  (frame-depth logic + a new abstraction across 5 walkers). Pin: the A5 repro fixture +
  a multi-`for` comprehension-conjunct remap + the `Self.<embed>`-inside-`for` Pass-2
  selection case. Cross-ref: item-7 frame-id divergence is the OTHER untyped-`Nat`-frame
  symptom (frame IDENTITY rather than frame DEPTH); B7 addresses depth, not identity, but
  both trace to frame coordinates being raw `Nat`s the type system doesn't police.

## Phase-B audit (2026-06-18, whole module graph — post A1-A4)

Architecture/refactor/cleanup pass over the full graph (broader than the recent diff),
run after Phase A landed A1-A4. Import graph is acyclic and sane (`Value` leaf →
`Lattice`/`Normalize`/`Resolve`/`Order`/`Format` → `Builtin`/`Decimal` → `Eval` →
`Runtime` → `Cli`; `Module` over `Parse`+`Runtime`). `FieldClass`/`Optionality` are the
model the rest of the code should match (orthogonal axes, smart constructors,
illegal-states-unrepresentable done right). Findings ranked, folded as fix-slices B1-B5
below. Perf guide (`kue-performance.md`) is CURRENT — reflects item 7 frame-id divergence,
Pass-2 selective re-eval, and the fuel-exhaustion-at-scale finding; no edit needed.

- **B1 (HIGH — latent soundness, sibling of A1).** `remapConjRefs` (`Eval.lean:415`,
  the conj-frame-remap that rebases a conjunct's `.refId`s to a merged frame on the
  lazy-conjunction-merge path) ends in `| _, value => value` that SILENTLY SWALLOWS
  `.structComp`, `.comprehension`, `.listComprehension`, `.embeddedList`, `.dynamicField`.
  `.structComp` is the DOMINANT prod9 `#Def` conjunct shape (`{embed; …; ...}`) and
  `.comprehension`/`.listComprehension` carry inner `.refId`s at `frameDepth` that MUST be
  remapped — a swallowed conjunct keeps STALE frame indices after the merge → wrong
  resolution or spurious bottom. Reachable: `remapConjRefs` is invoked on `defTail` / each
  conjunct value/field/alternative/pattern in the merge fold (`Eval.lean:2478` + the
  in-block recursions). Same class as A1 (a catch-all swallowing live constructors on a
  perf/merge path). Fix: add explicit recursing arms for `.structComp` (remap fields at
  `frameDepth+1` + comprehensions), `.comprehension`/`.listComprehension` (remap clause
  sources + body), `.dynamicField` (label+value), `.embeddedList` (items/tail/decls).
  Behavior change → full verify, NOT inline. Add a `native_decide` pin: a `structComp`
  conjunct with a `frameDepth` self-ref remaps correctly across a field-reindexing merge.

- **B2 (MEDIUM-HIGH — headline refactor; subsumes item-8 `StructOpenness`). FAMILY-1 COMPLETE
  (B2.1–B2.5 DONE 2026-06-19); only B2b (structComp collapse) remains.** The five struct
  constructors collapsed to one `Value.struct (fields, openness, tail, patterns)` and the
  pattern×tail cross-combination now unifies (B2.5). Historical diagnosis preserved below. `Value` HAD
  FIVE struct-bearing constructors (`struct`, `structTail`, `structPattern`,
  `structPatterns`, `structComp`) plus `embeddedList`. `meetWithFuel` (`Lattice.lean`)
  carries a 12-arm pairwise matrix (lines 971-1044) over `{struct, structTail,
  structPattern, structPatterns}` — and the matrix is INCOMPLETE: `structPattern×structTail`
  and `structPatterns×structTail` (BOTH orders) have NO explicit arm and fall through to the
  `meetWithFuel` catch-all (`| value, other => meetCore …`, `Lattice.lean:1151`) → `meetCore`
  bottoms all struct combos → `.bottom`. (`structPattern×structPatterns` and its reverse ARE
  now implemented, `Lattice.lean:1015-1034` — the 2026-06-19 LatticeTests slice corrected the
  stale "also missing" claim and PINS that cross-arm as a B2 regression gate.) Confirmed
  against cue v0.16.1 (`LatticeTests.lean` module header records the exact repro):
  `{[string]: int} & {a: 5, ...}` → cue `{a: 5}`, kue `_|_` (WRONG, Kue bug — not a cue
  divergence). These two missing arms are documented in `LatticeTests.lean` but deliberately
  NOT given a passing test (no expected-fail marker exists; A2 rule forbids pinning the wrong
  `.bottom`). Since `structPattern`/`structPatterns` carry an `open_` and are valid CUE
  (`{[string]: T, ...}`), meeting an open pattern-struct with a tail-struct silently bottoms
  where CUE unifies — a latent correctness hole the representation makes EASY to leave
  incomplete. Fix (own slice,
  large): collapse the struct constructors into ONE normalized `struct` carrying
  `(fields, openness, tail : Option Value, patterns : List (Value × Value))`, where
  `openness` is the 3-state `StructOpenness` sum (`regularOpen | defClosed | defOpenViaTail`)
  that item-8 already proposed — so the `open_`/`hasTail` nonsense state AND the missing meet
  cross-combinations are BOTH erased by construction, and the 12-arm matrix becomes one merge.
  This is the single biggest type-system-leverage win in the graph. ~28 `.structComp` sites +
  the 5-ctor match sites across `Lattice`/`Eval`/`Normalize`/`Resolve`/`Order`/`Manifest`/
  `Format`/`Parse` — design-spike first (normalization invariant + smart constructor), then a
  mechanical multi-commit migration. Supersedes the standalone item-8 `StructOpenness` entry
  (fold it into this). Byte-identical fixtures required + flip the documented
  `LatticeTests.lean` missing-arm entries into passing pins (`structPattern×structTail`,
  `structPatterns×structTail`, both orders, unify not bottom); the already-correct struct-arm
  pins in `LatticeTests.lean` (struct×struct open/closed, tail×tail, pattern×pattern,
  pattern×patterns, patterns×patterns — source-level JSON `export`, so B2-representation-stable)
  are the regression gate the migration must keep green.

  ### B2 design (implementable) — audited 2026-06-19 (Phase-B #4)

  Two FAMILIES of struct constructor exist and must be treated separately; the diagnostic
  above conflates them. (1) The **evaluated** forms `struct`/`structTail`/`structPattern`/
  `structPatterns` — these reach `meetWithFuel` and are the 12-arm matrix. (2) The
  **pre-eval** form `structComp` (carries unexpanded comprehensions + the two-bool
  `open_`/`hasTail` nonsense), which `evalValueCoreWithFuel` (`Eval.lean:2222`) expands and
  re-emits as one of the family-(1) forms. `structComp` NEVER reaches the meet matrix
  (`meetCore` bottoms it; lines 466-467 are dead-but-defensive). So B2 is two orthogonal
  collapses, and they should be SEPARATE slices.

  **Target representation (family 1 — the meet-bearing struct).** One constructor:
  ```
  | struct (fields : List Field) (openness : StructOpenness) (tail : Option Value)
           (patterns : List (Value × Value))
  ```
  with
  ```
  inductive StructOpenness | regularOpen | defClosed | defOpenViaTail
  ```
  Map of the 4 old forms onto it (tail and patterns are ORTHOGONAL axes — the old type
  could not carry both, which is exactly why `structPattern×structTail` had no arm):
  - `struct fields open_`            → `struct fields (boolOpen open_) none []`
  - `structTail fields tail`         → `struct fields .defOpenViaTail (some tail) []`
  - `structPattern fields lp c o`    → `struct fields (boolOpen o) none [(lp,c)]`
  - `structPatterns fields ps o`     → `struct fields (boolOpen o) none ps`

  where `boolOpen : Bool → StructOpenness := fun b => if b then .regularOpen else .defClosed`.
  This is exactly the `open_`/`hasTail` two-bool collapse item-8 proposed: today `structTail`
  IS the "`...`-tailed" form (def-open-via-tail) and the old `open_ : Bool` on the other three
  conflated regular-open with def-open. `StructOpenness` makes the three states
  (`regularOpen` = no-`...` regular struct, open; `defClosed` = no-`...` definition, closed;
  `defOpenViaTail` = explicit `...`, open-and-tail-bearing) mutually exclusive and total. The
  illegal states erased: (a) a value that is BOTH a tail-struct AND a pattern-struct could not
  be represented before (forcing the missing arm); now it is `tail = some _ ∧ patterns ≠ []`,
  fully representable and meetable. (b) the `open_=true ∧ hasTail=true` vs `open_=false ∧
  hasTail=true` ambiguity disappears — `defOpenViaTail` is one state.

  **One constructor, NOT a tighter encoding.** Rejected: a `StructShape` payload struct
  hoisted out of `Value`, or GADT-style indexing on presence of tail/patterns. Reason: the
  perf carve-out — `Value` deliberately omits `DecidableEq` (kernel reduces it slowly; behavior
  pinned by `native_decide`). A flat 4-field constructor adds NO kernel-proof burden and keeps
  the recursor shape simple; an indexed family would force motive elaboration on the hot meet
  path. Flat fields + a smart constructor is the illegal-states-unrepresentable win at zero
  perf cost.

  **Smart constructor + normalization invariant.** `mkStruct (fields) (openness) (tail)
  (patterns) : Value`, the ONLY way construction sites build the form. Invariants it enforces:
  - **`patterns` normalized**: this replaces `patternStructValue` (`Lattice.lean:727`), which
    today already picks `struct`/`structPattern`/`structPatterns` by list length — that length
    dispatch VANISHES (one constructor regardless of 0/1/n patterns). `mkStruct` keeps patterns
    in a canonical order and drops duplicates so meet is confluent.
  - **tail/openness coherence**: `tail = some _ ⟹ openness = .defOpenViaTail`, and
    `openness = .defOpenViaTail ⟹ tail = some _` (default `some .top` for a bare `...`). The
    smart constructor either derives openness from the tail or rejects the incoherent pair.
    This is the one pair that must NEVER be constructable: a `defOpenViaTail` with `tail =
    none`, or a `some tail` with `regularOpen`/`defClosed`.
  - **field ordering**: unchanged — `canonicalizeFields` already owns this; `mkStruct` calls it.

  **The single meet merge.** The 12 arms (`Lattice.lean:971-1044`) collapse to ONE arm
  `| .struct lf lo lt lp, .struct rf ro rt rp =>`. Algorithm, composing the EXISTING helpers
  (no new merge logic — the arms already factor through `mergeStructFieldsWith`,
  `applyTailToExtrasWith`, `applyPatternsToFieldsWith`, `applyPatternsClosednessWith`):
  1. `mergeStructFieldsWith` the two field lists → `none` ⇒ `.bottom`.
  2. tail: `meetTail lt rt` (both `none`→`none`; one `some`→propagate and apply via
     `applyTailToExtrasWith` to the other side's extras; both `some`→meet the tails, bottom if
     bottom). 
  3. patterns: `lp ++ rp` then `applyPatternsToFieldsWith` over the merged fields, then
     `applyPatternsClosednessWith` for the closed case.
  4. openness: `meetOpenness lo ro` (closed dominates; `defOpenViaTail` ⊓ `regularOpen` =
     open-with-tail; two opens stay open).
  5. `mkStruct mergedFields mergedOpenness mergedTail mergedPatterns`.
  The previously-MISSING cross-combinations now unify BY CONSTRUCTION: `structPattern×structTail`
  is just `lp = [(p)]` meeting `rt = some _` — step 2 applies the tail, step 3 applies the
  pattern, no arm to forget. This is the correctness payoff: `{[string]: int} & {a:5, ...}` →
  `{a:5}` (cue v0.16.1 confirmed), not `_|_`.

  **BEHAVIORAL split (critical).** The constructor collapse is byte-identical for every arm
  that EXISTS today; the cross-combination fix is a `bottom→unify` BEHAVIOR change. So B2 is
  NOT purely byte-identical and the migration MUST separate them:
  - The collapse slices keep all existing `LatticeTests` + struct fixtures green (byte-identical
    gate).
  - The FINAL slice adds the new arm's behavior and NEW oracle-checked fixtures for the four
    now-fixed cross-combinations (`structPattern×structTail`, `structPatterns×structTail`, both
    orders), flipping the documented-but-unpinned `LatticeTests` entries into passing pins.

  **Migration plan — MULTI-SLICE (5 slices).** Site counts (grep, 2026-06-19) — family-1 forms
  `struct`/`structTail`/`structPattern`/`structPatterns` and pre-eval `structComp`:
  `Lattice` struct20/tail8/pat10/pats10/comp2; `Eval` 48/29/14/15/comp29; `Normalize`
  6/0/2/4/comp4; `Resolve` 4/4/2/4/comp4; `Order` 4/5/9/9/comp0; `Manifest` 6/1/1/1/comp2;
  `Format` 1/1/1/1/comp1; `Parse` 2/4/3/3/comp4; `Value` tail1/pats1/comp1; `Builtin`
  2/1/3/2; `Runtime` 3/1/1/1. The `structComp` collapse (B2b) is INDEPENDENT and large enough
  (~44 sites) to be its own slice sequence; sequence:
  - **B2.1 — introduce `StructOpenness` + `mkStruct` + new struct ctor; keep old 4 ctors. DONE
    (2026-06-19).** Landed as specced, with these concrete choices:
    - **Naming/coexistence:** the new ctor is `Value.structN` (NOT `struct` — the old `struct`
      still exists). B2.4 deletes the four old forms and renames `structN → struct`. All match
      sites that gained a dead arm reference `.structN`.
    - **`StructOpenness`** (`Value.lean`, before `BindingId`): `regularOpen | defClosed |
      defOpenViaTail`, `deriving Repr, BEq, DecidableEq`. Helpers `isOpen`, `ofBool` (the
      design's `boolOpen` — named `ofBool` as it's a `StructOpenness` member), `meet` (the
      design's `meetOpenness`: closed dominates, `defOpenViaTail` preserved vs any open).
    - **`Value.structN fields openness tail patterns`** added after `structPatterns`. Tail is
      `Option Value`; patterns `List (Value × Value)` — both axes carried together (the fix for
      the missing `structPattern×structTail` arm). `valueTag` = 31.
    - **`mkStruct` lives in `Lattice.lean`** (next to `patternStructValue`, NOT `Value.lean`):
      the design said `mkStruct` calls `canonicalizeFields`, but that lives in `Eval` (downstream
      of both `Value` and `Lattice`) — a layering violation. **Divergence from the design,
      resolved by philosophy:** field ordering stays the CALLER's responsibility (callers already
      run `canonicalizeFields` before `patternStructValue` today), so `mkStruct` owns only the two
      invariants it CAN enforce locally: pattern dedup (`dedupPatterns`) + tail/openness coherence
      (`coherentTail`: `tail = some _ ↔ openness = .defOpenViaTail`, the never-constructable pairs
      normalized away). B2.2 keeps the caller-canonicalize contract.
    - **Theorems** (`LatticeTests.lean`, `native_decide`, all via `BEq` `==` — `Value` has no
      `DecidableEq` by the perf carve-out, so propositional `=` is undecidable): `mkStruct` forces
      `defOpenViaTail` on any `some` tail, defaults bare `...` to `some .top`, keeps non-tail
      openness tail-free, dedups + preserves distinct patterns (idempotent); `structNTailCoherent`
      holds for all six openness×tail inputs; `StructOpenness.meet` closed-dominates / tail-preserved
      / open-idempotent.
    - **Dead arms (5 sites)** — `structN` has no producer in B2.1, so each is dead-but-required,
      with a `-- B2.1 dead arm … filled in B2.3` comment. B2.3 MUST revisit each:
      `Lattice.meetCore` (→ `.bottom`, the bottoms-everything fallthrough — real merge lands in
      B2.4's `meetWithFuel`); `Format.formatValueWithFuel` (fields ++ patterns ++ optional tail in
      `{…}` — mirrors the four legacy arms); `Manifest.manifestWithFuel` (manifest fields only,
      tail/patterns/openness dropped — mirrors legacy); `Eval.classifyDefinedness` (→ `.defined`
      like `struct`/`structTail` — **B2.3 caveat:** old `structPattern`/`structPatterns` are
      `.incomplete`, so a PURE pattern-struct `structN` must be reconciled then);
      `Eval.valueTag` (= 31, total tag table). Every OTHER struct-family match site uses a
      catch-all and needed no change — confirming the B2.1/B2.3 boundary is clean.
    - Verify: `lake build` green, `scripts/check-fixtures.sh` → `fixture pairs ok` (ZERO drift),
      no shell changed. The design's `meetTail` helper is NOT yet needed (it's a B2.4 merge concern)
      — deferred to B2.4 rather than added dead.
  - **B2.3 — migrate MATCH sites (CONSUMER arms). DONE (2026-06-19, commits `b3881c6` +
    `eff5627`).** Ordering correction: the design's listed B2.2→B2.3→B2.4 order is UNSAFE
    (producing `structN` before consumers handle it makes catch-alls + the `meetCore`
    `.bottom` dead-arm mishandle live `structN` → drift). The slice was re-sequenced
    **consume-before-produce**: B2.3 (match sites) + B2.4 (the single meet arm) FIRST, with
    `structN` still unproduced so every arm is dead and byte-identity is trivial. Landed:
    explicit `.structN` arms at every struct-family match site across `Lattice`
    (`containsBottomWithFuel`), `Eval` (`refsSelfEmbeddedLabel`, `selfReferencedLabels`,
    `remapConjFields`, `selectEvaluatedField`/`Index`, `classifyDefinedness` — split
    `patterns⇒.incomplete` / no-patterns`⇒.defined`, `comprehensionPairs`,
    `conjStructOperand?`, `openStructValue`, `closeEmbeddedOver`, `evaluatedStructOperand?`,
    `hasSelfRefAtDepth`, `defBodyHasSiblingSelfRef`, the two `isStructLike` body
    classifiers, the package-binding `pkgFields` lookups, `meetEmbeddingsWithFuel`,
    `expandClausesWithFuel`, `forceClosureWithConjunctCore`, `evalStructRefsM`, the eval arm
    via `applyEvaluatedStructN`), `Builtin` (`closeValue`, `lenValue`), `Runtime`
    (`formatTopLevel`, `lookupField?`), `Normalize` (both def-normalizers — the highest-risk
    site: `defOpenViaTail` left verbatim like the legacy missing `structTail` arm, no-pattern
    closes, pattern keeps openness), `Resolve` (both ref-resolvers), `Parse` (`bindValueAlias`),
    `Module` (`parseDeps`/`versionOf`/`moduleFieldValue`/`bindImports`). (`Manifest`/`Format`
    already had theirs from B2.1.) **`mkStruct`/`dedupPatterns`/`coherentTail` MOVED from
    `Lattice` to `Value`** so `Parse`/`Normalize`/`Resolve` (which import only `Kue.Value`)
    can reach the sanctioned constructor — they have no Lattice dependency (B2.1 already made
    field ordering the caller's job).
  - **B2.4 — the single `.structN×.structN` meet arm. DONE (2026-06-19, `b3881c6`).**
    `meetWithFuel` gained ONE `.structN, .structN` arm delegating to `mergeStructN`, which
    reproduces ALL 12 legacy arms by dispatching on tail/pattern shape and preserving each
    arm's field-merge ORDER (notably `struct×structTail` merges `rf ++ lf` REVERSED) +
    closedness, emitting `structN` via `mkStruct`. The legacy-missing
    `structPattern/structPatterns × structTail` cross-combinations stay `.bottom` (B2.5
    flips them). `.structN × listLike` embedding + the `embeddedList` inner matches gained
    plain-struct-equivalent (`structN _ _ none []`) arms. Old 12 arms + 4 ctors NOT yet
    deleted (that's CP3, gated on the test migration below).
  - **B2.2 — flip CONSTRUCTION to produce `structN`. DONE (2026-06-19, CP3-pre + CP3-flip;
    the family-1 struct collapse is COMPLETE — 5 ctors → 1, except `structComp` = B2b).**
    (Phase-A 2026-06-19
    audited every dead `.structN` arm + `mergeStructN` by inspection vs the legacy forms —
    ALL reproduce legacy, see that audit section for the arm-by-arm verdict. THREE
    must-fix-before-flip items it raised: (1) `Order.subsumes` has no structN arm — MERGE the
    4 subsumption arms, don't just fix the rename arity; (2) add dedicated `mergeStructN` pins
    once live — the `rf++lf` reversal, tail×tail both-sides extras, arm-7 pattern dedup, and
    the still-`.bottom` cross-combos before B2.5; (3) pin `applyEvaluatedStructN`'s pattern
    path end-to-end.) The production flip
    (`Parse.parsedFieldsBaseValue`/`parsedFieldsValue`, `Runtime.mergeSourceValues`, the
    `Eval` eval/force/embedding/comprehension/dynamicField re-emit sites, `Module.bindImports`
    wrap) is WRITTEN AND SEMANTICALLY VALIDATED — with it applied, every `testdata/cue`
    fixture produces the correct output via direct `kue`/`kue eval` runs (incl. the
    `struct_embedding_*` + all `modules/*` fixtures, after adding `structN` arms to the
    `Module` field-extractors). **It cannot land green**, because the flip changes the
    INTERNAL `Value` representation (`struct`→`structN`) and the test suite (~17 files, ~940
    sites: `EvalTests`/`ClosureTests`/`StructTests`/`FixturePorts`/`ResolveTests`/… pin the
    OLD representation via `== .struct […] true` literals and construct legacy forms as
    inputs). `lake build` AND `scripts/check-fixtures.sh` both fail (the harness builds
    `Kue.Tests.FixturePorts`). So B2.2 is INSEPARABLE from the test-representation migration.
  - **B2.2/CP3-pre — test-only pre-migration to `structN`. DONE (2026-06-19, commits
    `b79af85`..`8923b51` on `main`).** The SAFE pre-migration: `Order.subsumes`'s eight
    struct-family arms MERGED into one `.structN, .structN` arm (`structNSubsumesWithFuel`,
    dispatch on expected then actual tail/pattern shape — reproduces every legacy arm
    EXACTLY; `subsumes` has NO production caller, grep-confirmed, so the structN-only arm
    changes no production behavior). Constructed-INPUT test literals migrated to `.structN`
    (no producer flip, no ctor delete, no rename): **OrderTests** (58 subsumes inputs),
    **StructTests** (all meet/format inputs+expecteds, ~148 sites incl. nested), **FixturePorts**
    (90 pure-op meet/close/format/manifest inputs across the 43 producer-free ports — the 85
    producer ports / 147 ctors LEFT for the flip), **ManifestTests**/**YamlTests**/**ListTests**/
    **BuiltinTests** (83 inputs; `ManifestValue.struct` collision guarded — only `Value.struct`
    migrated). ~360 constructed-input sites turned test-gated. `mergeStructN` pins added to
    LatticeTests (must-fix item 2): field-order reversal (both orders), tail×tail both-sides
    extras, arm-7 pattern dedup (oracle-checked vs cue v0.16.1) + distinct-concat, and the
    `.bottom` cross-combos (pattern×tail both orders, single+multi-pattern) pinned for now
    (B2.5 flips). NO migrated test went red ⟹ the structN meet/subsumes/close/format/manifest
    consumer arms are validated byte-identical to legacy. Build + `check-fixtures.sh` green at
    every commit; ZERO byte-drift. Produced-output sites (~95 `== .struct` LHS-of-resolver/eval
    in ClosureTests/EvalTests/ResolveTests/FixtureTests/Normalize/TwoPass/Presence/Bound +
    FixturePorts producer ports) correctly LEFT for the CP3-flip. Must-fix items 1+2 CONSUMED;
    item 3 (`applyEvaluatedStructN`) is flip-only.
  - **B2.2/CP3-flip — production flip + ctor delete + rename + class-2 tests. DONE (2026-06-19,
    worktree `worktree-agent-a73190051b5458ad4`, commits `ee7dfe5`..`3f5bbbe`; orchestrator
    fast-forwards `main`).** The irreversible landing, one green endpoint:
    (1) **Producers flipped to `mkStruct`** — `Parse.parsedFieldsBaseValue`/`parsedFieldsValue`
    (open_/hasTail → openness: no-tail ⇒ `.regularOpen`, explicit `...` ⇒ `.defOpenViaTail
    (some tail)`), `Runtime.mergeSourceValues` empty default, `Module.bindImports`, and every
    `Eval` re-emit (comprehension result, `dynamicField`, `evalConjStandard`, the `.structComp`
    host meet, `forceClosureWithConjunct`'s use-operand fold). `applyEvaluatedStructN` is now
    the LIVE struct re-emit. (2) **4 old ctors deleted** (`struct`/`structTail`/`structPattern`/
    `structPatterns`); `structComp` KEPT (= B2b). Every dead legacy match arm removed across all
    modules; Lattice's 12-arm meet matrix + 5 legacy merge helpers collapsed to the single
    `mergeStructN` arm. (3) **`Value.structN → Value.struct` renamed** (arity 2→4) by
    word-boundary token replace (~495 sites); `ManifestValue.struct` (1-arg, Manifest/Yaml/Json)
    left untouched, helper names `mergeStructN`/`applyEvaluatedStructN`/`structNSubsumes`/
    `structNTailCoherent` kept. (4) **~95 produced-output test literals + ~85 FixturePorts
    producer ports** (+ nested literals across 10 test files) migrated to the 4-arg `.struct
    fields openness tail patterns`. (5) **Must-fix item 3** pinned: two `applyEvaluatedStructN`
    pattern-path pins in EvalTests, oracle-checked vs cue v0.16.1.
    **Correctness gate met:** `lake build` green, `scripts/check-fixtures.sh` → `fixture pairs
    ok` with ZERO byte-drift on all testdata `.expected`, shellcheck clean. ONE documented
    representation divergence (this slice's authorized improvement): `mkStruct`/`dedupPatterns`
    now collapses repeated equal `[pattern]: c` constraints to one (legacy `structPatterns`
    accumulated them per meet), matching cue v0.16.1 — the 4 TwoPassTests embed-narrowing pins'
    expected strings updated from the legacy triple-`[string]: string` to the cue-correct single
    pattern. A separate eval-output pattern-elision divergence (cue elides residual patterns from
    `eval`; Kue shows them — values + concrete export agree) recorded in cue-divergences.md.

    ### B2.2/CP3 megaslice — DE-RISKED EXECUTION PLAN (Phase-B audit 2026-06-19 #5)

    Ground-truth measured at `9fa5593`: **266** old-ctor sites in impl (`Kue/*.lean`,
    `grep -E '\.struct |\.structTail|\.structPattern|\.structPatterns'`) + **758** in tests
    (`Kue/Tests/*.lean`) = ~1024 raw matches (the "~940" estimate is the same order). Impl by
    file: `Eval` 94, `Lattice` 42, `Resolve` 16, `Normalize`/`Parse` 12, `Manifest` 10,
    `Builtin` 8, `Examples`/`Yaml` 7, `Module`/`Runtime` 6, `Format`/`Json` 4/3, `Order` 13,
    `Tests` 2. Tests by file: `StructTests` 148, `FixturePorts` 99, `ClosureTests` 96,
    `EvalTests` 85, `OrderTests` 58, `FixtureTests` 55, `ResolveTests` 38, `YamlTests` 29,
    `TwoPassTests` 22, `Normalize`/`Manifest`/`List`/`Module` 16/15/15/14, `BuiltinTests` 10,
    `Presence`/`Bound`/`EvalPerf` 9/6/7, `Lattice` 3.

    **Sequencing verdict — a TEST-ONLY PRE-MIGRATION SLICE IS POSSIBLE and shrinks the
    megaslice. Tests split into two classes by what the literal pins:**

    1. **Constructed-input tests** (inputs AND expected are value literals; the test calls a
       PURE operation — `meet`/`subsumes`/`closeValue`/`lenValue`/`formatValue`/`manifest` —
       over them). These CAN pre-migrate to `structN`, because the `structN` meet/close/len/
       format arms are ALREADY LIVE today (`mergeStructN` at `Lattice.lean:906/1141`,
       `closeValue`/`lenValue` at `Builtin.lean:17/41`, `Format`/`Manifest` structN arms).
       Migrating a test's inputs AND its expected to `structN` ATOMICALLY in one edit keeps it
       green: `meet (structN…) (structN…)` dispatches to `mergeStructN` → `mkStruct` →
       `structN`, compared to a `structN` expected. Verified: `mergeStructN` reproduces every
       legacy arm by inspection (Phase-A), so the produced `structN` is byte/`BEq`-equal to the
       hand-written `structN` expected. Two sub-cases:
       - **String-compared** (`formatField`/`formatValue`/`manifest`/`exportJsonMatches` →
         `String`): representation-INVARIANT — output renders identically whether the meet
         produced old `.struct` or `structN`. These are the SAFEST to pre-migrate (inputs only;
         no expected to touch). Covers most of `FixturePorts` (meet/close inputs, e.g.
         `FixturePorts.lean:341/376`), the `LatticeTests` `exportJsonMatches` struct-arm pins
         (`176-212`), `ManifestTests`, `YamlTests`, `FormatTests`-style.
       - **Value-compared** (`== .struct … = true` via `BEq` over a pure-op result): inputs AND
         expected migrate together. Covers `StructTests` meet pins (`StructTests.lean:35-106`),
         `OrderTests` subsumes pins (`OrderTests.lean:34+`), `LatticeTests` mkStruct pins
         (already `structN`).
    2. **Produced-output tests** (LHS is the result of `resolveValue`/`resolveAndEval`/
       `evalValue`/`parseSource`/closure FORCE — i.e. PRODUCTION output — compared via `BEq` to
       a `.struct` value literal). These CANNOT pre-migrate: production still emits old `.struct`
       until B2.2 flips it, so a `structN` expected would `BEq`-mismatch the old-`.struct` LHS →
       RED. They MUST migrate in lockstep with the production flip. Identified by the `== .struct`
       value-comparisons whose LHS is a resolver/evaluator call: `ResolveTests.lean:9/15/21/28/…`
       (15 sites, all `resolveValue …  == .struct`), `ClosureTests` (21 `== .struct`),
       `EvalTests` (42 `== .struct`), `NormalizeTests` (5), `TwoPassTests` (3), `ModuleTests`
       (2), `PresenceTests` (4), `BoundTests`/`FixtureTests` (2/1). Total **~95** `== .struct`
       produced-output sites + the `structComp`/`structTail`/`structPattern` output pins
       (`ResolveTests.lean:59/65/103/119`).

    **So the megaslice splits into a SAFE pre-migration slice + a smaller hard flip:**

    - **CP3-pre (test-only, byte-identical, LOW risk) — do FIRST, lands green on its own.**
      Migrate the **constructed-input** tests (class 1) to `structN` literals — `StructTests`,
      `FixturePorts` (input literals), `LatticeTests` (already done), `OrderTests`,
      `ManifestTests`, `YamlTests`, `ListTests`, `BuiltinTests`, the input-only literals in
      `EvalPerfTests`. **GATE: this slice consumes must-fix item 1 (Order.subsumes structN
      arm).** `OrderTests` pre-migration is IMPOSSIBLE until `Order.subsumes` has a `structN`
      arm (today a `structN` input falls to `_, _ => false` → every migrated OrderTests pin goes
      RED). So CP3-pre's first commit is the `Order.subsumes` merged-`structN` arm (item 1), then
      the test literals. This slice turns ~660 of the ~1024 sites from inspection-only into
      TEST-GATED while production is unchanged — exactly the de-risking we want before the flip.
      Each test file is one reviewable commit; `lake build` + `check-fixtures.sh` green after
      each (the `structN` op-arms are live and correct).
    - **B2.2/CP3-flip (the hard landing — production flip + class-2 tests + ctor delete +
      rename, ONE green commit).** Now ~95 produced-output `== .struct` pins + the impl sites
      remain. This is still inseparable (the moment production emits `structN`, every class-2 pin
      and every impl `.struct` match arm must already be `structN`), but it is MUCH smaller and
      every remaining test site is a known, enumerated `== .struct`/`== .structTail`/etc.

    **Rename mechanics + the `ManifestValue.struct` collision guard.** `ManifestValue.struct`
    (`Manifest.lean:8`) is a 1-arg ctor `struct (fields : List (String × ManifestValue))` on a
    DIFFERENT type. A blind `sed structN→struct` or `.struct`-rewrite is UNSAFE. Safe sequence,
    COMPILER-DRIVEN:
      1. In the flip commit, FIRST rename `Value.structN → Value.struct` (arity 4) AFTER deleting
         the 4 old `Value.struct`/`structTail`/`structPattern`/`structPatterns` ctors. The old
         2-arg `Value.struct` vanishing means every legacy `.struct f bool` / `.structTail …` /
         `.structPattern …` / `.structPatterns …` site is now a COMPILE ERROR (wrong arity / no
         such ctor) — the compiler enumerates every site to fix. Nothing is silently mis-rewritten.
      2. Fix per compile error, module-by-module in dependency order: `Value.lean` (the ctor +
         `mkStruct`, already `structN`-shaped — just the rename) → `Lattice.lean` (delete the 12
         old meet arms `1067-1140`, the `meetCore` `.struct/.structTail/.structPattern(s)` bottoms
         `463-468`; `mergeStructN`/`structN` arm at `1141` becomes the only struct arm) →
         `Normalize`/`Resolve`/`Order`/`Format` → `Builtin`/`Eval` → `Runtime`/`Module`/`Manifest`
         → `Parse` (the producers) → `Examples`/`Json`/`Yaml`. `ManifestValue.struct` sites stay
         UNTOUCHED (they never error — different type, different arity). The `Manifest.lean`
         `Value`-side arm migrates; the `ManifestValue.struct […]` CONSTRUCTION (the manifest
         OUTPUT, `Manifest.lean:8` ctor used at the `.struct entries` build sites) does NOT — it
         is the 1-arg form and the compiler keeps it well-typed.  **Disambiguation rule for the
         executor: a `.struct` whose payload starts `List Field` / has an openness/tail/patterns
         shape is `Value.struct`; a `.struct` whose payload is `List (String × ManifestValue)` is
         `ManifestValue.struct`. When in doubt, the compile error's expected-type tells you.**
      3. Then the producers (`Parse.parsedFieldsBaseValue`/`parsedFieldsValue` `:509-532`,
         `Runtime.lean:60`, `Module.lean:60/162`, the `Eval` re-emit sites) flip to
         `mkStruct`/4-arg `.struct`. (`.structComp` is NOT touched — it stays; that is B2b.)
      4. Then the class-2 produced-output tests, also compile-error-driven (the `== .struct f
         bool` literals become arity errors once `Value.struct` is 4-arg).

    **The 3 Phase-A must-fix items — explicit megaslice sub-tasks:**
      1. **`Order.subsumes` structN arm (`Order.lean:227-262`).** Today 8 separate struct
         subsumption arms (`struct×struct`, `structTail×struct`, `structTail×structTail`,
         `structPattern×struct`, `structPatterns×struct`, `structPattern×structPattern`,
         `structPattern×structPatterns`, `structPatterns×structPattern`, `structPatterns×
         structPatterns`) feeding `structSubsumesWithFuel`/`structTailSubsumesWithFuel`/
         `structPatternSubsumesWithFuel`/`structPatternsSubsumesWithFuel`. MERGE into ONE
         `.struct ef eo et ep, .struct af ao at ap =>` arm that dispatches on the expected side's
         tail/pattern shape (NOT a mechanical arity fix that drops tail/pattern subsumption
         logic): no expected tail+no patterns → `structSubsumes`; expected tail → `structTail
         Subsumes`; expected patterns → `structPattern(s)Subsumes` + the pattern/openness checks
         the cross-arms carry. This is the FIRST commit of CP3-pre (gates `OrderTests`
         pre-migration). Keep all `OrderTests` subsumption pins green through it.
      2. **Dedicated `mergeStructN` pins** (add in CP3-pre, where the arms go test-live): the
         `struct×structTail` `rf++lf` field-order reversal (`{b:_, a:_, ...} & {c:_}` — reversal
         observable in output field order); the `applyTailToExtrasWith`-on-BOTH-sides tail×tail
         merge; the arm-7 pattern dedup (`{[=~"a"]:int} & {[=~"a"]:int}` → ONE pattern,
         oracle-checked vs cue v0.16.1); and the still-`.bottom` cross-combinations
         (`structPattern×structTail`, `structPatterns×structTail`, both orders) pinned AS
         `.bottom` now, so B2.5's `bottom→unify` flip is a VISIBLE diff. `native_decide` over
         `structN` literals (live path).
      3. **`applyEvaluatedStructN` pattern path** (`Eval.lean:384`) — pin a pattern-struct eval
         (`{a: int, [=~"x"]: string}` value) end-to-end once production emits `structN` (so in
         the flip commit, not CP3-pre), confirming byte-parity with the legacy
         `applyEvaluatedStructPattern(s)` output via a fixture + oracle check.

    **Test-literal rewrite mapping table** (mechanical; old form → `structN`/4-arg `struct`):

    | Old (2-arg / legacy ctor)              | New (`structN` in CP3-pre; `struct` post-rename) |
    | -------------------------------------- | ------------------------------------------------ |
    | `.struct fs true`                      | `.structN fs .regularOpen none []`               |
    | `.struct fs false`                     | `.structN fs .defClosed none []`                 |
    | `.structTail fs t`                     | `.structN fs .defOpenViaTail (some t) []`        |
    | `.structPattern fs lp c true`          | `.structN fs .regularOpen none [(lp, c)]`        |
    | `.structPattern fs lp c false`         | `.structN fs .defClosed none [(lp, c)]`          |
    | `.structPatterns fs ps true`           | `.structN fs .regularOpen none ps`               |
    | `.structPatterns fs ps false`          | `.structN fs .defClosed none ps`                 |

    Post-rename (flip commit) the executor does a second pass `.structN → .struct` ONLY on
    `Value`-side sites (compiler-driven; `ManifestValue.struct` untouched). In CP3-pre, write
    `.structN` directly (the rename has not happened yet). A bare `...`-tail with no explicit tail
    value parses to `some .top` via `mkStruct`'s coherence; hand-written tail literals already
    carry `(some t)`.

    **Effort & failure modes.** CP3-pre: ~660 sites across ~12 test files + the `Order.subsumes`
    arm + ~3 new pin theorems — mechanical, each file a green commit, LOW risk (live arms,
    inspection-confirmed). B2.2/CP3-flip: ~266 impl + ~95 class-2 test sites, ONE green landing,
    MEDIUM-HIGH risk (representation flip; build + fixtures both red mid-flip until every site is
    fixed). Failure modes: (a) the `ManifestValue.struct` collision — guarded by compiler-driven
    per-error fixing, never global sed; (b) a missed produced-output pin that should have been
    class-2 (mitigated: the flip commit's compile errors enumerate ALL remaining `.struct` arity
    mismatches — nothing compiles green with a stale literal); (c) `mergeStructN` subtly wrong on a
    path inspection missed (mitigated by CP3-pre's new pins landing the arms test-live BEFORE the
    flip); (d) field-ordering drift from `mkStruct`'s `dedupPatterns` (already a known deliberate
    divergence — pin per item 2).

    **Worktree isolation: YES — spawn B2.2/CP3-flip with `isolation: worktree`.** It is a large,
    self-contained representation flip touching ~360 sites that goes red mid-edit and only green at
    the end; a worktree keeps the main tree clean during the long red window and lets the
    orchestrator verify the landing atomically. CP3-pre does NOT need a worktree (each file is an
    independently-green commit on `main`). Recommended order: **CP3-pre (item 1 + class-1 tests,
    on `main`, multiple green commits) → B2.2/CP3-flip (worktree, one green landing) → B2.5
    behavioral.**
  - **B2.5 — cross-combination BEHAVIOR fix + new fixtures. DONE (2026-06-19).** Replaced the
    residual `| _, _, _, _ => .bottom` catch-all in `mergeStructN` with a general composition arm:
    base = the tail-bearing side's fields (cue field order; left if both have tails), meet the
    tails (apply each to the other's extras via `applyTailToExtrasWith`), concat + apply patterns
    (`applyPatternsToFieldsWith`), retain BOTH axes → `mkStruct … .defOpenViaTail (some tail)
    patterns`. The previously-`.bottom` `structPattern/structPatterns × structTail` (both orders)
    now UNIFY: `{[string]: int} & {a: 5, ...}` → `{a: 5}` (open), cue v0.16.1 confirmed. No arm
    1-7 touched. Flipped the 4 LatticeTests `*_is_bottom_for_now` pins to `*_unifies` + added 2
    edge pins (pattern-violation bottoms the field only; compositional both-tails re-meet) + 2
    end-to-end fixtures (`definitions/{pattern_tail,multi_pattern_tail}_unify`). The only
    behavioral (non-byte-identical) slice of B2; ZERO drift on existing fixtures (confirming none
    relied on the buggy `.bottom`). The B2 family-1 collapse + correctness fix is now FULLY
    complete — only B2b (structComp collapse) remains of B2.

  ### B2b design (implementable) — `structComp` two-bool → `StructOpenness` (Phase-B audit 2026-06-19 #6)

  **Decision: option (a) — adopt `StructOpenness` on `structComp`, KEEP it a distinct pre-eval
  ctor. NOT option (b) (fold into the unified `struct`).** The choice turns on the Phase-B #4
  invariant "`structComp` is pre-eval and NEVER reaches meet" — `meetCore` bottoms it
  (`Lattice.lean:456-457`, dead-but-defensive), `evalValueCoreWithFuel` (`Eval.lean:2129`) expands
  it into the unified `struct` BEFORE any meet. That clean separation is worth more than the
  one-ctor reduction option (b) would buy.

  **Why NOT option (b) — folding into `struct (… comprehensions : List Value)`.** It would put a
  `comprehensions` field on the meet-bearing struct, where `comprehensions ≠ []` can ONLY mean
  "not yet evaluated." Every `mergeStructN` arm, every `Order.subsumes` arm, every
  `Manifest`/`Format` output site would then have to either (i) handle a non-empty `comprehensions`
  on a value that reached meet (re-introducing the exact "this can't happen" branch B2 just
  erased), or (ii) carry an unenforced invariant `comprehensions = []` on every evaluated struct —
  a nonsense state representable in the type, which is what B2 exists to kill. The pre-eval/
  evaluated distinction Phase-B #4 identified is a REAL type boundary; option (b) deletes it to
  save one constructor. Rejected on philosophy (illegal-states-unrepresentable WITHOUT muddying the
  invariant).

  **Why NOT option (c) — leaving the two bools.** The reachable `(open_, hasTail)` states are
  exactly Parse's `(true, false)` / `(true, true)` and normalize-def's `(false, false)` /
  `(true, true)`; `(false, true)` (closed-with-tail) is the never-constructed nonsense state — the
  same illegal state B2 erased for family-1. Leaving it is inconsistent with the milestone.

  **Target representation.** `structComp` keeps its shape but swaps the two bools for one
  `StructOpenness`:
  ```
  | structComp (fields : List Field) (comprehensions : List Value) (openness : StructOpenness)
  ```
  Note: `structComp` has NO tail VALUE (unlike family-1's `struct`, whose `defOpenViaTail` couples
  to `tail : Option Value`). The pre-eval `...` is a bare flag, not a stored tail — the tail value
  is synthesized when the eager arm re-emits the unified `struct`. So the mapping is:
  - Parse no-`...`  `(open_=true, hasTail=false)` → `structComp fields cs .regularOpen`
  - Parse `...`     `(open_=true, hasTail=true)`  → `structComp fields cs .defOpenViaTail`
  - normalize-def closes a no-`...` body → `.regularOpen` becomes `.defClosed`; a `...` body
    (`.defOpenViaTail`) stays open. This IS the old `open_ := hasTail` rule, re-expressed as a
    total `StructOpenness → StructOpenness` map: `regularOpen ↦ defClosed`, `defOpenViaTail ↦
    defOpenViaTail`, `defClosed ↦ defClosed` (idempotent). The `defClosed` state is unreachable at
    parse but the map is total over all three for free.

  `defOpenViaTail` on `structComp` means "open via a bare `...`, no stored tail value" — coherent
  because `structComp` carries no `tail` field for the coherence invariant to relate it to. The
  eager eval arm (`Eval.lean:2129`) and the closure-force arm (`Eval.lean:2483`) currently pass
  `open_ : Bool` to `closeEmbeddedOver`/use it as `defOpen`; under the new rep they pass
  `openness.isOpen` (or thread `openness` and let `closeEmbeddedOver` take `StructOpenness` — a
  ride-along tightening, since `closeEmbeddedOver` immediately does `.ofBool defOpen`). The
  `hasTail` consumers vanish: only `normalizeDefinitionValueWithFuel` read it, and it becomes the
  `StructOpenness` map above.

  **No new meet/subsumes/manifest behavior.** `structComp` still bottoms in `meetCore`
  (dead-defensive arms unchanged, just arity), still expands before meet, still manifests as
  `.incomplete` (`Manifest.lean:115`) — option (a) touches the REPRESENTATION of the pre-eval node,
  not its lifecycle. The eager arm's OUTPUT is the family-1 `struct`, already on `StructOpenness`.
  So B2b is BYTE-IDENTICAL by construction (no behavior change anywhere — the reachable two-bool
  states map 1:1 onto the three `StructOpenness` states).

  **Migration plan — ONE slice, 3 fixture-gated commits (~44 sites, NO worktree).** Smaller and
  strictly lower-risk than B2.2/CP3 (byte-identical throughout, no production-flip red window, no
  ctor delete/rename). The B2 playbook (introduce → consume → produce) collapses because
  `structComp` is changing arity in place, not coexisting with a new ctor — so the compiler
  enumerates every site. Sequence:
  1. **Flip the ctor + the one semantic site, compiler-driven.** Change `Value.structComp`'s last
     two `Bool` params to one `openness : StructOpenness` (`Value.lean:567`). Every one of the ~44
     sites becomes a compile error (arity 4→3). Fix per error in dependency order: `Value.lean` →
     `Lattice.lean` (the two dead `meetCore` arms, `valueTag`) → `Normalize.lean` (the `open_ :=
     hasTail` site `:11-21` becomes the `StructOpenness` map — the ONE semantic site; the spine
     walker `:137-143` threads `openness` verbatim) → `Resolve.lean` (`:120`, `:148` thread
     verbatim) → `Format.lean` (`:196` ignores openness, unchanged output) → `Manifest.lean`
     (`:115` threads into the `.incomplete` re-wrap) → `Eval.lean` (the ~29 sites: the eager arm
     `:2129` and force arm `:2483` use `openness.isOpen` where they used `open_`; `remapConjRefs`
     `:448`, the classifiers `:121/229/1472/1531/1591/1658/1744`, `defBodyHasSiblingSelfRef`
     `:1531`, `classifyDefinedness` `:727`, all thread/ignore verbatim) → `Parse.lean` (the
     producers `:526-527` emit `.regularOpen`/`.defOpenViaTail` from `hasTail`; `bindValueAlias`
     `:662-663` threads verbatim). All match arms that `_`-ignored both bools collapse to one `_`.
     Build green + `check-fixtures.sh` zero drift = the gate (byte-identical: the rep change is
     invisible to output).
  2. **Migrate test literals.** ~44 test-side `structComp` sites across `EvalTests` (9),
     `ClosureTests` (26), `FixturePorts` (28), `TwoPassTests` (11), `EvalPerfTests` (8),
     `ResolveTests` (4), `PresenceTests` (2), `LatticeTests` (1) (counts from grep 2026-06-19).
     Mechanical rewrite: `true false → .regularOpen`, `true true → .defOpenViaTail`, and the
     normalize-output literals `hasTail hasTail → (if hasTail then .defOpenViaTail else .defClosed)`
     concretely (`false false → .defClosed`, `true true → .defOpenViaTail`). Compiler-driven (the
     arity change makes every stale literal an error), so nothing is silently mis-rewritten. Add a
     `native_decide` pin that the `normalizeDefinitionValue` `StructOpenness` map closes a no-`...`
     structComp def body (`.regularOpen → .defClosed`) and leaves a `...` body open
     (`.defOpenViaTail` fixed point) — the one semantic site, pinned at the type level.
  3. **Verify + plan/log/breadcrumb.** Full gate (`lake build` + `check-fixtures.sh` +
     `shellcheck`); cert-manager + `packs.#Argo` content-identical spot-check (pure rep change, no
     eval-path change → perf unchanged, no `kue-performance.md` edit). Mark B2b DONE; B2 fully
     closed.

  **Worktree: NO.** Byte-identical throughout, each commit independently green, no long red window
  (unlike CP3-flip's production flip). On `main`, 3 green commits. Effort: ~44 impl+test sites,
  mechanical, LOW risk (the only semantic site is one total `StructOpenness` map replacing one
  `open_ := hasTail`; everything else threads or ignores).

  **Risk/soundness + regression gate.** Highest-risk site: the `meetWithFuel` matrix rewrite
  (B2.4) — it must reproduce the tail-extras application (`applyTailToExtrasWith` runs on BOTH
  sides' extras, `Lattice.lean:990-994`) and the pattern-closedness marking exactly, or
  byte-parity breaks subtly. Second-highest: `Parse.lean:526-527` + `Normalize.lean:140-145`,
  where `structComp` is built with `hasTail` feeding the def-body openness — the B2b slice must
  preserve the `normalizeDefinitionValueWithFuel` `open_ := hasTail` rule under `StructOpenness`
  (the `hasTail` bool becomes "construct `defOpenViaTail` vs `defClosed`"). Gate: LatticeTests
  (struct×struct open/closed, tail×tail, pattern×pattern, pattern×patterns, patterns×patterns —
  source-level JSON `export`, B2-representation-stable) + all struct fixtures are the
  byte-identical gate for B2.1–B2.4; the four new cross-combination fixtures are the gate for
  B2.5. **B2b (structComp collapse) is a SEPARATE follow-on**, not in the family-1 critical path
  — fold the `open_`/`hasTail` two-bool into a `StructOpenness`-carrying pre-eval form (or unify
  it INTO the family-1 `struct` with a `comprehensions : List Value` field defaulting to `[]`),
  decided after B2.1–B2.5 land. Keep B2b out of the headline so the meet-correctness payoff
  ships first.

- **B3 (LOW-MEDIUM — incompleteness, embeddedList family).** `comprehensionPairs`
  (`Eval.lean:988`) returns `none` for `.embeddedList`, so `for x in {#a:1, [1,2]}` (source
  evaluates to an `embeddedList`) iterates ZERO times where CUE iterates `[1,2]`. Add an
  `.embeddedList items _ _ => some (listPairsFrom 0 items)` arm. Incompleteness, not unsound;
  folds into the item-8 `scalar-embed-with-decls`/embeddedList edge family — do as a
  ride-along when next touching that area. Add a fixture `for x in {#a:1,[1,2]} {x}` → `[1,2]`.
  (Audit-cross-check: `resolveValueWithFuel:145` and `evalValueCoreWithFuel:2181` catch-alls
  were flagged but are DEFENSIBLE — `embeddedList` is an eval-OUTPUT and cannot reach the
  parse-time `resolveValueWithFuel`; the eval-core catch-all's residual forms (scalars,
  unresolved constraints) correctly pass through. Not findings.)

- **B4 (LOW — seam test coverage gap) — DONE (`LatticeTests`); `DecimalTests`/`FormatTests`
  deferred.** `Kue/Tests/LatticeTests.lean` added (2026-06-19, ride-along with the item-5
  test-org pass): pins `meet`/`join` algebra — lattice laws, scalars, kinds, bounds, regex,
  lists, disjunctions, and the struct-shape arms B2 collapses (struct×struct open/closed,
  tail×tail, pattern×pattern, pattern×patterns, patterns×patterns), the latter via source-level
  JSON `export` so they survive B2's constructor collapse as a regression gate. The two
  genuinely-missing meet arms (`structPattern×structTail`, `structPatterns×structTail`, both
  orders → wrongly `.bottom`) are documented in the module header but NOT pinned (no expected-fail
  marker; A2 rule). DEFERRED: small `DecimalTests`/`FormatTests` (`Decimal`/`Format`/`Json`/`Base64`
  still only indirectly covered) — pick up as a future ride-along.

- **B5 (LOW — extraction-item corrections, cleanup).** Two backlog cleanup items need their
  stated shape corrected from this audit:
  - Item 3 (Regex → `Kue/Regex.lean`): CONFIRMED clean — the ~240-line engine (`RegexAtom` +
    matchers + group/alternation) touches only `Char`/`String`/`RegexAtom`, consumed by
    `Eval`/`Lattice`/`Order` via `stringRegexMatches`. After extraction, drop
    `Init.Data.String.Search` from `Value.lean` (still imported by `Parse.lean`, so it stays
    in the build — the win is `Value.lean` becoming a true leaf).
  - Item 4 (EvalOps → `Kue/EvalOps.lean`): the scalar-op block (`evalAdd…evalBinary`) is NOT
    `{Value, Decimal}`-only as item 4 states — it also calls `divValue`/`modValue`/`quoValue`/
    `remValue` from `Builtin.lean`. So `EvalOps` must import `Builtin` too, OR those four div/mod
    helpers move into `EvalOps`/`Decimal` first. Resolve the import shape in the slice; the
    carve-out is otherwise clean (no back-edge into the recursive evaluator).
  - `Order.lean` (subsumption) is a DELIBERATE test-only oracle (imported only by `Tests/*`),
    NOT dead code and NOT duplicated in the pipeline — `meet` (join) and `subsumes` (partial
    order) are orthogonal. Recorded so a future audit does not re-flag it as an orphan.

## Live Backlog (open work, ranked)

Correctness gates real-app adoption; cleanups are parallel-safe filler. Sequence:
**A5 DONE (`c3d0089`)** → **A5-followup DONE (`e00c3de` — the OBSERVABLE wrong value flipped; see
below)** → audit fix-slices DONE (A1+B1, A3, A4; A2 BLOCKED on a representation marker →
A2-followup design-slice) → TWO-PHASE AUDIT DONE (Phase-A found A5; Phase-B #2 found B7) →
**B7 DONE (`bbb00b2`/`c5cbb0e`/`aa5518c` + this docs commit — five frame-depth walkers unified behind one
`descendClauses` authority in `Value.lean`; `clauseFrameShift` + the per-walker re-derivations
gone; NEW guarantee = two agreement theorems make future drift a build/`native_decide` failure)** →
**test-org pass (item 5) + B4 `LatticeTests` DONE (2026-06-19 — `EvalTests` split 4 ways +
LatticeTests pins the struct-meet arms B2 collapses; B2 now de-risked)** →
**TWO-PHASE AUDIT DUE (2 slices since last audit: B7 + this test-org/LatticeTests slice — due
NEXT, or after B2)** →
B2 family-1 collapse **DONE (B2.1–B2.5, 2026-06-19)**; **Phase-A audit of CP3-pre/flip/B2.5 DONE
2026-06-19 — CLEAN**, two LOW fix-slices filed (**B2-A1** pattern+tail tail-drop guard,
**B2-A2** reverse-order B2.5 fixture; both above) →
B2b (structComp collapse — last of B2) /
B6 design-spike / item 1 follow-up / A2-followup →
parallel-safe cleanups (3,4 + B5; remaining test-org for `FixtureTests`/`StructTests`/`BuiltinTests`
— and `EvalTests` is STILL 1210 lines after the item-5 split, re-split candidate;
B4 ride-along `DecimalTests`/`FormatTests`) interleaved → deeper parity/perf (2,6,7) →
borderline/LOW (8 + B3) ride-alongs.

### Post-B2 re-ranking (Phase-B audit 2026-06-19 #6) — recommended next 3-4 slices

B2 (the headline) is done. Re-assessed against the North Star (correct CUE v0.15 + real-app
adoption). Correctness gaps gate adoption; the perf wall gates FULL-app adoption; consistency is
finishing-touches. Recommended order:

1. **TWO-PHASE AUDIT (overdue) — do FIRST.** 5 slices have landed since the last full A+B cadence
   audit (CP3-pre, CP3-flip, B2.5, + this is the Phase-B half). The cadence is mandatory at the
   2-3-slice mark; clear it before more forward motion. (This audit IS the Phase-B half of that
   cycle — pair it with the matching Phase-A over the same batch if not already run.)
2. **B6 — def-body closedness enforcement (CORRECTNESS, real-app).** The highest-value OPEN
   correctness gap: a nested `#Def` under a regular field, or via the eager nested-selector path,
   admits extra fields where cue REJECTS (oracle-confirmed). prod9 `#Def`s are exactly this shape
   (`{embed; …}` consumed with extra fields), so this is adoption-relevant, not a corner. Needs a
   design-spike (split `normalizeFieldWithFuel`'s two conflated contexts + route the eager selector
   through closedness) — do the spike first, like B2/B7. Ranked above B2b because a wrong-acceptance
   is a correctness defect; B2b is hygiene.
3. **B2b — structComp collapse (consistency, completes B2).** Now fully designed (above):
   byte-identical, ONE slice / 3 commits, ~44 sites, LOW risk, no worktree. Finishes the struct-
   family unification milestone and erases the last `open_`/`hasTail` nonsense state. Cheap and
   self-contained — a natural ride-along or filler slice. Ranked below B6 (consistency < correctness)
   but above the perf wall because it is small, certain, and closes a named milestone; landing it
   keeps the struct representation coherent for any later struct-touching work (incl. item 7's
   frame work, which threads through struct eval).
4. **item 7 — frame-id canonical identity (PERF wall, gates FULL argocd).** The deeper frontier:
   reclaims cert-manager (~92s) and unblocks the heavy `argo` sub-package (>200s timeout). This is
   what stands between "content-correct in a scratch module" and "full real-app adoption" — the
   North Star's second half. Ranked 4th only because it is audit-HEAVY and risky (must not violate
   "independently-built frames never falsely share" — a soundness trap), so it wants a clear runway
   AFTER the cheap correctness/consistency wins land and the audit cadence is clean. It is the
   single biggest adoption lever once the correctness backlog is drained.

Below the top 4: **A2-followup** (CORRECTNESS but narrow — the `{#u:{x:_|_}}` shape, needs the
import-binding-marker representation spike; pairs naturally with B6's normalize work) and **item 1**
(argocd full-app follow-up — partly gated on item 7's perf). **B2-A1/B2-A2** (LOW — latent
tail-drop guard + reverse-order fixture; ride along with any struct/typed-ellipsis touch).
**B3/B5/items 3,4** (LOW cleanups, parallel-safe filler). **Test-org** (`FixtureTests` 1093,
`StructTests` 765, `BuiltinTests` 735, `EvalTests` still 1210 post-split) — schedule when Phase-B
next flags it overdue. Rationale summary: drain CORRECTNESS (B6) before CONSISTENCY (B2b) before
the PERF wall (7); the audit cadence pre-empts all of them this cycle.

**A5-followup. Comprehension-body self-ref deferral gate — DONE (`e00c3de`).** The OBSERVABLE
wrong value (a static field whose value is a comprehension reading `Self.<embedded>` inside a `for`
body, narrowed at the use site, kept its stale Pass-1 value) is fixed.
```
#H: {#t: string | *"def"}
#R: Self={#H, out: [for x in [1] {v: Self.#t}]}
v: #R & {#t: "y"}   # cue v0.16.1 → v.out[0].v: "y"; now kue too (was string | *"def")
```
The plan's "Pass-2 re-eval gap" diagnosis was the SYMPTOM, not the cause. Tracing showed `#R &
{narrow}` never reached the Pass-2 arms: the DEFERRAL GATE `hasSelfRefAtDepth` scanned the
comprehension BODY at the comprehension node's `depth`, missing the body self-ref that resolves
`#forClauses` frames deeper, so `#R` was judged to have no sibling self-ref and took the
eager-then-meet path (which cannot re-expand the comprehension) instead of the closure-FORCE path
(which splices the narrowing into the frame before the body evaluates — the already-correct,
already-perf-optimized arm). Fix: `hasSelfRefAtDepth` made `mutual` with `hasSelfRefAtDepthClauses`,
threading loop-frame depth like `resolveClausesWithFuel` (+1 per `for`, +0 per `guard`). FOURTH
A5-family walker (after `remapConj*`, `selfReferencedLabels`, `refsSelfEmbeddedLabel`); Pass-2
selective re-eval untouched, no full-re-eval perf regression. End-to-end fixture
`comprehension_embed_self_narrow_body` + native_decide gate pins (body-detected, loopvar boundary,
multi-`for`, guard-no-frame, struct clause helper). See implementation-log for the full trace.

**B7. Frame-depth clause-walkers unified behind one `descendClauses` authority — DONE
(`bbb00b2`/`c5cbb0e`/`aa5518c` + this docs commit).** The de Bruijn "comprehension body lives `#forClauses`
deeper" rule (`+1` per `for`, `+0` per `guard`, body at end) was re-derived by hand at five
walkers — a bug that recurred FOUR times. B7 factored it into a single total `descendClauses`
fold in `Value.lean` (leaf where `Clause` is defined). The three scanners
(`refsSelfEmbeddedLabelClauses`, `selfReferencedLabelsClauses`, `hasSelfRefAtDepthClauses`) are now
one-line instantiations; `remapConjRefs`'s body shift derives from `clauseChainDepth` (same fold)
and **`clauseFrameShift` is deleted**; `resolveClausesWithFuel` (the fifth, scopes-threading,
`mutual` with eval) stays the reference, tied to the fold by `descend_clauses_frame_count_matches_resolve`.
NEW guarantee: two `native_decide` agreement theorems make future drift between the fold and a
walker / the resolver a build failure, not a silent wrong value. Behavior-preserving (zero fixture
byte-drift across all four commits; existing A5/A5-followup pins were the regression gate). NOT a
`Depth` newtype — that was ~24 sites of churn + kernel cost on the hot resolve path for zero new
guarantee, since the recurring bug was the re-derivation, not a raw `+1`. Full design rationale +
trace in the implementation-log "B7" entry. The design spike that preceded this implementation is
retained below for the record.

Phase-A audit (2026-06-19) — walker-consistency VERDICT for B7's implementer: all four fixed
walkers thread depth IDENTICALLY to the authority (`forIn` source at current depth, +1 for
rest+body; `guard` at current depth, +0), no off-by-one, no guard-counted-as-frame, no latent 5th
instance. The rule is currently encoded in TWO inequivalent FORMS: `clauseFrameShift` (total #for)
used by ONLY `remapConjRefs`'s BODY recursion, while the other three scanners AND
`remapConjClauses` (the source threading) re-derive it as recursive `+1-per-forIn`. So
`remapConjRefs` alone carries BOTH encodings that must agree by hand — the sharpest recurrence
risk B7 collapses.

### B7 design (implementable) — `descendClauses` fold over the clause chain (Phase-B #3, 2026-06-19)

**Decision: option (b), a single shared depth-threading fold, NOT a `Depth` newtype.** Evaluated
all three:

- **(a) `Depth` newtype** whose only deeper-going op is a `forIn`-descent the body-recursion must
  consume. Tempting — it makes a flat-depth body recursion a *compile* error. But it does NOT pay
  off here: the four Eval walkers thread depth through a **single shared `match` arm body**
  (`.struct` already does `depth + 1`, `.comprehension` already routes to the `*Clauses` helper).
  A newtype would force `+1` to become `Depth.descendStruct` etc. at ~6 arms × 4 walkers (~24
  sites) and the comparison `id.depth == depth` becomes `id.depth == d.toNat` — churn with no new
  guarantee, because the recurring bug is NOT "someone wrote `depth` instead of `depth+1`", it is
  "someone re-derived the clause-chain rule independently". Eliminate the *re-derivation*, not the
  `Nat`. (And per the perf carve-out: a `Depth` newtype with `DecidableEq` against `BindingId.depth`
  drags more kernel reduction onto the hot resolve path for zero behavioral win.)
- **(b) one shared `descendClauses` combinator [CHOSEN].** A single total fold that OWNS the
  `+1-per-forIn`/`+0-per-guard`/body-at-end shape, parameterized over the per-step accumulator. All
  four `*Clauses` helpers become one-liners that instantiate it; `clauseFrameShift` is deleted
  (its value is recovered as the fold's final depth). The rule then lives in exactly ONE function
  body. A future walker that needs to descend a clause chain MUST call `descendClauses` to get the
  body's depth — it physically cannot get a different number without re-implementing the fold,
  which a reviewer sees immediately (vs today's invisible per-walker `+1`).
- **(c) richer de Bruijn coordinate** (frame *identity*, not just depth) — out of scope; that is
  item-7's frame-id problem, a different axis. B7 is depth only.

**The shared function (lives in `Value.lean`, the leaf where `Clause` is defined).** Pure,
total, no `Value`-recursion (it does NOT descend into sources/body — it only threads depth and
hands each piece back to the caller's per-walker logic). Signature:

```lean
/-- The single authority for comprehension clause-chain frame-depth threading: a `forIn`
    source is processed at the current depth and pushes one frame; a `guard` condition at the
    current depth pushes none; the body is processed at the accumulated depth. Mirrors
    `resolveClausesWithFuel`'s `clauseLoopFrame :: scopes` push. Generic over the accumulator
    `α` with a monoid-like `(empty, append)` so it instantiates as Bool(‖,false),
    List(++,[]), or a rewrite. -/
def descendClauses {α : Type}
    (empty : α) (append : α → α → α)
    (onSource : Nat → Value → α)      -- forIn source at current depth
    (onGuard  : Nat → Value → α)      -- guard condition at current depth
    (onBody   : Nat → α)              -- body at the accumulated (post-chain) depth
    (depth : Nat) : List (Clause Value) → α
  | []                       => onBody depth
  | .forIn _ _ src :: rest   => append (onSource depth src) (go (depth+1) rest)
  | .guard cond     :: rest  => append (onGuard depth cond) (go depth rest)
```

(`go` = the recursive self-call; written as a top-level `def` with `depth` as the recursed
argument, structural on the clause list — total, no fuel needed since the clause list shrinks.)

The three scanners instantiate it directly:
- `refsSelfEmbeddedLabelClauses f d sel labs cs body` = `descendClauses false (·||·) (fun d s => refsSelfEmbeddedLabel f d sel labs s) (fun d c => refsSelfEmbeddedLabel f d sel labs c) (fun d => refsSelfEmbeddedLabel f d sel labs body) d cs`
- `selfReferencedLabelsClauses` = same with `[] (·++·)` and `selfReferencedLabels`.
- `hasSelfRefAtDepthClauses` = same with `false (·||·)` and `hasSelfRefAtDepth` (no `labels`/`selfIndex` — its `onSource`/`onGuard`/`onBody` just close over `depth`).

`remapConjClauses` (the rewriter) does NOT fit the monoid fold cleanly (it rebuilds the clause
LIST, not an accumulator, and the body is remapped *separately* by `remapConjRefs`'s
`.comprehension` arm). Handle it in two parts, both off the same authority:
1. The **clause-list rebuild** stays a small dedicated recursion (it produces `List (Clause Value)`,
   structurally different from the accumulator fold), BUT its `+1-per-forIn` is the same rule — so
   it is the one site that genuinely needs the list shape. Keep it, and add a `native_decide`
   theorem `descendClauses_agrees_remapConjClauses` pinning that the depth `remapConjClauses` reaches
   for the body equals `descendClauses`'s `onBody` depth, so the two cannot drift.
2. **Delete `clauseFrameShift`** — `remapConjRefs`'s `.comprehension`/`.listComprehension` body
   recursion currently does `frameDepth + clauseFrameShift clauses`. Replace with a thin
   `clauseChainDepth : Nat → List (Clause Value) → Nat := descendClauses 0 (·+·) (fun _ _ => 0) (fun _ _ => 0) id` (the fold with the *identity* body-handler returns the final depth) — i.e. recover the total #for as `descendClauses … startDepth clauses - startDepth`, OR more directly keep the body-depth = `descendClauses`'s final depth. So both `remapConjClauses`'s source threading AND the body shift derive from the SAME fold; the two-encodings-in-`remapConjRefs` hazard is gone.

**Why `resolveClausesWithFuel` is NOT migrated to consume `descendClauses` directly.** The
authority threads a *scopes list* (`clauseLoopFrame :: scopes`), not a `Nat` depth, and is `mutual`
with `resolveValueWithFuel` (it resolves sources/body inline, not via a handed-back closure).
Forcing it through the `Nat`-depth fold would either (i) drag the scopes-stack into the fold's `α`
(then the four walkers carry an unused scopes param — leaky), or (ii) split resolve's mutual block.
Both are churn for no safety: resolve is the REFERENCE the fold is modeled on, and it is structurally
identical (`+1 frame per forIn`). Pin the agreement with a theorem instead:
`descendClauses_frame_count_matches_resolve` — for any clause list, the number of frames
`resolveClausesWithFuel` pushes (length of `clauseLoopFrame ::`-prepends) equals `descendClauses`'s
final-depth minus start. This makes resolve and the fold provably agree without coupling their code.
So B7's "single authority" is: `descendClauses` is the authority for the FOUR Eval walkers (the ones
that recurred), and a theorem ties it to `resolveClausesWithFuel` (the fifth, the reference).

**Module placement.** `descendClauses` + `clauseChainDepth` go in `Value.lean` (leaf, defines
`Clause`; imported by both `Resolve` and `Eval`). They are pure and `Value`-non-recursive, so no
import-graph disturbance. The agreement theorems live in `Kue/Tests/EvalTests.lean` (or a new
`Kue/Tests/ClauseDepthTests.lean` if EvalTests is split first by the test-org pass — it is at 2976
lines, overdue).

**Migration plan (ONE slice, four byte-identical-fixture-gated commits).** Each commit
re-verifies `lake build` + `scripts/check-fixtures.sh` (zero drift) + the per-walker `native_decide`
pins that already exist (A5/A5-followup pins are the regression gate):
1. **Introduce `descendClauses` + `clauseChainDepth` in `Value.lean`** + the two agreement theorems
   (`descendClauses_frame_count_matches_resolve`, and a `descendClauses` self-consistency pin).
   No walker changed yet → build + fixtures must be byte-identical (pure addition).
2. **Migrate the three scanners** (`refsSelfEmbeddedLabelClauses`, `selfReferencedLabelsClauses`,
   `hasSelfRefAtDepthClauses`) to one-line `descendClauses` instantiations. Their existing pins
   (`hasSelfRefAtDepthClauses` body-detected / loopvar-boundary / multi-`for` / guard-no-frame;
   the `selfReferencedLabelsClauses` and `refsSelfEmbeddedLabelClauses` pins) are the gate —
   each must stay green, byte-identical.
3. **Migrate `remapConjRefs`'s body shift + `remapConjClauses`** to derive from the fold
   (`clauseChainDepth` for the body, `descendClauses_agrees_remapConjClauses` pin); **delete
   `clauseFrameShift`**. Gate: `comprehension_conj_body_remap` fixture (`s.a.out: 99`) +
   `remap_comprehension_conjunct_reindexes_source_and_body` + the multi-`for` remap pin.
4. **Final verify + plan/log/breadcrumb.** End-to-end `comprehension_embed_self_narrow_body` +
   `comprehension_conj_body_remap` byte-identical; cert-manager content-identical (no regression,
   spot-check — this is a pure refactor, no eval-path change, so perf is unchanged → no
   `kue-performance.md` edit). Confirm via oracle (`/Users/chakrit/go/bin/cue` v0.16.1) that the two
   fixtures still match.

**One slice, not split.** ~5 walker bodies + 1 new leaf function + 2 theorems; mechanical and
fully fixture-gated. Splitting buys nothing — the four commits ARE the internal seams (checkpoint
discipline). Soundness gate: B7 is a behavior-PRESERVING refactor (the rule is already correct
post-A5/followup; B7 only de-duplicates its encoding), so the existing A5/A5-followup fixtures +
per-walker `native_decide` pins are a complete regression gate. The NEW guarantee B7 adds is the
two agreement theorems, which make a future drift a COMPILE/`native_decide` failure rather than a
silent wrong value. Add NO new behavioral fixture (nothing behavioral changes); add the agreement
theorems as the structural pin.

**A5. `remapConjRefs` comprehension BODY remapped at the wrong frame depth — DONE (`c3d0089`).**
Fixed in all 3 frame-depth walkers via a new `clauseFrameShift` (+1 per `for`, +0 per `guard`) and
per-walker depth-threading helpers (`remapConjClauses` increments per `for`; `selfReferencedLabelsClauses`
and `refsSelfEmbeddedLabelClauses` thread depth like resolution). The misleading depth-0 pin was
replaced with realistically-resolved native_decide pins + an end-to-end source fixture
(`comprehension_conj_body_remap`, oracle-checked vs cue 0.16.1 → `s.a.out: 99`). Sibling #3
(`refsSelfEmbeddedLabel`) was found UNSOUND (too-shallow under-fires the gate = a stale-value miss,
not perf-only as the old comment claimed) and fixed too. The OBSERVABLE wrong value for the
narrowing-in-`for`-body case was flipped by **A5-followup** above (`e00c3de`) — which turned out to
be a FOURTH walker (`hasSelfRefAtDepth`, the deferral gate), not a Pass-2 re-eval gap as first
diagnosed. Original diagnosis below for the record.

**A5 (original diagnosis). `remapConjRefs` comprehension BODY remapped at the wrong frame depth (HIGH — correctness
regression introduced by B1 `80df01e`).** The B1 `.comprehension`/`.listComprehension` arms recurse
the comprehension BODY at plain `frameDepth`, ignoring the loop frame each `for` clause pushes.
`resolveClausesWithFuel` (Resolve.lean:59-62) resolves the body under `clauseLoopFrame :: scopes`, so
a refId in the body that targets the merged conjunction frame is at depth `frameDepth + (#for-clauses)`,
NOT `frameDepth`. `remapConjRefs` compares `id.depth == frameDepth`, so it MISSES that ref (leaves the
stale conjunct-local index) and can spuriously rewrite an inner ref that coincidentally equals
`frameDepth`. The `.structComp` comprehensions bucket inherits the same bug (each element is a
`.comprehension` hit by the buggy arm). Clause SOURCES/guards at `frameDepth` are CORRECT (resolved in
the enclosing scope before the loop frame is pushed). Pre-B1 the comprehension was swallowed entirely
(also wrong); B1's partial fix did not thread the loop-frame depth.

Repro (oracle-confirmed, cue v0.16.1 — Kue WRONG):
```
t: {s: {p: 10, q: 20}} & {s: {a: {for v in [1] {out: zz}}, zz: 99}}
```
cue → `s.a.out: 99`; Kue → `s.a.out: 20`. The body's `zz` (conjunct-local slot 1, under the `for`
loop frame at depth+1) is not reindexed to the merged slot 3, so it resolves to merged slot 1 = `q`.

The existing pin `remap_comprehension_conjunct_reindexes_source_and_body` does NOT catch this: it
hand-writes a body refId at `⟨0,1⟩` (depth 0), but a real resolved body under a `for` is at depth ≥1,
so the pin tests an unreachable shape. **Fix:** thread an incrementing frame depth through the clause
chain exactly as `resolveClausesWithFuel` does — each `.forIn` clause adds 1 to the depth used for
subsequent clause sources and the body; guards do not. Add a NEW `remapConjClauses`-like walker (or
have it return the post-clause depth) so the body is remapped at `frameDepth + #forClauses`. Replace
the misleading hand-written pin with the end-to-end repro fixture above (testdata + FixturePorts) AND
a native_decide pin on a `.comprehension` with one `for` clause whose body ref is at depth+1.
NOT a low-risk inline fix (frame-depth logic change with regression-class risk); left for a fix-slice.

**Phase-B #2 cross-ref → B7.** A5 is the value-rewriter face of a deeper type-system gap: the
comprehension-body depth-shift rule (`for` pushes a frame, `guard` doesn't) is re-derived by hand
at 5 walkers with no type enforcing agreement — `resolveClausesWithFuel` (the authority),
`remapConj*` (A5: WRONG VALUE), the `refsSelfEmbeddedLabel` gate (conservative, sound by direction),
and `selfReferencedLabels` (a latent MISS: a `Self.<embedded>` read inside a `for` body is at
`depth+#for` but compared `== depth`, so the field is skipped in Pass-2 → stale value — same A1-class
hole, narrow). Fix A5 pointwise first (unblock the wrong value now), then harden structurally via
**B7** (a typed `Depth` / one shared `clauseDepthShift` the 5 walkers consume — makes a recurrence a
compile error). Add the `Self.<embed>`-inside-`for` Pass-2-selection case as a sibling pin to A5's.

**A1 + B1 — catch-all soundness sweep — DONE (`80df01e`, `a7b2724`).** Both HIGH soundness holes
(a catch-all over `Value` silently swallowing compound constructors a recursive function must
descend) fixed in one slice, plus a graph-wide sweep:
- **A1 (`80df01e`).** `selfReferencedLabels`/`refsSelfEmbeddedLabel` (Eval.lean) gained
  `builtinCall`/`embeddedList`/`structPattern`/`structPatterns` arms — a `Self.<embedded>` read
  inside a builtin arg (`len(Self.#x)`) is now visible to the Pass-2 gate + selection, so the
  builtin-wrapped field is no longer skipped (stale) after `2d87b8e`'s selective re-eval.
  Oracle-confirmed end-to-end (`len(Self.#hosts)` over a use-site-narrowed embedded label refreshes
  to the narrowed count, vs cue 0.16.1). Residual catch-all = scalar leaves + closure.
- **B1 (`80df01e`).** `remapConjRefs` (Eval.lean) gained `.structComp`/`.comprehension`/
  `.listComprehension`/`.embeddedList`/`.dynamicField` arms (+ new `remapConjClauses` helper) — a
  swallowed conjunct no longer keeps stale `.refId` frame indices after a field-reindexing merge.
  `closure` stays in the catch-all (its body's refs live in the captured-env space, not the
  conjunction frame — remapping would be wrong).
- **Sweep finding → NEW unsound catch-all FIXED (`a7b2724`).** `normalizeDefinitionValueWithFuel`
  AND `normalizeDefinitionsWithFuel` (Normalize.lean) both ended in `| _, value => value`,
  swallowing `.list`/`.listTail`/`.embeddedList`/`.comprehension`/`.listComprehension`/
  `.interpolation`/`.dynamicField` (and `.structComp` for the spine walker). A definition field
  whose value is directly a list/comprehension carrying a nested `#Def` never had that nested def
  closed. Added recursing arms (closing normalizer for def-body struct literals — CUE closes nested
  struct literals within a definition body, verified). Pins in NormalizeTests; zero fixture drift.
  → spawned NEW backlog item **B6** for the SEPARATE downstream enforcement gap this surfaced.
- **Sweep — defensible catch-alls (left, noted).** `resolveValueWithFuel:145` and
  `evalValueCoreWithFuel:2181` (pre-cleared, confirmed). Additionally confirmed defensible:
  `meetWithFuel` (delegates to exhaustive `meetCore`), `subsumesWithFuel` (false on non-matching
  pairs is correct for a partial order), `selectEvaluatedField`/`lookupField?`/`closeValue`
  (struct-specific by design, pass-through correct), `Format`/`Manifest` (no Value catch-all —
  fully enumerated).

**B6. Definition-body closedness ENFORCEMENT through regular fields + eager selector (MEDIUM —
soundness, surfaced by the A1/B1 sweep).** The Normalize sweep fix (`a7b2724`) closes nested defs
that normalize REACHES, but two gaps remain so a nested `#Def` still admits extra fields where CUE
rejects: (1) `normalizeFieldWithFuel` (Normalize.lean) descends ONLY definition fields, so a nested
`#Def` under a REGULAR field (`a: {#Inner: {…}}`, then `a.#Inner & {extra}`) is never normalized —
inside a def body CUE closes regular-field struct values too (`#D: {l: [{a:1}]}` → `#D.l[0] & {b}`
rejected); (2) even when normalize DOES close a nested def, the eager nested-selector path
(`x.#Inner & {extra}`) does not enforce the closedness (admits `extra`) — the `import-eager-closedness`
family (item 8). Both are reachable (oracle-confirmed vs cue 0.16.1). Fix needs a design-spike: the
shared `normalizeFieldWithFuel` conflates two contexts (closing inside a def body vs spine-walking at
top level) — split it, and route the eager selector path through closedness enforcement. NOT a
catch-all fix (a behavior change with the def-open-tail regression class of risk).

**B6 — PARTIAL (gaps 1+2 DONE `7da65d8`; one sub-gap DEFERRED). Design-spike `3b2beb6`.**

*Landed (sound):* a closed `#Def` nested under a REGULAR field (`a.#Inner & {extra}`, the eager
`x.#Inner` form too) now rejects undeclared fields, matching cue v0.16.1. One-edit fix in
`normalizeFieldWithFuel`: recurse a non-hidden/non-let field's value through the SPINE walker
(preserves the host's own openness — an instantiated regular struct stays open — while closing
nested `#Def`s). Hidden fields skipped → import bindings stay cue-lazy, decoupling B6 from
A2-followup (no cert-manager re-bottom). Gap 2 was the SAME root cause (the eager selector returns
the body verbatim; once normalize closes the def, the existing meet enforces it). 2 fixtures + 3
`native_decide` pins; zero fixture drift.

*DEFERRED sub-gap (separate mechanism — NOT forced, correctness-over-performance):* selecting a
nested REGULAR-field struct through a NON-instantiated def literal (`#D.l[0] & {b}`, `#D.r & {b}`).
cue closes these on the direct def-path (`#D.r & {a:1,b:2}` → `b: field not allowed`) but RE-OPENS
them on ANY instantiation/binding (`(#D & {}).r & {b}` and `(y: #D).r & {b}` both ADMIT `b` —
oracle-confirmed v0.16.1). So closedness of nested regular structs is a property of the literal
def-path selection, SHED by `&`-unification. Enforcing it needs the closing-vs-instantiation
distinction wired into `mergeStructN`'s closedness composition (the instantiation must re-open
nested regular structs — the `eval_def_with_self_ref_closes` EvalTests pin DEPENDS on instantiated
`out` staying `.regularOpen`). That is larger than one slice and carries over-close risk; STOPPED
and filed here rather than force an unsound close. Next: a dedicated design-slice for the
def-path-selection closed-marker (likely a value-level "closed on this selection path" flag the meet
clears on instantiation). Repros saved conceptually in the design section below.

**B6 design (implementable) — DONE 2026-06-19 (design-spike `3b2beb6`).**

*Repros (cue v0.16.1; all confirmed Kue ADMITS where cue REJECTS — Kue wrong, cue right):*
- R1 closed `#Def` under regular field: `a: {#Inner: {x:int}}`, `out: a.#Inner & {x:1, extra:2}`
  → cue `out.extra: field not allowed`; Kue exports `out:{x:1,extra:2}`.
- R1b list-nested def: `#D: {l: [{a:1}]}`, `out: #D.l[0] & {b:2}` → cue `out.b: field not allowed`;
  Kue exports `out:{a:1,b:2}`.
- R2 eager nested-selector: `x: {#Inner: {y:int}}`, `out: x.#Inner & {y:1, extra:3}` → cue
  `out.extra: field not allowed`; Kue exports `out:{y:1,extra:3}`.
- Sanity (must NOT change): R3 open def `#Inner: {x:int, ...}` admits `extra` (cue + Kue agree);
  R4 regular (non-def) struct stays open.

*Mechanism map (post-B2 closedness surface).* Closedness lives in `openness : StructOpenness`
(`.defClosed`/`.regularOpen`/`.defOpenViaTail`, `Value.lean`). Enforcement is in `mergeStructN`
via `applyStructClosedness`/`applyClosednessFrom` (`Lattice.lean:651-665`): a side with
`structIsOpen=false` (`.defClosed`) marks any merged field not in its allowed set
`fieldNotAllowed`. So the meet ALREADY enforces — the bug is that the nested `#Inner` body reaches
the meet still `.regularOpen` (never closed), so `leftOpen=true` and nothing is marked.
WHY it's never closed: `normalizeDefinitions` = `normalizeDefinitionsWithFuel` (the top-value
SPINE walker) runs at eval (`Eval.lean:2739`). Its `.struct` arm maps `normalizeFieldWithFuel` over
fields; `normalizeFieldWithFuel` routes ONLY `isDefinition` fields into the CLOSING normalizer
(`normalizeDefinitionValueWithFuel`) and returns every other field UNCHANGED. So a `#Inner` under a
REGULAR field `a` is never visited (gap 1). The eager selector `selectEvaluatedField`
(`Eval.lean:572`) returns `Field.value field` verbatim — so it carries WHATEVER openness normalize
left; gap 2 is NOT a separate selector defect, it is downstream of gap 1: once the nested def is
closed in normalize, the selector returns the `.defClosed` body and the existing meet enforces it.
Confirmed by reading `selectEvaluatedField` (no openness rewrite) — single root cause.

*The fix (one edit).* In `normalizeFieldWithFuel` (`Normalize.lean:95`), replace the regular-field
ELSE branch (`else field`, returns unchanged) with: recurse the field value through the SPINE
walker `normalizeDefinitionsWithFuel` — which closes nested `#Def`s (their `.struct _ _ _ []` arm →
`.defClosed`) WITHOUT closing the regular field's own struct (the spine walker preserves the host's
`openness`). Dispatch by class:
- `isDefinition` → close (current closing-normalizer path), unchanged.
- `isHidden` → leave UNCHANGED. **A2 trap guard:** import-package bindings are bound as `.hidden`
  fields (`Module.lean:164`); recursing them re-closes unreferenced nested defs and re-bottoms
  cert-manager/argocd (the exact A2 laziness trap). `hidden` must stay lazy. This also means B6 does
  NOT need A2-followup first — the two are decoupled by skipping hidden here.
- `letBinding` → leave UNCHANGED (conservative; not output, avoids churn).
- regular/optional/required → recurse value via `normalizeDefinitionsWithFuel fuel` (spine walker,
  preserves host openness, closes nested defs).

NO over-close risk: the spine walker keeps the host struct's own `openness`, only the nested
DEFINITION sub-bodies flip to `.defClosed` (which is correct — cue closes nested `#Def`s). R3 (open
def via `...` = `.defOpenViaTail`) is returned unchanged by the spine walker's `.defOpenViaTail`
arm, so it stays open. Regression gate: zero byte-drift on all existing fixtures (esp.
cert-manager/argocd module fixtures + def-open-tail) is the soundness signal.

**B2. Unify the 5 struct constructors into one normalized struct (MEDIUM-HIGH — headline).**
Collapse `struct`/`structTail`/`structPattern`/`structPatterns`/`structComp` into one
`struct (fields, openness : StructOpenness, tail, patterns)`; erases the 12-arm meet matrix,
its missing cross-combinations (`structPattern×structTail` etc. silently bottom today,
`Lattice.lean:458-478`), AND the `open_`/`hasTail` nonsense state. Subsumes item-8
`StructOpenness`. Design DONE (Phase-B #4, 2026-06-19): see the "B2 design (implementable)" section under
Phase-B B2. **Re-sequenced to consume-before-produce** (the design's B2.2→B2.3→B2.4 order is
unsafe): B2.1 (type+`mkStruct`, DONE) → **B2.3 match sites + B2.4 single meet arm (DONE
2026-06-19, `b3881c6`+`eff5627`, byte-identical, `structN` unproduced)** → **B2.2 production
flip — BLOCKED, inseparable from the ~940-site test-representation migration; combined with
CP3 (ctor delete + `structN→struct` rename) as one next megaslice** → B2.5 behavioral
cross-combination fix + new fixtures. `structComp` `open_`/`hasTail` collapse split out as a
separate B2b follow-on — **design DONE (Phase-B #6, 2026-06-19): option (a), `StructOpenness`
on the pre-eval `structComp` ctor (NOT folded into the meet-bearing `struct`), byte-identical,
ONE slice / 3 commits / ~44 sites / no worktree. See "B2b design (implementable)" above.**
Implementation pending.

**A2. Hidden-field deep bottom not propagated (MEDIUM — Kue wrong vs cue) — BLOCKED on a
representation change; SOUND shallow check retained (`46bd161`).** The proposed reached-vs-unreferenced
predicate (recurse the SELECTED value's output spine) is UNSOUND and was reverted. Verified vs cue
v0.16.1 (3-file import repro: a `main` importing a `dep` whose unreferenced fields hold both a derived
conflict AND an explicit `_|_` literal → cue exports `main` clean): cue's laziness tracks
OUTPUT-REACHABILITY (referenced via `pkg.#X`), NOT field class, and is equally lazy on an explicit
`_|_` literal as on a derived conflict. `bindImports` (Module.lean:160) binds each imported package as
an ordinary `FieldClass.hidden` field, indistinguishable from a real in-file `#u`, so an output-spine
recurse re-bottoms cert-manager. The predicate is NOT locally reconstructible at manifest with the
current representation. **A2-followup (the real fix, becomes a design-slice):** add an
import-binding marker — a distinct `FieldClass` axis (e.g. `packageBinding`) or a value wrapper on the
synthetic hidden field — so manifest can treat bound packages as cue-lazy while still recursing real
in-file hidden fields' output spines. Then `{#u: {x: _|_}}` → error becomes shippable (+ fixture).
Until then `{#u: {x: _|_}}` exporting `{}` is a KNOWN gap (Kue wrong, tracked here, NOT a cue bug).

**A3. `classifyDefinedness .disj` untyped invariant (MEDIUM — illegal-states) — DONE (`96bef05`).**
`classifyDefinedness` (Eval.lean) now classifies a `.disj` by its LIVE alternatives: no live arm ⇒
`.error` (the disjunction IS bottom), ≥1 live arm ⇒ `.defined`. Checks the "≥1 live arm" invariant at
the one site soundness depends on it, instead of trusting `.disj _ => .defined`. Chose this defensive
classification over a blanket smart `mkDisj` (option a): several sites build a `.disj` where pruning is
WRONG (`remapConjAlternatives` alpha-renaming, the conj-distribution sites), so a universal
`normalizeDisj` route is not semantics-preserving in one slice. Pins (PresenceTests): live disj
`.defined`; empty + all-bottom disj `.error`; presence test over all-bottom disj reports absent. Live
default/plain-disj guard regression-checked byte-identical to cue.

**A4. Catch-all hygiene (LOW) — DONE (inline, `f72995d`+1).** Enumerated all residual forms
explicitly in `classifyDefinedness` (replacing `_ => .incomplete`) so a future present-value
constructor forces a compile error. The exhaustive rewrite SURFACED a latent misclassification: a
`.structComp` (struct-with-embeds) was falling into `_ => .incomplete` — it is a PRESENT struct
value and now correctly classifies `.defined` (a presence test `X != _|_` over a structComp now
returns `true`, not a residual incomplete comparison). Build + fixtures green (zero drift), so the
case was either unreachable post-eval or strictly more correct. (The
`selfReferencedLabels`/`refsSelfEmbeddedLabel` catch-all is fixed under A1, still open.) See A4.

1. **`argocd-packs-argo` (argocd link 5) — `packs.#Argo` UNBLOCKED (2026-06-18).** Landed as a
   4-link correctness chain (commits `8ce2462`, `6436d08`, `14994e6`, `7898cff`; see the
   implementation-log "argocd-packs-argo" entry). `packs.#Argo & {[...]; …}` bottomed in isolation;
   the four independent root causes were: (1) list-embed use-site narrowing dropped in the
   conjunction-deferral fold (`spliceNarrowingOperand?`); (2) disjunction-arm pruning over-fired on
   UNSET impossible optional fields (`fieldBottomCounts` skips optionals) + hidden-bottom propagation
   at manifest; (3) a cert-manager REGRESSION from (2)'s deep manifest recurse — fixed by a SHALLOW
   `isBottom` check (imported-package bindings carry unreferenced conflicts cue is lazy on); (4) the
   presence test `X != _|_` over a `.disj` classified incomplete, dropping the `parts.#Metadata`
   `if Self.#ns != _|_ {namespace}` guard — `classifyDefinedness` now treats `.disj` as `.defined`.
   `packs.#Argo` + all three components (`#ArgoRepo`/`#ArgoApp`/`#ArgoProject`) now content-identical
   to cue (sorted-key, modulo field-order #3) in the scratch module. ~71s — perf-wall-adjacent (item
   7). Full `apps/argocd.cue` HEADLINE in the latest breadcrumb. KNOWN latent shape (not on the
   `packs.#Argo` path, deferred): an inline `Self=`-struct embedding a no-default disjunction-of-defs
   whose arms read host-`Self` is eagerly resolved before use-site narrowing (the `resolveEmbedDefBodies?`
   deferral-detection half is correct but insufficient — also needs eager/deferred double-eval dedup).
   ```cue
   #App: {#name?: string, if #name != _|_ {name: #name}, ...}
   out: packs.#Argo & {#name: "web"}  // now content-correct vs cue
   ```

2. **`truncate-primitive` (HIGH — soundness hardening, Phase B step 1).** The
   truncation-bump invariant (a `fuel=0` helper that drops fields MUST bump `truncCount`)
   is currently held by DISCIPLINE across six sites. Step 1 (do now): add
   `EvalState.truncate` combinator fusing bump+return; rewrite all six sites — strictly
   behavior-preserving, byte-identical fixtures, localizes the bump to one definition.
   Step 2 (only if cheap): a `withFuel` combinator routing the `fuel=0` dispatch so a
   seventh helper physically cannot skip the bump — attempt only for the four
   top-level-`fuel`-dispatch helpers; STOP at step 1 + a one-line doc invariant if step 2's
   restructuring exceeds mechanical. Priority HIGH: this is the illegal-states-unrepresentable
   reason-to-be and the audit-#6 corruption it prevents already shipped once latent.

3. **Regex extraction → `Kue/Regex.lean` (ACTIONABLE, PARALLEL-SAFE).** The ~240-line
   engine (`Value.lean`, `RegexAtom` + fuel-bounded matcher + alternation/group expansion)
   depends only on `Char`/`String`, is consumed by `Eval`/`Builtin` only, sits below the
   closure ctor in `Value.lean`. Extracting makes `Value.lean` a TRUE leaf. New leaf module +
   `import Kue.Regex` in the consumers (`Eval`/`Lattice`/`Order` use `stringRegexMatches`; NOT
   `Builtin`). Phase-B B5 confirmed clean. NOTE: `Init.Data.String.Search` is ALSO imported by
   `Parse.lean`, so it stays in the build — the win is `Value.lean` shedding it, not removing it
   project-wide. Zero conflict with any `Eval.lean` slice — runs in its own subagent concurrently.

4. **EvalOps extraction → `Kue/EvalOps.lean` (ACTIONABLE).** ~256 lines of self-contained
   pure scalar algebra (`evalAdd…evalBinary`) carved out from under the recursive evaluator,
   no back-edge into `evalValueWithFuel`. CORRECTION (Phase-B B5): it is NOT `{Value, Decimal}`-
   only — it also calls `divValue`/`modValue`/`quoValue`/`remValue` from `Builtin.lean`. So
   `EvalOps` imports `{Value, Decimal, Builtin}`, OR move those four div/mod helpers into
   `EvalOps`/`Decimal` first (cleaner — they are pure `Value→Value` decimal ops with no Builtin-
   dispatch dependency). Resolve the import shape in the slice. Mechanical otherwise.

5. **Test-org pass (periodic) — DONE for `EvalTests` (2026-06-19).** `EvalTests.lean`
   (~3022 lines, the worst offender) split by subsystem into per-`Kue/`-area modules,
   behavior- and coverage-preserving (theorem 256→256, native_decide 253→253, def 28→28,
   verified pre/post; zero fixture byte-drift):
   - `EvalTestHelpers.lean` — shared `evalSourceMatches` + `exportJsonMatches` source oracles.
   - `EvalPerfTests.lean` — frame-id sharing, Pass-2 selective re-eval, fuel-saturation, perf-B.
   - `ClosureTests.lean` — closure ctor/eval/producer/meet, embed chains, import-selector aliases.
   - `TwoPassTests.lean` — two-pass gate, B1/A1/A5 remap, B7 `descendClauses` agreement,
     hidden-def + embed-disj narrowing.
   - `EvalTests.lean` (slimmed ~1210 lines) — ref/selector/cycle eval, arithmetic/ordering/unary,
     list-comprehensions, scalar-embed collapse, F1 default-mark algebra, refs/aliases, lazy-chain.
   All wired into `Kue/Tests.lean`. `testdata/` left untouched (clean, no churn). REMAINING for a
   future pass: `FixturePorts` (~2524, generated — leave whole), `FixtureTests` (~1093),
   `StructTests` (~765), `BuiltinTests` (~735) — not yet split; schedule when next overdue.
   B4 folded in (next item).

6. **Field-ordering parity #3 (MEDIUM, DEEP — byte-parity vs cue).** cue orders
   `ref & {own}` own-fields-first; kue is left-struct-first (`mergeStructFieldsWith`,
   `Lattice.lean`). cue's rule tracks where each label is *first introduced* across
   conjuncts in eval order — faithful replication needs a per-`Field` introduction-provenance
   key threaded through every merge/manifest site, not a one-line fold flip. The byte-order
   tail between cert-manager content-match and byte-exact cue; affects the dominant
   `#Def & {…}` prod9 pattern's exported order. Multi-slice + a provenance-key design spike
   first. Do AFTER argocd unless it blocks a needed fixture.
   ```cue
   #Def: {kind: "X", ...}
   out: #Def & {own: 1}  // cue: own-fields ordered first
   ```

7. **Per-eval-cost perf (frontier #2, NOW MORE URGENT — downstream of correctness).** The heavy
   `argo` sub-package (`argo_.{stage9,bluepages,…}.configs`) times out >200s once past the early
   bottom; cert-manager's residual GREW from ~31s to ~92s after the link-3/4 fixes (the parser
   open-struct-with-embeds collapse routes `{embed;…;...}` defs through the single-`.structComp`
   two-pass path — more embed re-evaluation than the old `.conj` split — and the two-pass gate now
   fires on more/deeper refs). All SOUND (byte-identical fixtures), but it pushes more shapes toward
   the wall: `defs.#TLSRoute` ~4s→~9s, `defs.#Secret` ~3s→~13s, `packs.#Argo` ~36s. Root is
   exponential frame-id divergence — structurally-identical re-pushes get fresh ids, defeating the
   memo `envIds` key. Fix is frame-id sharing / canonical frame identity (same fields + same parent
   id-stack → reuse id), audit-heavy (must not violate "independently-built frames never falsely
   share"). Frame-id sharing + force-memo are partially landed; finish them here. Profile against a
   resolving target (cert-manager, or `packs.#Argo` once link 5 lands).

   **PART-B audit verdict (2026-06-18) — the 31s→92s regression is REDUNDANT, not inherent;
   a cheap fix reclaims most of it.** Measured eval-counts (`evalStructRefsCalls`/`runEvalStats`)
   on a faithful `{embed; …; ...}` open-def repro, new (HEAD `15f871d`) vs old (`6667a7e`):
   headline 34→86 (2.5×, mirrors the 3× wall). Isolated by probe:
   - The dominant cost is the embedding-`Self` **Pass-2 re-eval** (the `.structComp` eval arm,
     `Eval.lean:1976-1982`), NOT the parser-collapse routing. Gate-fires vs gate-not-needed on
     the same open shape: 86 vs 43.
   - Pass 2 calls `pushFrame (fields ++ newEmbeddedFields)` → a DIFFERENT `FrameKey` →
     a FRESH frame-id, so every static field re-evaluated in Pass 2 MISSES the Pass-1
     `cache`/`satCache` (both keyed on `env.ids`). It recomputes EVERY static field, including
     ones that never read `Self.<embedded-label>`.
   - Quantified: each unrelated heavy field costs +8 evals when gate fires (full duplicate of its
     Pass-1 eval) vs +0 if it weren't re-run. N-unrelated-field scaling is exactly linear: gate
     +16/field, no-gate +8/field, `cacheHits` FLAT at 8 (zero reuse). The +8/field is pure
     redundant recompute. Headline N=3: 86 evals, of which 3×8=24 are redundant
     (~28% on this small shape; larger on real `#Def`s with many fields + few `Self.<embed>`
     reads).
   - **Cheap fix — LANDED (Pass-2 selective re-eval).** `embeddedSelfPassFieldIndices` returns the
     TRANSITIVE-closure set of field indices the Pass-2 frame change can alter; both `.structComp`
     Pass-2 sites re-evaluate ONLY those (feeding their `(index, field)` entries to
     `evalFieldRefsListWithFuel`), reusing Pass-1 values for the rest. SOUND + byte-identical
     (fixtures + cert-manager output unchanged); eval-count pins prove +10 → +5 per unrelated field
     (n=8: 94 → 51 core evals, ~46% on the modeled shape). **BUT it did NOT reclaim the
     cert-manager 31s→92s regression** — wall-clock stayed ~88-104s (±15-20s noise swamps it). The
     audit's modeled redundancy is real but is NOT what dominates cert-manager. The cheap fix helps
     many-unrelated-field defs (`packs.#Argo`-class), so it ships; the cert-manager regression
     stands.
   - **The deeper lever (STILL OPEN — now the primary perf frontier): canonical frame identity.**
     Structurally-identical re-pushes get fresh ids, defeating the memo `envIds` key (exponential
     divergence). Same fields + same parent id-stack → reuse id, audit-heavy (must not violate
     "independently-built frames never falsely share"). This is what actually reclaims cert-manager
     and unblocks `packs.#Argo`'s wall. Profile against cert-manager (resolving) + `packs.#Argo`
     once link 5 lands.

8. **Borderline / LOW (opportunistic; none block adoption).**
   - **`scalar-embed-with-decls`** — `{#a:1, 5}`→`5` (cue manifests `5`, keeps `.#a`
     selectable); kue bottoms. Incompleteness, not unsound. Needs a scalar-with-decls
     carrier (the `.embeddedList` analog for scalars). Do NOT "fix" item-relate by widening
     the scalar collapse — that is the unsound direction.
     ```cue
     out: {#a: 1, 5}  // cue -e out: 5 (and .#a stays selectable); kue bottoms
     ```
   - **`module-file-scoped-imports`** (arch-sized) — kue merges every sibling file's import
     bindings into one shared package frame; CUE scopes them per-file. Bites only the
     same-NAME-different-target case (which dedupe turned silent-wrong); real prod9 doesn't
     hit it. Bind each file's imports into a per-file scope frame.
   - **`import-eager-closedness`** (MEDIUM) — an imported plain closed `.struct` def met
     with extra fields admits them on the EAGER selector path (the force path closes
     correctly). Close imported def bodies at load, or route the eager path through
     `normalizeDefinitionValueWithFuel`. Pin both silent-admit and incomplete-mask facets.
   - **`scalar-embed` provenance follow-ups** — opportunistic pins (3-level flatten, disj
     ops beyond `+`/`&`, composed select-into-F1-default) when next touching Lattice/Eval.
   - **Parser strictness** — `*(1|2)` laxity (cue rejects at parse); `__x` double-underscore
     accepted (cue reserves `__`-prefixed idents). Track under a parser-strictness pass.
     ```cue
     x: *(1|2)  // cue rejects at parse: "preference mark not allowed at this position"
     ```
   - **DRY `selectEvaluatedField .disj`** — the resolved-default arm re-lists the 5-arm
     struct-shape dispatch; collapse to `match resolveDisjDefault? alternatives with | some
     v => selectEvaluatedField v label | none => …` (gains free nested-disjunction recursion).
   - **`resolveEmbeddedDisjDefault` (`Eval.lean:2093`, next-audit confirm)** — verify the
     pass-1 label-surfacing path does NOT also need the use-site-narrowing distribution that
     `embed-disj-arm-fallthrough` added, or that label-surfacing-only is correct there.
   - **`.structComp` openness 3-state sum — SUPERSEDED by Phase-B B2.** The `open_`/`hasTail`
     nonsense state is now folded into the larger struct-constructor unification (B2), which
     introduces `StructOpenness` as part of collapsing all five struct constructors. Do it there,
     not standalone. (B2 also closes the missing meet cross-combinations the two-bool design
     never surfaced.)
   - **`comprehensionPairs` `.embeddedList` (Phase-B B3, LOW).** `for x in {#a:1,[1,2]}` iterates
     zero times (source evals to `embeddedList`, `comprehensionPairs` returns `none`). Add an
     `.embeddedList` arm; ride-along with the `scalar-embed-with-decls` work above. Fixture
     `for x in {#a:1,[1,2]} {x}` → `[1,2]`.

## Pointers (history + reference for anything dropped)

- **Completed-slice history + verification record:** [`../reference/implementation-log.md`](../reference/implementation-log.md)
  (chronological, one entry per commit) and `git log`.
- **CUE-divergence record:** [`../reference/cue-divergences.md`](../reference/cue-divergences.md).
- **Decisions:** [`../decisions/`](../decisions/) (compatibility target, correctness-over-perf,
  Value-model fork resolution).
- **Slice loop + audit cadence:** [`../guides/slice-loop.md`](../guides/slice-loop.md).
- **Status page:** [`../www/index.html`](../www/index.html) — single human-scannable status
  page (where Kue stands, what works, what's next); refreshed on plan-hygiene passes.
- **CUE semantics reference:** [`cue-language-guide.md`](cue-language-guide.md);
  [`architecture.md`](architecture.md) + [`compat-assumptions.md`](compat-assumptions.md)
  in this `spec/` directory.
- **Latest session state / next step:** the most recent breadcrumb in [`../notes/`](../notes/).
