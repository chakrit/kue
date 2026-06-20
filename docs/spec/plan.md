# Kue Plan

The live implementation roadmap. Kept small, current, and actionable — one focused slice
at a time. The full record of completed slices lives in
[`../reference/implementation-log.md`](../reference/implementation-log.md), retained for
verification; this file holds only where we are and what's next. Distilled 2026-06-18 back
to the live roadmap (history moved to the log + git); a periodic plan-hygiene pass keeps
it lean (see [`../guides/slice-loop.md`](../guides/slice-loop.md)).

## North Star

Kue targets **CUE v0.15 semantics, done correctly**. Where the official `cue` v0.15 binary
is buggy, Kue should implement the *correct* behavior, not replicate the bug. The
compatibility target is the language as specified, not bug-for-bug parity with the
reference implementation. See
[`../decisions/2026-06-14-cue-compatibility-target.md`](../decisions/2026-06-14-cue-compatibility-target.md).

## Working Principles

- Use TDD where behavior is testable: write theorem checks or executable examples before
  implementation.
- Keep the semantic model simple before optimizing representation.
- Prefer total functions and explicit semantic values over hidden host-language failure.
- Avoid dependencies until they clearly remove more complexity than they add.
- Keep each commit small enough to review, revert, or extend safely. One slice per commit;
  the commit subject mirrors the slice title.
- **Correctness over performance.** A latent unsound result is a Violation even with no
  failing fixture; a perf miss is acceptable. See [`../decisions/`](../decisions/).
- **Real-app compilation is a stress test, not the goal.** Getting prod9 infra (argocd,
  cert-manager, …) to `export` *validates* correct semantics; it is never an end in
  itself. Rank slices by spec-correctness and clean design evolution — never let one app's
  shape pull the loop into deep per-app special-casing. A real-app blocker that needs
  app-specific narrowing is parked as a stress-test finding (e.g. argocd/Bug2-5), not
  promoted to the critical path; it resolves as the general semantics mature.

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
- **Fuel-saturation perf.** Eval count is FLAT across fuel (bracketed monotonic truncation
  counter; truncated values stay fuel-keyed, saturated results go fuel-free). `evalFuel =
  100`. Frame-id sharing + force-memo (partial).
- **Builtins.** `base64.Encode`, `json.Marshal` (`Kue/Json.lean`), `yaml.Marshal`
  (`Kue/Yaml.lean`), `strings.*`/`list.*`/`math.*` hardcoded namespaces. Multiline strings
  (`"""`/`'''`).
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
- **cert-manager: content-identical drop-in, ~30.6s.** Exports correctly at production
  fuel, byte-identical to `cue` modulo field-order #3 (per the item-7 cache-key hash
  digest, which collapsed the ~119s O(N²) wall to ~30.6s).
- **argocd: `packs.#Argo` (link 5) content-correct** (4-link chain, 2026-06-18).
  `packs.#Argo` and all three components content-identical to cue (sorted-key, modulo
  field-order #3) in the scratch module. **Full `apps/argocd.cue` STILL bottoms** — the
  residual blocker is a deterministic correctness divergence (Bug2-4 / Bug2-5, the
  let-buried two-level embed comprehension-guard narrowing), NOT a fuel ceiling; tracked
  in `spec-conformance-audit.md` § Consolidated fix backlog. cert-manager byte-identical
  to baseline (no regression).

## Live Backlog (open work, ranked)

Correctness gates real-app adoption; cleanups are parallel-safe filler.

**Spec-conformance fixes (ranked): see
[`spec-conformance-audit.md`](spec-conformance-audit.md) § Consolidated fix backlog — the
authoritative list.** That backlog owns the ranked spec-conformance work: the argocd
export blockers (**Bug2-4**, then the residual **Bug2-5** narrowing-injection),
structural-cycle detection (**D#2a/D#2b**), regex feature coverage (**RX-2a**), the MED
tail (**D#1b/D#1c**, **D#3** let-clauses, **SC-3** disj-display, **BI-1** Unicode
case-fold, **BI-2** `math.Pow`/`list.Sort`, **F-3** qualified import), **SC-4**
(spec-gap-first), the spec-gap ratifications, and low/hardening (**A#6** `containsBottom`
fuel-cap, **DRY-1** shared walker extraction). Do NOT duplicate that ranking here; this
file holds only the NON-spec-conformance roadmap below.

### Plan-only roadmap (not in the spec-conformance backlog)

Sequence after the spec-conformance blockers above: bank the cheap-ready cleanups, then
PIVOT to the perf frontier (item 7's residual), then the deeper parity gap (item 6).
Numbered items 2–8 below are the durable plan-only list; the ranked DONE chain that
produced today's state (A1–A5, B1–B7, B2-family, A2-followup, the Bug2-1/2/3 argocd
narrowing chain) is archived under **Audit & design history** below + the
implementation-log.

**Open plan-only fix-slices (folded from past audits; LOW unless noted):**
- **A-EN3 (LOW — DRY, Phase-B refactor candidate).** `defFrameRefIndices`,
  `selfReferencedLabels`, and `refsSelfEmbeddedLabel` are three structural `Value`
  recursions with the same per-ctor descent and `+1`-per-frame-pusher depth discipline,
  differing only in their leaf payload — consolidatable behind one generic frame-aware
  fold (the same B7 did for the clause-depth walkers). `closeDefFrameReadIndices` REUSES
  `defFrameRefIndices` (no new walker) and `embedDisjArmDeclLabels` is a shallow one-hop
  ref-follow (NOT a 4th walker), so A-EN3 is exactly those three. **PARKED** behind the
  argocd export unblock — interposing a generic-fold refactor (must preserve totality +
  B7-style agreement theorems) ahead of the last blocker re-couples two risks. Land it as
  the FIRST LOW cleanup AFTER argocd unblocks, when it races nothing. (Note: the `DRY-1`
  shared-walker extraction in audit.md is a sibling of this — sequence both after the
  argocd unblock to avoid walker-edit contention.)
- **B2-A1 (LOW — latent, currently lossless).** `applyEvaluatedStructN` (`Eval.lean:330`)
  routes the patterns-present case through a meet that DROPS the `tail` argument.
  Currently lossless because the only tail a parsed struct can carry is the bare `...` =
  `.top` (cue v0.16.1 rejects typed ellipsis `...T`), and dropping then re-supplying `some
  .top` via `coherentTail` is a no-op. A GUARDED ASSUMPTION, not an active bug: it breaks
  the day typed-ellipsis lands. Fix: thread `tail` through the pattern arm (`meet
  (mkStruct [] openness tail patterns) …`) + a `native_decide` round-trip pin. Pairs with
  any future typed-ellipsis slice.
- **B2-A2 (LOW — test-gap fill).** The two B2.5 fixtures both exercise patterns-on-LEFT ×
  tail-on-RIGHT. The reverse orientation (tail-on-LEFT × patterns-on-RIGHT) and
  both-tails+ patterns are pinned only by `native_decide`, not end-to-end. Add
  `testdata/cue/definitions/{tail_pattern_unify,both_tails_pattern_unify}` pairs +
  FixturePorts entries (oracle-confirmed: `{a:5,...} & {[string]:int}` → `{a:5}` open;
  reverse same).
- **B3 (LOW-MEDIUM — incompleteness, embeddedList family).** `comprehensionPairs`
  (`Eval.lean:988`) returns `none` for `.embeddedList`, so `for x in {#a:1,[1,2]}` (source
  evaluates to an `embeddedList`) iterates ZERO times where CUE iterates `[1,2]`. Add an
  `.embeddedList items _ _ => some (listPairsFrom 0 items)` arm. Incompleteness, not
  unsound; folds into the `scalar-embed-with-decls`/embeddedList edge family (item 8) —
  ride-along when next touching that area. Fixture `for x in {#a:1,[1,2]} {x}` → `[1,2]`.
- **B5 (LOW — extraction-item corrections, cleanup).**
  - Item 3 (Regex → `Kue/Regex.lean`): CONFIRMED clean — the engine touches only
    `Char`/`String`/`RegexAtom`, consumed by `Eval`/`Lattice`/`Order` via
    `stringRegexMatches`. After extraction, drop `Init.Data.String.Search` from
    `Value.lean` (still imported by `Parse.lean`, so it stays in the build — the win is
    `Value.lean` becoming a true leaf).
  - Item 4 (EvalOps → `Kue/EvalOps.lean`): the scalar-op block is NOT `{Value,
    Decimal}`-only — it also calls `divValue`/`modValue`/`quoValue`/`remValue` from
    `Builtin.lean`. So `EvalOps` must import `Builtin` too, OR those four helpers move
    into `EvalOps`/`Decimal` first. Resolve the import shape in the slice.
  - `Order.lean` (subsumption) is a DELIBERATE test-only oracle (imported only by
    `Tests/*`), NOT dead code and NOT duplicated — `meet` (join) and `subsumes` (partial
    order) are orthogonal. Recorded so a future audit does not re-flag it as an orphan.
- **A2-x (LOW, latent) — `importBinding` merge-asymmetry vs the old `.hidden`.**
  `mergeFieldClass` returns `none` for `importBinding & <real field>` (merges only with
  itself), whereas the old `.hidden` would have merged via the `.field` arm. Currently
  unobservable: the only collision is one cue rejects at LOAD (`redeclared as imported
  package name` — see A2-y). Note the refusal is intentional in the merge-arm docstring;
  revisit if A2-y lands.
- **A2-y (LOW, pre-existing) — missing import-name redeclaration check.** A top-level
  field colliding with an imported package's local name (`import ".../dep"` + `dep: {…}`)
  is a LOAD error in cue; Kue silently keeps both. A missing loader-level diagnostic —
  file as a small loader slice; behind item 7. (Both A2-x/A2-y are corners prod9 real apps
  don't hit.)

**Durable plan-only items (numbered for cross-reference):**

1. **`argocd-packs-argo` (argocd link 5) — DONE (2026-06-18,
   `8ce2462`/`6436d08`/`14994e6`/ `7898cff`).** `packs.#Argo` + all three components
   content-identical to cue in the scratch module (~71s). Full detail in the
   implementation-log "argocd-packs-argo" entry. The full-app blocker is now Bug2-4/Bug2-5
   (spec-conformance backlog). KNOWN latent shape (not on the `packs.#Argo` path,
   deferred): an inline `Self=`-struct embedding a no-default disjunction-of-defs whose
   arms read host-`Self` is eagerly resolved before use-site narrowing
   (`resolveEmbedDefBodies?` deferral-detection is correct but insufficient — also needs
   eager/deferred double-eval dedup).
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
   top-level-`fuel`-dispatch helpers; STOP at step 1 + a one-line doc invariant if step
   2's restructuring exceeds mechanical. Priority HIGH: this is the
   illegal-states-unrepresentable reason-to-be and the audit-#6 corruption it prevents
   already shipped once latent.

3. **Regex extraction → `Kue/Regex.lean` (ACTIONABLE, PARALLEL-SAFE).** The ~240-line
   engine (`Value.lean`, `RegexAtom` + fuel-bounded matcher + alternation/group expansion)
   depends only on `Char`/`String`, is consumed by `Eval`/`Builtin` only, sits below the
   closure ctor in `Value.lean`. Extracting makes `Value.lean` a TRUE leaf. New leaf
   module + `import Kue.Regex` in the consumers (`Eval`/`Lattice`/`Order` use
   `stringRegexMatches`; NOT `Builtin`). Phase-B B5 confirmed clean. NOTE:
   `Init.Data.String.Search` is ALSO imported by `Parse.lean`, so it stays in the build —
   the win is `Value.lean` shedding it, not removing it project-wide. Zero conflict with
   any `Eval.lean` slice — runs in its own subagent concurrently. (Cross-check: audit.md's
   RX-1 replaced the regex ENGINE with an RE2-equivalent NFA; reconcile this extraction
   item against the as-built engine before scheduling.)

4. **EvalOps extraction → `Kue/EvalOps.lean` (ACTIONABLE).** ~256 lines of self-contained
   pure scalar algebra (`evalAdd…evalBinary`) carved out from under the recursive
   evaluator, no back-edge into `evalValueWithFuel`. CORRECTION (Phase-B B5): it is NOT
   `{Value, Decimal}`- only — it also calls `divValue`/`modValue`/`quoValue`/`remValue`
   from `Builtin.lean`. So `EvalOps` imports `{Value, Decimal, Builtin}`, OR move those
   four div/mod helpers into `EvalOps`/`Decimal` first (cleaner — they are pure
   `Value→Value` decimal ops with no Builtin- dispatch dependency). Resolve the import
   shape in the slice. Mechanical otherwise.

5. **Test-org pass (periodic) — DONE for `EvalTests` (2026-06-19); REMAINING split open.**
   `EvalTests.lean` (~3022 lines) split by subsystem into per-`Kue/`-area modules
   (`EvalTestHelpers`/`EvalPerfTests`/`ClosureTests`/`TwoPassTests` + slimmed `EvalTests`
   ~1210 lines), behavior- and coverage-preserving (theorem 256→256, native_decide
   253→253, zero fixture byte-drift), all wired into `Kue/Tests.lean`. **REMAINING for a
   future pass:** `FixturePorts` (~2524, generated — leave whole), `FixtureTests` (~1093),
   `StructTests` (~765), `BuiltinTests` (~735), and `EvalTests` (still ~1210 post-split,
   re-split candidate); B4 ride-along `DecimalTests`/`FormatTests`
   (`Decimal`/`Format`/`Json`/`Base64` only indirectly covered). Schedule when Phase-B
   next flags it overdue.

6. **Field-ordering parity #3 (MEDIUM, DEEP — byte-parity vs cue).** cue orders `ref &
   {own}` own-fields-first; kue is left-struct-first (`mergeStructFieldsWith`,
   `Lattice.lean`). cue's rule tracks where each label is *first introduced* across
   conjuncts in eval order — faithful replication needs a per-`Field`
   introduction-provenance key threaded through every merge/manifest site, not a one-line
   fold flip. The byte-order tail between cert-manager content-match and byte-exact cue;
   affects the dominant `#Def & {…}` prod9 pattern's exported order. Multi-slice + a
   provenance-key design spike first. Do AFTER argocd unless it blocks a needed fixture.
   ```cue
   #Def: {kind: "X", ...}
   out: #Def & {own: 1}  // cue: own-fields ordered first
   ```

7. **Per-eval-cost perf (frontier #2) — hash digest DONE (2026-06-19); residual wall
   open.** The cache-key hash digest landed (`valueDigest (depth) : Value → UInt64`,
   `DIGEST_DEPTH=3`, swapped into both `Hashable` instances, `BEq` UNCHANGED so soundness
   is unconditional): **cert-manager 119s → ~30.6s (~3.9×), byte-identical modulo
   field-order #3, zero fixture drift.** FrameKey follow-up profiled as NOT NEEDED (zero
   wall-clock change). See the implementation-log + the Audit & design history pointer for
   the full design spike. **RESIDUAL (open, the live perf frontier):** the heavy `argo`
   sub-package times out >200s once past the early bottom; full `apps/argocd.cue` is much
   faster (>7.5min → ~88s) but its bottom is now known to be the Bug2-4/Bug2-5 CORRECTNESS
   divergence, NOT fuel/perf. So item 7's live remainder is the per-eval constant on the
   heavy `argo` sub-package — meaningful once argocd exports (gated on the
   spec-conformance argocd unblock). Profile against a resolving target.

8. **Borderline / LOW (opportunistic; none block adoption).**
   - **`scalar-embed-with-decls`** — `{#a:1, 5}`→`5` (cue manifests `5`, keeps `.#a`
     selectable); kue bottoms. Incompleteness, not unsound. Needs a scalar-with-decls
     carrier (the `.embeddedList` analog for scalars). Do NOT "fix" by widening the scalar
     collapse — that is the unsound direction.
     ```cue
     out: {#a: 1, 5}  // cue -e out: 5 (and .#a stays selectable); kue bottoms
     ```
   - **`module-file-scoped-imports`** (arch-sized) — kue merges every sibling file's
     import bindings into one shared package frame; CUE scopes them per-file. Bites only
     the same-NAME-different-target case (which dedupe turned silent-wrong); real prod9
     doesn't hit it. Bind each file's imports into a per-file scope frame.
   - **`import-eager-closedness`** (MEDIUM) — an imported plain closed `.struct` def met
     with extra fields admits them on the EAGER selector path (the force path closes
     correctly). Close imported def bodies at load, or route the eager path through
     `normalizeDefinitionValueWithFuel`. Pin both silent-admit and incomplete-mask facets.
   - **`scalar-embed` provenance follow-ups** — opportunistic pins (3-level flatten, disj
     ops beyond `+`/`&`, composed select-into-F1-default) when next touching Lattice/Eval.
   - **Parser strictness** — `*(1|2)` laxity (cue rejects at parse); `__x`
     double-underscore accepted (cue reserves `__`-prefixed idents). Track under a
     parser-strictness pass.
     ```cue
     x: *(1|2)  // cue rejects at parse: "preference mark not allowed at this position"
     ```
   - **DRY `selectEvaluatedField .disj`** — the resolved-default arm re-lists the 5-arm
     struct-shape dispatch; collapse to `match resolveDisjDefault? alternatives with |
     some v => selectEvaluatedField v label | none => …` (gains free nested-disjunction
     recursion).
   - **`resolveEmbeddedDisjDefault` (`Eval.lean:2093`, next-audit confirm)** — verify the
     pass-1 label-surfacing path does NOT also need the use-site-narrowing distribution
     that `embed-disj-arm-fallthrough` added, or that label-surfacing-only is correct
     there.
   - **`comprehensionPairs` `.embeddedList` (Phase-B B3, LOW).** = B3 above; ride-along
     with the `scalar-embed-with-decls` work.

## Audit & design history (archived — full detail in implementation-log.md + git)

One terse pointer per landed audit batch and per shipped design spike. The narrative,
arm-by-arm verdicts, and as-built design records are preserved in
[`../reference/implementation-log.md`](../reference/implementation-log.md) and `git log`;
this list is only a date/commit/topic index for re-locating them.

- 2026-06-19 — `0d4b1a0` — argocd perf-spike → CORRECTNESS finding: the full-app bottom is
  a deterministic divergence (comprehension-guard / embed-narrowing), NOT fuel; fuel sweep
  (100/200/600) never clears it. Decomposed Bug #2 into Gap-1 (let-buried read detection)
  + Gap-2 (force-tier disjunction-arm narrowing); soundness GO / GO-WITH-GATE. Residual
  argocd blocker now tracked as Bug2-4/Bug2-5 in `spec-conformance-audit.md`.
- 2026-06-19 — `2820b58` — Bug #1 single-embed comprehension-guard splice
  (`embedComprehensionReadLabels` + `spliceOperandForEmbed`); DONE. Plus item-7 cache-key
  hash digest (`78bef86`) re-confirmed sound.
- 2026-06-19 — Bug2-1 (`e124a5e`, Gap-1 let-buried read detection via
  `closeDefFrameReadIndices`; subsumes A-EN1 `for`-source variant) + Bug2-2 (`1819b98`,
  Gap-2 force-tier disjunction-arm narrowing via `embedDisjArmDeclLabels`); both DONE.
- 2026-06-19 — Bug2-3 / Gap-2b (`d9f66ca`, structural list-arm-vs-struct-host disjunction
  pruning via `embedBodyEmbedsDisj`); DONE — argocd did NOT unblock, surfacing Bug2-4
  (tracked in `spec-conformance-audit.md`).
- 2026-06-19 — `c3ccae9..1819b98` — Phase-A audit (Bug2-1 + Bug2-2): CLEAN; one LOW DRY
  fix applied (`Field.isRegularOutput` extracted). A-EN2 strengthened the real-conflict
  pin to `exportJsonBottoms`.
- 2026-06-19 — `ff30617..2820b58` — Phase-A audit (item-7 hash + Bug #1): found A-EN1
  (DONE via Bug2-1), A-EN2 (DONE inline), A-EN3 (LOW DRY, parked — see backlog).
- 2026-06-19 — `24da14d..463f8e1` — Phase-A audit (B2 CP3-pre/flip + B2.5): CLEAN, zero
  byte- drift; filed B2-A1 (pattern+tail tail-drop guard) + B2-A2 (reverse-order fixture),
  both LOW — see backlog.
- 2026-06-18 — `114eba8` — Phase-A audit (argocd link 3/4): VIOLATION found (parser
  collapse silently closed an open def); fix-slice 0 `def-open-tail-closedness` landed
  (`hasTail` flag on `.structComp`, later folded into `StructOpenness` by B2b).
- 2026-06-18 — `6ad6033..7898cff` — Phase-A audit (def-open-tail + Pass-2 + argocd
  link-5): filed A1 (Pass-2 builtin-arg selector miss), A2 (hidden-field deep bottom), A3
  (`.disj` definedness invariant), A4 (catch-all hygiene); all subsequently DONE.
- 2026-06-19 — `4bdc602..6f73286` — Phase-A audit (B2 struct collapse in-progress): the
  dead `structN` consumer arms + `mergeStructN` validated arm-by-arm against the legacy
  forms; three must-fix-before-flip items raised, all consumed by CP3-pre/flip.
- 2026-06-19 — `7d73bb9..a03ff4a` — Phase-A audit (B7 impl + test-org reorg + B4
  LatticeTests): CLEAN; one LOW dead-param fix (`descendClauses` `empty`) applied inline.
- 2026-06-19 — `24bb86f..b7fc0e3` — Phase-A audit (B6-A2 + B6-T1 + A2-followup): CLEAN;
  filed A2-x + A2-y (both LOW, latent/pre-existing) — see backlog.
- 2026-06-19 — `88d78f4..d8252f4` — Phase-A audit (B6 + B2b): both sound;
  B6-A1/B6-T1/B6-A2 all DONE; deferred B6 sub-gap (def-path-selection closed-marker)
  honestly filed.
- 2026-06-19 — `0d4b1a0`/`7e776ec` — Phase-B re-ranks (Bug #2 design, then Gap-2b spike):
  set the next-3-4 ordering (argocd unblock → item 7 → A-EN3 → tail). The post-Bug2-1/2
  re-rank is now reflected in the backlog above.
- 2026-06-19 — Phase-B audit #7 (`d1f537c`-era) — A2-followup design (import-binding
  marker) produced + post-B2-complete whole-graph sweep: no actionable cleanup; import
  graph acyclic/clean. A2-followup DONE (`78ec47a`/`7a54ad6`, `FieldClass.importBinding`).
- 2026-06-19 — Phase-B audit #3 (`c3d0089..3a58b53`) — B7 design finalized (option (b),
  `descendClauses` fold); light sweep, no new findings.
- 2026-06-18 — Phase-B audit #2 (post A5/B1) — found B7 (the highest-leverage type win:
  five frame-depth walkers re-deriving the de Bruijn clause-chain rule by hand). B7 DONE
  (`bbb00b2`/`c5cbb0e`/`aa5518c`).
- 2026-06-18 — Phase-B audit #1 (post A1-A4, whole graph) — filed B1 (`remapConjRefs`
  catch-all, DONE), B2 (5-struct-ctor unification, DONE B2.1–B2.5+B2b), B3 (embeddedList
  comprehension, LOW open — see backlog), B4 (LatticeTests, DONE), B5 (extraction
  corrections, LOW open — see backlog).
- 2026-06-19 — B2 design + B2.2/CP3 megaslice de-risked execution plan (Phase-B #4/#5) —
  the 5-struct-ctor collapse into one `struct (fields, openness, tail, patterns)` on
  `StructOpenness`, consume-before-produce sequencing, the ~1024-site test-representation
  migration split into CP3-pre (test-only, green) + CP3-flip (worktree). All DONE
  (B2.1–B2.5, CP3-pre/flip).
- 2026-06-19 — B2b design (Phase-B #6) — `structComp` two-bool → `StructOpenness` (option
  (a), kept distinct pre-eval ctor); DONE (byte-identical, arity 4→3, `open_:=hasTail` →
  `closeDefBody`).
- 2026-06-19 — B6 design (`3b2beb6`) — nested-def closedness through regular fields +
  eager selector; gaps 1+2 DONE (`7da65d8`), one sub-gap (def-path-selection re-open on
  instantiation) deferred.
- 2026-06-19 — A2-followup design (`importBinding` marker) — peer of `letBinding`,
  produced only at `Module.bindImports`, two consumer splits (Normalize 4-way + Manifest
  deep-bottom); DONE, bundled B6-A1, subsumed B6-A2's Normalize edit.
- 2026-06-19 — B7 design (`descendClauses` fold over the clause chain, Phase-B #3) —
  single shared depth-threading fold in `Value.lean`; the three scanners become
  one-liners, `clauseFrameShift` deleted, `resolveClausesWithFuel` tied by an agreement
  theorem; DONE.
- 2026-06-19 — item-7 design spike (the per-eval wall is a HASH COLLISION, not frame-id
  divergence) — `valueDigest` bounded-depth structural digest, `BEq` untouched →
  unconditional soundness; DONE (cert-manager 119s → ~30.6s).
- 2026-06-19 — A5 (`c3d0089`) + A5-followup (`e00c3de`) — comprehension-body frame-depth
  remap + the deferral-gate (`hasSelfRefAtDepth`) self-ref detection; the observable wrong
  value flipped; DONE. A1+B1 catch-all soundness sweep (`80df01e`/`a7b2724`) + A3
  (`96bef05`) + A4 (`f72995d`) all DONE.

## Pointers (history + reference for anything dropped)

- **Completed-slice history + verification record:**
  [`../reference/implementation-log.md`](../reference/implementation-log.md)
  (chronological, one entry per commit) and `git log`.
- **Spec-conformance fix backlog (authoritative):**
  [`spec-conformance-audit.md`](spec-conformance-audit.md) § Consolidated fix backlog.
- **CUE-divergence record:**
  [`../reference/cue-divergences.md`](../reference/cue-divergences.md).
- **CUE spec-gap record:**
  [`../reference/cue-spec-gaps.md`](../reference/cue-spec-gaps.md).
- **Decisions:** [`../decisions/`](../decisions/) (compatibility target,
  correctness-over-perf, Value-model fork resolution).
- **Slice loop + audit cadence:** [`../guides/slice-loop.md`](../guides/slice-loop.md).
- **Status page:** [`../www/index.html`](../www/index.html) — single human-scannable
  status page (where Kue stands, what works, what's next); refreshed on plan-hygiene
  passes.
- **CUE semantics reference:** [`cue-language-guide.md`](cue-language-guide.md);
  [`architecture.md`](architecture.md) + [`compat-assumptions.md`](compat-assumptions.md)
  in this `spec/` directory.
- **Latest session state / next step:** the most recent breadcrumb in
  [`../notes/`](../notes/).
