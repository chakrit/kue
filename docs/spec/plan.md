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
  narrowing is parked as a stress-test finding (argocd/Bug2-7), not promoted to the
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
  Dispatch is via a closed `BuiltinFamily` enum (`core` + the 7 qualified packages) classified
  by `BuiltinFamily.ofName?` and matched EXHAUSTIVELY — a non-builtin name bottoms on concrete
  args (no silent residual); a new family forces a dispatch arm (TL-1).
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
  **Full `apps/argocd.cue` STILL bottoms (~55s)** — the residual is a deterministic
  CORRECTNESS divergence. **Bug2-5** (transitive-embed disj-path narrowing injection) FIXED
  (`5fca57e`, 2026-06-22) — NOT the final blocker. **Bug2-6** (definition multi-declaration
  close-once) FIXED (`ef824cb`, 2026-06-23) — also NOT the final blocker. **Bug2-7** (same-def
  multi-decl close-once on the def-REFERENCE / force-fold path) FIXED (`3361699`, 2026-06-23 —
  per-operand `canonicalizeFields`) — also NOT the final blocker. **Bug2-8** (same-def multi-decl
  close-once ACROSS AN EMBED boundary) FIXED (`2332aff`, 2026-06-23 — a `DeclProvenance`
  sum on a named `ConjOperand`; a plain embed's same-def-path decls fold into the static frame as
  an `embeddedDecl` operand, close-once-UNIONing via `mergeConjOperandFields`/`mergeDefinitionDecls`,
  and the meet-fold strips the embed's matching decl; the cert-manager REGULAR closed pattern stays
  a MEET) — also NOT the final blocker. **Bug2-9** (use-site narrowing of a REFERENCED NAMED
  multi-conjunct def, `ls = defaults.#ListenerSet & {#name,…}` where `defaults.#ListenerSet =
  defs.#ListenerSet & parts.#UseCertManager & {…}`) FIXED (`5d9cf8f`, 2026-06-23 —
  `flattenConjDefRef` flattens a depth-0 ref-to-`.conj`-bodied def into its constituents before the
  `.conj` fold, making the named ref byte-identical to the inlined meet) — also NOT the final
  blocker. **Bug2-10** (use-site narrowing into a `.structComp` HOST's embedded self-ref) FIXED
  (`aa4172b`, 2026-06-23 — `conjStructCompDefer?` defers a structComp host with a sibling-self-ref
  embed into the shared-`useOperands` fold; PLUS a pre-existing embed-meet closedness leak fixed via
  `embeddingClosesHost`) — also NOT the final blocker. **The actual on-path argocd blocker is now
  Bug2-11** (use-site narrowing of a TWO-LEVEL cross-package def-of-def selector whose terminal def
  embeds a sibling self-ref). Landing Bug2-10 advanced argocd from `incomplete value: string` to
  `conflicting values`; probing the real `defaults.#ListenerSet & {#name, #passthrough_hosts}` (a
  cross-pkg def whose body refs the cross-pkg `defs.#ListenerSet`, which embeds `parts.#Metadata`)
  shows `metadata: {name: string}` (un-narrowed) + `#passthrough_hosts: _|_` — the cross-package
  selector forces STANDALONE with no use-operands. Self-contained 3-package repro confirms (see
  `spec-conformance-audit.md` Bug2-11 + ARGOCD-DEPTH REFRAME CORRECTED). **This CORRECTS the prior
  "argocd is same-frame, Bug2-11 off-path" claim, which was empirically WRONG.** Full `apps/argocd.cue`
  STILL bottoms (~54s, `conflicting values`); argocd localized to `listener.yaml`. NOT a stress-test
  parking — Bug2-11 is the spec-correctness leader.

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
(LOW spec-gap-first). **ON-PATH ARGOCD LEADER: Bug2-11** (use-site narrowing of a TWO-LEVEL
cross-package def-of-def selector whose terminal def embeds a sibling self-ref — `defaults.#ListenerSet
& {#name, #passthrough_hosts}` → kue `metadata.name: string` un-narrowed + `#passthrough_hosts: _|_`,
cue narrows; the cross-package selector forces standalone with no use-operands. Same fix family as
Bug2-10, distinct frame — needs the terminal package frame capture). RESOLVED / ruled out (do not
re-file — see Resolved/ruled-out below): **Bug2-10** (use-site narrowing into a `.structComp` host's
embedded self-ref, `aa4172b` 2026-06-23 — `conjStructCompDefer?` + an embed-meet closedness-leak fix
via `embeddingClosesHost`; was NOT the final argocd blocker; CORRECTED the prior "argocd is Bug2-10
alone" claim — the blocker is Bug2-11), **Bug2-9** (use-site narrowing of a REFERENCED NAMED
multi-conjunct def, `5d9cf8f` 2026-06-23 — `flattenConjDefRef`; was NOT the final argocd blocker;
surfaced Bug2-10), **Bug2-8** (same-def multi-decl close-once ACROSS AN
EMBED boundary, `2332aff` 2026-06-23 — `DeclProvenance`/`ConjOperand`; was NOT the final argocd
blocker; surfaced Bug2-9), **Bug2-7** (def multi-decl close-once on the reference / force-fold
path, `3361699` 2026-06-23 — surfaced Bug2-8), **Bug2-6** (definition
multi-declaration close-once, `ef824cb` 2026-06-23 — surfaced Bug2-7), **Bug2-5**
(transitive-embed disj-path narrowing injection, `5fca57e` 2026-06-22 — was NOT the final
argocd blocker), **AD2-1** (lone-default normalizer unified, 2026-06-21), **DRY-1**. **SC-3**
is now a recorded spec-gap only (the multi-arm-default display divergence; the lone-default
half is gone — collapsed under AD2-1).

**🚨 TOP-RANKED SOUNDNESS FIX-SLICE — CARRIER-STRUCT-MEET — DONE (2026-06-22).** A scalar/list
embedding carrier (`.embeddedScalar`/`.embeddedList` — the carrier IS its scalar/list) met with a
PURE decls-only struct that had NO embed of its own WRONGLY MERGED the decls instead of
conflicting. cue (spec-conformant here) rejects: `{#a:1,5} & {#b:2}` is `5 & {#b:2}` =
int-vs-struct bottom (spec: unifying different types is `_|_`); Kue admitted `{#a:1,#b:2,5}` —
MORE PERMISSIVE than the spec, a genuine soundness gap. **FIXED at 4 sites in `Lattice.lean`** (the
`.struct fields _ none [] _` sub-case in each carrier's `none`-branch: `.embeddedList` left/right +
`.embeddedScalar` left/right): a mechanical DELETION — dropped the `else <merge decls>` and routed
the sub-case to `meetCore` (`_, .struct .. => .bottom`), applied UNIFORMLY to both carriers, by hand
(per the Phase-B no-shared-meet-seam ruling). **Boundary held (oracle-confirmed v0.16.1, all green):**
carrier & carrier MERGES (untouched — routes via the `scalarCarrierPartner?`/`asListPair` partner
branch); carrier & output-field-struct BOTTOMS (untouched — `structHasOutputField`); carrier &
decls-only-struct-without-embed now BOTTOMS (the fix). The source-level path (`{#a:1,5} & {#b:2}`)
flows through `evalConjStandard`'s deferral fold → `meet` of the built carrier against the plain
struct, hitting the fixed arm — NOT `lazyConjMergedFields` (a `{…,5}` is a `.structComp`, not a
`conjStructOperand?`-eligible plain struct). Pins FLIPPED:
`ListTests.meet_scalar_carrier_with_decls_struct` → `…_bottoms` (+ symmetric + `.embeddedList`
analogs); `EvalTests.WITNESS_scalar_carrier_meet_{plain_decls_struct,lone_hidden_struct}_wrongly_
merges` → positive `meet_*_with_declsonly_struct_bottoms` (+ symmetric, multi-decl, list analogs,
carrier&carrier-merge + carrier&output-field-bottom source-level pins). `cue-spec-gaps.md` row 58
updated to CONFORMING. Zero fixture drift (no `testdata` asserted the old merge). Next leader
(after CARRIER-DECL-SELECT, now DONE — below): the **item-6 LOW list**.

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

3. **Test/fixture-org pass (periodic) — `TwoPassTests` SPLIT SCHEDULED (ranked next-after-Bug2-10);
   module carve DONE `4b25cef`; fixture regroup DEFERRED.**
   **🚨 `TwoPassTests.lean` SPLIT — SCHEDULED as a near-term slice (Phase-B 2026-06-23 ruling).**
   At 1879 lines it is the demonstrated silent-failure surface (the Phase-A dead-theorem incident:
   ~140 theorems silently dead under unterminated `/-- -/`). The file IS too large to eyeball. Seam =
   **by bug-family**: carve the `bug2x_*` sections (Bug2-1/2-2/2-4/2-5/2-6/2-7/2-8/2-9 + the
   let-local/Mixin narrowing family — the ~bug26_*/bug27_*/bug28_*/bug29_*/mixin_*/let_* pins, lines
   ~734–1879) into `Bug2xTests.lean`, leaving the foundational two-pass/argocd-link/disjunction-
   selection/RESID-MASK pins in `TwoPassTests.lean`. Each resulting file gets the same end-of-file
   COVERAGE TRIPWIRE (per-section `#check @<last-theorem>` anchors; see the `0150095` hardening). The
   SPLIT-SLICE's first step: convert the carved file's headers to `--` line comments (TwoPassTests
   already converted, `0150095`). Pin-count conserved; org-only, zero behavior change. **TEST-HEALTH
   CONVENTION (durable, applies to ALL new/touched `Kue/Tests/*.lean`):** section headers are `--`
   LINE comments, never `/-- -/`/`/-! -/` block comments (a line comment cannot swallow the next
   theorem); every test module carries an end-of-file `#check @<last-theorem-per-section>` tripwire.
   Recorded in `docs/reference/failure-modes.md`; flagged for `ace-school` (a `general-coding`/test
   convention) — NOT edited into a skill from here. The suite-wide block→line conversion of the OTHER
   ~19 test files (≈440 comments) is LOW-priority defense-in-depth (the build already proves none are
   currently swallowed, and the tripwire is the real guard) — fold it into this org slice opportunistically,
   do not churn 440 sites as a standalone.
   `EvalTests.lean` (had re-grown to 1593) was carved into
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

5. **Per-eval-cost perf (frontier — hash digest DONE; residual open, STILL GATED).** The
   cache-key hash digest landed (cert-manager 119s → ~30.6s, byte-identical modulo #3, zero
   drift; FrameKey follow-up profiled as NOT needed). **Residual (the live perf frontier):**
   the heavy `argo` sub-package times out >200s once past the early bottom. STILL gated on the
   argocd unblock — Bug2-5..Bug2-10 are fixed but argocd STILL bottoms on **Bug2-11** (use-site
   narrowing of a two-level cross-package def-of-def selector — `defaults.#ListenerSet & {#name,
   #passthrough_hosts}` leaves `metadata.name: string` un-narrowed + `#passthrough_hosts: _|_`),
   a CORRECTNESS divergence, not fuel. (Bug2-10's landing CORRECTED the prior "un-gates once
   Bug2-10 lands" claim — it advanced argocd `incomplete`→`conflict` but did NOT export it.)
   Un-gates once Bug2-11 lands and argocd actually exports; profile against a resolving target then.

6. **Borderline / LOW (opportunistic; none block adoption).** (E#4-fix — arithmetic
   operator domain — landed 2026-06-20; see the implementation-log + `cue-spec-gaps.md`
   row 55.)
   - ~~**`scalar-embed-with-decls`**~~ — **DONE 2026-06-22.** `{#a:1, 5}` → `5` keeping
     `.#a` selectable, via a dedicated **`.embeddedScalar (scalar) (decls)`** carrier in
     `Value.lean` — the direct scalar analog of `.embeddedList`. Built at embed-eval
     (`meetEmbeddingsWithFuel`, the producer) when the host has no output field, HAS decls,
     and the embedding is a terminal scalar (`isTerminalScalar`); manifests as the scalar,
     decls stay selectable (`selectEvaluatedField`/`Runtime.lookupField?`), conflict
     surfaces inline (RESID-MASK → `containsBottom` → export rejects). **The pure-collapse
     path was left UNTOUCHED** (the soundness boundary): `collapsesToScalarEmbed` (no decls)
     still drops `{5}`→`5`; widening it to admit decls would DROP them — the unsound
     direction, avoided. New ctor handled at EVERY match site with NO catch-all swallow
     (Lattice meet + `containsBottom`; Eval select/definedness/guard/dynlabel/digest/tag/
     walkers; EvalOps arith-operand + `resolveOperand` unwrap; Format/Manifest/Normalize×2/
     Runtime). 1 cue-divergence (non-iterable `for` zero-iter, pre-existing) + 1 spec-gap
     (carrier semantics) recorded.
   - **`module-file-scoped-imports`** (arch-sized) — Kue merges every sibling file's
     import bindings into one shared package frame; CUE scopes them per-file. Bites only
     the same-NAME-different-target case; real prod9 doesn't hit it. Bind each file's
     imports into a per-file scope frame.
   - ~~**TL-1 (type-leverage, MEDIUM) — builtin-family dispatch is stringly-typed**~~ —
     **DONE 2026-06-22.** Closed `BuiltinFamily` enum (`core` + the 7 qualified packages
     `strings`/`list`/`math`/`regexp`/`base64`/`json`/`yaml`) in `Builtin.lean` (the only
     consumer — no new import edge); the LEAF stays `String`. A single total classifier
     `BuiltinFamily.ofName?` interprets the name at the one point it is read as a builtin
     (the parser cannot — it can't tell `strings.X` from a user `pkg.X`), and
     `evalBuiltinCall` matches it EXHAUSTIVELY (no catch-all → a new family forces a
     dispatch arm). The previously-silent fall-through (`foobar.Baz`/`nosuchfn`/`error(…)`
     with CONCRETE args produced an inert `.builtinCall` residual = `incomplete value`,
     masking a resolution error) now routes through `unresolvedOrBottom`: concrete ⇒
     BOTTOM (conforms to `cue`'s `reference … not found` / `cannot call non-function`),
     abstract ⇒ deferred residual (preserved). The 8 `core` exact-name arms moved to
     `evalCoreBuiltin`.
     Behavior-preserving for known builtins (the `BuiltinTests` net stays byte-identical
     green; +13 pins incl. the corrected unknown-name cases + a yaml family pin). 1
     cue-divergence (generic vs name-specific bottom message) + 1 spec-gap (unimplemented
     builtin diagnostic) recorded. See implementation-log.
   - ~~**TL-2 (type-leverage, LOW-MED) — `BindingId` packs two swappable bare `Nat`s.**~~
     — **DONE 2026-06-22.** `BindingId { depth : Depth, index : FieldIndex }` — two
     single-field `structure` newtypes (zero-cost over `Nat`) in `Value.lean`, with
     `OfNat` instances so the ~300 `.refId ⟨d, i⟩` test literals stay byte-identical (Lean
     does NOT auto-flatten numerals into nested single-field structures — `OfNat` is
     load-bearing). The two axes are now DISTINCT nominal types (a `Depth` cannot be
     passed where a `FieldIndex` is wanted — the transposition class is unrepresentable,
     compile-checked). Consumers unwrap with `.val` at the frame/slot-arithmetic boundary
     (`env.drop id.depth.val`, `nthField id.index.val`); no `Coe` (implicit widening would
     reopen the swap); `Hashable` not derived (the one digest site hashes through `.val`).
     ~57 mechanical ripple sites: 1 construction (`findInScopes`), ~50 in `Eval.lean`, the
     `Format` render, 4 test fixups. Behavior-preserving: 110-job build clean, full
     suite + fixtures byte-identical green, pin-count conserved; +5 `native_decide` pins
     (`ResolveTests`) locking the surviving runtime contract (the swap-guard itself is
     compile-time). See implementation-log.
   - ~~**`import-eager-closedness`** (MEDIUM)~~ — **DONE 2026-06-22.** Resolved via option
     (b), structurally unified: a new single `selectedFieldValue` closes a SELECTED definition
     field's body (`normalizeDefinitionValueWithFuel`), shared by all four eager pluck sites, so
     the eager and force paths share ONE closing decision and cannot disagree. Option (a)
     (close at load) rejected — the A2 trap (closing a whole bound package re-closes unreferenced
     nested defs). Both facets pinned (silent-admit + incomplete-mask) + over-close guard + pattern
     edges; 1 cue-divergence (incomplete-mask error message). See implementation-log + audit doc.
   - **Parser strictness** — `*(1|2)` laxity (`cue` rejects at parse); `__x`
     double-underscore accepted (`cue` reserves `__` -prefixed idents). Track under a
     parser-strictness pass.
   - **`release-linux.sh` no dirty-tree guard (LOW, Phase-B 2026-06-23).** `release.sh`
     requires a clean working tree before building (`git status --porcelain`);
     `release-linux.sh` does not (it builds from `COPY . /src`, `.dockerignore` excludes
     `.git`). A dirty tree could ship a Linux asset built from uncommitted changes that diverges
     from the committed macOS asset on the SAME release. Add the same clean-tree precondition.
     (Whether `release.sh` should auto-chain `release-linux.sh` — currently a deliberate two-step
     split, Linux backfilled per-release — is a UX call left to the user, not filed.)
   - **DRY `selectEvaluatedField .disj` ** — the resolved-default arm re-lists the
     struct-shape dispatch; collapse to `match resolveDisjDefault? alternatives` (gains
     free nested-disjunction recursion). PARTIALLY addressed by CARRIER-DECL-SELECT (the
     three carrier arms inside the sub-case now share `selectFromDecls`); the remaining win
     is folding the disj match itself into a recursive `selectEvaluatedField` call on the
     resolved default — still open, LOW.
   - ~~**B3 (`comprehensionPairs` `.embeddedList`)**~~ — **DONE 2026-06-22** (rode along
     with `scalar-embed-with-decls`). Added the
     `.embeddedList items _ _ => some (listPairsFrom 0 items)` arm, so `for x in
     {#a:1,[1,2]}` now iterates `[1,2]` (was zero). A scalar carrier (`{#a:1,5}`) is
     non-iterable → zero-iter via the `_ => none` catch-all (Kue's standing non-iterable
     handling; cue type-errors — a tracked divergence).
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
unified); embedChainAny SHARED (2026-06-23, `0619097`).** No open members. The embed-chain
share (`bodyNeedsDefer` + `embedBodyEmbedsDisjDeep` → one `embedChainAny (leaf)` combinator)
is the AD4-1-safe case — pure non-recursive leaf, recursion owned by the combinator — NOT a
re-litigation of DRY-1 (whose variation point WAS the recursion). Detail in Resolved/ruled-out
(`embedChainAny` entry) + git.

**CARRIER-DECL-SELECT (DRY, LOW) — DONE 2026-06-22.** Extracted `selectFromDecls (base) (label)
(decls) : Value` (`findEvalField` → `selectedFieldValue` / deferred `.selector base label`) and
routed all SIX byte-identical Eval sites through it: top-level `.struct`/`.embeddedList`/
`.embeddedScalar` + the three `resolveDisjDefault?` sub-case arms. **Home = `Eval.lean`, no new
edge** — `Runtime` already imports `Eval`, so `Eval` is the lowest module both reach (graph
unchanged). **`Runtime.lookupField?` is a DIFFERENT operation, NOT shared across the seam** — it
yields the RAW `Field.value` (no close) and returns `Option` (genuine-absence `none` for the `-e`
"field not found" diagnostic, never a deferred `.selector`); routing it through `selectFromDecls`
would silently change behavior + DRY across a module boundary. Only the WITHIN-Runtime triplication
collapsed (a 1-line local `fieldValue?`). +2 `native_decide` pins
(`TwoPassTests.select_into_default_disjunction_{scalar,list}_carrier` — the thin disj-resolved
carrier-select path). Behavior-preserving: 110-job build clean, fixtures zero-drift, pin-count
conserved +2. NO cue-divergence, NO spec-gap. Detail in the implementation-log. **Distinct from
FOUR-classifiers** (those DISAGREE on the partition; here the three shapes AGREE exactly — real
dedup, not false-sharing). Next leader: the **item-6 LOW list** (`module-file-scoped-imports`,
parser strictness `*(1|2)`/`__x`, A2-x/y, B2-A1/A2, `resolveEmbeddedDisjDefault` check — all LOW,
none soundness-bearing).

## Resolved / ruled-out (recorded so they are not re-raised)

- **Phase-B audit (2026-06-23, batch `9b78c3d`..`2e337b1`: Bug2-8 + Bug2-9; Phase A HEALTHY
  `2e337b1` + the dead-tests recovery `0109bb4`) — architecture HEALTHY.** Module graph
  re-checked WHOLE: ACYCLIC, strictly layered (`Builtin → {Lattice, Regex, Decimal, Base64,
  Json, Yaml, CaseTable}` — NO `Eval`/`EvalOps` edge; `EvalOps → {Builtin, Decimal, Regex}` no
  back-edge; `Eval → {Builtin, Decimal, EvalOps, Lattice, Regex, Normalize}`; `Lattice →
  {Value, Regex}`; `Runtime → Eval`; `Module → {Parse, Runtime}`; `Cli → Runtime`). The Bug2-8
  types (`DeclProvenance` 2-ctor sum + `ConjOperand` record) live in **`Value.lean`** (L1,
  correct — they ARE struct-conjunction data, not eval logic) and are EXEMPLARY type-leverage:
  `DeclProvenance` admits no nonsense "own-and-embedded" (a `Bool` would) and FORCES a match arm
  on a new origin (no wildcard); `ConjOperand` carries provenance in the TYPE, not inferred from
  operand position — the union-vs-meet boundary (`incomingProv != existingProv` in
  `mergeConjOperandFields`) is type-driven, not positional. The Bug2-9 `flattenConjDefRef` sits
  in the pre-`mutual` helper tier near `conjStructOperand?` (`Eval.lean:1575`) — RIGHT home (a
  pure unevaluated-constraint transform, fuel-structural total, ONE call site at the `.conj`
  fold's raw-constraint flatMap, NO catch-all swallow — every non-flattenable case returns
  `[constraint]` identity). Cleanliness sweep CLEAN: NO `sorry`/`panic!`/`unreachable!`
  /`.get!`-in-pure-code, NO `String.dropRight`/`dropLeft`, NO dead code, NO stale TODO/FIXME/HACK;
  the `partial def`s are the standing carve-outs only (`Parse.lean` 62 lexer/parser, `Module.lean`
  4 IO-loader; `Eval.lean`/`Lattice.lean` FULLY total). File sizes: `Eval.lean` **3780** (+222
  over the prior Phase-B 3558 — Bug2-8/2-9 growth), still WELL under the ~4500 re-split watch — the
  `Eval.DefDeferral`-first-carve ruling STANDS. **Type-leverage next-candidate: NONE high-value** —
  `FieldClass.field (isDefinition, isHidden, optionality)`'s two `Bool`s are DELIBERATELY orthogonal
  CUE axes (every combination legal, per-axis merge; a sum would be the 2×2×3 cube = worse); the
  representation is mature post-TL-1/TL-2. **Test/fixture redundancy: NONE to prune** — the
  `.cue/.expected` fixtures (full parse→eval→export) and the `native_decide` pins (internal eval
  primitives) pin DIFFERENT layers; the dead-theorem incident itself proves both are load-bearing
  (fixtures kept behavior correct while the pin layer was dead). **APPLIED INLINE (re-verified green,
  cert-canary jq-S=0):** (1) **test-health hardening** (`0150095`) — TwoPassTests block→line comments
  + coverage tripwire (the dead-theorem fallout, headline #1); (2) **perf-doc de-stale** —
  `kue-performance.md` argocd-bottoms said "blocker is now **Bug2-8**" (STALE — Bug2-8 `2332aff` +
  Bug2-9 `5d9cf8f` LANDED); corrected the chain to Bug2-8/2-9 LANDED + gating to **Bug2-10**, wall
  ~58s→~53s. **Bug2-10 DESIGN NOTE + Bug2-10/2-11/2-12 SHARED-ROOT ANALYSIS** written into
  `spec-conformance-audit.md` (root = conjunct-deferral gate, `conjDefClosure?` is `.refId`-only;
  fix = defer a structComp host's embeds into the shared-use-operand fold; 2-10↔2-11 PARTIAL shared
  root, 2-12 orthogonal closedness-leak; argocd chain is ONE deep fix Bug2-10, not three). **Filed:**
  `TwoPassTests` SPLIT scheduled (item 3, by bug-family) + the durable test-health convention
  (failure-modes.md row). **Verdict: HEALTHY; test-health hardened inline (`0150095`); one perf-doc
  de-stale; Bug2-10 design note + shared-root analysis in place; SPLIT scheduled; no new code
  fix-slice.**

The per-round Phase-A/B audit verdicts (~13 rounds, 2026-06-20/21) and the FILED diagnoses
for now-DONE items (MEET-RESID-1, D#1d-RESIDUAL, RESID-MASK-1/2, A#6, the dyn-field
family, …) are HISTORY: the as-built detail is in
[`../reference/implementation-log.md`](../reference/implementation-log.md) and `git log`
(each audit is its own commit). What stays here is only the durable rulings — the ones a
future audit would otherwise re-litigate.

- **Phase-B audit (2026-06-23, batch `d949666`..`10e8837`: Bug2-6 + Bug2-7 close-once;
  Phase A HEALTHY `10e8837`) — architecture HEALTHY.** Module graph re-checked whole:
  ACYCLIC, strictly layered (`EvalOps → {Builtin, Decimal, Regex}` no back-edge; `Builtin`
  carries NO `Eval`/`EvalOps` edge; `Eval → {Builtin, Decimal, EvalOps, Lattice, Regex,
  Normalize}`; `Lattice → {Value, Regex}`; `Runtime → Eval`; `Module → {Parse, Runtime}`).
  The Bug2-6/2-7 changes (`mergeDefinitionDecls`, `unionDefOpenness`,
  `canonicalizeFields`/`mergeUnevaluatedFieldInto`, per-operand canonicalize in
  `mergeConjOperands`) sit correctly in `Eval`'s unevaluated-merge tier — they need
  `mergeFieldClass`/`isDefinition` (the eval layer's field-class machinery), so they belong
  in `Eval`, not `Lattice` (`Lattice` owns the EVALUATED `meet` merge; the UNEVALUATED
  `.conj`/close-once merge is an eval concern). Cleanliness sweep CLEAN: NO
  `sorry`/`panic!`/`unreachable!`/`.get!`-in-total-code, NO `String.dropRight`/`dropLeft`,
  NO dead code, NO stale TODO/FIXME/HACK; the 10 `Parse.lean` `partial def`s are the
  standing IO/lexer carve-out, pure core total. File sizes: `Eval.lean` 3558 (+93 over the
  prior Phase-B's 3465 — Bug2-6/2-7 growth), still WELL under the ~4500 re-split watch — the
  `Eval.DefDeferral`-first-carve ruling STANDS (below). `TwoPassTests.lean` 1713 (+217 over
  the prior 1496; 56 Bug2-x pin refs) — the file to watch; the test-org pass is
  APPROACHING-due, not yet due (filed as a tracked note, not scheduled — Bug2-8 is next
  leader). **APPLIED INLINE (re-verified green, cert-canary jq-S=0):** `kue-performance.md`
  argocd-bottoms entry de-staled — said "the residual full-app blocker is now **Bug2-6**"
  (STALE: Bug2-6 `ef824cb` + Bug2-7 `3361699` both LANDED); corrected the narrowing-fix
  chain to include Bug2-6/2-7 + gating to **Bug2-8**, wall `153s → ~58s`. **Bug2-8 design
  note** written into `spec-conformance-audit.md` (def-path provenance carrier
  `DeclProvenance` through the embed force-fold). **Verdict: HEALTHY; `mergeFieldsWith`
  RULED-OUT (below); one inline perf-doc de-stale; Bug2-8 design note in place; no new
  fix-slice.**
- **`mergeFieldsWith` consolidation (`mergeFieldListWith` / `canonicalizeFields` /
  `mergeConjFields` skeleton-share) — RULED OUT: keep SEPARATE. The skeleton-share is real
  but the seam where it matters (`mergeFieldListWith` ↔ `mergeConjFields`) is ALREADY shared
  via `mergeFieldIntoWith`; `canonicalizeFields` cannot join under a `Value→Value→Value`
  combiner AND must not, on soundness-boundary grounds (Phase-B 2026-06-23, the headline
  adjudication).** Decomposed:
  - **Two of the three already share their match-helper.** `mergeFieldListWith meetValue`
    (Lattice:689) and `mergeConjFields` (Eval:631) both `foldl` over the SAME per-label
    helper `mergeFieldIntoWith` (Lattice:666), differing only in the `meetValue` arg
    (`meet` vs `joinUnevaluated`) and the seed (`[]` vs `accumulated`). The Phase-A-proposed
    "parameterize the skeleton" is, for this pair, already DONE — `mergeFieldIntoWith` IS
    the parameterized skeleton. `mergeConjFields` is a 5-line `foldl` wrapper that picks the
    seed + fixes the combiner; collapsing it into a direct `mergeFieldListWith
    joinUnevaluated` call buys nothing (the seed differs, and the named wrapper carries the
    load-bearing conj-of-EMBEDS doc-comment) and is not worth touching.
  - **`canonicalizeFields` cannot join under the proposed signature.** Its per-label helper
    `mergeUnevaluatedFieldInto` (Eval:401) is NOT a `Value→Value→Value` combiner: it
    dispatches on the MERGED field-class (`fieldClass.isDefinition` →
    `mergeDefinitionDecls` close-once-union, else `joinUnevaluated`), a decision the plain
    combiner signature cannot express. It also DELIBERATELY omits the bottom-rewrite that
    `mergeFieldValueWith` does (`isBottom` → `.fieldConflict`) — an unevaluated decl is not
    yet a meet, so it carries no conflict marker. Forcing it under a shared `mergeFieldsWith`
    would mean threading the field-class into the combiner type — a strictly looser, more
    error-prone signature than the two it would merge. This is the four-classifiers / DRY-1
    precedent: the shared part (the `foldl … else-append` shell) is too thin to name; the
    per-label DECISION is the point, and it differs irreducibly.
  - **🚨 Soundness-boundary: consolidation is FORBIDDEN regardless of skeleton, because the
    within-operand-vs-cross-operand (union-vs-meet) distinction lives in WHICH FUNCTION the
    caller invokes, and that is the whole safety.** `canonicalizeFields` (within ONE operand
    → close-once-UNION via `mergeDefinitionDecls`) and `mergeConjFields` (CROSS-operand →
    `.conj`-MEET) are deliberately DIFFERENT named functions so a call site picks the
    semantics by name — `mergeConjOperands` canonicalizes each operand's OWN fields, then
    `mergeConjFields`-merges ACROSS operands; the soundness boundary IS that ordering of two
    differently-named calls. A merged `mergeFieldsWith combiner` would put union-vs-meet
    into a COMBINER ARGUMENT — making it one wrong argument to pass the union combiner on a
    cross-operand path, which re-opens closed patterns (the cert-manager trap, the exact
    Bug2-8 hazard). The distinct names make the union combiner UNREACHABLE on the
    cross-operand path by construction. Per the prompt's own constraint: "if consolidation
    would blur or endanger that boundary, that's a reason to KEEP SEPARATE even if the
    skeleton is shared." It would, so they stay separate. **Do not re-file as a DRY win.**

- **Phase-B audit (2026-06-23, batch `fcede10`..`71d4cf0`: CARRIER-STRUCT-MEET /
  CARRIER-DECL-SELECT / Bug2-5 + Linux release infra; Phase A HEALTHY `71d4cf0`) —
  architecture HEALTHY.** Module graph re-checked whole: ACYCLIC, strictly layered
  (`EvalOps → {Builtin, Decimal, Regex}` no back-edge; `Builtin → Lattice/…` NO
  `Builtin → Eval`; `Eval → {Builtin, Decimal, EvalOps, Lattice, Regex, Normalize}`;
  `Runtime → Eval`). The Bug2-5 gate (`embedBodyEmbedsDisjDeep`) sits correctly in Eval's
  def-deferral tier (follows `resolveEmbedDefBody?`, needs the eval-layer env) — right module.
  Linux release infra (`scripts/release-linux.sh`, `Dockerfile.linux-build`, `.dockerignore`,
  `df40b62`) does NOT touch the Lean graph; it is sound + robust (strict `set -euo pipefail`,
  preconditions gated, toolchain single-sourced from `lean-toolchain`, idempotent `--clobber`,
  trap-cleaned container extract, double smoke-test; debian-bullseye glibc-2.31 base,
  container-local elan, no host mutation). **GitHub Actions ban CLEAN** (no `.github/`, no
  workflow files; `.dockerignore` excludes `.github/` defensively). Cleanliness sweep clean:
  NO `sorry`/`panic!`/`unreachable!`/`.get!`-in-total-code, NO `String.dropRight`/`dropLeft`,
  NO dead code, NO stale TODO/FIXME/HACK (the `\uXXXX` hits in `Json.lean` are escape-doc); the
  4 `Module.lean` `partial def`s are the justified IO-loader carve-out, not the pure core.
  File sizes: `Eval.lean` 3465 (the `embedChainAny` dedup net-shaved a few off the Bug2-5
  growth) — well under the ~4500 re-split watch, ruling STANDS (`embedChainAny` joins the
  def-deferral tier, reinforcing it as the named first carve). `TwoPassTests.lean` 1496 (Bug2-5/
  2-6 pins accreting) — the file to watch for the next test-org pass, not yet unwieldy.
  **APPLIED INLINE (re-verified green):** (1) **`embedChainAny` share** (`0619097`) — the headline
  ruling, below; (2) **perf-doc gating correction** — `kue-performance.md` argocd-bottoms entry
  said "residual blocker is now **Bug2-5**" (STALE — Bug2-5 LANDED `5fca57e`); corrected to
  Bug2-6, timing 153s→~54s. (`plan.md` item-5 + Standing Capabilities were already correct — no
  un-gate had been wrongly applied.) **Bug2-6 design note** written into
  `spec-conformance-audit.md` (provenance via `closedClauses` union-into-one-clause at the
  `joinUnevaluated` seam; meet path untouched so `#A & #B` rejection structurally preserved).
  **Filed:** one LOW Linux-script consistency item (item-6, `release-linux.sh` no dirty-tree
  guard). **Verdict: HEALTHY; `embedChainAny` shared inline; one LOW item filed; no fix-slice.**
- **`embedChainAny` (embed-chain walker share) — RULED: SHARE, applied inline `0619097`
  (2026-06-23). The AD4-1-safe case, NOT the DRY-1 trap.** `bodyNeedsDefer` and
  `embedBodyEmbedsDisjDeep` were byte-isomorphic except the leaf predicate
  (`defBodyHasSiblingSelfRef` vs `embedBodyEmbedsDisj`). Factored the shared fuel-bounded
  chain-walk into `embedChainAny (leaf : Value → Bool) (env) (fuel) (body)`; both became
  one-line instantiations. **Why this is NOT DRY-1:** DRY-1 failed because its variation point
  WAS the recursion (routing the nested-let recursion through a callback hid the `fuel+1`
  pattern, breaking structural-recursion inference). Here the variation point is a PURE
  NON-RECURSIVE `Value → Bool` leaf the combinator owns, and the recursion (the fixed
  chain-walk) stays lexically in the combinator — exactly AD4-1 / `expandClauseChain`'s shape
  (`onExhausted` is "pure and non-recursive, so the fuel/clause recursion stays lexically
  visible to `termination_by`" — that comment IS the precedent). Neither leaf recurses into the
  walk, so `termination_by fuel` infers unchanged. Build clean (native_decide pins green),
  fixtures zero-drift, shellcheck clean. Do NOT re-litigate as a DRY-1-style false share — the
  distinction (leaf-varies vs recursion-varies) is the whole ruling.
- **CARRIER share/no-share (`.embeddedScalar` vs `.embeddedList`) — RULED: keep DISTINCT
  constructors; do NOT merge into an `embeddedCarrier`; share ONLY the decl-selection seam
  (CARRIER-DECL-SELECT, filed). Do NOT share the meet seam (Phase-B 2026-06-22, the
  headline adjudication).** The scalar-embed slice's parallel-ctor design is the RIGHT call.
  Basis, decomposed into the three separable seams the prompt names:
  - **Constructors — keep distinct (no merge).** A scalar is not a list: it never indexes
    and never iterates (the `Value.lean` doc-comment already states this). The divergence is
    structural and load-bearing at the OUTPUT/ITERATION sites, where a merge would
    re-introduce illegal states: `Manifest` (`embeddedScalar` → `manifestWithFuel scalar`,
    NO list-wrap / NO item recursion; `embeddedList` → `.ok (.list items)` + recurse items),
    `Format` (scalar renders the bare value in `{…}`; list renders a `[…]` sub-list with
    tail handling), `comprehensionPairs` (`embeddedList` → `listPairsFrom`; scalar →
    non-iterable via catch-all), `selectEvaluatedListIndex` (list-only), `classifyGuard`
    /`classifyDynLabel`/`classifyArithOperand` (scalar RECURSES onto its inner scalar; list
    → `.nonBool .list`/`.nonString .list`/`.concreteNonArith .list`). A merged
    `embeddedCarrier (payload : Value) (decls)` would force every one of these sites to
    re-discriminate scalar-vs-list on `payload` at RUNTIME — exactly the illegal-state
    (`index a scalar`, `iterate a scalar`) that the two-ctor split makes UNREPRESENTABLE by
    construction. This is the four-classifiers / walker-dedup precedent applied: the shared
    part (carry `decls`) is too thin to name; the divergence IS the point. **Do not
    re-litigate the merge.**
  - **Meet seam — do NOT share, despite the shared bug.** Phase-A's evidence (both carriers
    have the SAME CARRIER-STRUCT-MEET bug + SAME fix) is real but does NOT imply a shared
    meet helper. The two meet arm-BLOCKS (`Lattice.lean:1244-1278` list, `:1285-1316`
    scalar) are structurally isomorphic at the SKELETON (partner-check → payload-meet+decl-
    merge → re-wrap; else struct-sub-case; else `meetCore`) but the PAYLOAD-MEET step is
    irreducibly different — list uses `asListPair`+`meetListPairWith` (prefix/tail
    alignment), scalar uses `scalarCarrierPartner?`+a bare `meetWithFuel` on the scalar. A
    shared higher-order seam parameterized over (partner-extractor, payload-meet, re-wrap)
    would be a 3-callback combinator wrapping ~12 lines of skeleton — the lambda-hides-`fuel
    +1` trap that broke DRY-1 (the payload-meet callback recurses through `meetWithFuel
    fuel`, which Lean's structural-recursion inference cannot see through a passed lambda).
    The skeleton is cheap to keep parallel; the seam is expensive to abstract. **CARRIER-
    STRUCT-MEET writes the fix TWICE (4 sites: the `.struct fields _ none [] _` sub-case at
    `:1257`/`:1272`/`:1295`/`:1310`), by hand, identically — that is the correct cost.** The
    fix is a deletion (drop the `else <merge decls>`, route to `meetCore`→bottom), not new
    logic, so writing it 4× is mechanical, not a maintenance hazard. CARRIER-STRUCT-MEET's
    diagnosis already says "apply uniformly to both carriers" — it composes with this ruling
    as-written; it does NOT need a shared meet seam to land.
  - **Decl-selection seam — DO share (CARRIER-DECL-SELECT, filed above).** This is the ONE
    seam where the carriers genuinely AGREE (both select decls identically, and identically
    to plain `.struct`), so a `selectFromDecls` helper is real dedup, not false-sharing.
    Ranked BELOW CARRIER-STRUCT-MEET (lands after, to avoid touching the same arms twice).
- **Phase-B audit (2026-06-22, batch `1ab6f19`(Phase-B prev)..`fa0a414`(scalar-embed) +
  Phase-A `fc2bb6a`; TL-1 `384380e` / TL-2 `69239a2` / scalar-embed+B3 `fa0a414`) —
  architecture HEALTHY.** Whole module graph re-checked after the carrier landed. ACYCLIC,
  strictly layered, NO new edge from the carrier: the two ctors live in `Value` (L1, correct
  — they ARE `Value` variants), meet in `Lattice` (imports only `Value`/`Regex`), produced
  once at embed-eval in `Eval` (`meetEmbeddingsWithFuel:3021-3030`). `EvalOps` carve from the
  prior round still clean (`EvalOps → {Builtin, Decimal, Regex}`, no back-edge). New-ctor
  discipline VERIFIED graph-wide: `.embeddedScalar` has an explicit arm at every match site
  (Lattice meet + `containsBottom`; Eval select/definedness/guard/dynlabel/digest/tag/
  walkers; EvalOps `classifyArithOperand`+`resolveOperand` unwrap; Format/Manifest/Normalize
  ×2/Runtime) — NO catch-all swallow. `valueTag .embeddedScalar => 32` correctly assigned (a
  termination measure, not a finding — same deliberate `Value→Nat` pattern the prior ruling
  noted). File sizes: `Eval.lean` 3442 (was 3396; +46 from the carrier arms — well under the
  ~4500 re-split watch, ruling stands), `Lattice` 1417, `Value` 921, all others ≤2438
  (`CaseTable`, generated). Cleanliness sweep clean: NO `sorry`/`panic!`/`unreachable!`
  /`get!`-in-total-code, NO `String.dropRight`/`dropLeft`, NO dead code, NO stale
  TODO/FIXME/HACK (the `\uXXXX` hits in `Json.lean` are escape-doc, not markers).
  Perf-guide: NO note warranted — the carrier meet/normalize/format path is O(1) over the
  inner scalar + O(decls), the same trivial profile as the pre-existing `.embeddedList`
  carrier (which the guide also doesn't single out); no new slow pattern. **Filed as
  fix-slices:** CARRIER-DECL-SELECT (DRY, LOW — the one genuine cross-carrier duplication,
  the decl-selection seam; ranked below CARRIER-STRUCT-MEET). **Headline ruling:** carrier
  share/no-share RESOLVED (above) — keep distinct ctors, share decl-selection only, NOT the
  meet seam. **Verdict: HEALTHY; one DRY fix-slice filed; carrier design VINDICATED.**
- **Phase-B audit (2026-06-22, batch `cd2f0a9`(BI-2-§3)/`3cc09ab`(EvalOps)/`b5d670c`
  (import-eager) + Phase-A inline `31c76c8`/`8eaa180`) — architecture HEALTHY.** Whole
  module graph re-checked: ACYCLIC, strictly layered (`Regex`/`Base64`/`CaseTable` L0 →
  `Value` L1 → `Decimal`/`Lattice`/`Parse`/… L2 → `Manifest`/`Json`/`Yaml` → `Builtin` L6 →
  **`EvalOps` L7** → **`Eval` L8** → `Runtime`/`Module` L10). The new EvalOps carve confirmed
  clean: `EvalOps → {Builtin, Decimal, Regex}`, NO back-edge, NO `Builtin → Eval` (Builtin
  L6, Eval L8); `classifyArithOperand` is FULLY exhaustive (every `Value` ctor → a decision,
  no catch-all) — exemplary type-leverage. `selectedFieldValue` (the import-eager unification)
  and `normalizeEvaluatedDisj`'s `normalizeDisj` reuse both clean. Cleanliness sweep: NO
  `sorry`/`panic!`/`unreachable!`/`get!`-in-total-code, NO `String.dropRight`/`dropLeft`, NO
  dead code (the `Order.lean` test-oracle ruling stands; all private helpers referenced), NO
  stale TODO/FIXME/HACK markers. **APPLIED INLINE (low-risk, re-verified green):** the
  `kue-performance.md` Pow row de-staled — split the integer-exponent row and added a
  fractional/negative-exponent row (BI-2-residual + BI-2-§3 LANDED; `math.Pow`/`math.Sqrt`
  now cover their full real domain in exact decimal — the old "currently bottom — see
  BI-2-residual" text was stale). **Filed as fix-slices:** TL-1 (stringly-typed
  builtin-family dispatch → `BuiltinFamily` enum, MEDIUM — **DONE 2026-06-22**) + TL-2
  (`BindingId` two-bare-`Nat` → `Depth`/`FieldIndex` newtypes, LOW-MED —
  **DONE 2026-06-22**) — both type-leverage tightenings, were in the item-6 LOW list,
  neither inline (blast radius too broad). **Verdict: HEALTHY, two ranked tightenings
  filed — both now landed.**
- **`Eval.lean` split — NOT WARRANTED at 3396 lines (Phase-B 2026-06-22 ruling; do not
  re-litigate below ~4500).** Structural map: 4 `mutual` blocks (`foldValueWithDepth` ~80
  lines; `remapConjRefs` ~147; `hasSelfRefAtDepth` ~110; **the core evaluator
  `evalValueWithFuel`…`expandListClausesWithFuel`, ~1140 lines / 15 mutually-recursive
  defs**) — the core block is UNSPLITTABLE: its `termination_by (fuel, tag, length)` tuple
  ordering (tags 0–6) would have to be proven across a module boundary, fragile and
  unmaintainable. The only semantically-coherent carve candidate is the **def-deferral tier**
  (`resolveEmbedDefBody?`/`bodyNeedsDefer`/`followAliasDefBody?`/`importDefClosureBody?`
  /`refDefClosureBody?`/… ~228 lines, `Eval.lean:1904–2131`): one-directional call graph
  (→ force/eval, no back-edge), but too tightly coupled to its `.refId`/`.selector`/`.conj`
  call sites to gain from isolation now. RULING: leave Eval.lean cohesive; IF it crosses
  ~4500, the def-deferral tier is the named first carve (`Eval.DefDeferral`, importing
  `hasSelfRefAtDepth`/`defBodyHasSiblingSelfRef`/core types). The classifier cluster
  (`classifyGuard`/`classifyDynLabel` ~124) and embedding-splice complex (~191) are also
  carveable but lower-value (too small / too coupled). Never split the evaluator mutual block
  at any size.
- **Escape-helper cross-module "duplication" (`escapeJsonChar` Json.lean vs
  `escapeCueStringChar` Format.lean) — RULED NOT A FINDING (Phase-B 2026-06-22).** The two
  share only 5 trivial literal arms (`"`/`\`/`\n`/`\r`/`\t`); they DIVERGE in the
  substance — JSON does control-char escaping (`\b`/`\f`/`\uXXXX`), CUE passes through
  verbatim. Collapsing the 5 shared arms behind a callback for the divergent tail is the
  "stuff they all do" false-sharing the four-classifiers + DRY-1 rulings already reject:
  the shared part is too thin to name, the divergence IS the point. Keep separate; do not
  re-file.
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
