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
argocd residual **Bug2-5** (PARKED), **BI-1** (✅ DONE 2026-06-20 — Unicode case-fold for
`ToUpper`/`ToLower` via oracle-generated BMP simple-mapping table, no network; ToTitle +
full-folding tail deferred), **E#4-fix** (✅ DONE 2026-06-20 — arithmetic operator domain now
type-errors concrete out-of-domain operands + string/bytes `*` repetition; see item #6),
**BI-2-residual** (Sqrt + neg/fractional Pow), **SC-3** display-residual, **SC-4** (spec-gap-first),
**SC-1b** (closed×closed-pattern), **A#6** (`containsBottom` fuel cap, standalone), **DYN-DEF-1**
(✅ DONE 2026-06-20 — a dynamic field with a non-concrete key now DEFERS as a residual instead of
being dropped; see the walker-dedup section + implementation-log).
**DRY-1 is RULED OUT** (the let-walkers
don't share a combinator — collect-vs-rewrite + a `List Nat` worklist + a termination trap;
attempted under A-EN3 and reverted, see the walker-dedup section — do not re-file).
**The 4 spec-gap ratifications are DONE (2026-06-20):** gaps 1–3 RATIFIED + test-pinned; gap 4
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

**Walker / normalizer dedup family (UNBLOCKED — schedulable DRY cleanups, LOW/MED-risk):**

**Gating ruling (Phase-B 2026-06-20, the second one this date — supersedes the "post-argocd"
gate):** these are now **UNBLOCKED and schedulable**. The original "gated post-argocd / after
Bug2-5 un-parks" gate had ONE rationale — avoid walker-edit contention while argocd was being
actively debugged on the same `Eval.lean` walker code. argocd/Bug2-5 is now **PARKED** (a
stress-test finding, explicitly off the critical path, may never un-park), so no such debugging
is happening: the contention the gate guarded against no longer exists. "Gated post-argocd" had
therefore silently become "deferred forever," which is wrong for real DRY cleanups. They are NOT
correctness fixes, so they still never PREEMPT a spec-conformance fix in the ranking — but with
the spec-conformance HIGH levers all DONE (only PARKED Bug2-5 remains), the family is the
schedulable DRY backlog. Schedule by the settled sequencing below; re-confirm line-refs at slice
start (the eval region shifts ±tens of lines per slice).

Decomposition ruling (Phase-B 2026-06-20, earlier — do not re-litigate): these are NOT one
problem. There are THREE distinct walker families plus a separate normalizer pair — four
different mechanisms, result types, recursion domains, and termination measures. Folding all
under one abstraction would be a false "stuff they all do" extraction. **Family status: AD4-1 DONE
→ A-EN3 DONE (`5652717`) / DRY-1 RULED OUT (the let-walkers genuinely don't share a combinator —
see the A-EN3+DRY-1 entries below) → AD2-1 is now the SOLE remaining dedup-family member
(file-not-inline).**

**Next-leader ranking (correctness-first; updated Phase-A 2026-06-20, the audit of the A-EN3-DYN +
DYN-DEF-1 dyn-field batch):** **A-EN3-DYN and DYN-DEF-1 are both ✅ DONE and AUDITED SOUND** (Phase-A
verified the depth-mirror, `classifyDynLabel` exhaustiveness, and the corrected fixture — see the
Phase-A entry below). Phase-A found and **FIXED INLINE two NEW wrong-results** (D#1d comprehension-
body tail/pattern drop; default-disjunction dyn-field label collapse) and **FILED one** as the new
leader. **Live order: (1) D#1d-RESIDUAL** (MEDIUM Violation — a held residual inside a comprehension
body is silently dropped; wrong-result, outranks everything below) → **(2) AD2-1** (LOW-MED
disjunction-normalizer dedup, file-not-inline, value-sound display-only) → **(3)** the LOW cosmetic
tail (item 6). **Phase-B is still DUE** for this batch (architecture/refactor over the module graph;
the breadcrumb's AUDIT-DUE flag is Phase-B's to clear) — and should weigh the now-FOUR parallel
classifiers (`classifyGuard`/`classifyDefinedness`/`classifyArithOperand`/`classifyDynLabel`):
re-evaluate whether the prior "leave separate" ruling holds at four, or a shared concreteness
partition is now warranted.

- **AD4-1 (MEDIUM — comprehension-walker dedup) — ✅ DONE (this batch; see implementation-log).**
  The struct/list comprehension clause-walkers had BYTE-IDENTICAL `.guard`/`.letClause`/`.forIn`
  arms + identical bottom/deferred folds, differing only in payload type and the exhausted-chain
  (`[]`) body handler. Unified behind ONE generic `ClauseOutcome β` (ctors `payload`/`bottom`/
  `deferred`; `ClauseExpansion`/`ListClauseExpansion` are now `abbrev`s = `ClauseOutcome (List
  Field)` / `(List Value)`) and ONE generic driver pair `expandClauseChain` + `expandForPairs`
  (`[EmptyCollection β] [Append β]`), parameterized SOLELY by the `[]`-arm body→outcome handler.
  The two public `*ClausesWithFuel` defs are now thin β-instantiating wrappers; the two
  `*ForPairsWithFuel` defs were DEAD after the dedup (the `for` recursion goes straight through the
  generic `expandForPairs`) and were DROPPED — net four walkers → two combinators + two wrappers.
  **The VERIFIED-CORRECT `[_|_]`≠`_|_` asymmetry was preserved AND newly pinned** (it lives entirely
  in the `onExhausted` parameter: struct short-circuits a bare-`.bottom`/`.bottomWith` body to
  `.bottom` per D#1a; list wraps ANY body, incl. a bottom, as `.payload [body]` — a bottom ELEMENT
  is not the list being bottom). Four new `native_decide` pins in `ComprehensionTests`:
  struct-body-bottom → `_|_`, list-body-bottom → `[_|_]`, and both → `export` error
  (`exportJsonBottoms`). **`termination_by` preserved** by keeping the `match fuel with | 0 | fuel+1`
  skeleton + recursive self-calls LEXICALLY visible in the generic combinators (the `onExhausted`
  callback is pure/non-recursive, so it hides no fuel pattern — the truncate-primitive Step-2 trap
  avoided); the two thin wrappers carry measure tag 2 (between the tag-0 chain they call and the
  tag-3 `evalListItemsWithFuel` caller, both at equal fuel). Gate met: byte-identical fixtures,
  axiom-clean (no `sorryAx`/`partial`), cert-manager content-identical.
- **A-EN3 (LOW — pure structural `Value` folds) — ✅ DONE (`5652717`).** The three structural
  folds `refsSelfEmbeddedLabel`/`selfReferencedLabels`/`defFrameRefIndices` collapsed to thin
  instantiations of ONE generic `foldValueWithDepth` (combine + empty + a pre-order `Option` leaf
  hook + a `dynValShift` offset for the lone structural divergence at `.dynamicField`'s value
  position). The three `*Clauses` helpers were dropped — the fold's single `descendClauses`-based
  clause handler subsumes them. Termination preserved STRUCTURALLY (no `termination_by`, matching
  the originals; recursive self-call lexically visible inside the combinator's own `match fuel`);
  axiom-clean (`propext`/`Quot.sound` only). All two-pass agreement + Bug2-1..2-4 soundness pins
  re-run green (`native_decide` recomputes = definitional equivalence — no hand re-proof needed);
  +3 new combinator pins (empty-monoid, leaf short-circuit, `dynValShift` divergence). Byte-identical
  fixtures + cert-manager content-identical to cue. **Latent finding surfaced (not fixed — would
  break byte-identical):** `defFrameRefIndices` scans a `.dynamicField`'s VALUE at `depth+1`
  (`dynValShift=1`), but the resolver pushes NO frame for a dynamic field (`Resolve.lean:139`
  resolves key+value in the same scope) — an over-deep scan that systematically misses def-frame
  refs buried in a dynamic-field value. The DRY refactor correctly preserved this byte-identically
  (the old `defFrameRefIndices` scanned the dyn-field value at `depth+1` too — verified against
  `f9c1e56`); the refactor introduced NOTHING. See A-EN3-DYN for the reachability verdict.
- **A-EN3-DYN — ✅ DONE (this slice; see implementation-log).** A comprehension inside an embedded
  def reading a regular def sibling SOLELY through a DYNAMIC field's value, where the sibling is
  narrowed at the use site, produced a wrong result (the narrowing was lost; the witness exported as
  an incomplete `string`). The static-body control (`{k: kind}`) was always correct — clean
  static-vs-dynamic isolation. **Root cause turned out to be TWO parallel sites of the same
  depth-mirror bug, not one** (the original diagnosis named only the first):
  1. `foldValueWithDepth`/`defFrameRefIndices` scanned the dyn-field value at `depth+1` (the
     `dynValShift=1` knob) → `embedComprehensionReadLabels` missed the sibling as a splice seed.
  2. `hasSelfRefAtDepth` had the IDENTICAL `+1` on the dyn-field value (and dropped the key entirely)
     → `defBodyHasSiblingSelfRef` returned `false`, so the def took the EAGER path (resolves `out`
     against `kind: string`, caches it) instead of the deferral/closure-force path. **This second
     site was found by instrumenting the eval after fixing only the first did not move the result.**
  Both were necessary. Spec basis: a `.dynamicField` pushes NO resolver frame (`Resolve.lean`
  resolves key+value in the parent scope), so both scans must read the value at the PARENT depth.
  **Fix:** dropped the now-dead `dynValShift` parameter (all three `foldValueWithDepth`
  instantiations passed `0`) and inlined the `0` offset; changed `hasSelfRefAtDepth`'s dyn-field arm
  to scan key+value at `depth`. **Tests:** four `testdata/cue/comprehensions/` fixtures (witness,
  static control, multi-level key+nested-value, unaffected-no-sibling) + `FixturePorts` entries, each
  cross-checked against cue v0.16.1; the A-EN3 pin `fold_value_dynfield_shift_divergence` (which
  LOCKED the over-scan) REPLACED by `fold_value_dynfield_value_scanned_at_parent_depth` asserting the
  corrected arms. CONFORMS to spec (cue was right → no `cue-divergences.md` entry). Gate green:
  build/`fixture pairs ok` (full corpus byte-identical except the now-correct buggy case)/shellcheck;
  cert-manager byte-identical to the pre-fix HEAD baseline. Separately surfaced while probing:
  **dynamic fields inside DEFINITIONS are dropped entirely when the keying field is narrowed at the
  use site** (`#Add: {kind: string, (kind): "m"}` then `#Add & {kind: "specific"}` → cue keeps
  `specific: "m"`, kue drops it) — a DISTINCT pre-existing bug (no comprehension, so
  `defFrameRefIndices` is not on its path), filed as **DYN-DEF-1** below.
- **DYN-DEF-1 (MEDIUM Violation) — ✅ DONE (the 2nd dyn-field slice; see implementation-log).** A
  dynamic field `(expr): v` whose label was NOT a concrete string was silently DROPPED instead of
  held as a residual. The original "specific to definitions / def-splice" framing was WRONG: the
  narrowed witness (`#Add & {kind: "specific"}`) already re-keyed on HEAD (the A-EN3-DYN
  `hasSelfRefAtDepth` key-scan fix had repaired the deferral gate); the residual bug was a pair of
  silent-drop arms keyed on a non-string label (`expandComprehensionWithFuel` `_ => .ok ([], [])`
  and the standalone `.dynamicField` eval `_ => .bottom`) — NOT def-specific (a plain struct with an
  abstract key dropped identically). Fix: one exhaustive `classifyDynLabel : Value ->
  DynLabelVerdict` (mirrors `classifyGuard`) at BOTH sites — concrete string re-keys; bottom
  propagates; concrete non-string is a type error (`BottomReason.nonStringLabel`); abstract/incomplete
  (incl. the `string` kind) DEFERS, holding the unevaluated `.dynamicField` so a later narrowed
  re-eval re-keys it. Renamed `NonBoolGuardType → ConcreteTypeName` (now shared by 4 reasons).
  CONFORMS to spec (cue correct); the held-residual `@d.i` key display folds into the existing D#1b
  display divergence row. Gate green; cert-manager byte-identical to pre-fix HEAD.

- **── Phase-A audit (2026-06-20, A-EN3-DYN + DYN-DEF-1 batch) — adversarial dyn-field probe ──**
  The two batch fixes were audited adversarially against `cue` v0.16.1 across the whole reshaped
  dyn-field path (bytes/int/bool/null keys, field collisions, abstract/never-concrete keys,
  dyn-key-refs-dynfield, nested comprehensions, disjunction/bounded/default keys). **Both batch
  fixes are SOUND**: `classifyDynLabel` is exhaustive (28/28 `Value` ctors, no catch-all, green
  build proves it); the four verdicts are spec-correct (a non-string concrete label — incl. bytes,
  int, bool, null, struct, list — is a type error matching cue, not a coercion; abstract/incomplete
  defers and export-errors matching cue's hold-then-error). The **A-EN3-DYN two-site depth-mirror is
  EXACT**: `Resolve.lean` (`resolveValueWithFuel` `.dynamicField` arm) resolves key AND value against
  the SAME `scopes` with NO `buildFrame` push (contrast `.structComp`, which DOES push), so both
  scanners — `foldValueWithDepth` (`rec' depth l`/`rec' depth inner`) and `hasSelfRefAtDepth`
  (`… depth key || … depth value`) — correctly scan both sub-positions at the parent depth.
  `dynValShift` is fully removed from the implementation (the sole residual hit is a FixturePorts
  CODE COMMENT recording the historical fix). The corrected fixture
  `dynfield_comprehension_key_and_nested_value.expected` is oracle-faithful (`patch.out:
  [{t: {label: "n"}}]` byte-matches cue; only the `#Add` def-body `@d.i` rendering is the documented
  D#1b display limitation). **Two NEW wrong-results found and FIXED INLINE this audit** (below:
  D#1d, default-label-collapse); **one filed** as a new leader (D#1d-RESIDUAL). Two display-only
  observations (NOT bugs): (a) `{(a):"z", a:"k"}` exports the same keys/values as cue but in
  declaration order vs cue's graph order — same field-ordering family as the RATIFIED spec-gap;
  (b) a held dyn-field/comprehension residual renders its re-keyed label as `@d.i` (D#1b).

- **D#1d (MEDIUM Violation — comprehension-body tail/pattern DROP) — ✅ DONE (fixed inline, this
  audit).** A struct-comprehension whose body carried a `...` tail OR a `[pat]:` constraint dropped
  the body WHOLESALE (`x: {for _ in [1] {a:1, ...}}` → kue `{}` vs cue `{a:1}`) — its regular fields
  vanished with the tail/pattern. Root cause: the struct `[]`-arm handler in `expandClausesWithFuel`
  matched only `.struct _ _ none [] _` (no tail, no patterns), so a tail/pattern-bearing body fell
  to the catch-all `_ => .payload []`. A comprehension body's tail/patterns are BODY-LOCAL — they
  bound the body block but do NOT propagate out of the `for`/`if`; only the named fields merge
  (cue-confirmed). Fix: match ANY `.struct fields _ _ _ _` → `.payload fields`. CONFORMS to spec
  (cue correct). Pins: `ComprehensionTests` `comprehension_body_tail_is_body_local` /
  `_pattern_is_body_local` / `_tail_exports_field` + fixtures `comprehensions/
  comprehension_body_{tail,pattern}_local`. The LIST twin needs no change (it correctly wraps any
  body as a held element — the D#1a asymmetry). Gate green (build/`fixture pairs ok`/shellcheck);
  TwoPassTests preserved (the broadened `.struct` match does not over-fire — verified).

- **Default-disjunction dyn-field LABEL collapse — ✅ DONE (fixed inline, this audit).** A dynamic
  field whose label evaluated to a DEFAULT disjunction (`(*"a" | "b"): 1`) was wrongly HELD/export-
  errored instead of keying on its default (cue → `{x: {a: 1}}`). `classifyDynLabel`'s `.disj` arm
  sent EVERY disjunction to DEFER, never consulting the default mark. Fix: a tiny pure helper
  `resolveDynLabelDefault` (collapses a marked-default disjunction via `resolveDisjDefault?`, leaves
  an ambiguous one untouched) applied at BOTH `.dynamicField` sites BEFORE `classifyDynLabel` —
  mirroring the EXISTING precedent in the `if`-guard path (`expandClauseChain`, which collapses a
  default-disjunction guard the same way before `classifyGuard`). A default label thus keys
  concretely; an ambiguous (no-default, ≥2-arm) disjunction STILL defers (boundary preserved). A
  default that selects a concrete non-string (`*3 | "b"`) correctly type-errors (the collapse
  exposes `3`). CONFORMS to spec (a default disjunction concretizes in a concrete context — the
  same selection D#2b notes; this is a VALUE re-key, distinct from D#2b's display question). Pins:
  `ComprehensionTests` `dyndef_default_disj_key_collapses` / `_via_ref` / `_nonstring_errors` /
  `dyndef_nondefault_disj_key_still_defers` + `PresenceTests` `resolve_dynlabel_default_*` /
  `classify_dynlabel_after_default_collapse_concrete`. Gate green.

- **D#1d-RESIDUAL (MEDIUM Violation — held residual inside a comprehension body DROPPED) — ⛔ FILED,
  NEXT LEADER (ahead of AD2-1).** A comprehension body that itself evaluates to a HELD RESIDUAL — a
  `.structComp` carrying a held dynamic field with a non-concrete key (`x: {for k in [string]
  {(k):1}}`) OR a nested deferred `if`/`for` (`x: {for _ in [1] {if g {y:1}}}`) — is silently
  DROPPED to `{}` (cue HOLDS the entire block under eval, errors incomplete under export). The
  struct `[]`-arm handler (`expandClausesWithFuel`) emits only a fully-resolved `.struct`'s fields;
  a `.structComp` body falls to `_ => .payload []`. This is the DYN-DEF-1 silent-drop bug class ONE
  LAYER UP, at the comprehension-body boundary — adjacent to but distinct from the (now-fixed) D#1d
  tail/pattern drop. **Attempted inline, REVERTED:** a `.structComp → .deferred` arm is NOT safe — a
  `.structComp` body is ALSO the normal in-progress two-pass carrier that later RESOLVES (it broke 7
  `TwoPassTests` where `add.#patch` is transiently `.structComp` then concretes). The correct fix
  must distinguish a GENUINELY-undecidable body residual (defer the whole comprehension) from a
  transient-but-resolvable one (let the two-pass machinery complete it) — `onExhausted` runs too
  early to tell them apart, so this needs the deferral decision moved to where the body's final
  resolvedness is known, or a residual-vs-transient discriminator on the body value. NOT a contained
  one-arm fix; FILED rather than forced. The LIST twin is already CORRECT (a held-residual struct is
  a valid held list ELEMENT — verified vs cue). Witnesses (eval): `for-abstract-key` and
  `for-nested-deferred-if` both → kue `{}` vs cue holds. **This is a wrong-result Violation and
  outranks AD2-1** (the LOW-MED display-only dedup) per correctness-first.

- **DRY-1 (let-walker dedup) — ✗ RULED OUT (attempted under A-EN3's slice, reverted; no behavior
  change shipped).** The plan was ONE `walkFollowedLets` with `closeDefFrameReadIndices` /
  `letPromotedReadLabels` / `injectLetLocalNarrowings` as thin instantiations. It is the DRY trap,
  on three independent grounds: (1) **`closeDefFrameReadIndices` shares nothing mechanically** — it
  recurses on a `List Nat` worklist (visited-set `List Nat` via `slotVisited`, lets followed BY
  INDEX via `nthField`), never destructuring a `Value`; a different carrier, visited-set, and
  follow mechanism from the other two. (2) **collect vs rewrite** — `letPromotedReadLabels` is a
  catamorphism (`Value → List String`), `injectLetLocalNarrowings` is an endo-REWRITE (`Value →
  Value`) that must reconstruct the exact `.structComp`/`.struct` preserving openness/tail/patterns;
  a combinator doing the struct-dispatch DISCARDS that metadata, so the rewrite can only be
  expressed by handing the whole `v` back and re-dispatching — zero leverage. (3) **termination** —
  EMPIRICALLY confirmed: routing the nested-let recursion through a combinator's `step` callback
  breaks Lean's structural-recursion inference (`failed to eliminate recursive application … Could
  not find a decreasing measure`), the same lambda-hides-`fuel+1` trap that killed truncate Step-2.
  The contrast with the SUCCESSFUL AD4-1 dedup is the lesson: AD4-1's variation point (`onExhausted`)
  was a PURE non-recursive leaf, so the combinator could own the recursion; DRY-1's variation point
  (the per-walker nested-let step) IS itself the recursion, so it can't be factored into a pure
  callback. The shared skeleton is only ~4 lines (`match fuel | 0 | f+1 => if seen.contains v then`
  …) between TWO of the three walkers, not worth an indirection that worsens the code. Mirrors the
  Phase-A ruling on the analogous `classifyArith/Guard/Defined` trio ("the stuff they all do is not
  a name"). Note `injectLetLocalNarrowings` already reuses `letPromotedReadLabels` — they are
  factored at the right seam. **Do not re-file.** (If Bug2-5's hypothetical 4th disj-path walker
  ever lands and is itself catamorphic over the same carrier, re-evaluate THEN — but on current
  evidence the family does not share a combinator.)
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

**Phase-B audit 2026-06-20 (`a788f5c`, whole-graph; scopes AD4-1 `524a402` + A-EN3 `5652717`;
Phase A `6a5521a` found both dedups SOUND, re-classified A-EN3-DYN to a REACHABLE Violation + filed
DYN-DEF-1) — verdict: HEALTHY; no code fix; rankings/rulings folded in. CLOSES the audit round.**

- **★ Abstractions CONFIRMED right-level + sound (the headline; Phase A already verified soundness,
  this is the architecture sign-off).** Both dedups land at the correct seam, with the variation
  point isolated as a PURE non-recursive callback so the combinator owns the recursion (the
  truncate-Step-2 / DRY-1 trap avoided):
  - **`foldValueWithDepth` (A-EN3, `Eval.lean:110`)** — one depth-threading structural `Value` fold;
    the three scanners (`refsSelfEmbeddedLabel` `Bool`/`||`, `selfReferencedLabels` `List String`/`++`,
    `defFrameRefIndices` `List Nat`/`++`) are thin instantiations differing only in the monoid, the
    pre-order `leaf` hook, and the `dynValShift` offset. Clause-depth threading is centralized in
    `foldValueWithDepthClauses`/`descendClauses` — a single authority, not duplicated per scanner.
    (The `dynValShift` knob that documented the one structural divergence was the A-EN3-DYN bug
    locus; A-EN3-DYN is now DONE and the knob was dropped — all instantiations scan at the same
    depth. See the A-EN3-DYN entry.)
  - **`ClauseOutcome β` + `expandClauseChain`/`expandForPairs` (AD4-1, `Eval.lean:2492`/`3443`)** —
    `[EmptyCollection β] + [Append β]` is exactly the right interface (empty payload for the
    `fuel=0`/`concreteFalse`/no-pairs cases, `++` to concatenate iteration payloads). The struct/list
    twins reduce to two thin β-wrappers parameterized SOLELY by the `onExhausted` `[]`-arm handler,
    which is where the VERIFIED-CORRECT `[_|_]`≠`_|_` asymmetry lives (struct short-circuits a bottom
    body per D#1a; list wraps any body as a one-element payload). Clean composition, pure variation
    point. The dropped `*ForPairsWithFuel` twins are genuinely GONE (dead-code grep: zero defs, zero
    refs); the surviving `expand{,List}ClausesWithFuel` are the intended β-instantiating wrappers.
- **Walker-dedup family DRAINED — AD2-1 is the SOLE remaining member; plan reflects it.** DRY-1 ruled
  out, AD4-1 + A-EN3 DONE. Confirmed in the walker-dedup section's family-status line (updated this
  round to separate "sole dedup-family member" from "next overall leader").
- **Bug ranking RE-ORDERED to correctness-first (folded into the walker-dedup section).** Phase A's
  re-classification of A-EN3-DYN (LOW corner → REACHABLE wrong-result Violation) outranks the DRY
  cleanup AD2-1 under the correctness-over-everything gate. At that round's close the order was
  **DYN-DEF-1 (MEDIUM Violation) → AD2-1**; **both dyn-field Violations (A-EN3-DYN, DYN-DEF-1) have
  since landed**, so the live leader is now **AD2-1** (the sole dedup-family member, a value-sound
  display-only cleanup). The walker-dedup section formerly read "AD2-1 is NEXT leader" (written
  pre-re-classification); after the two Violations DONE it is once again the leader, this time with
  nothing ahead of it.
- **`.any`→`foldl` short-circuit (Phase A flag) — RULED: ACCEPT, no fix.** `refsSelfEmbeddedLabel`
  was a lazy `Bool` `.any` (early-cut on the first hit); as a `foldValueWithDepth` it is a `foldl`
  over the whole tree (`(· || ·)`, fuel-bounded, value-identical, no early exit). NOT worth a fix:
  (1) the only caller, `needsEmbeddedSelfPass` (`Eval.lean:202`), runs it inside `canonical.any` —
  that OUTER `.any` still short-circuits across fields, so a hit in field 1 never scans field 2; only
  the WITHIN-a-single-field-value scan lost its early exit, the smaller cost. (2) The tree is fuel-
  bounded (`evalFuel=100`) and the values are bounded canonical-field expressions, so the worst case
  is a bounded constant, not unbounded work. (3) Restoring `.any` JUST for the `Bool` case would
  require a separate short-circuiting fold variant (a `foldl`-with-early-stop or a `Bool`-specialized
  combinator) — re-introducing exactly the per-shape duplication A-EN3 removed, for no measurable
  gain on bounded trees. A short-circuiting monadic-fold variant is over-engineering here. NOT a perf
  row in `kue-performance.md` (the cost is a bounded constant inside an already-gated two-pass; a row
  would be misleading noise in a "what is expensive" guide). Re-evaluate ONLY if a profiler ever shows
  `needsEmbeddedSelfPass` hot on a large real input (none does — cert-manager content-identical at
  ~30.6s, the two-pass gate spares the common embedding case entirely).
- **Architecture HEALTHY (whole module graph) — confirmed, not manufactured.** Both dedups are
  intra-`Eval.lean` (zero new import edges — verified). Layering acyclic and correct, unchanged from
  the last three Phase-B passes: `Builtin → {Lattice, Regex, Decimal, Base64, Json, Yaml, CaseTable}`
  (true leaves — `CaseTable`/`Regex`/`Base64` import nothing), `Eval → {Builtin, Decimal, Lattice,
  Regex, Normalize}`, `Lattice → {Value, Regex}`, `Value → Regex`, `Decimal/Resolve/Normalize →
  Value`, `Runtime → Eval` (the one-directional app edge). NO `Builtin → Eval` back-edge (grep-
  confirmed — `Eval → Builtin` is the correct direction; the sort lives in `Eval` BECAUSE its
  comparator needs `EvalM`). No cycle anywhere.
- **`Eval.lean` 3605 lines — extraction watch, NOT due; shrank ~136 since last Phase B (3741).** The
  AD4-1 + A-EN3 dedups NET-removed lines (four walkers → two combinators + two wrappers; three folds +
  three `*Clauses` helpers → one fold + one clause handler). Well under the ~4500 re-split threshold.
  **EvalOps** (item 2, ~256 lines pure scalar algebra, parallel-safe) remains the right first carve,
  unchanged/live; no second extraction justified. The `foldValueWithDepth` family is correctly placed
  in `Eval.lean` (the scanners feed the embedding-`Self` two-pass and the def-frame splice — both
  eval-internal; extracting them would force a back-reference into the evaluator), NOT a shared helper
  module — re-confirms the breadcrumb's open question with "stays in Eval.lean."
- **Dead code — CLEAN.** The dropped `*ForPairsWithFuel` (AD4-1) and `*Clauses` scanner helpers
  (A-EN3) are gone with zero dangling refs (grep-verified). No deprecated APIs, no orphans introduced.
- **Perf-guide CURRENT — no edit.** The two dedups are behavior-preserving refactors (byte-identical
  fixtures); they change no eval cost. The `.any`→`foldl` change is a bounded-constant within an
  already-gated path (see the ruling above) — no new slow pattern, no mitigation landed, nothing stale.
  `kue-performance.md` reflects current reality.
- **Verify gate GREEN.** `lake build` 108 jobs; `scripts/check-fixtures.sh` → `fixture pairs ok`
  (zero drift); `shellcheck scripts/*.sh` clean. No inline code fix applied (the one flagged item,
  `.any`→`foldl`, ruled accept); doc-only changes committed.

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

**Phase-B audit 2026-06-20 (whole-graph; scopes truncate-primitive `7dfaadd` + ratifications
`47ff318` + E#4-fix `02b8b9d`; Phase A `8be4457` found all SOUND, no code fix) — verdict:**

- **★ Two rulings (the headline) — both CLOSED.** (1) **Three-parallel-classifiers DRY → LEAVE
  SEPARATE** (option a; option b rejected). Recorded in Resolved/ruled-out below with the full
  basis: the three classifiers disagree on the PARTITION (`.disj`/`.structComp`/`.bottom`/`.prim`/
  `.binary` all land differently), so a shared concreteness helper would need per-classifier hooks
  for exactly those ctors, factoring out only the inert abstract tail = "the stuff they all do" =
  not a name (general-coding), while RAISING coupling + LOWERING the new-ctor-forces-a-decision
  guarantee. (2) **Walker-dedup gating → UNBLOCKED.** The "post-argocd" gate's sole rationale was
  walker-edit contention during active argocd debugging; argocd/Bug2-5 is now PARKED (off the
  critical path, may never un-park), so the contention is gone and "gated post-argocd" had degraded
  to "deferred forever" — wrong for real DRY cleanups. They are not correctness fixes (still never
  preempt a spec-conformance fix), but with the spec-conformance HIGH levers all DONE, **AD4-1 is now
  the strong next-batch leader.** Plan ranking/gating language updated (see the walker-dedup section).
- **Architecture HEALTHY (whole module graph) — confirmed, not manufactured.** Layering acyclic
  and correct: `Builtin → {Lattice, Regex, Decimal, Base64, Json, Yaml, CaseTable}`, `Eval →
  {Builtin, Decimal, Lattice, Regex, Normalize}`, `Lattice → {Value, Regex}`, `Value → Regex`,
  `Decimal/Resolve/Normalize → Value`. NO `Builtin → Eval` back-edge (still `Eval → Builtin`, the
  correct direction — the sort lives in `Eval` BECAUSE its comparator needs `EvalM`). `Kue.Normalize`
  (238 lines, `import Kue.Value` only) is a clean leaf, not previously called out in the layering
  prose but no cycle. E#4 + truncate touched only `Eval.lean` interiors — no boundary impact.
- **Eval.lean 3741 lines — extraction watch, NOT yet due.** Grew ~96 since the last Phase B (3645);
  E#4-fix added the arithmetic classifier/gate (`classifyArithOperand`/`arithmeticDomainResult`/
  `evalRepeat`, ~80 lines) to the `evalAdd…evalDiv` region. Still well under the ~4500 re-split
  threshold. **EvalOps** (item 2, ~256 lines pure scalar algebra incl. the new arith defs — fold
  them into the carve per the breadcrumb note) remains the right first carve, unchanged/live. No
  second extraction justified yet. NOT more urgent than the DRY cleanups — both are schedulable.
- **E#4 / truncate type-system leverage — already tight.** `classifyArithOperand` is a total
  no-catch-all enumeration; the two new `BottomReason`s ride the generic `.bottomWith` (no match
  site to update); `EvalState.truncate` is the single bump choke point. Nothing to tighten beyond
  the standing items (truncate-primitive's residual routing-discipline is the documented, ruled-out
  limit — full type-level unrepresentability breaks the mutual block's `termination_by`).
- **Doc-staleness — FIXED INLINE (LOW risk, docs-only).** `spec-conformance-audit.md` carried two
  obsolete ranking/cadence paragraphs (the old "NOW LEADS — the MED tail" + a duplicate MED-tail
  block, ~old-lines 205-222) that listed the now-CLOSED 4 ratifications as open backlog (twice) and
  announced a two-phase audit that already closed at `4593185` with a stale `7ee15d8`-era counter.
  Replaced with a short current-state pointer that defers ranking to the authoritative Consolidated
  fix backlog + `plan.md` (so it cannot drift again). E#4 confirmed correctly marked DONE/RESOLVED
  everywhere else (audit doc lines 405-420, `cue-spec-gaps.md` row 55); `## Status` E-row needs no edit.
- **Test/fixture health + perf-guide — unchanged, correct.** Test-MODULE split sound; `testdata/cue`
  fixture-regroup STAYS DEFERRED (hand-maintained `FixturePorts` join key, high blast radius, low win
  — judgment unchanged). Perf-guide current: E#4 added string-repeat (O(n) `String.join`, cheap) +
  arith domain checks (O(1) ctor match, cheap); truncate is a behavior-preserving refactor. No perf
  row warranted (a row in a "what is expensive" guide would be misleading noise) — judgment call, left
  unchanged. No new code-shaped findings.

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
- **Three-parallel-classifiers DRY (`classifyArithOperand` / `classifyGuard` /
  `classifyDefinedness`) — RULED: LEAVE SEPARATE (option a), do NOT extract a shared
  concreteness partition (option b rejected). Phase-B 2026-06-20.** All three enumerate every
  `Value` ctor with no catch-all and bucket the long inert abstract tail (kind/bound/ref/conj/
  builtin/unary/selector/index/comprehension/interpolation/dynamicField/closure/thisStruct/top/
  notPrim/stringRegex) into "defer/incomplete". But that inert tail IS "the stuff they all do" —
  not a name (general-coding). Option (b), a `classifyConcreteness` partition the three call,
  does NOT factor cleanly: the three disagree on the PARTITION itself, not merely on verdict
  names. `.disj` is abstract for arith+guard but concrete-decidable for definedness (`liveAlternatives`
  → defined/error); `.structComp` is abstract for arith+guard but `.defined` for definedness;
  `.bottom`/`.bottomWith` is (unreachable-)incomplete for arith, `.error` for definedness, a
  bottom-PAYLOAD verdict for guard; `.prim` is one verdict for arith/definedness but a 3-way split
  (`true`/`false`/non-bool) for guard; `.binary` is incomplete for arith/definedness but a
  presence-test split (`.eq/.ne _ .bottom` → false) for guard. A shared partition would need
  per-classifier hooks for exactly those five ctor groups, leaving only the inert tail genuinely
  common — so (b) would RAISE coupling (three soundness-critical exhaustive matches depending on
  one helper) while LOWERING the compile-time guarantee that a NEW `Value` ctor forces an
  independent decision at all three sites (the whole point of the no-catch-all enumeration). Verdict
  sums (`ArithOperandClass`/`GuardVerdict`/`Definedness`) are genuinely distinct. Analogous to the
  AD3-4 ruling above. Leave as three independent total functions.

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
