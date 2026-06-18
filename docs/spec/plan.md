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

- **B2 (MEDIUM-HIGH — headline refactor; subsumes item-8 `StructOpenness`).** `Value` has
  FIVE struct-bearing constructors (`struct`, `structTail`, `structPattern`,
  `structPatterns`, `structComp`) plus `embeddedList`. `meetWithFuel` (`Lattice.lean`)
  carries a 12-arm pairwise matrix (lines 971-1044) over `{struct, structTail,
  structPattern, structPatterns}` — and the matrix is INCOMPLETE: `structPattern×structTail`,
  `structPatterns×structTail`, and `structPattern×structPatterns` have NO explicit arm and
  fall through to the early `.bottom` defaults (`Lattice.lean:458-478`). Since
  `structPattern`/`structPatterns` carry an `open_` and are valid CUE (`{[string]: T, ...}`),
  meeting an open pattern-struct with a tail-struct silently bottoms where CUE unifies — a
  latent correctness hole the representation makes EASY to leave incomplete. Fix (own slice,
  large): collapse the struct constructors into ONE normalized `struct` carrying
  `(fields, openness, tail : Option Value, patterns : List (Value × Value))`, where
  `openness` is the 3-state `StructOpenness` sum (`regularOpen | defClosed | defOpenViaTail`)
  that item-8 already proposed — so the `open_`/`hasTail` nonsense state AND the missing meet
  cross-combinations are BOTH erased by construction, and the 12-arm matrix becomes one merge.
  This is the single biggest type-system-leverage win in the graph. ~28 `.structComp` sites +
  the 5-ctor match sites across `Lattice`/`Eval`/`Normalize`/`Resolve`/`Order`/`Manifest`/
  `Format`/`Parse` — design-spike first (normalization invariant + smart constructor), then a
  mechanical multi-commit migration. Supersedes the standalone item-8 `StructOpenness` entry
  (fold it into this). Byte-identical fixtures required + a pin for each previously-missing
  cross-combination (`structPattern×structTail` etc. unify, not bottom).

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

- **B4 (LOW — seam test coverage gap).** Foundational modules with NO dedicated unit-test
  module, exercised only indirectly via fixtures/`EvalTests`: `Lattice` (the meet operator!),
  `Format`, `Decimal`, `Json`, `Base64`. `Lattice` most deserves a direct `LatticeTests`
  pinning `meet`/`join` algebra (incl. the struct-shape arms B2 touches — a `LatticeTests`
  written first de-risks the B2 refactor). Add `LatticeTests` + small `DecimalTests`/
  `FormatTests`; ride-along with the test-org pass (item 5) or before B2.

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
**TWO-PHASE AUDIT DUE (2 slices since last: A5 + A5-followup)** → **B7 (MEDIUM-HIGH —
frame-coordinate type-tightening; subsumes A5's structural fix, now FIVE hand-coded walkers)** →
B6 design-spike / B2 headline struct refactor (design-spike then migrate) / item 1 follow-up →
parallel-safe cleanups (3,4,5 + B4/B5) interleaved → deeper parity/perf (2,6,7) → borderline/LOW
(8 + B3) ride-alongs.

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

**B7. Frame coordinate is an untyped `Nat` — the comprehension-body depth-shift rule is
re-derived by hand at 5 walkers (MEDIUM-HIGH — type-system leverage; root cause of A5 + its
followup).** The de Bruijn "body lives `#forClauses` deeper" rule lives once in
`resolveClausesWithFuel` but is open-coded at five sites: correctly in resolve, and (all now
fixed by hand) `remapConjClauses` (A5), `selfReferencedLabelsClauses` (A5), `refsSelfEmbeddedLabelClauses`
(A5), and `hasSelfRefAtDepthClauses` (A5-followup — the deferral gate, was a real loop-deep MISS, not
the "over-detect only" the old comment claimed). Five `*Clauses` helpers all repeat +1-per-`for`. A
typed `Depth` (only obtainable deeper via a `forIn`-descent the body-recursion must route through)
makes the whole A5 family a compile error. A5 + followup point-fixes are landed; B7 now factors the
shift into ONE shared authority the 5 walkers consume. Design-spike first. See Phase-B #2 B7.

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

**B2. Unify the 5 struct constructors into one normalized struct (MEDIUM-HIGH — headline).**
Collapse `struct`/`structTail`/`structPattern`/`structPatterns`/`structComp` into one
`struct (fields, openness : StructOpenness, tail, patterns)`; erases the 12-arm meet matrix,
its missing cross-combinations (`structPattern×structTail` etc. silently bottom today,
`Lattice.lean:458-478`), AND the `open_`/`hasTail` nonsense state. Subsumes item-8
`StructOpenness`. Design-spike + multi-commit migration; byte-identical fixtures + a pin per
previously-missing cross-combination. See Phase-B B2.

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

5. **Test-org pass (ACTIONABLE, periodic).** Theorem modules in `Kue/Tests/` are oversized
   (`EvalTests` 2688, `FixturePorts` 2524, `FixtureTests` 1093, `StructTests` 765,
   `BuiltinTests` 735 — Phase-B confirmed sizes). Split each by subsystem in ONE pass; leave
   `FixturePorts` whole (generated). `testdata/` is clean and well-organized (no orphans; 155
   cue pairs + 22 export + 30 module dirs; both `FixturePorts` and `check-fixtures.sh` cover
   it with zero silent gaps) — do NOT churn it. Run AFTER the next correctness slice lands its
   pins. FOLD IN B4: while here, add the missing seam unit-tests (`LatticeTests` for the meet
   operator above all, plus small `DecimalTests`/`FormatTests`) — `Lattice`/`Format`/`Decimal`/
   `Json`/`Base64` currently have NO dedicated module, only indirect fixture coverage. Write
   `LatticeTests` BEFORE B2 if B2 lands first (de-risks the struct-meet rewrite).

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
