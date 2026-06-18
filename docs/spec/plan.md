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
- **argocd: correct through link 4** (`defs.#Secret` base64 `data`, `#TLSRoute`, `#ListenerSet`
  all content-identical to cue modulo field-order #3; cert-manager + links 2/3/4 no regression).
  **Blocked on link 5** (`packs.#Argo` — see backlog item 1, the live blocker).

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

### Fix-slice 0 — `def-open-tail-closedness` (HIGH — correctness regression, do FIRST)
Make an open def survive normalize. The collapse loses no info IF normalize honors the
`open_` flag. Two candidate fixes, prefer the one that's clearly sound:
- **(A) honor `open_` in normalize.** `Normalize.lean:13` `.structComp` arm: close only when
  the incoming `open_` is false — `.structComp (…) comprehensions open_` (preserve flag)
  instead of hard `false`. Mirror the `.struct` arm too (line 11 also hard-`false`s, but the
  parser only routes `...`-bearing plain structs to `.structTail`, so `.struct` reaching
  normalize is always closed-intent — verify before touching). This is the root fix and
  matches CUE: `...` overrides a def's default closedness.
- **(B) keep the tail node.** Revert Fix 2 toward carrying the openness explicitly — but the
  old `.conj` split is what link 4 fixed, so a plain revert reintroduces the `#ListenerSet`
  bottom. Would need a NEW representation (e.g. `.structComp` + a dedicated open marker the
  parser sets and normalize reads) — heavier than (A).
Pick (A). Pin: def-with-`...`-with-embed accepts extra field at use site (the regressed
shape) AND the link-4 `open_embed_selfref_guard` fixture still passes (narrowing still
works). Add fixtures for embed+`...`+extra and comp+`...`+extra (both currently bottom).
Full verify gate; this unblocks a real correctness hole.

## Live Backlog (open work, ranked)

Correctness gates real-app adoption; cleanups are parallel-safe filler. Sequence:
correctness frontier (1) → parallel-safe cleanups (3,4,5) interleaved → deeper parity/perf
(2,6,7) → borderline/LOW (8) as opportunistic ride-alongs.

1. **`argocd-packs-argo` (HIGH — LIVE real-app blocker; argocd link 5).** Links 3
   (`#TLSRoute`) and 4 (`#ListenerSet`) LANDED (2026-06-18 `argocd-tlsroute-list-guard` slice —
   two-pass gate depth + `.listComprehension` self-ref detection; parser open-struct-with-embeds
   collapse). Both now content-match cue. Full `kue export apps/argocd.cue` STILL bottoms on
   `packs.#Argo` (the `argo_.{stage9,bluepages,…}.configs` sub-package): `packs.#Argo & {…}`
   bottoms in isolation (~36s, perf-wall-adjacent). Root cause is deeper than links 3/4 — nested
   `defs.#ArgoRepo`/`#ArgoProject`/`#ArgoApp` embeds each with their own `if Self.#x != _|_`
   guards, a `[...]` open list, and many cross-`defs` embeds. Bisect via the scratch-module +
   editable-cache-copy method (breadcrumb). This is the next correctness link to make argocd a
   drop-in. NOTE: `packs.#Argo` is ALSO near the per-eval perf wall (item 7) — distinguish
   "correct but slow" from "still bottoms" while bisecting.
   ```cue
   #App: {#name?: string, if #name != _|_ {name: #name}, ...}
   out: packs.#Argo & {#name: "web"}
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
   closure ctor in `Value.lean`. Extracting makes `Value.lean` a TRUE leaf (drops the lone
   `Init.Data.String.Search` import). New leaf module + `import Kue.Regex` in `Eval`/`Builtin`.
   Zero conflict with any `Eval.lean` slice — runs in its own subagent concurrently.

4. **EvalOps extraction → `Kue/EvalOps.lean` (ACTIONABLE).** ~256 lines of self-contained
   pure `{Value, Decimal}` scalar algebra (`evalAdd…evalBinary`, ~lines 369-635) carved out
   from under the recursive evaluator. New module imports only `{Value, Decimal}`. No
   line-number collision with `truncate-primitive` (mutual block, ~1471+) or argocd work
   (closure/conj path, below 635) — interleaves freely. Mechanical.

5. **Test-org pass (ACTIONABLE, periodic).** Theorem modules in `Kue/Tests/` are oversized
   (`EvalTests` 1700+, `FixtureTests` 1033, `BuiltinTests` 735, `StructTests` 765). Split
   each by subsystem in ONE pass; leave `FixturePorts` whole (generated). Don't churn
   `testdata/` (sensibly named). Run AFTER the next correctness slice lands its pins so the
   split doesn't immediately stale.

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
   - **Dead OR-branch `refsSelfEmbeddedLabel` (`Eval.lean:97`)** — the `… || refsSelfEmbeddedLabel
     … (.refId id)` recursion hits `_ => false` unconditionally (no `.refId` arm). Remove on
     the next embedding-Self touch.
   - **DRY `selectEvaluatedField .disj`** — the resolved-default arm re-lists the 5-arm
     struct-shape dispatch; collapse to `match resolveDisjDefault? alternatives with | some
     v => selectEvaluatedField v label | none => …` (gains free nested-disjunction recursion).
   - **`resolveEmbeddedDisjDefault` (`Eval.lean:2093`, next-audit confirm)** — verify the
     pass-1 label-surfacing path does NOT also need the use-site-narrowing distribution that
     `embed-disj-arm-fallthrough` added, or that label-surfacing-only is correct there.

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
