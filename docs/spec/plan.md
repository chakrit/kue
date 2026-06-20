# Kue Plan

The live implementation roadmap. Kept small, current, and actionable — one focused slice
at a time. The full record of completed slices lives in
[`../reference/implementation-log.md`](../reference/implementation-log.md) (chronological,
one entry per commit) and `git log`; this file holds only where we are and what's next.
A periodic plan-hygiene pass distills it back to the live roadmap (history → log + git);
see [`../guides/slice-loop.md`](../guides/slice-loop.md). Last distilled 2026-06-20.

## North Star

Kue targets **CUE v0.15 semantics, done correctly**. Where the official `cue` v0.16.1
binary is buggy, Kue implements the *correct* behavior, not the bug. The compatibility
target is the language as specified, not bug-for-bug parity. See
[`../decisions/2026-06-14-cue-compatibility-target.md`](../decisions/2026-06-14-cue-compatibility-target.md).

## Working Principles

- TDD where behavior is testable: theorem checks or executable examples before code.
- Keep the semantic model simple before optimizing representation.
- Total functions and explicit semantic values over hidden host-language failure.
- Avoid dependencies until they clearly remove more complexity than they add.
- One slice per commit; subject mirrors the slice title. Small enough to review/revert.
- **Correctness over performance.** A latent unsound result is a Violation even with no
  failing fixture; a perf miss is acceptable. See [`../decisions/`](../decisions/).
- **Spec is the authority; `cue` is a fallible cross-check, never the gate.** Byte-identical
  to `cue` is structurally bug-replicating. Conform to the CUE spec; where it is silent, to
  lattice first principles (precise, total, illegal-states-unrepresentable). When `cue`
  disagrees with the spec it is WRONG → follow the spec, record in `cue-divergences.md`.
- **Real-app compilation is a stress test, not the goal.** Getting prod9 infra (argocd,
  cert-manager) to `export` *validates* correct semantics; it is never an end in itself.
  Rank slices by spec-correctness and clean design evolution — never let one app's shape
  pull the loop into per-app special-casing. A real-app blocker needing app-specific
  narrowing is parked as a stress-test finding (argocd/Bug2-5), not promoted to the
  critical path; it resolves as the general semantics mature.

## Standing Capabilities (what Kue does now)

The semantic core is broad and oracle-checked against `cue` v0.16.1
(`/Users/chakrit/go/bin/cue`). Currently working, cue-exact modulo the tracked
field-ordering byte-parity gap (#3):

- **Evaluator + lattice.** Total `meet`/`join` over the full `Value` domain; primitives,
  kinds, bounds, regex, struct/list shapes. `Field` is a `structure`. Disjunctions with
  default-mark algebra (unification ANDs default sets; arithmetic/comparison/unary
  resolve-operand-first; nested two-level precedence; equal-default dedup). Structural-cycle
  detection: `#L:{n,next:#L}` errors; `#List | *null` terminates on `*null` (D#2).
  ```cue
  port: int & >0 & <=65535
  port: 8080  // 8080
  ```
- **Closures / cross-package def-meet.** `Value.closure (frame) (body)` carries the capture
  frame so an imported def's body unifies with the use-site *before* its cross-frame
  self/sibling refs resolve. Deep/nested self-ref detection (`hasSelfRefAtDepth`); multi-level
  embed chains resolve. Forcing tier closes imported def bodies at capture.
  ```cue
  import "ex.com/pkg"
  web: pkg.#Def & {name: "web"}
  ```
- **Comprehensions.** Struct (`for k,v in s {…}`) and list (`[for x in xs {x}]`, incl. `if`
  guards, `let` clauses (D#3), nested/multi/zero-yield, plain+comp interleave). Guard
  classification (D#1b/c): incomplete guard DEFERS (residual node), concrete non-bool guard
  is a TYPE ERROR, presence-test `X !=/== _|_` drops. Scalar struct-embedding collapse
  (`{5}`→`5`) at embed-eval.
  ```cue
  out: [for x in [1, 2, 3] {x * 2}]  // [2, 4, 6]
  ```
- **Disjunction defaults under embedding.** Use-site narrowing distributes into every arm of
  an embedded default disjunction, pruning dead arms.
  ```cue
  x: (*"a" | "b") & ("b" | "c")  // "b"
  ```
- **Fuel-saturation perf.** Eval count FLAT across fuel (bracketed monotonic truncation
  counter; truncated values fuel-keyed, saturated results fuel-free). `evalFuel = 100`.
  Frame-id sharing + force-memo. Cache keyed on a bounded-depth structural digest
  (`valueDigest`, `DIGEST_DEPTH=3`; `BEq` untouched → soundness unconditional).
- **Builtins.** `base64.Encode`, `json.Marshal` (`Kue/Json.lean`), `yaml.Marshal`
  (`Kue/Yaml.lean`), `regexp.Match`, `math.Pow` (exact non-neg-int-exponent domain),
  `list.Sort`/`SortStable`, `strings.*`/`list.*`/`math.*` namespaces. Multiline strings.
  ```cue
  import "encoding/json"
  out: json.Marshal({a: 1})  // "{\"a\":1}"
  ```
- **Regex.** RE2-equivalent AST → NFA matcher in `Kue/Regex.lean` (a true leaf), incl. `\b`,
  lazy quantifiers, in-class `\D`/`\W`/`\S` set-complement, `maxRepeat=1000`. Corpus
  divergence-free.
- **Imports / modules.** `cue.mod` discovery, in-module + cross-module (vendored or
  extract-cache) resolution by longest module-path prefix, multi-file merge, transitive
  loads, package-dir entry (`kue export ./apps`), qualified import path
  `"location:identifier"` (F-3, `Import.packageName`). IO confined to `Kue/Module.lean`;
  `Eval`/`Resolve` stay pure. (Registry/OCI fetch deferred — prod9 is fully on-disk.)
- **CLI.** `kue eval`, `kue export [--out yaml|json] [file|dir]` (stdin or arg), clean
  missing-file diagnostics + exit codes.

**Real-app status** (prod9 infra, read-only oracle):
- **cert-manager: content-identical drop-in, ~30.6s.** Exports correctly at production fuel,
  byte-identical to `cue` modulo field-order #3 (the item-7 cache-hash digest collapsed the
  ~119s O(N²) wall to ~30.6s).
- **argocd: `packs.#Argo` (link 5) content-correct** (4-link chain). All three components
  content-identical to `cue` (sorted-key, modulo field-order #3) in the scratch module. **Full
  `apps/argocd.cue` STILL bottoms** — the residual is a deterministic CORRECTNESS divergence
  (**Bug2-5**, let-buried two-level embed comprehension-guard narrowing), NOT a fuel ceiling.
  PARKED as a stress-test finding; resolves as the general semantics mature.

## Live Backlog (open work, ranked)

Correctness gates real-app adoption; cleanups are parallel-safe filler. Two backlog owners:
the **spec-conformance fixes** are owned by
[`spec-conformance-audit.md`](spec-conformance-audit.md) § Consolidated fix backlog (the
authoritative ranked list — do NOT duplicate it here); the **plan-only roadmap** below owns
the non-spec-conformance work.

**Spec-conformance fixes (authoritative ranking in `spec-conformance-audit.md`):** the
argocd residual **Bug2-5** (PARKED), **BI-1** (Unicode case-fold — spike DONE: chose
oracle-generated BMP simple-mapping table, no network; see audit doc), **E#4-fix** (✅ DONE
2026-06-20 — arithmetic operator domain now type-errors concrete out-of-domain operands +
string/bytes `*` repetition; see item #6), **BI-2-residual** (Sqrt + neg/fractional Pow), **SC-3**
display-residual, **SC-4** (spec-gap-first), **SC-1b** (closed×closed-pattern), **A#6**
(`containsBottom` fuel cap, standalone), **DRY-1** (let-walker extraction). **The 4
spec-gap ratifications are DONE (2026-06-20):** gaps 1–3 RATIFIED + test-pinned; gap 4
(E#4) was MIS-FILED — the spec mandates the operator domain, so it became the E#4-fix slice
above. See `cue-spec-gaps.md` (RATIFIED/ESCALATED rows) + `spec-conformance-audit.md`.

### Plan-only roadmap (not in the spec-conformance backlog)

Sequence after the spec-conformance correctness work: bank cheap-ready cleanups, then the
perf frontier (#7 residual), then the deeper parity gap (#6).

**Numbered durable items (cross-reference IDs):**

1. **`truncate-primitive` (HIGH — soundness hardening). STEP 1 DONE; STEP 2 ATTEMPTED & RULED
   OUT (commit on `main`).** The truncation-bump invariant (a `fuel=0` helper that drops fields
   MUST bump `truncCount`) was held by DISCIPLINE across **seven** sites (the plan said six —
   stale; the seventh, `expandListClausesWithFuel`, landed with the later list-comprehension
   slice and bumped correctly by discipline — NOT a latent bug; no drop-without-bump existed).
   **Step 1 (DONE):** added the `EvalState.truncate {α} (result : α) : EvalM α` primitive fusing
   bump+return; rewrote all seven sites through it (two `evalValueCoreWithFuel` arms + five
   expansion helpers). Strictly behavior-preserving — byte-identical fixtures, cert-manager
   content-identical to `cue`. The bump now lives at ONE choke point; a drop site can no longer
   split bump from return. **Step 2 (RULED OUT, not deferred):** a `withFuel` combinator routing
   the `fuel=0` dispatch to make the bump physically unskippable was IMPLEMENTED and TESTED — it
   breaks the mutual block's well-founded `termination_by`: routing the dispatch through a lambda
   hides the `fuel = n+1` pattern, so Lean loses the structural-decrease equation (`fuel < fuel✝`
   unprovable). Full type-level unrepresentability of "truncated-without-bump" would require
   re-architecting the saturation mechanism away from the monotonic-counter+bracket (the design
   the audit-#6 fix deliberately chose over per-arm bit-threading) — NOT worth it. Residual
   routing-discipline is documented as an invariant note at the primitive + on the `truncCount`
   field. **Item CLOSED.**

**BI-EFF. Effectful-builtin seam (TRIGGERED — gated on the 2nd effectful builtin; Phase-B
2026-06-20 ruling).** `list.Sort`/`SortStable` live as one shared inline `runSort` case in the
`.builtinCall` arm of `evalValueWithFuel` (`Eval.lean` ~2772) — the RIGHT layer (the `{x,y,less}`
comparator needs `EvalM`, which the pure `Builtin` layer cannot reach), and one logical case is
below the abstraction threshold today. **Do NOT abstract now.** Trigger: when the SECOND effectful
builtin lands — `list.IsSorted` (reuses `sortWithComparator`'s `lt` verbatim) or a validator
(`matchN`/`matchIf`/`list.MatchN`, element-vs-constraint unify) — extract the effectful cases, AS
THAT SLICE'S FIRST STEP, into a named `evalEffectfulBuiltin? : String → List Value → … → EvalM
(Option Value)` (in the mutual block, calls `evalValueWithFuel`), tried in `.builtinCall` BEFORE the
pure-evaluate-then-`evalBuiltinCall` fallback; new effectful builtins add an arm to the SEAM, never
to the evaluator top-level match. A full name→`EvalM`-closure registry is **rejected** (less
traceable than an exhaustive `match`; population ~3-4, not dozens). Risk: eval hot path +
`termination_by` measure → real slice, byte-identical gate, NOT inline. A forward-pointing seam
comment is already at the site (Phase-B 2026-06-20). `struct.MaxFields`/`MinFields` are PURE → stay
in `Builtin`, never effectful.

2. **EvalOps extraction → `Kue/EvalOps.lean` (ACTIONABLE, PARALLEL-SAFE).** ~256 lines of
   self-contained pure scalar algebra (`evalAdd…evalBinary` + `distributeUnary`/
   `distributeBinary`, `Eval.lean:782/1042/1088/1093`) carved out from under the recursive
   evaluator, no back-edge into `evalValueWithFuel`. CORRECTION: it also calls
   `divValue`/`modValue`/`quoValue`/`remValue` from `Builtin.lean` — so `EvalOps` imports
   `{Value, Decimal, Builtin}`, OR move those four pure decimal ops into `EvalOps`/`Decimal`
   first (cleaner). Resolve the import shape in the slice. Mechanical otherwise. (Confirmed
   still inline + live by Phase-B 2026-06-20.)

3. **Test/fixture-org pass (periodic) — module carve DONE `4b25cef`; fixture regroup DEFERRED.**
   `EvalTests.lean` (had re-grown to 1593) was carved into `ComprehensionTests.lean` (29 pins —
   `listcomp_*`/`letcomp_*`/`eval_comprehension_*` incl. comprehension-guard shapes) +
   `SortTests.lean` (13 pins — BI-2 `list.Sort`/`SortStable`); EvalTests → 1246. Org-only, zero
   behavior change, pin-count conserved 179→137+29+13. **No `GuardTests`** — the `classify_guard_*`
   classifier units already live in `PresenceTests`; only the comprehension-guard *shapes* were in
   EvalTests and folded into ComprehensionTests. **Remaining sub-item (DEFERRED, optional):**
   sub-grouping `testdata/cue/{definitions (50), comprehensions (27)}` into nested subdirs —
   high-blast-radius because `FixturePorts.lean` (3049) is hand-maintained source whose
   `fileName := "subdir/stem.expected"` strings are the join key (each move = multi-file `git mv` +
   exact string edit, ~77 fixtures). Deferred per "DEFER rather than break discovery"; low marginal
   win (layout already subsystem-grouped one level deep). Pick up as a dedicated careful slice or drop.

4. **Field-ordering parity #3 — RATIFIED CLOSED (2026-06-20): Kue keeps source order; parity
   DECLINED.** The spec-gap ratification settled this: spec is silent (structs are unordered
   sets; output order is implementation-defined), so Kue's declaration / first-seen-across-conjuncts
   order is the principled choice and is now test-pinned (`StructTests`
   `meet_struct_field_order_is_declaration_order`). `cue`'s cross-conjunct order is an undocumented
   internal-graph artifact — re-probed v0.16.1, it is NOT the "first introduced" rule this item
   once claimed: separate one-field literals come out *sorted* (`{z}&{a}&{m}` → `a,m,z`) while a
   def-ref meet interleaves by introduction (`#Def:{kind,zfield} & {own,afield}` → `kind, own,
   afield, zfield`). Chasing byte-parity would mean reverse-engineering that graph order through a
   provenance key on every merge/manifest site — rejected as gating on a presentation artifact the
   spec does not mandate. Reopen ONLY if a concrete needed fixture demands cue's exact bytes (none
   does). See `cue-spec-gaps.md` (RATIFIED row) for the full re-derivation.
   ```cue
   out: {b: 1} & {a: 2}  // cue: a, b (graph order); Kue: b, a (source order) — both spec-valid
   ```

5. **Per-eval-cost perf (frontier — hash digest DONE; residual open).** The cache-key hash
   digest landed (cert-manager 119s → ~30.6s, byte-identical modulo #3, zero drift; FrameKey
   follow-up profiled as NOT needed). **Residual (the live perf frontier):** the heavy `argo`
   sub-package times out >200s once past the early bottom. Gated on the argocd unblock (its
   bottom is the Bug2-5 CORRECTNESS divergence, not fuel) — profile against a resolving target.

6. **Borderline / LOW (opportunistic; none block adoption).**
   - **E#4-fix — ✅ DONE (2026-06-20; spec divergence, LOW-MED; surfaced by the spec-gap
     ratification slice).** A concrete operand outside an arithmetic op's domain is now a TYPE-ERROR
     bottom, not a held residual. The spec closes `+ - * /` over int/decimal, plus `+`/`*` over
     string/bytes (*"The four standard arithmetic operators … apply to integer and decimal
     floating-point types; + and * also apply to strings and bytes"*) — a list/struct/bool/null
     operand is ill-typed, exactly like `1 + "x"`. `cue` is spec-correct (hard-errors). **Fix:**
     `classifyArithOperand` (`Eval.lean`) splits each operand `prim` / `concreteNonArith`
     (`.struct`/`.list`/`.listTail`/`.embeddedList`, no-catch-all enumeration) / `incomplete`;
     `arithmeticDomainResult` type-errors (`.bottomWith [.nonArithmeticOperand op ty]`) a
     concrete-nonarith operand ONLY when its partner is also concrete, and DEFERS (`.binary`) when
     either side is incomplete — so `[1] + x` holds while `x: int` is abstract, erroring only after
     `x` resolves (matches cue; same concrete-vs-incomplete discipline as `classifyGuard` D#1b/c).
     The four ops swap their `_,_ => .binary` catch-all for `arithmeticDomainResult op`; the
     `prim,prim` arms are untouched (`1+"x"` etc. still `.bottom`). **Sibling fix:** `evalMul`
     gained the string/bytes `*` int **repetition** arms (`"ab"*2="abab"`, either order; `0`→empty;
     negative→`negativeRepeatCount` error) — cue's behavior superseding strings/bytes.Repeat, a
     previously silent wrong-bottom. New `BottomReason`s: `nonArithmeticOperand`,
     `negativeRepeatCount`. Pins: `numeric/{list_arithmetic_type_error,string_repeat_multiplication,
     arithmetic_incomplete_operand_defers}` + ~19 `EvalTests` `native_decide` theorems (incl. the
     incomplete-still-defers regression pin). NOT a `cue-divergence` (cue is correct).
   - **`scalar-embed-with-decls`** — `{#a:1, 5}`→`5` (`cue` manifests `5`, keeps `.#a`
     selectable); Kue bottoms. Incompleteness, not unsound. Needs a scalar-with-decls carrier
     (the `.embeddedList` analog for scalars). Do NOT "fix" by widening the scalar collapse —
     that is the unsound direction.
   - **`module-file-scoped-imports`** (arch-sized) — Kue merges every sibling file's import
     bindings into one shared package frame; CUE scopes them per-file. Bites only the
     same-NAME-different-target case; real prod9 doesn't hit it. Bind each file's imports into a
     per-file scope frame.
   - **`import-eager-closedness`** (MEDIUM) — an imported plain closed `.struct` def met with
     extra fields admits them on the EAGER selector path (the force path closes correctly).
     Close imported def bodies at load, or route the eager path through
     `normalizeDefinitionValueWithFuel`. Pin both silent-admit and incomplete-mask facets.
   - **Parser strictness** — `*(1|2)` laxity (`cue` rejects at parse); `__x`
     double-underscore accepted (`cue` reserves `__`-prefixed idents). Track under a
     parser-strictness pass.
   - **DRY `selectEvaluatedField .disj`** — the resolved-default arm re-lists the 5-arm
     struct-shape dispatch; collapse to `match resolveDisjDefault? alternatives` (gains free
     nested-disjunction recursion).
   - **B3 (`comprehensionPairs` `.embeddedList`)** — `for x in {#a:1,[1,2]}` iterates ZERO
     times where CUE iterates `[1,2]`; add an `.embeddedList items _ _ => some (listPairsFrom 0
     items)` arm. Incompleteness, not unsound; ride-along with `scalar-embed-with-decls`.
   - **B2-A1 (latent, currently lossless)** — `applyEvaluatedStructN` (`Eval.lean:330`) routes
     the patterns-present case through a meet that DROPS `tail`. Lossless today (the only tail a
     parsed struct carries is bare `...` = `.top`, a no-op to drop+re-supply); breaks the day
     typed-ellipsis lands. Thread `tail` through the pattern arm + a round-trip pin; pairs with
     any typed-ellipsis slice.
   - **B2-A2 (test-gap fill)** — both B2.5 fixtures exercise patterns-LEFT × tail-RIGHT; the
     reverse and both-tails+patterns are pinned only by `native_decide`. Add
     `testdata/cue/definitions/{tail_pattern_unify,both_tails_pattern_unify}` pairs +
     `FixturePorts` entries (oracle: `{a:5,...} & {[string]:int}` → `{a:5}` open).
   - **A2-x (latent) — `importBinding` merge-asymmetry.** `mergeFieldClass` returns `none` for
     `importBinding & <real field>` (merges only with itself) where the old `.hidden` merged via
     `.field`. Unobservable today (the only collision `cue` rejects at LOAD — see A2-y).
   - **A2-y (pre-existing) — missing import-name redeclaration check.** A top-level field
     colliding with an imported package's local name (`import ".../dep"` + `dep: {…}`) is a LOAD
     error in `cue`; Kue silently keeps both. File as a small loader slice. (Both A2-x/A2-y are
     corners prod9 doesn't hit.)
   - **`scalar-embed` provenance follow-ups** — opportunistic pins (3-level flatten, disj ops
     beyond `+`/`&`, composed select-into-F1-default) when next touching Lattice/Eval.
   - **`resolveEmbeddedDisjDefault` (`Eval.lean:2093`)** — verify the pass-1 label-surfacing
     path does NOT also need the use-site-narrowing distribution that `embed-disj-arm-fallthrough`
     added, or that label-surfacing-only is correct there.

**Walker / normalizer dedup family (post-argocd, LOW/MED-risk + LOW-urgency, gated behind
correctness — never promoted ahead of a spec-conformance fix):**

Phase-B 2026-06-20 ruling (do not re-litigate): these are NOT one problem. There are THREE
distinct walker families plus a separate normalizer pair — four different mechanisms, result
types, recursion domains, and termination measures. Folding all under one abstraction would
be a false "stuff they all do" extraction. **Sequencing: AD4-1 first → A-EN3+DRY-1 locality
batch → AD2-1.**

- **AD4-1 (MEDIUM — comprehension-walker dedup; FIRST in the sequence).** The four `expand*`
  comprehension clause-walkers (`expandClausesWithFuel`/`expandForPairsWithFuel` →
  `ClauseExpansion`; `expandListClausesWithFuel`/`expandListForPairsWithFuel` →
  `ListClauseExpansion`, `Eval.lean:3310–3462`) are `EvalM`-effectful clause-chain drivers
  whose `.guard`/`.letClause`/`.forIn` arms are BYTE-IDENTICAL (verified line-by-line), as are
  the bottom/deferred short-circuit folds. `ClauseExpansion`/`ListClauseExpansion` are
  STRUCTURALLY IDENTICAL 3-ctor sums (`fields`/`items` ⊕ `bottom Value` ⊕ `deferred`) → one
  generic `ClauseOutcome β` (β = `List Field` / `List Value`); the two named sums collapse to β
  instantiations, the four public defs become thin β-instantiating wrappers. Combinator: one
  `expandClauseChain` + one `expandForPairs`, both generic in β, parameterized by the whole
  `[]`-arm body-handler.
  **VERIFIED-CORRECT asymmetry the refactor MUST preserve+pin (orchestrator probe 2026-06-20):**
  the struct `[]` arm short-circuits a `.bottom`/`.bottomWith` body (D#1a); the LIST `[]` arm
  does NOT (`expandListClausesWithFuel:3408-3409` wraps ANY `evaluatedBody`, incl. a bottom, as a
  one-element list). `out: [for x in [1] {x & "s"}]` → Kue `out: [_|_]` (1-element list, bottom
  element); `cue eval` renders the SAME value as `out.0: conflicting values`. So `[_|_]` ≠ `_|_`
  is CORRECT CUE list semantics — a bottom element does NOT collapse the list. The body→outcome
  callback is where this divergence lives, so the combinator MUST take the whole `[]`-arm
  body-handler as a parameter (a naive "wrap the body" callback would wrongly make the list twin
  bottom-propagate). PIN both eval forms + the export-errors; do NOT reconcile the twins on this
  point. (Whether the list-arm non-propagation is itself a latent bug is a SEPARATE correctness
  question — file/verify independently of the dedup.) Gate: byte-identical fixtures +
  `termination_by` preserved + axiom-clean. Most self-contained of the three (one mutual block,
  no cross-module reach, no agreement-theorem surface).
- **A-EN3 (LOW — pure structural `Value` folds; bundle with DRY-1 by edit-LOCALITY).**
  `defFrameRefIndices`/`selfReferencedLabels`/`refsSelfEmbeddedLabel` (`Eval.lean:303/209/101`)
  are three structural folds over the FULL `Value` ctor tree, `+1`-at-each-frame-pusher depth,
  `descendClauses` for the comprehension arms; differ ONLY in leaf (`.refId`/`.selector`) +
  monoid (`List Nat`/`List String`/`Bool`). Abstraction: `foldValueWithDepth` parameterized on
  monoid + leaf (the shape B7 used). `closeDefFrameReadIndices` REUSES `defFrameRefIndices`,
  `embedDisjArmDeclLabels` is a shallow one-hop ref-follow — so A-EN3 is exactly those three.
  Gate: B7-style agreement theorems + totality preserved. (DRY-1 is the sibling — see audit doc;
  both CALL `defFrameRefIndices`, so do them together to avoid touching that callee + its
  theorems twice. They produce TWO combinators, not one.)
- **AD2-1 (LOW-MEDIUM — disjunction-normalizer dedup; FILE as a slice, do NOT apply inline).**
  `normalizeEvaluatedDisj` (`Eval.lean:694`, EVAL path) and `normalizeDisj` (`Lattice.lean:277`,
  LATTICE/meet path) are near-identical over the same domain, differing ONLY on the LONE-arm
  rule: `normalizeDisj` collapses only `[(.regular, v)]` (a lone DEFAULT arm stays `.disj
  [(.default, v)]`, surfacing as `*1`), `normalizeEvaluatedDisj` collapses `[(_, v)]`
  mark-agnostically (→ `1`). Both VALUE-sound. **Paths are DISJOINT (different layers, different
  post-conditions — eval keeps the marked disjunction for display); the shared core is just the
  `liveAlternatives` lone-arm rule.** The lone-DEFAULT case `a: (*1|2)&(>=1 & <2)` flows through
  `normalizeDisj` (the lattice `.disj & value` arm): `cue`'s value is `1`, Kue displays `*1` —
  the eval-display divergence, on the lattice path. **File-not-inline because option (a) flips
  TWO NAMED theorem pins** (`meet_disjunction_preserves_default_marker:Tests.lean:75` +
  `lattice_meet_disjunction_preserves_default_marker:LatticeTests.lean:152`, both asserting lone
  -default-marker preservation) + the SC-3 display contract — exceeds the inline byte-identical
  bar; the named-pin rename is a contract change a human should sign off. Zero `.expected`
  fixtures flip (swept all 7 `*`-carrying — every one is MULTI-arm, which the lone-arm rule never
  touches; multi-arm soundness `b: a & 2 = 2` is INDEPENDENT). **The slice:** (a) make
  `normalizeDisj`'s lone-arm collapse mark-agnostic (`[(_, v)] => v`); (b) update + rename the two
  pins to `= .prim (.int 1)` (the marker is NOT preserved on a lone arm — the name now lies); (c)
  have `normalizeEvaluatedDisj`'s has-default branch DELEGATE to `normalizeDisj` for the
  `[]`/lone/multi shape (the all-regular `joinValues` branch stays in `normalizeEvaluatedDisj`);
  (d) amend `cue-spec-gaps.md` row-6 to scope its "keep marked" basis to MULTI-arm only. Couples
  with SC-3; sequence with any disjunction-DISPLAY slice, NOT with the walkers (it is a
  lattice/eval layer-boundary dedup, not a frame/clause walker).

- **F-CASE-ARCH (RULED — Phase-B 2026-06-20). Both rulings landed; nothing to do.** BI-1
  (`9bd6927`) committed a 49KB GENERATED `Kue/CaseTable.lean` (1190+1173 pairs) derived from the
  local `cue` oracle. (a) **artifact — committed-stays.** A committed leaf data table wins on
  reproducibility (byte-identical re-gen verified), reviewability, offline build, and no
  build-time `cue` dependency; regenerate only on a deliberate Unicode-version bump. The file
  already carries a `DO NOT EDIT — generated by scripts/gen-case-table.py` header and the
  generator a provenance docstring with the regenerate command (both pre-existing — no inline fix
  needed). (b) **★ oracle-as-data-source convention — WRITTEN as an ADR:**
  [`../decisions/2026-06-20-oracle-as-data-source.md`](../decisions/2026-06-20-oracle-as-data-source.md).
  States the rule (oracle = sound data source for an externally-standardized, `cue`-faithful
  domain; NEVER a correctness gate for CUE semantics), the two-part test, the obligations
  (independently verify vs the EXTERNAL standard, record provenance, never let it become a
  semantics gate), and examples (OK: Unicode case table from Go; NOT OK: deriving CUE
  unification/eval expected-outputs from `cue`). Cross-linked from `slice-loop.md`'s
  spec-authority section. Both (a) and (b) are discharged.

**Phase-A audit 2026-06-20 (BI-1 `9bd6927`/`6065380` + test-org `4b25cef`) — verdict + inline fix:**

- **★ Oracle-derivation SOUND — the table is faithful to the Unicode STANDARD, not a `cue`
  quirk.** Verified independently of re-running `cue`: cross-checked all 1190 upper + 1173
  lower committed entries against Python 3.12 (UCD 15.0.0). 28 entries *appear* to diverge
  from Python's `str.upper()`/`.lower()`, but ALL 28 are cases where Python applies FULL
  (multi-char) mapping and `cue`/Go correctly applies the **simple** mapping the spec calls
  for — i.e. Python is the outlier, the table is right. Two classes, both proven against
  UnicodeData.txt semantics: (1) 27 Greek-Extended small letters U+1F80–U+1FFC whose simple-
  upper is the single-char *titlecase* letter (cat Lt) because full-upper is 2 chars (e.g.
  `ᾳ`U+1FB3→`ᾼ`U+1FBC; field-12 simple slot holds the Lt letter) — `cue` reads field 12,
  correct; (2) `İ`U+0130 simple-lower = `i`U+0069 (full-lower is `i`+combining-dot, 2 chars) —
  `cue` reads field 13, correct. Named spot-checks all clean: `é`↔`É`, `α`↔`Α`, `я`↔`Я`,
  `µ`→`Μ`, `ÿ`→`Ÿ`, `ß` unchanged (simple), `İ`/`ı` default mappings, Latin-Ext-A `ā`↔`Ā`.
  Zero coverage holes (every Python-simple-mapped BMP point is in the table). Table is SIMPLE
  1:1 only — correct scope vs full folding (the deferred tail). **No cue-divergence to file.**
- **Generator reproducible + hygienic.** Re-ran `gen-case-table.py` to a temp path → BYTE-
  IDENTICAL to the committed `CaseTable.lean`, tree stayed clean. Deterministic (`sorted()`
  on dict items; one `cue export` round-trip). No network — reads only the local READ-ONLY
  oracle. BMP range `range(0x0000,0x10000)` correct, no off-by-one at U+FFFF; surrogates
  U+D800–DFFF, C0/C1 controls + DEL, and string-illegal NUL/BOM excluded via `probeable()`
  (none have case mappings). Chunked-array workaround sound — 128-element chunks `++`-joined,
  no entry dropped/duplicated at seams (verified by the entry-count + spot-check equality).
- **Totality + ASCII-regression CLEAN.** `caseTableSearch` total (`termination_by hi - lo`,
  `decreasing_by omega`, no `partial`); `caseMapChar` identity-on-miss; sorted-key invariant
  holds (generator emits `sorted()`, binary search assumes ascending — matched). ASCII fully
  preserved post-`asciiToUpper`/`Lower` deletion: the missing-set check found 0 ASCII pairs
  absent from the table, so all 26+26 are present; no dangling refs to the deleted helpers
  anywhere in `Kue/`+`scripts/`.
- **test-org pin conservation VERIFIED (light check).** At the carve commit `4b25cef`, parent
  `EvalTests` = **179 theorems** → split to `EvalTests` 137 + `ComprehensionTests` 29 +
  `SortTests` 13 = **179** (also `native_decide` 176→134+29+13=176). Zero loss, pure move.
  All three of `ComprehensionTests`/`SortTests`/`StringsTests` imported by `Kue/Tests.lean`
  (checked at build). New `strings_case_unicode` fixture has its `FixturePorts` entry; its
  `.expected` correctly pins KUE's held `titleNonAscii: "über Alles"` (≠ live cue `"Über
  Alles"` — the documented ToTitle divergence, fixtures pin Kue not cue).
- **FIXED INLINE (1 LOW-risk doc-precision + test-coverage tightening).** compat-assumptions /
  spec-gaps / log glossed the deferred tail as "locale rules (Turkish `ı`/`İ`)", which reads
  as if `İ`/`ı` are unhandled — but their *default* (`und`) simple mappings ARE in the table
  (`İ`→`i`, `ı`→`I`, oracle-confirmed). Tightened compat-assumptions to say only Turkish/Azeri
  *locale tailoring* is deferred, and added two pins (`strings_to_lower_dotted_capital_i`,
  `strings_to_upper_dotless_small_i`) locking the default behavior — the highest-value missing
  pins (confusable cases a reader would doubt). Full gate green; committed.
- **FLAG for Phase B (filed, not fixed): the committed-generated-table artifact + an oracle-
  as-data-source CONVENTION.** Two architecture-shaped questions BI-1 raises, both LOW: (a) is
  a 49KB committed generated `CaseTable.lean` the right artifact vs build-time generation? — a
  committed table is reproducible/reviewable/offline-buildable and needs no build-time `cue`
  dep (arguably correct for a leaf data table), but the size + "DO NOT EDIT" generated-code-in-
  tree pattern is worth a deliberate ruling. (b) BI-1 establishes a NEW pattern — deriving
  committed data from the `cue` oracle — that currently has no written policy distinguishing it
  from the banned "byte-identical-to-cue" gate; the distinction (oracle sound *as a data source*
  for non-buggy standardized domains like Unicode tables, vs oracle as a *correctness gate*) is
  real and load-bearing and should be a documented convention. See **F-CASE-ARCH** below.

**Phase-A audit 2026-06-20 (BI-2 `4c59989` + F-3 `a6dc012`) — verdict + inline fixes:**

- **Load-bearing soundness CLEAN.** The eval-layer sort interception is sound: the non-bool
  `lt` fallback returns `false` AND records a sticky `sortError`, but `mergeRunsM`/`mergePassM`/
  `mergeRunsLoopM` fuel is fixed by list length (independent of `lt`'s answers), so a lying
  comparator cannot break termination or fuel — the recorded error makes the whole call bottom
  regardless of the garbage order produced. `sortValuesM` is total (bottom-up structural merge,
  `termination_by (fuel,6,0)` for `sortWithComparator` dominates the `(fuel,1,0)` per-pair
  `evalValueWithFuel` re-entry — measure intact). Passing the comparator UNEVALUATED is required
  (the `x`/`y` slot refs must survive the per-pair meet). One stable sort for both Sort/SortStable
  is correct (stable ⇒ valid Sort). `math.Pow` exact-domain is sound: `decimalPowNat` structural
  on `Nat` (terminates, large exponents fine), domain gate (`exp.scale != 0 || exp.numerator < 0`)
  correctly bottoms fractional/negative; `Pow(0,0)` bottoms (CONFORMS — cue errors); out-of-domain
  bottoms honestly. Oracle-confirmed all probed boundaries.
- **FIXED INLINE (2 LOW-risk F-3 conformance tightenings, behavior-preserving + more conformant).**
  (1) `isPackageIdentifier "_"` accepted the lone blank `_`, but cue REJECTS it (`_ is not a valid
  import path qualifier`) — added `['_'] => false`. (2) `splitImportPath` accepted an empty
  ImportLocation (`":foo"` → `path:=""`), but cue rejects (`invalid import path`) — added a
  non-empty-location guard on both arms. Both make Kue strictly more spec-conformant (the F-3 story
  is "Kue parse-rejects junk cue load-rejects"); cue rejects these too, just later. Pins extended
  (`parse_is_package_identifier_cases` + bare `_`/`__`; new `parse_import_empty_location_errors`);
  `cue-spec-gaps.md` F-3 row + `cue-divergences.md` F-3 row amended. Full gate green; committed.
- **Test strength GOOD, no gaps filed.** Sort: stability (discriminating fixture), incomparable→
  bottom, non-list→bottom, by-field, inline-comparator, empty/singleton/dup all pinned. Pow: domain
  boundary incl. `Pow(0,0)`/whole-float-exp/neg-base-parity + residual-bottom pins. F-3: all
  precedence combos + invalid-id/empty-qualifier + 4 module fixtures.
- **FLAG for Phase B → RULED (BI-EFF below).** The eval-layer effectful-builtin interception flag
  is RESOLVED: the layer is right, the placement gets a named seam at the second effectful builtin,
  and a full registry is rejected. See **BI-EFF** in the backlog.

**Phase-A audit 2026-06-20 (truncate-primitive `7dfaadd` + ratifications `47ff318` + E#4-fix
`02b8b9d`; batch since `4593185`) — verdict: CLEAN, no code fix:**

- **★ E#4 per-operator domain correctness — SOUND (oracle-verified, v0.16.1).** Probed every
  operator × operand-type against the oracle: `[1]+[2]`, `[1]-3`, `3*[1,2]`, `[1]/3`,
  `{a:1}+{b:2}`, `true*false`, `null-null`, `null+1`, `"a"-"b"` all HARD-ERROR in cue — Kue now
  matches (the four ops route their `_,_` catch-all through `arithmeticDomainResult`, which
  bottoms a concrete-nonarith operand paired with a concrete partner via `.bottomWith
  [.nonArithmeticOperand op ty]`). `"a"+"b"` concat and the `prim,prim` mismatches (`1+"x"`,
  `"ab"*2.0`) left untouched and still correct. Per-op asymmetry (`+`/`*` admit string/bytes,
  `-`/`/` do not) is faithful.
- **★ String/bytes `*` repetition IS real cue/spec behavior — CONFIRMED, no quirk blessed.**
  Independently oracle-verified: `"ab"*2="abab"` AND `2*"ab"="abab"` (both orders), `"ab"*0=""`,
  `"ab"*-1` errors `cannot convert negative number to uint64` (exactly the cited message),
  `'ab'*2='abab'`/`'ab'*0=''` (bytes). Kue's `evalRepeat` matches end-to-end through the binary.
  The negative guard precedes `.toNat` (line 863), so no `Int→Nat` underflow. Spec basis: *"+ and
  * also apply to strings and bytes"* — repetition is the documented `*` semantics. NOT a
  non-spec quirk.
- **★ Concrete-vs-incomplete (the regression risk) — SOUND, no wrong-bottom.** Oracle-verified:
  `[1] + x` with `x: int` abstract HOLDS the residual (cue: `y: [1] + x`, NOT bottom), symmetric
  `x + [1]` likewise, `{a:1} + x` likewise, `[1] + z` (unresolved ref) likewise — and once
  resolved (`resolved: 5; resolved + 3`) it computes to `8`. `arithmeticDomainResult` checks
  `.incomplete` FIRST (lines 853-854), so a concrete-nonarith × incomplete pair DEFERS. End-to-end
  through `kue`: incomplete operands surface `incomplete value: int` (held residual), both-concrete
  cross-type (`[1]+2`) bottoms — the exact fork. `classifyArithOperand`'s concreteNonArith set is
  EXACTLY the four fully-evaluated non-arith shapes (`struct [] _`, `list`, `listTail`,
  `embeddedList`); a pattern-bearing `struct (_::_)`, `structComp`, `disj`, bounds, kinds, refs all
  → incomplete (defer). No incomplete value mis-classified as concrete. **No soundness regression.**
- **Illegal-states / exhaustiveness — CLEAN.** `classifyArithOperand` enumerates every `Value`
  ctor (29 arms = 28 ctors with `struct` split on `patterns.isEmpty`) with NO catch-all;
  green build (108 jobs) is the compile-time exhaustiveness proof. The two new `BottomReason`s
  (`nonArithmeticOperand`, `negativeRepeatCount`) ride the generic `.bottomWith` — grep confirms
  ZERO code anywhere pattern-matches individual `BottomReason` ctors (carried opaquely in a list,
  compared via derived `BEq`/`DecidableEq`, printed via derived `Repr`), so no match site needs
  updating. `BottomReason`/`NonBoolGuardType` are tight sum types.
- **Totality — CLEAN.** No `partial` in the arithmetic region; `classifyArithOperand`/
  `arithmeticDomainResult`/`evalRepeat` total (non-recursive); truncate-primitive's mutual-block
  `termination_by` intact (build green). The `_,_ => .binary` tail of `arithmeticDomainResult` is
  a totality-completion arm (structurally `prim,prim`, unreachable since each op handles its prim
  pair first) — a safe residual, not a "can't happen" hiding a real case.
- **Test strength — STRONG.** 3 fixtures (each with a `FixturePorts` entry, all oracle-faithful):
  `list_arithmetic_type_error` (4 ops × list + struct + bool + null), `string_repeat_multiplication`
  (both orders + `*0` + `+`/`-` asymmetry), `arithmetic_incomplete_operand_defers` (the regression:
  `int + [1]` / `int * 2` defer, `resolved + 3 = 8`). EvalTests pins cover each op × wrong-type,
  both repetition orders + `*0` + negative, and the incomplete-defers regression in both operand
  orders + bound + ref. No pre-existing fixture blessed the old wrong residual (clean — the only
  list/struct/bool arithmetic fixtures are the three new ones).
- **truncate-primitive light-check — SOUND.** Exactly 7 drop sites route through
  `EvalState.truncate` (the single choke point); 0 hand-written bumps remain at drop sites. The 2
  cache-rebump sites (`cache` 2756, `forceClosureWithConjunct` 3365) correctly use a CONDITIONAL
  `+ bump` (fires only on a cached `.truncated` hit) and are correctly NOT routed through the
  unconditional primitive. The 3 bump-invariant pins are real contract tests (arbitrary-start
  increment-by-one, polymorphic return-unchanged, three-shape bump), not smoke.
- **ratifications light-check — SOUND.** The 3 StructTests pins assert what they claim:
  open-disjunction stays open + is meet-identity with `.top` (oracle confirms `{a:int}|{b:string}`
  stays open), field-order is declaration order (oracle confirms cue SORTS `{b:1}&{a:2}`→`a,b`,
  Kue keeps `b,a` — a principled spec divergence, correctly recorded). E#4 row in
  `cue-spec-gaps.md` correctly flipped to RESOLVED→CONFORMING with full spec citation + matrix
  verdict. implementation-log / spec-conformance-audit E#4 entries match the code.
- **FLAG for Phase B (the "three parallel classifiers" DRY question — Phase-A read: likely leave
  separate).** `classifyArithOperand` / `classifyGuard` / `classifyDefinedness` share the same
  big `Value`-ctor enumeration with the same concrete-shape partition (the four concrete shapes
  singled out, the long abstract tail bucketed). But they are GENUINELY DISTINCT verdict functions:
  different target sums (`ArithOperandClass` / `GuardVerdict` / `Definedness`), different leaf
  verdicts (`prim`→prim vs nonBool vs defined), and ctor-specific arms the others lack
  (`classifyGuard`'s presence-test `.binary .eq/.ne _ .bottom`→concreteFalse; `classifyDefinedness`'s
  `disj`-liveness→defined/error and `structComp`→defined where the others defer/incomplete). A naive
  shared fold either loses these or needs so many per-classifier hooks it adds no leverage. The
  shared *structure* is the concrete-vs-incomplete partition (a candidate `classifyConcreteness`
  helper with a real name); the *verdicts* are not shared. Analogous to the A-EN3 fold family —
  Phase B's judgment whether a shared concreteness-partition core is warranted (likely NO per
  general-coding's "the stuff they all do is not a name", but worth a deliberate ruling).
- **Minor doc-staleness (deferred to plan-hygiene, NOT a Phase-A fix).** `spec-conformance-audit.md`
  lines ~211/219 still list "the 4 spec-gap ratifications" as OPEN backlog and ~212-215 describe a
  stale audit-cadence state (`7ee15d8`-era counter, "test-org=slice 1, BI-1=slice 2"). Both closed
  by this batch. Roadmap-section currency is owned by the due plan-hygiene pass / Phase B, not
  Phase A — flagged here for that pass to sweep.

**Phase-B audit 2026-06-20 (`28894ef`, whole-graph; scopes BI-2 `4c59989` + F-3 `a6dc012`) — verdict:**

- **Architecture HEALTHY.** Module layering is clean and acyclic: `Builtin → {Lattice, Regex,
  Decimal, Base64, Json, Yaml}` with NO `Builtin → Eval` edge; `Eval → Builtin` is the correct
  direction, and the sort living in `Eval` is correct *because* of this (the comparator needs
  `EvalM`, which the pure `Builtin` layer structurally cannot reach). BI-2's eval-layer sort
  interception and F-3's `Import.packageName` import changes both respected layering — no leak.
- **BI-EFF (the escalated PRIMARY question) — RULED: scoped seam at the 2nd effectful builtin;
  full registry REJECTED; one inline case is below-threshold TODAY.** `list.Sort`/`SortStable` are
  the only effectful builtins so far (a CUE `{x,y,less}` comparator evaluated per pair), handled as
  ONE shared inline `runSort` case in the `.builtinCall` arm + helpers `sortWithComparator` /
  `sortValuesM` / `mergeRunsM`/`mergePassM`/`mergeRunsLoopM`. Effectful-builtin population survey
  (what would accrete inline arms): genuinely effectful + NOT-yet-done = **`list.IsSorted`** (the
  SAME `{x,y,less}` comparator — reuses `sortWithComparator`'s `lt` wholesale) and the **validator
  family** `matchN` / `matchIf` / `list.MatchN` (unify each element against a CUE constraint — meet
  + eval per element, a different shape). `struct.MaxFields`/`MinFields` are PURE (field count, no
  CUE function) → stay in `Builtin`. So the population is real and certain to grow, but small
  (~3-4), not dozens. RULING: (a) a full name-keyed dispatch TABLE / registry of `EvalM` closures
  is **rejected** — it is LESS traceable than an exhaustive `match` (the per-builtin semantics are
  load-bearing and heavily commented; a `HashMap` of closures hides them) and the population never
  justifies the indirection; this is the illegal-states/traceability philosophy, not YAGNI alone.
  (b) ONE logical inline case (Sort+SortStable sharing `runSort`) is **below the abstraction
  threshold today** — extracting a seam for a single case is speculative. (c) **TRIGGER: when the
  SECOND effectful builtin lands** (`list.IsSorted`, or any validator), do the seam extraction *as
  that slice's first step* — pull the effectful cases into a named `evalEffectfulBuiltin? : String →
  List Value → … → EvalM (Option Value)` helper (in the mutual block, since it calls
  `evalValueWithFuel`), tried in `.builtinCall` BEFORE the pure-evaluate-then-`evalBuiltinCall`
  fallback; new effectful builtins then add an arm to the SEAM, never to the evaluator's top-level
  match. Risk: touches the eval hot path + a `termination_by` measure → a real slice, byte-identical
  gate, NOT an inline cleanup. APPLIED INLINE this round: a forward-pointing seam comment at the
  `.builtinCall` site documenting this rule (comment-only; full gate re-run green).
- **Eval.lean size (3633 lines) — extraction watch, not yet due.** The standing **EvalOps**
  extraction (item 2, ~256 lines of pure scalar algebra, parallel-safe) remains the right first
  carve and is unchanged/live. The mutual evaluator block itself (comprehension walkers + sort
  interception) is large but COHESIVE — every member shares the `EvalM` + fuel + mutual-recursion
  context; splitting it would force a mutual-block-spanning seam. No second extraction is justified
  beyond EvalOps yet; revisit if the file crosses ~4500 or the seam-helper above lands (which would
  itself be a natural small extraction point).
- **Test-org pass (item 3) — module carve LANDED `4b25cef`.** `EvalTests.lean` (1593) carved into
  `ComprehensionTests` (29 pins) + `SortTests` (13 pins) → EvalTests 1246, well under the ~1800
  re-split ceiling; pin-count conserved 179→137+29+13; `lake build` 104 jobs (both modules in the
  build graph via the `Kue/Tests.lean` aggregator). Scope correction: no `GuardTests` (classifier
  units already in `PresenceTests`; comprehension-guard shapes → ComprehensionTests). Other large
  modules unchanged: `BuiltinTests` 943, `FixtureTests` 992, `TwoPassTests` 1030, `FixturePorts`
  3049 (hand-maintained — leave whole). Only residual: the DEFERRED `testdata/cue` fixture regroup
  (see item 3 above). NEXT slice is BI-1.
- **Perf-guide — UPDATED inline.** Added two `kue-performance.md` rows: `list.Sort`/`SortStable`
  cost O(n log n) comparator evals (each a meet + nested `evalValueWithFuel` on `less`; mitigations:
  smaller lists, shallow `less`, pre-concrete elements, prefer `SortStrings`); `math.Pow` exact
  bignum multiply (large exponent → many big-int multiplies, exact result, avoid in hot loops).
- **Walker-dedup family + AD3-4 — survived distillation INTACT, correctly ranked.** Confirmed
  unchanged this batch: AD4-1 (comprehension clause-drivers, FIRST; preserves the VERIFIED-CORRECT
  list/struct `[_|_]`≠`_|_` bottom-non-propagation asymmetry) → A-EN3 + DRY-1 (locality batch) →
  AD2-1 (normalizer pair, file-not-inline). Four distinct mechanisms, all post-argocd, gated behind
  correctness. AD3-4 (bottom-payload newtype) stays RULED OUT. Nothing this batch changed their
  status.

**Phase-B audit 2026-06-20 (whole-graph; scopes test-org `4b25cef` + BI-1 `9bd6927`/`6065380`) — verdict:**

- **★ F-CASE-ARCH RULED — both halves discharged (the headline).** (a) committed `CaseTable.lean`
  STAYS (reproducible/reviewable/offline/no build-time `cue` dep for a frozen leaf table); the
  `DO NOT EDIT` header + generator provenance docstring already exist (no fix needed). (b) the
  oracle-as-data-source convention is WRITTEN as an ADR
  (`docs/decisions/2026-06-20-oracle-as-data-source.md`),
  cross-linked from `slice-loop.md` — oracle = sound DATA SOURCE for an externally-standardized,
  `cue`-faithful domain (verify vs the EXTERNAL standard, record provenance), NEVER a correctness
  GATE for CUE semantics. See the F-CASE-ARCH entry above (now marked RULED).
- **Architecture HEALTHY (whole module graph).** `Builtin → CaseTable` is a clean leaf data
  dependency: `CaseTable.lean` imports NOTHING (true leaf), `Builtin` is its single consumer, no
  cycle, no `Builtin → Eval` edge (still `Eval → Builtin`, the correct direction). BI-1 introduced
  one new leaf module and one import edge — both clean. The test-org carve (`ComprehensionTests` +
  `SortTests`) added two test modules under the `Kue/Tests.lean` aggregator — no production-graph
  impact. No new boundary issue.
- **`Eval.lean` 3645 lines — extraction watch, EvalOps still the right standing carve.** Grew ~12
  lines since the last Phase B (3633), well under the ~4500 re-split threshold. **EvalOps** (item 2,
  ~256 lines pure scalar algebra, parallel-safe) remains the right first carve and is unchanged/live;
  no second extraction justified yet. The BI-EFF seam-helper, when it lands, is a natural small
  extraction point (unchanged ruling).
- **Test/fixture health — module split GOOD; fixture-regroup STAYS DEFERRED (judgment).** The
  test-MODULE carve is sound (pin-count conserved 179, all under ceiling). The `testdata/cue`
  fixture-regroup remains correctly deferred: `FixturePorts.lean` (3049) is hand-maintained source
  whose `fileName` strings are the join key, so each move is a multi-file `git mv` + exact string
  edit across ~77 fixtures with one-typo-breaks-discovery risk, for a low marginal win (layout is
  already subsystem-grouped one level deep). Not worth scheduling now — pick up only as a dedicated
  careful slice or drop. No new fixture-harness debt from BI-1.
- **Perf-guide — current; NO case-lookup row added (judgment call).** The case lookup is a per-char
  O(log n) binary search over ~1190 sorted entries with NO fuel, NO eval re-entry, NO meet, NO
  structural `BEq` — categorically cheaper than every row in the expensive-patterns table (all of
  which involve fuel/eval/meet). A 1000-char string is 1000 bounded array searches = microseconds.
  Adding a row would be misleading noise in a guide framed as "what is expensive." `kue-performance.md`
  reflects current reality; left unchanged.
- **No new code-shaped findings.** BI-1 + test-org left nothing to tidy beyond what Phase A already
  fixed inline. Carried-forward dedup family (AD4-1 → A-EN3+DRY-1 → AD2-1), BI-EFF, and AD3-4-ruled-out
  all survived distillation INTACT and correctly ranked (re-confirmed this batch — see the walker-dedup
  section + BI-EFF item above). Type-system leverage across the graph: nothing new to tighten beyond
  the standing `truncate-primitive` (illegal-states hardening, plan item 1) — recommended next leader.

**Resolved / ruled-out (recorded so they are not re-raised):**

- **AD3-1 / item-3 Regex extraction / B5 regex bullet — DROPPED (stale).** `Kue/Regex.lean`
  already exists as a verified TRUE LEAF (no top-level `import`; `Value.lean:1` is `import
  Kue.Regex`, so the engine is OUT of `Value.lean`). The RX-1a/b NFA rebuild superseded the
  "extract the backtracking engine" framing. Nothing to do.
- **AD3-4 (bottom-payload newtype) — RULED OUT (over-engineering).** `GuardVerdict.bottom`,
  `ClauseExpansion.bottom`, `ListClauseExpansion.bottom` carry an unconstrained `Value` where
  only a bottom is valid, but the invariant is already enforced BY CONSTRUCTION (every
  construction site is one of two arms that can physically only pass a bottom — `classifyGuard`,
  the two clause-expansion arms). A `BottomValue` newtype would ripple through every
  `.bottom`/`.bottomWith` match site (the whole `Value` domain deliberately models bottom as two
  ordinary ctors) for safety already bought. Leave as-is.
- **B5 extraction notes (kept).** `Order.lean` (subsumption) is a DELIBERATE test-only oracle
  (imported only by `Tests/*`), NOT dead code and NOT duplicated — `meet` (join) and `subsumes`
  (partial order) are orthogonal. Recorded so a future audit does not re-flag it as an orphan.

## Pointers (history + reference for anything dropped)

- **Completed-slice history + verification record:**
  [`../reference/implementation-log.md`](../reference/implementation-log.md)
  (chronological, one entry per commit) and `git log`. Every audit batch and design spike is
  recorded there — this plan holds only the live roadmap.
- **Spec-conformance fix backlog (authoritative):**
  [`spec-conformance-audit.md`](spec-conformance-audit.md) § Consolidated fix backlog.
- **CUE-divergence record:** [`../reference/cue-divergences.md`](../reference/cue-divergences.md).
- **CUE spec-gap record:** [`../reference/cue-spec-gaps.md`](../reference/cue-spec-gaps.md).
- **Decisions:** [`../decisions/`](../decisions/) (compatibility target,
  correctness-over-perf, Value-model fork resolution).
- **Slice loop + audit cadence:** [`../guides/slice-loop.md`](../guides/slice-loop.md).
- **Performance guide:** [`../guides/kue-performance.md`](../guides/kue-performance.md).
- **Status page:** [`../www/index.html`](../www/index.html) — single human-scannable status
  page; refreshed on plan-hygiene passes.
- **CUE semantics reference:** [`cue-language-guide.md`](cue-language-guide.md);
  [`architecture.md`](architecture.md) + [`compat-assumptions.md`](compat-assumptions.md).
- **Latest session state / next step:** the most recent breadcrumb in
  [`../notes/`](../notes/).
