# Kue Plan

The live implementation roadmap. Kept small, current, and actionable — one focused slice
at a time. The full record of completed slices lives in
[`../reference/implementation-log.md`](../reference/implementation-log.md) (chronological,
one entry per commit) and `git log`; this file holds only where we are and what's next. A
periodic plan-hygiene pass distills it back to the live roadmap (history → log + git); see
[`../guides/slice-loop.md`](../guides/slice-loop.md). Last distilled 2026-06-21.

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
- **Spec is the authority; `cue` is a fallible cross-check, never the gate.**
  Byte-identical to `cue` is structurally bug-replicating. Conform to the CUE spec; where
  it is silent, to lattice first principles (precise, total,
  illegal-states-unrepresentable). When `cue` disagrees with the spec it is WRONG → follow
  the spec, record in `cue-divergences.md`.
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

- **Evaluator + lattice.** Total `meet` /`join` over the full `Value` domain; primitives,
  kinds, bounds, regex, struct/list shapes. `Field` is a `structure`. Disjunctions with
  default-mark algebra (unification ANDs default sets; arithmetic/comparison/unary
  resolve-operand-first; nested two-level precedence; equal-default dedup).
  Structural-cycle detection: `#L:{n,next:#L}` errors; `#List | *null` terminates on
  `*null` (D#2).
  ```cue
  port: int & >0 & <=65535
  port: 8080  // 8080
  ```
- **Closures / cross-package def-meet.** `Value.closure (frame) (body)` carries the
  capture frame so an imported def's body unifies with the use-site *before* its
  cross-frame self/sibling refs resolve. Deep/nested self-ref detection
  (`hasSelfRefAtDepth`); multi-level embed chains resolve. Forcing tier closes imported
  def bodies at capture.
  ```cue
  import "ex.com/pkg"
  web: pkg.#Def & {name: "web"}
  ```
- **Comprehensions.** Struct (`for k,v in s {…}`) and list (`[for x in xs {x}]`, incl.
  `if` guards, `let` clauses (D#3), nested/multi/zero-yield, plain+comp interleave). Guard
  classification (D#1b/c): incomplete guard DEFERS (residual node), concrete non-bool
  guard is a TYPE ERROR, presence-test `X !=/== _|_` drops. Scalar struct-embedding
  collapse (`{5}`→`5`) at embed-eval.
  ```cue
  out: [for x in [1, 2, 3] {x * 2}]  // [2, 4, 6]
  ```
- **Disjunction defaults under embedding.** Use-site narrowing distributes into every arm
  of an embedded default disjunction, pruning dead arms.
  ```cue
  x: (*"a" | "b") & ("b" | "c")  // "b"
  ```
- **Fuel-saturation perf.** Eval count FLAT across fuel (bracketed monotonic truncation
  counter; truncated values fuel-keyed, saturated results fuel-free). `evalFuel = 100`.
  Frame-id sharing + force-memo. Cache keyed on a bounded-depth structural digest
  (`valueDigest`, `DIGEST_DEPTH=3`; `BEq` untouched → soundness unconditional).
- **Builtins.** `base64.Encode`, `json.Marshal` (`Kue/Json.lean`), `yaml.Marshal`
  (`Kue/Yaml.lean`), `regexp.Match`, `math.Pow`/`math.Sqrt` (full real domain, exact decimal),
  `list.Sort` /`SortStable`, `strings.*` /`list.*`/`math.*` namespaces. Multiline strings.
  ```cue
  import "encoding/json"
  out: json.Marshal({a: 1})  // "{\"a\":1}"
  ```
- **Regex.** RE2-equivalent AST → NFA matcher in `Kue/Regex.lean` (a true leaf), incl.
  `\b`, lazy quantifiers, in-class `\D` /`\W`/`\S` set-complement, `maxRepeat=1000`.
  Corpus divergence-free.
- **Imports / modules.** `cue.mod` discovery, in-module + cross-module (vendored or
  extract-cache) resolution by longest module-path prefix, multi-file merge, transitive
  loads, package-dir entry (`kue export./apps`), qualified import path
  `"location:identifier"` (F-3, `Import.packageName`). IO confined to `Kue/Module.lean`;
  `Eval` /`Resolve` stay pure. (Registry/OCI fetch deferred — prod9 is fully on-disk.)
- **CLI.** `kue eval`, `kue export [--out yaml|json] [file|dir]` (stdin or arg), clean
  missing-file diagnostics + exit codes.

**Real-app status** (prod9 infra, read-only oracle):
- **cert-manager: content-identical drop-in, ~30.6s.** Exports correctly at production
  fuel, byte-identical to `cue` modulo field-order #3 (the item-7 cache-hash digest
  collapsed the ~119s O(N²) wall to ~30.6s).
- **argocd: `packs.#Argo` (link 5) content-correct** (4-link chain). All three components
  content-identical to `cue` (sorted-key, modulo field-order #3) in the scratch module.
  **Full `apps/argocd.cue` STILL bottoms** — the residual is a deterministic CORRECTNESS
  divergence (**Bug2-5**, let-buried two-level embed comprehension-guard narrowing), NOT a
  fuel ceiling. PARKED as a stress-test finding; resolves as the general semantics mature.

## Live Backlog (open work, ranked)

Correctness gates real-app adoption; cleanups are parallel-safe filler. Two backlog
owners: the **spec-conformance fixes** are owned by
[`spec-conformance-audit.md`](spec-conformance-audit.md) § Consolidated fix backlog (the
authoritative ranked list — do NOT duplicate it here); the **plan-only roadmap** below
owns the non-spec-conformance work.

**Spec-conformance backlog — see `spec-conformance-audit.md` § Genuinely-open ranked
backlog (authoritative; do NOT duplicate the detail here).** Everything
spec-conformance-HIGH is DONE (the closedness family incl. SC-1b/1e + EMBED-CLOSE-1, the
MEET-RESID-1/A#6 family, the dyn-field family, D-area, regex, BI-1/BI-2, E#4, F-1/2/3, the
4 ratifications). The BI-2 family is now **COMPLETE**: **BI-2** (math.Pow exact + Sort)
+ **BI-2-residual** (math.Sqrt + Pow(·,½), 2026-06-21) + **BI-2-§3** (general neg-int +
non-½ fractional Pow via `decimalExpScaled`/`decimalLnScaled`, 2026-06-21) — ALL in EXACT
DECIMAL, Float correctly AVOIDED, axiom-clean. `math.Pow`/`math.Sqrt` now cover their full
real domain. The genuinely-open set: **EvalOps** (item 2 — DONE 2026-06-22), **SC-4**
(LOW spec-gap-first). PARKED: **Bug2-5** (argocd residual, a stress-test finding). RESOLVED
/ ruled out (do not re-file — see Resolved/ruled-out below): **AD2-1** (lone-default
normalizer unified, 2026-06-21), **DRY-1**. **SC-3** is now a recorded spec-gap only (the
multi-arm-default display divergence; the lone-default half is gone — collapsed under
AD2-1).

### Plan-only roadmap (not in the spec-conformance backlog)

Sequence after the spec-conformance correctness work: bank cheap-ready cleanups, then the
perf frontier (#7 residual), then the deeper parity gap (#6).

**Numbered durable items (cross-reference IDs):**

1. **`truncate-primitive` (soundness hardening) — CLOSED.** Step 1 DONE (the
   truncation-bump invariant fused into one `EvalState.truncate` choke point across all
   seven drop sites, behavior-preserving); Step 2 (a `withFuel` combinator making the bump
   physically unskippable) RULED OUT — routing the `fuel=0` dispatch through a lambda
   hides the `fuel=n+1` pattern and breaks the mutual block's `termination_by`. Residual
   routing-discipline is documented at the primitive. Detail in the implementation-log.
   (BI-EFF — the effectful-builtin seam, triggered at the 2nd effectful builtin — is in
   Resolved/ruled-out.)

2. **EvalOps extraction → `Kue/EvalOps.lean` — DONE (2026-06-22).** Carved the
   self-contained pure scalar algebra (`ArithOperandClass`/`classifyArithOperand`
   /`arithmeticDomainResult`/`evalRepeat`/`evalAdd…evalDiv`, plus
   `collapseDefaultDisjunction`/`evalEq…evalBinary`/`resolveOperand`/`distributeUnary`
   /`distributeBinary`) out from under the recursive evaluator into `Kue/EvalOps.lean`
   (346 lines). No back-edge into `evalValueWithFuel` (the carve set sits entirely above the
   `mutual` block; verified independent of the `classifyGuard`/`classifyDynLabel` classifier
   block, which STAYS in `Eval.lean`). **Import shape: option (a)** — `EvalOps` imports
   `{Builtin, Decimal, Regex}`. Rejected (b) (moving `div`/`mod`/`quo`/`remValue` into
   EvalOps): those four ALSO back the `div`/`mod`/`quo`/`rem` builtins at `Builtin.lean:892`,
   so relocating them would force a NEW `Builtin → EvalOps` edge — strictly worse than
   `EvalOps → Builtin`. Graph stays acyclic (`EvalOps → {Builtin, Decimal, Regex}`; nothing
   imports EvalOps back). `Eval.lean` 3701 → 3377 (−324); `Eval` now imports `EvalOps`;
   registered in `Kue.lean`. Behavior-preserving: all existing pins + fixtures green,
   pin-count conserved. **Pins ADDED (18, in `EvalTests.lean`):** the comparison ops
   (`lt`/`le`/`gt`/`ge` true cases, incomparable-kind `int`×`string` → bottom, bool-unordered
   → bottom, incomplete-operand defer), `evalEq`/`evalNe`, boolean ops (`&&`/`||`, non-bool →
   bottom), unary (`!` on bool + non-bool → bottom, `-` on int + non-numeric → bottom +
   incomplete defer) — the carve-set ops that previously had only end-to-end fixture coverage.

3. **Test/fixture-org pass (periodic) — module carve DONE `4b25cef`; fixture regroup
   DEFERRED.** `EvalTests.lean` (had re-grown to 1593) was carved into
   `ComprehensionTests.lean` (29 pins — `listcomp_*` /`letcomp_*`/`eval_comprehension_*`
   incl. comprehension-guard shapes) + `SortTests.lean` (13 pins — BI-2 `list.Sort`
   /`SortStable`); EvalTests → 1246. Org-only, zero behavior change, pin-count conserved
   179→137+29+13. **No `GuardTests` ** — the `classify_guard_*` classifier units already
   live in `PresenceTests`; only the comprehension-guard *shapes* were in EvalTests and
   folded into ComprehensionTests. **Remaining sub-item (DEFERRED, optional):**
   sub-grouping `testdata/cue/{definitions (50), comprehensions (27)}` into nested subdirs
   — high-blast-radius because `FixturePorts.lean` (3049) is hand-maintained source whose
   `fileName := "subdir/stem.expected"` strings are the join key (each move = multi-file
   `git mv` + exact string edit, ~77 fixtures). Deferred per "DEFER rather than break
   discovery"; low marginal win (layout already subsystem-grouped one level deep). Pick up
   as a dedicated careful slice or drop.

4. **Field-ordering parity #3 — RATIFIED CLOSED: Kue keeps source order; parity
   DECLINED.** Spec silent (structs unordered, output order implementation-defined), so
   Kue's declaration order is the principled choice, test-pinned
   (`meet_struct_field_order_is_declaration_order`). `cue` 's cross-conjunct order is an
   undocumented internal-graph artifact (often sorts, sometimes interleaves) — chasing
   byte-parity would mean reverse-engineering it, rejected. Full re-derivation in
   `cue-spec-gaps.md` (RATIFIED row). Reopen only if a concrete fixture demands cue's
   exact bytes (none does).
   ```cue
   out: {b: 1} & {a: 2}  // cue: a, b (graph order); Kue: b, a (source order) — both spec-valid
   ```

5. **Per-eval-cost perf (frontier — hash digest DONE; residual open).** The cache-key hash
   digest landed (cert-manager 119s → ~30.6s, byte-identical modulo #3, zero drift;
   FrameKey follow-up profiled as NOT needed). **Residual (the live perf frontier):** the
   heavy `argo` sub-package times out >200s once past the early bottom. Gated on the
   argocd unblock (its bottom is the Bug2-5 CORRECTNESS divergence, not fuel) — profile
   against a resolving target.

6. **Borderline / LOW (opportunistic; none block adoption).** (E#4-fix — arithmetic
   operator domain — landed 2026-06-20; see the implementation-log + `cue-spec-gaps.md`
   row 55.)
   - **`scalar-embed-with-decls`** — `{#a:1, 5}` →`5` (`cue` manifests `5`, keeps `.#a`
     selectable); Kue bottoms. Incompleteness, not unsound. Needs a scalar-with-decls
     carrier (the `.embeddedList` analog for scalars). Do NOT "fix" by widening the scalar
     collapse — that is the unsound direction.
   - **`module-file-scoped-imports`** (arch-sized) — Kue merges every sibling file's
     import bindings into one shared package frame; CUE scopes them per-file. Bites only
     the same-NAME-different-target case; real prod9 doesn't hit it. Bind each file's
     imports into a per-file scope frame.
   - **`import-eager-closedness`** (MEDIUM) — an imported plain closed `.struct` def met
     with extra fields admits them on the EAGER selector path (the force path closes
     correctly). Close imported def bodies at load, or route the eager path through
     `normalizeDefinitionValueWithFuel`. Pin both silent-admit and incomplete-mask facets.
   - **Parser strictness** — `*(1|2)` laxity (`cue` rejects at parse); `__x`
     double-underscore accepted (`cue` reserves `__` -prefixed idents). Track under a
     parser-strictness pass.
   - **DRY `selectEvaluatedField .disj` ** — the resolved-default arm re-lists the 5-arm
     struct-shape dispatch; collapse to `match resolveDisjDefault? alternatives` (gains
     free nested-disjunction recursion).
   - **B3 (`comprehensionPairs` `.embeddedList`)** — `for x in {#a:1,[1,2]}` iterates ZERO
     times where CUE iterates `[1,2]`; add an
     `.embeddedList items _ _ => some (listPairsFrom 0 items)` arm. Incompleteness, not
     unsound; ride-along with `scalar-embed-with-decls`.
   - **B2-A1 (latent, currently lossless)** — `applyEvaluatedStructN` (`Eval.lean:330`)
     routes the patterns-present case through a meet that DROPS `tail`. Lossless today
     (the only tail a parsed struct carries is bare `...` = `.top`, a no-op to
     drop+re-supply); breaks the day typed-ellipsis lands. Thread `tail` through the
     pattern arm + a round-trip pin; pairs with any typed-ellipsis slice.
   - **B2-A2 (test-gap fill)** — both B2.5 fixtures exercise patterns-LEFT × tail-RIGHT;
     the reverse and both-tails+patterns are pinned only by `native_decide`. Add
     `testdata/cue/definitions/{tail_pattern_unify,both_tails_pattern_unify}` pairs +
     `FixturePorts` entries (oracle: `{a:5,...} & {[string]:int}` → `{a:5}` open).
   - **A2-x (latent) — `importBinding` merge-asymmetry.** `mergeFieldClass` returns `none`
     for `importBinding & <real field>` (merges only with itself) where the old `.hidden`
     merged via `.field`. Unobservable today (the only collision `cue` rejects at LOAD —
     see A2-y).
   - **A2-y (pre-existing) — missing import-name redeclaration check.** A top-level field
     colliding with an imported package's local name (`import ".../dep"` + `dep: {…}`) is
     a LOAD error in `cue`; Kue silently keeps both. File as a small loader slice. (Both
     A2-x/A2-y are corners prod9 doesn't hit.)
   - **`scalar-embed` provenance follow-ups** — opportunistic pins (3-level flatten, disj
     ops beyond `+` /`&`, composed select-into-F1-default) when next touching
     Lattice/Eval.
   - **`resolveEmbeddedDisjDefault` (`Eval.lean:2093`)** — verify the pass-1
     label-surfacing path does NOT also need the use-site-narrowing distribution that
     `embed-disj-arm-fallthrough` added, or that label-surfacing-only is correct there.

**Walker / normalizer dedup family — FULLY CLOSED.** Decomposition ruling (durable, do not
re-litigate): the walkers were NEVER one problem — three distinct walker families + a
separate normalizer pair, different mechanisms/result-types/recursion-domains/termination
measures; folding them under one abstraction would be a false "stuff they all do"
extraction. **Status: AD4-1 + A-EN3 DONE; DRY-1 RULED OUT; AD2-1 RESOLVED (2026-06-21,
unified).** No open members. Detail in Resolved/ruled-out (AD2-1 entry) + git.

## Resolved / ruled-out (recorded so they are not re-raised)

The per-round Phase-A/B audit verdicts (~13 rounds, 2026-06-20/21) and the FILED diagnoses
for now-DONE items (MEET-RESID-1, D#1d-RESIDUAL, RESID-MASK-1/2, A#6, the dyn-field
family, …) are HISTORY: the as-built detail is in
[`../reference/implementation-log.md`](../reference/implementation-log.md) and `git log`
(each audit is its own commit). What stays here is only the durable rulings — the ones a
future audit would otherwise re-litigate.

- **Phase-B audit (2026-06-21, batch `3d0124a`/`f3262a1`/`0091aba`) — architecture HEALTHY;
  one trivially-clean DRY win applied inline.** Whole module graph: import edges acyclic
  (`Builtin → Decimal`, `Eval → {Builtin, Decimal, Lattice, Regex, Normalize}`; no
  `Builtin → Eval` back-edge); no dead code (the prior `Order.lean` ruling stands). All three
  in-scope slices fit cleanly: **sqrt** (`isqrtNewton`/`isqrtNat`/`sqrtGuardScale`
  /`decimalSqrt` in `Decimal.lean`, the signed-domain `decimalSqrtSigned`/`mathSqrt?`/`mathPow?`
  in `Builtin.lean`) is in the right home, reuses `divideDecimalRational?` (DRY), adds no bad
  import edge; **SC-1e** `closeTailResult` is correctly a local helper inside `mergeStructN`
  (not leaked to module scope); **AD2-1** keeps the two normalizers' genuinely-distinct
  branches. File sizes all under the ~4500 re-split watch (`Eval` 3702, `CaseTable` 2438,
  `Parse` 1586, `Lattice` 1363, others ≤960; `Decimal` 271 after the sqrt add). Perf-guide:
  no note warranted — `decimalSqrt`'s fixed Newton budget (~few dozen `Nat` steps, once per
  call, no eval-fuel interaction) is trivially cheap. **APPLIED INLINE (low-risk, re-verified
  green):** `normalizeEvaluatedDisj`'s `else` tail was byte-identical to all of `normalizeDisj`
  — collapsed to a direct `normalizeDisj alternatives` call (the AD2-1-adjacent trivially-clean
  shared-helper reuse; `Eval` already imports `Lattice`). `native_decide` pins + fixtures
  unchanged ⇒ behavior-preserving. **Ranking of remaining work (next leader = EvalOps):**
  (1) **BI-2-§3 — DONE (2026-06-21, `cd2f0a9`).** General neg-int + non-½ fractional
  `math.Pow` landed in exact decimal: §1 `x^(-n)=1/x^n` (exact rational, no exp/ln); §2
  `x^y = exp(y·ln x)` via `decimalExpScaled`/`decimalLnScaled` (fixed 40/60-term Taylor +
  binary range reduction at working scale 50, structurally total, axiom-clean). Mantissa
  byte-identical to cue's apd across 40 random + extreme cases; integral results collapse;
  domain edges bottom. The **BI-2 family is now COMPLETE** — `math.Pow`/`math.Sqrt` cover
  their full real domain, no Float. (2) **EvalOps extraction** (item 2) — mechanical,
  parallel-safe, lower-risk, not urgent (`Eval` under threshold). (3) the **item-6
  LOW/opportunistic list** — none block adoption. **Nothing here is user-gated**: the
  once-"user-gated" trio is fully resolved (AD2-1 unified, SC-3 = documented spec-gap
  convention, BI-2 family fully DONE) — the backlog is fully autonomous.
- **Phase-A audit (2026-06-21, batch `3d0124a`/`f3262a1`/`0091aba`) — three soundness claims
  RE-VERIFIED CLEAN; no fix needed.** Adversarial destroy-tests, not byte-compare-to-`cue`.
  (1) **AD2-1 lone-`*v` ≡ `v`** — meeting the OLD residual form `.disj [(.default,v)]` against a
  battery of right operands equals meeting bare `v` in VALUE on every chain tried: `*1&(*2|1)→1`
  (NOT 2), `*1&(*1|2)`, `*1&(*3|1)→1`, order-flip `(*2|1)&*1`, `*1&(1|2)`, `*1&*1→1`, `*1&*2→⊥`
  (both ⊥; only the bottom-REASON payload differs — disj-cross strips it via `containsBottom`,
  orthogonal to the collapse), nested `*(*1|2)` resolving to `*1`, and a lone-`*1` inside a struct
  field unified with `*2|1`. Multi-arm marks STILL preserved (`*1|2 & int == *1|2`) — the
  rename did not weaken the boundary. `normalizeDisj` axiom-clean (`propext` only).
  (2) **`Decimal.sqrt` total + exact + precise** — `isqrtNewton` depends on NO axioms;
  `isqrtNat`/`decimalSqrt`/`mathSqrt?`/`mathPow?` on the 3 standard axioms only (no `sorryAx`,
  no `partial`). Floor-exactness (`r²≤N<(r+1)²`) holds on perfect squares at 10^40/10^60, N²±1 at
  10^20/10^30, ugly non-squares ~10^60, and scaled radicands at scale 80–120; `√2` renders the
  correctly-rounded 34-sig-digit floor; `Sqrt(neg)/Pow(neg,½)→⊥`, `Pow(0,neg)→none`,
  `Pow(0,0)→⊥`; `Sqrt(x)≡Pow(x,½)` for x∈{2,4,0,-2}; tiny scaled `Sqrt(0.0001)=0.01`. Budget
  `2·digits+8` confirmed sufficient. The cue-divergence rows (Sqrt float64-vs-decimal; NaN/Inf→⊥)
  are accurate and frame Kue as more-correct.
  (3) **SC-1e closedness monotone across all 4 tail arms** — every adversarial ordering matches
  the oracle in VALUE: field-closed tail-LEFT rejects forbidden, field-closed×field-closed×tail
  conjunction-rejects all, pattern-closed reversed tail-left admits, closed-embed+tail rejects
  forbidden / admits allowed, mixed field+pattern closed conjunction-rejects, SC-1b closed×closed
  NOT regressed. One benign find: kue's struct-merge field-ORDER (`x2,x1`) differs from cue's
  (`x1,x2`) on the embed+tail-admit case — same value, a merge-order render artifact (already
  ratified, SC-3-area row 44), not a closedness divergence. `StructOpenness.meet` correctly makes
  `defClosed` dominate. Verdict: all three claims SOUND; no code change.
- **AD2-1 (disjunction-normalizer lone-arm rule) — RESOLVED (2026-06-21, UNIFIED).** The
  prior "USER-GATED" framing was over-caution about renaming named pins; the real question
  was autonomous (is the lone-default marker load-bearing?) and is answered NO. Proof: a
  lone default `*v` (direct or residual from a collapsed larger disjunction) has no other
  arm, so the mark is VACUOUS — value-identical to bare `v` in EVERY onward meet. Mechanism:
  `combineMark` is AND and `withDefaultConvention` only synthesizes a default for an
  all-regular operand, so a vacuous lone default never beats a real default nor manufactures
  one (the sharpest witness: `*1` (lone, vacuous) `& (*2|1)` → `1`, NOT `2` — identical to
  bare `1 & (*2|1)`). Adversarially cross-checked vs `cue` v0.16.1 (default-containing /
  default-absent / marked / conflict-marked / nested onward meets — all `export`
  byte-identical; cue's *display* also collapses the lone `*v` → `v`, so the fix moves Kue
  TOWARD cue). FIX: `normalizeDisj`'s lone-arm collapse is now mark-agnostic
  (`[(_, v)] => v`), matching `normalizeEvaluatedDisj`'s lone-arm rule — the two normalizers
  now agree on every lone-arm case (the eval path keeps its `joinValues` all-regular branch,
  a genuinely distinct subsumption op, so it is NOT folded wholesale — only the divergent
  lone-arm rule is unified). Named pins RENAMED to assert the corrected behavior
  (`meet_disjunction_collapses_vacuous_lone_default`,
  `lattice_meet_disjunction_collapses_vacuous_lone_default`) + adversarial non-load-bearing
  witnesses added (`lattice_lone_default_vacuous_*`, `lattice_multi_arm_default_marker_preserved`).
  `TwoPassTests.embed_disj_live_default_kept` expected display updated (lone-default residual
  `*{…}` → `{…}`, matching cue). SC-3 / `cue-spec-gaps.md` scope narrowed: the "keep marked"
  display contract now applies ONLY to MULTI-arm defaults (where the mark IS load-bearing —
  it selects among live arms a later meet can pick). No fixture display changed (none
  currently render a lone-default residual). Fixtures byte-identical; cert hot-path
  unchanged.
- **DRY-1 (let-walker dedup) — RULED OUT (attempted under A-EN3, reverted; no behavior
  shipped).** The three let-walkers (`closeDefFrameReadIndices` `List Nat` worklist,
  `letPromotedReadLabels` catamorphism, `injectLetLocalNarrowings` endo-rewrite) genuinely
  do NOT share a combinator — different carriers/visited-sets/follow-mechanisms,
  collect-vs-rewrite, and routing the nested-let recursion through a callback breaks
  Lean's structural-recursion inference (the lambda-hides-`fuel+1` trap). Contrast AD4-1's
  success: its variation point (`onExhausted`) was a PURE non-recursive leaf the
  combinator could own; DRY-1's variation point IS the recursion. **Do not re-file**
  unless a future catamorphic 4th walker over the same carrier lands.
- **BI-EFF (effectful-builtin seam) — TRIGGERED at the 2nd effectful builtin; full
  registry REJECTED.** `list.Sort` /`SortStable` are the only effectful builtins
  (comparator needs `EvalM`), one shared inline `runSort` case in `Eval` 's `.builtinCall`
  arm — the right layer, below the abstraction threshold for one case. Trigger: when the
  SECOND effectful builtin lands (`list.IsSorted` or a `matchN` /`matchIf` validator),
  extract a named `evalEffectfulBuiltin?` seam AS THAT SLICE'S FIRST STEP. A
  name→`EvalM`-closure registry is rejected (less traceable than an exhaustive `match`;
  population ~3-4). A forward-pointing comment is at the site.
- **F-CASE-ARCH (committed generated table + oracle-as-data-source) — RULED; both halves
  discharged.** (a) the 49KB generated `Kue/CaseTable.lean` STAYS committed (reproducible,
  reviewable, offline build, no build-time `cue` dep; `DO NOT EDIT` header + generator
  provenance present). (b) the oracle-as-data-source convention is an ADR
  ([`../decisions/2026-06-20-oracle-as-data-source.md`](../decisions/2026-06-20-oracle-as-data-source.md)):
  oracle = sound DATA SOURCE for an externally-standardized `cue` -faithful domain (verify
  vs the EXTERNAL standard, record provenance), NEVER a correctness GATE for CUE
  semantics.
- **FOUR-parallel-classifiers DRY
  (`classifyArithOperand`/`classifyGuard`/`classifyDefinedness`/ `classifyDynLabel`) —
  RE-RULED at four: keep the four verdict functions SEPARATE; extract only the shared
  default-collapse PRE-STEP (`collapseDefaultDisjunction`, DONE inline); a shared
  concreteness partition is REJECTED.** They disagree on the partition
  (`.prim`/`.struct`/`.disj`/`.structComp` land differently per classifier), so a shared
  helper would special-case exactly the disagreeing ctors, leaving only the inert abstract
  tail = "the stuff they all do" = not a name. Sharing would raise coupling + lower the
  new-ctor-forces-a-decision guarantee. Do not re-raise at five.
- **AD3-1 / Regex extraction / B5 regex bullet — DROPPED (stale).** `Kue/Regex.lean`
  already exists as a verified TRUE LEAF (no top-level `import`); the RX-1a/b NFA rebuild
  superseded the "extract the backtracking engine" framing. Nothing to do.
- **AD3-4 (bottom-payload newtype) — RULED OUT (over-engineering).** `GuardVerdict.bottom`
  / `ClauseExpansion.bottom` / `ListClauseExpansion.bottom` carry an unconstrained `Value`
  where only a bottom is valid, but the invariant is already enforced BY CONSTRUCTION
  (every construction site can physically only pass a bottom). A `BottomValue` newtype
  would ripple through every `.bottom` match site for safety already bought.
- **`Order.lean` (subsumption) — DELIBERATE test-only oracle**, imported only by `Tests/*`,
  NOT dead code and NOT duplicated (`meet`/join and `subsumes` /partial-order are
  orthogonal). Recorded so a future audit does not re-flag it as an orphan.

## Pointers (history + reference for anything dropped)

- **Completed-slice history + verification record:**
  [`../reference/implementation-log.md`](../reference/implementation-log.md)
  (chronological, one entry per commit) and `git log`. Every audit batch and design spike
  is recorded there — this plan holds only the live roadmap.
- **Spec-conformance fix backlog (authoritative):**
  [`spec-conformance-audit.md`](spec-conformance-audit.md) § Consolidated fix backlog.
- **CUE-divergence record:**
  [`../reference/cue-divergences.md`](../reference/cue-divergences.md).
- **CUE spec-gap record:**
  [`../reference/cue-spec-gaps.md`](../reference/cue-spec-gaps.md).
- **Decisions:** [`../decisions/`](../decisions/) (compatibility target,
  correctness-over-perf, Value-model fork resolution).
- **Slice loop + audit cadence:** [`../guides/slice-loop.md`](../guides/slice-loop.md).
- **Performance guide:** [`../guides/kue-performance.md`](../guides/kue-performance.md).
- **Status page (human-facing, served):** [`../../www/index.html`](../../www/index.html) —
  single human-scannable status page, OUTSIDE the agent design-record; refreshed on
  plan-hygiene passes.
- **CUE semantics reference:** [`../reference/cue-language-guide.md`](../reference/cue-language-guide.md);
  [`architecture.md`](architecture.md) + [`compat-assumptions.md`](compat-assumptions.md).
- **Latest session state / next step:** the most recent breadcrumb in
  [`../notes/`](../notes/).
