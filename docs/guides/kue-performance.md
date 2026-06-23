# Writing Kue-Friendly CUE (Performance Guide)

Kue prioritizes **correctness over speed** (see
[the decision](../decisions/2026-06-18-correctness-over-performance.md)). It is usable for
ordinary configs, but some CUE patterns cost far more in Kue than in `cue`. This guide
lists what is expensive, *why*, and how to structure CUE so Kue evaluates it fast.

**Living doc.** The engine is actively optimized and these characteristics shift as
sound optimizations land. Treat specific timings as snapshots, not guarantees. If you hit
a slow case not covered here, file it (see "Reporting a slow case" below).

## How Kue evaluates (the cost model)

Kue uses **fuel-bounded, total evaluation**: every value is reduced under a fuel budget
(no host-language recursion, so termination is guaranteed). `fuel` is *load-bearing* — it
is what tells a real value apart from a cycle-truncated one — so it cannot simply be
lowered to go faster.

Since **fuel-saturation caching** landed (2026-06-18), the cost of evaluating a value is
roughly:

```
per-level work  ×  the fuel depth at which the value converges
```

— and crucially **NO LONGER multiplied by the remaining fuel levels above convergence.**
A value that settles at shallow depth is cheap. A value that only stabilizes after many
fuel levels — deep self-reference, long indirection chains — still pays its per-level cost
up to the depth where it converges, but once a subtree converges it is cached
*fuel-independently* and never re-derived at higher fuel.

**Fuel multiplication is eliminated.** Previously the default ceiling re-derived an
already-converged value across every remaining fuel level (a real `#ClusterIssuer`-style
app converged at fuel ~16 but re-derived across ~84 further levels at ~1.35× each →
effectively unbounded; a full-fuel run was killed at 8 min CPU). Now any result whose
entire subtree never ran out of fuel (never hit the `fuel = 0` base nor a cycle cut) is
*saturated* — proven fuel-insensitive — and cached under a fuel-free key, so it is computed
ONCE regardless of the ceiling. The measured effect on that app: eval count went from 583k
(fuel 16) → 1.05M (fuel 20) → unbounded, to a FLAT ~290k at any fuel; it now exports
correctly at the production ceiling in ~30 s. Results that genuinely *do* depend on fuel
(cycle-truncated values) stay fuel-keyed and are never served across fuel levels, so the
fix is purely a speedup — byte-identical output.

## Expensive patterns (minimize these)

| Pattern | Why it is slow | Faster shape |
|----------------------------------|--------------------------------------|----------------------------------|
| Deep self-referential defs — `#D: Self={ … Self.#x … }` chained many levels | Raises the *convergence depth* (the per-level cost is paid up to the depth where it settles — no longer multiplied above it) | Flatten; resolve shared values once at a shallow level and reference them |
| Long alias / selector chains — `#A: parts.#M`, `#B: #A`, `#C: #B`, … | Each hop adds convergence depth (still paid once per level up to convergence) | Reference the terminal value directly where practical |
| Deep cross-package embed chains — `#Outer{ pkg.#Mid{ pkg.#Inner } }` | Correct, but each embedded level adds convergence depth | Keep embedding shallow; prefer a few wide defs over many nested ones |
| Gratuitously duplicating a large sub-expression across fields | Historically caused exponential blow-up | Mitigated by frame-id sharing (see below); still cheaper to bind once and reference |
| A field reading `Self.<label>` where `<label>` comes from an EMBEDDING (`type: Self.#type` with `#type` from an embedded `(*_#A \| …)` or `parts.#X`) | Triggers a second pass over the struct's static fields (the embedded label is not in the frame on the first pass) — cost ~2x for that struct only, gated so it fires solely on a genuine such selection | Read the embedded field directly where the embed declares it, or lift the shared value to a sibling field of the host |
| A use-site-narrowed field whose def lives in an embedded DEFAULT DISJUNCTION arm (`#S: {#data:…, (*_#A \| _#B)}` + `#S & {#data:…}`, the `defs.#Secret` shape) | The narrowing is DISTRIBUTED into each disjunction arm (`*(_#A & narrow) \| (_#B & narrow)`), so each deferral-needing arm is force-spliced separately — correct, bounded, gated (a plain scalar/struct disjunction is not deferred) | Fine as-is; the cost is one force per live arm. Keep the disjunction arm count small |
| A reference whose resolved body is a STRUCT, re-evaluated through `.refId` (any `#D: ref` / `a: ref-to-struct`) | Structural-cycle detection (D#2a) pushes the body onto an ancestor `structStack` and runs `List.contains` (an O(stack-depth) structural `BEq` over the full `Value` tree) on every such re-entry to detect re-entrancy (`#L: {next: #L}`). A NO-OP for non-cyclic programs (no false cycle), but a new per-`.refId`-into-struct constant — the stack is bounded by genuine struct-ref nesting depth and restored after each body, so it is shallow in practice | Unavoidable for correct cycle detection; lower struct-ref nesting depth (flatten, fewer indirection hops) to keep the stack — and thus each `contains` scan — short |
| `list.Sort(xs, cmp)` / `list.SortStable(xs, cmp)` over a large list with a custom comparator | The comparator is evaluated PER COMPARISON, not per element: a stable merge sort does O(n log n) comparisons, and EACH comparison meets the `{x,y,less}` comparator struct with `{x: a, y: b}` and fully evaluates its `less` field to a bool (a meet + a nested `evalValueWithFuel`). So the cost is O(n log n) full sub-evaluations, scaled by how expensive `less` is to reduce. `list.SortStrings` (no CUE comparator) does NOT pay this — it is a pure string sort | Sort the smallest list possible; keep the comparator's `less` shallow (a direct `x < y` is cheap, a `less` that itself selects/computes through deep refs multiplies the per-comparison cost). Pre-reduce list elements to concrete values before sorting so each comparison meet is trivial. Prefer `list.SortStrings` when sorting plain strings |
| `math.Pow(b, e)` with a large integer exponent | Exact (never floating-point): computed by repeated EXACT bignum multiply (`decimalPowNat`, structural on the `Nat` exponent), so a large exponent does many big-integer multiplications and the result grows to full precision (no rounding, no overflow) | Fine for ordinary exponents; for a very large exponent the bignum result is correctness-exact but large — avoid `Pow` in a hot loop with big exponents |
| `math.Pow(b, e)` with a non-½ FRACTIONAL or NEGATIVE exponent | Exact (never floating-point): negative-integer `x^(-n)=1/x^n` is exact rational; a general fractional `x^y = exp(y·ln x)` runs `decimalExpScaled`/`decimalLnScaled` (fixed 40/60-term Taylor + binary range reduction at working scale 50). The Taylor term count is a per-CALL constant, NOT coupled to eval fuel — cheap, but heavier than the integer-exponent bignum path | Fine for ordinary fractional/negative exponents; the cost is the fixed Taylor budget, paid once per call. `math.Sqrt` (and `Pow(·,½)`) take the cheaper Newton-iteration path (`decimalSqrt`) instead — prefer `Sqrt` over `Pow(·,0.5)` |

## Cheap patterns (prefer these)

- **Concrete values and shallow structs** — nothing to converge.
- **References that resolve in a few steps** — short indirection, shallow nesting.
- **Flat definitions** over deep self-referential nesting — lower convergence depth is the
  single biggest lever.
- **Binding a shared sub-value once** and referencing it, rather than re-inlining it.

## What the engine already handles for you

- **Structurally-identical re-pushes share work.** Duplicating the same sub-expression
  under multiple fields (`{a: B, b: B}`) used to blow up exponentially (each copy pushed a
  fresh evaluation frame). Frame-id sharing now reuses one frame for structurally-identical
  pushes under the same scope, so this is no longer exponential. You still pay convergence
  depth, so deep duplicated nesting is cheaper avoided, but flat duplication is fine.
- **Forced cross-package def-meet is memoized**, so repeated use of the same imported def
  with the same use-site does not re-evaluate from scratch.
- **Converged subtrees are cached fuel-independently** (fuel-saturation caching). Once a
  value settles below the fuel ceiling it is never re-derived at higher fuel — the dominant
  real-app cost (fuel multiplication) is gone. The only values that re-derive per fuel
  level are genuinely fuel-sensitive ones (cycle-truncated), which is correct, not waste.
- **Multi-ref CYCLIC def flatten is bounded** (flatten-fan-out bound, 2026-06-23). A closed
  cycle whose head conjoins ≥2 back-referencing defs (`#A: #B & #C & {a}`, `#B: #A & {b}`,
  `#C: #A & {c}`) is now flattened in LINEAR time instead of blowing up on the cross-product
  of expansion paths. `flattenConjDefRef` threads an `expanding` visited-path set: a depth-0
  ref to a cycle member already on the current expansion path is returned UNEXPANDED — its
  literals are already collected by the ancestor that put it on the path, and the bare
  `.refId` it returns is EXACTLY the leaf the unbounded recursion bottoms to at fuel
  exhaustion (the structural-cycle path D#2a bottoms a re-entrant ref). So each cycle
  member's literals are collected ONCE, not once per reference path. **Sound by
  construction:** `mergeDefinitionDecls` unions literals idempotently (a re-collected `{b}`
  merges to itself) and the re-entrant `.refId`s in `rest` `.conj`-meet idempotently under
  D#2, so the literal UNION and the `rest` ref set are the SAME finite sets regardless of how
  many times each member is reached — the allowed-set and value are byte-identical, only the
  expansion COST changes. (Field ORDER for a multi-hop chain canonicalizes to
  reverse-declaration, an unordered-map detail, not correctness.) **Measured:** the 3-line
  repro above went from **>40s (killed)** to **~0.01s warm / ~0.55s cold**; the single-ref
  cycle is byte-identical before→after; cert-manager (~12.4s) and argocd (~54s) jq-S=0
  unchanged (the bound fires only on closed multi-ref cycle re-entry, which the real apps do
  not hit). The previously
  un-pinnable multi-ref cases (2/3/4-way, genuine-extra-reject, open-tail, split-literal,
  duplicated back-ref) are now fast `native_decide` pins.
- **Env-independent leaves skip the cache entirely** (perf-#7 leaf fast path). A scalar/closed
  constant (`.prim`/`.kind`/`.top`/`.bottom`/`.notPrim`/`.stringRegex`/`.boundConstraint`/
  `.thisStruct`) is the identity of evaluation, so `evalValueWithFuel` returns it directly
  without an env-keyed cache probe+insert. On a deep app these are ~37% of all core evals (each
  re-reached under many distinct frame envs); bypassing them is a pure, value-identical speedup.
  Only the fuel-TRUNCATED population now occupies the fuel-keyed `cache`; everything saturated
  lives solely in the fuel-free `satCache`.

## Known limitations (current)

- **Absolute per-eval cost on deep apps.** With fuel multiplication eliminated, a deep
  real-app (e.g. a prod9 infra app with deep `Self=` def chains) now exports correctly at
  the production fuel ceiling, but the absolute eval count (hundreds of thousands of core
  evals for cert-manager) × the per-eval constant still costs ~tens of seconds (cert-manager
  ~90-100s as of the 2026-06-18 link-3/4 correctness fixes — up from ~31s, because an open
  definition that embeds a self-ref def (`{ embed; …; ... }`, the dominant prod9 `#Def` shape)
  now routes through the single-`.structComp` two-pass embed-re-evaluation path; this is sound
  and correctness-required, but more expensive than the prior representation). This is no
  longer a fuel-axis problem; the next perf lever is the per-eval constant, not the fuel
  ceiling. The practical advice above (flatten, shorten chains → lower convergence depth →
  fewer evals) remains the lever you control.
- **The embedding-`Self` two-pass is now bounded (2026-06-18 Pass-2 selective re-eval).** When a
  definition reads `Self.<label>` for a label supplied by an embedding, Kue runs a second pass over
  an augmented frame. It used to re-evaluate EVERY static field (a fresh frame id → no Pass-1 cache
  hit), so a def with many fields but few `Self.<embed>` reads paid a full duplicate eval per
  unrelated field. Now Pass 2 re-evaluates ONLY the fields that depend (directly or transitively via
  a sibling `Self.<L>` read) on an embedded label — the rest reuse their Pass-1 value, byte-identical
  (a non-dependent field's value is frame-id-independent under the augment). Measured: the per-
  unrelated-field Pass-2 cost dropped from +10 to +5 core evals (~46% on the audit repro shape). It
  helps defs shaped like `packs.#Argo` (dozens of fields, a handful of `Self.<embed>` reads); it did
  NOT measurably move cert-manager's wall-clock, whose cost is dominated instead by the broader
  frame-id divergence (see below), not the per-field Pass-2 recompute.
- **Cache-key hash deepened to a bounded-depth digest — O(N²) memo lookups FIXED (item 7,
  landed 2026-06-19).** The `EvalKey`/`SatKey` hashes used to key on `valueTag` (the top
  constructor tag only) + `envIds.LENGTH`, so at a deep app's steady state every distinct
  `.struct`/`.selector` value at the ceiling fuel collided into ONE hash bucket; each
  `cache.get?` then ran structural `BEq` over the full value tree against every colliding
  entry → O(N) per lookup, O(N²) total (cert-manager exported correctly but in **~119s**
  vs `cue` 0.03s). The fix swaps in `valueDigest DIGEST_DEPTH` (depth 3) — a TOTAL,
  fuel-free, bounded-depth structural digest mixing each constructor's tag with its field
  labels + child digests — and hashes the FULL `envIds` (not `.length`). It is provably
  sound by construction: a hash only selects a bucket, `BEq` (UNCHANGED) is the sole
  equality arbiter, so a lossy digest can only cause a recompute-miss or collide-scan
  (slower), never a wrong value — proven by zero fixture byte-drift. **Measured:
  cert-manager 119s → ~30.6s (~3.9×), byte-identical to `cue` modulo field order (#3).** A
  bucket-distribution `native_decide` pin witnesses 1000 distinct k8s-shaped structs →
  1000 distinct buckets at depth 3 (vs 1 under the old `valueTag` hash). `FrameKey`'s hash
  was profiled with the same deepening and showed ZERO change (frame sharing + `parentIds`
  already discriminate the table), so it was left shallow. Full `apps/argocd.cue` is much
  faster (>7.5min/killed → ~88s) but still hits the fuel ceiling (`conflicting values
  (bottom)`) — that is the separate fuel-exhaustion-at-scale limit below, NOT a hash
  problem.
  > **Currency note RECONCILED (2026-06-19, Bug2-2 slice):** fresh `time kue export apps/cert-manager.cue`
  > on the current `main` (post Bug2-1 + Bug2-2) measures **30.52s, content-identical to cue** (modulo
  > field-order #3) — the **~30.6s** reading is the live one, NOT the **~92s** that was in `plan.md`
  > Standing Capabilities. The 92s figure was stale (it predates the item-7 hash fix landing, or was a
  > cold/contended run); the steady measurement across the Bug2-1 and Bug2-2 slices is consistently
  > ~30.5s. Treat **~30.5s** as the cert-manager number; the 92s is retired.
  > **Currency note RE-RECONCILED (2026-06-23, Phase-B audit, post-Bug2-14):** fresh
  > `/usr/bin/time -p kue export apps/cert-manager.cue` on the current `main` measures
  > **12.6s wall (12.3s user), content-identical to cue** (jq -S diff = 0) — a 2.4× drop from
  > the ~30.5s above. The improvement accrued across the Bug2-6..2-14 close-once / frame-id
  > chain (fewer redundant force-folds + tighter frame-id discrimination cut cert-manager's
  > per-eval churn). **Treat ~12.6s as the live cert-manager number; ~30.5s is retired.**
- **Full `apps/argocd.cue` EXPORTS content-identical (2026-06-23) — the correctness chain
  is CLOSED; the residual ~50s is the perf-#7 frontier (profiled + partially optimized).** The
  Bug2-x narrowing chain (Bug #1 … Bug2-14/14b/14c) all LANDED; `kue export apps/argocd.cue` is
  byte-identical to `cue` (jq -S diff = 0, 51178 bytes, **~50.3s wall** post-perf#7, was ~53.4s,
  vs `cue` 0.03s) — the 2nd prod9 real-app drop-in alongside cert-manager (~11.7s). The block
  below records the correctness history (resolved) and the perf-#7 profile + the two sound
  optimizations the unblock enabled.
  > **perf-#7 PROFILED + PARTIALLY OPTIMIZED (2026-06-23) — the wall is a ~175× RE-EVALUATION
  > of env-DEPENDENT value shapes, NOT a subtree hot spot, NOT output-driven, NOT fuel-axis,
  > NOT an O(N²) hash collapse.** Profiled the 832K-eval whole-root export by instrumenting
  > `evalValueWithFuel`. Decisive numbers: `evalCalls=832338` core (cache-miss) evals,
  > `evalCacheHits=0` (the fuel-keyed `cache` NEVER hits — every re-served value comes from the
  > fuel-free `satCache`), and **`distinctShapes=4763`** distinct value subtrees (digest-depth 8)
  > → a **~175× re-eval factor**: the SAME subtree is core-evaluated ~175× because it is reached
  > under ~175 distinct frame envs and the cache keys on `env.ids`. This is frame-id divergence
  > (the "frame-id churn" lens), NOT fuel: DIGEST_DEPTH 1 vs 3 measured FLAT in wall-time, so the
  > item-7 hash is well-tuned and the per-key digest cost is not the wall. Tag histogram of the
  > 832K: `.prim` 185K, `.struct` 129K, `.kind` 123K, `.refId` 108K, `.binary` 66K, `.conj` 49K,
  > `.selector` 39K, `.list` 35K — **`.prim`+`.kind` ≈ 37%** are env-INDEPENDENT constants
  > re-keyed per env. The flat-per-field signature holds: `-e "<field>"` fires the identical
  > 832K-eval line because `selectExprPath` does `resolveAndEval root` (the whole-root eval)
  > before the lookup.
  >
  > **Two sound optimizations landed (both jq-S=0, zero fixture drift):** (1) a
  > **self-evaluating-leaf fast path** — `evalValueWithFuel` returns env-independent leaves
  > (`selfEvaluatingLeaf?`: `.prim`/`.kind`/`.top`/`.bottom`/`.bottomWith`/`.notPrim`/
  > `.stringRegex`/`.boundConstraint`/`.thisStruct`) directly, skipping the `valueDigest`-hashed
  > satCache/cache probe+insert per occurrence (these are the core's identity arm; sound by
  > construction); (2) **saturated-only `satCache` insert** — a saturated result lives ONLY in the
  > fuel-free `satCache` (checked first), never in the fuel-keyed `cache` (which now holds only the
  > fuel-TRUNCATED population), eliminating 832K dead `cache` inserts (`evalCacheHits=0` proved them
  > unread). Measured **~53.4s → ~50.3s** (argocd), **~12.6s → ~11.7s** (cert-manager). The win is
  > modest because the leaves are trivial work; the dominant ~50s is the ~175× re-eval of
  > env-DEPENDENT shapes (structs/refs/conjunctions forced under divergent frames), which a leaf
  > bypass cannot touch — see the next-step note below.
  >
  > **Next step (designed, deferred — a dedicated gated slice):** share env-DEPENDENT evaluations
  > across frame envs — more aggressive frame canonicalization (so structurally-identical def
  > bodies forced under different resource scopes collapse to one frame id, hitting the env-keyed
  > satCache), or content-addressing def-body closures independent of the capturing frame. Both
  > touch the soundness core of frame identity (`FrameKey`/`ForceKey` proxy argument) and need a
  > dedicated no-false-share proof — not foldable into a leaf-bypass slice.
  >
  > **perf-#7 frame-sharing fix DESIGNED-AND-DEFERRED — the win does not exist (2026-06-23,
  > measurement-driven REJECTION, NOT a proof-blocker punt).** The dedicated gated slice MEASURED
  > the share ceiling before touching the soundness core, and the data kills the approach. Method:
  > a zero-risk content-addressed SHADOW of `satCache` keyed on the FULL env CONTENTS (`(env,
  > visited, value)` compared by derived structural `BEq`, never read by the result path), counting
  > how many of the `satCache`-miss core evals a content-addressed env key would COLLAPSE (`env`s
  > that are content-identical but id-distinct — exactly the frames a sound canonicalization could
  > merge). Result on the whole-root export:
  >
  > | app          | core evals (`satMisses`) | content-collapsible | ceiling |
  > |--------------|-------------------------:|--------------------:|--------:|
  > | cert-manager |                  317,788 |                 144 |  0.045% |
  > | argocd       |                  486,773 |                 288 |  0.059% |
  >
  > **The ~175× re-eval is REAL but NOT content-redundant.** The profile's `distinctShapes≈4763`
  > counted *shape* similarity at digest-depth 8; the cache keys on *content* (via the sound
  > ids-as-content-proxy). When the same shape is reached under ~175 frame envs, those envs carry
  > ~175 GENUINELY-DIFFERENT observable bindings (distinct resource fields, distinct use-site
  > narrowings) — distinct evaluations that share a top shape but not a resolved value. Collapsing
  > them is a **FALSE SHARE** (serve one resource's value for another → wrong value), which is why
  > the ceiling is ~0%: there are almost no id-distinct-but-content-identical envs to recover. No
  > sound frame-sharing widening (aggressive canonicalization OR content-addressed closure key) can
  > reclaim the ~175× factor — it is the irreducible cost of genuinely-distinct content, not
  > id-divergence waste. **The proof obligation is moot: the share it would license is empirically
  > almost empty AND unsound where non-empty.** The residual ~50s is the per-eval constant over a
  > genuinely-large distinct-eval population, addressable only by lowering the per-eval cost or the
  > eval COUNT (flatten/shorten chains — the user-controllable lever above), NOT by cross-env
  > sharing. perf #7's frame-sharing leg is CLOSED as won't-fix; the live perf frontier rotates to
  > the per-eval constant (item-6 LOW tail / a future per-eval-cost slice).
- **[HISTORICAL] Full `apps/argocd.cue` bottomed — was a CORRECTNESS bug, NOT a perf/fuel
  limit (2026-06-19; RESOLVED 2026-06-23 by the Bug2-x chain — kept for the diagnosis trail).
  Superseded the earlier "fuel-exhaustion-at-scale" and "cross-module import-laziness"
  readings, both DISPROVEN — fuel sweep 100/200/600 + `resolve`/`remapFuel` 100000 all still
  bottomed; it reproduced SAME-MODULE.** Root cause:
  a `parts.#Mixin` comprehension guard reads a use-site-narrowed sibling through a buried
  embed, and the narrowing did not reach the guard. The chain of narrowing fixes — Bug #1
  (single-embed), **Bug2-1** (let-buried read detection), **Bug2-2** (force-tier
  disjunction-arm narrowing for a regular discriminator), **Bug2-3 / Gap-2b** (structural
  list-arm-vs-struct-host disjunction pruning), **Bug2-4** (let-LOCAL declare-and-read
  narrowing), **Bug2-5** (transitive-embed disj-path narrowing injection, `5fca57e`
  2026-06-22), **Bug2-6** (definition multi-declaration close-once: `#Foo: {a}; #Foo: {c}`
  unify-then-close-once, `ef824cb` 2026-06-23), **Bug2-7** (same-def multi-decl close-once
  on the def-REFERENCE / force-fold path, `3361699` 2026-06-23), **Bug2-8** (same-def
  multi-decl close-once ACROSS AN EMBED boundary via a `DeclProvenance` sum, `2332aff`
  2026-06-23), **Bug2-9** (use-site narrowing of a REFERENCED NAMED multi-conjunct def via
  `flattenConjDefRef`, `5d9cf8f` 2026-06-23), **Bug2-10** (use-site narrowing into a
  `.structComp` host's embedded self-ref via `conjStructCompDefer?` + an embed-meet
  closedness-leak fix, `aa4172b` 2026-06-23), **Bug2-11** (use-site narrowing of a
  TWO-LEVEL cross-package def-of-def selector via `conjBodyHasDeferringArm` + `.conj`-body
  capture + a `.conj` force-fold arm, `bdced40` 2026-06-23), **Bug2-13** (an UNSET OPTIONAL
  presence-test `#opt == _|_` / `!= _|_` returns the WRONG polarity — kue resolved the unset
  optional's reference to its declared TYPE, classifying it `.defined`, so `if #service != _|_
  {…}` in `attr.#ServiceRef` fired when it must not, bottoming `#service_port` in `route.yaml`;
  fixed at the selection boundary, `7e69e43` 2026-06-23) — all LANDED. Bug2-5 cut the argocd
  wall **153s → ~54s** but was NOT the final blocker; neither were Bug2-6/2-7/2-8/2-9/2-10
  /2-11/2-13. Bug2-11 advanced the real argocd `listener.yaml` subtree to FULLY narrow and
  Bug2-13 cleared `route.yaml`'s `#service_port`; **Bug2-14 + Bug2-14b/14c** (2026-06-23 —
  the embed-merge frame-binding bug + the disjunction-arm let-local on the cross-package force
  path: `injectEmbedSiblingNarrowings`, `bodyForceFrameEnv`, and the two-pass multi-closure
  `.conj` fold) were the TERMINAL blockers, now LANDED → the full app EXPORTS content-identical.
  **Perf takeaway (was a value-correctness divergence, now CLOSED):** with correctness resolved,
  the ~53s wall (vs cert-manager ~12.6s) is the pure per-eval-constant frontier profiled in the
  block above — a fixed definition/import-closure setup cost, NOT a fuel-axis problem and NOT a
  subtree hot spot. The per-eval constant (not the fuel ceiling) is the live perf frontier
  (item 7 residual); profile the SETUP closure, not argo's outputs.
- **Regex matching is linear (RX-1a/b LANDED 2026-06-19).** The `=~`/`regexp.Match` engine
  is now a Thompson-NFA + Pike-VM in `Kue/Regex.lean` (replaced the old backtracking
  fuel-matcher, which is deleted): LINEAR in `input.length × NFA.size`, NO backtracking
  blowup, NO fuel-out-reads-as-non-match soundness hole — the ε-closure dedups by pc over a
  fixed-size program (fuel = `insts.size`, exact, never spuriously reached). Deeply-nested
  quantifiers (`(a*)*`) terminate and match correctly. The old known-limitation here is
  RESOLVED; the engine no longer has a regex perf cliff. (Remaining regex work is feature
  coverage — RX-1c submatch/`ReplaceAll`, RX-2a in-class perl negation — not perf.)
- **Field ordering** in output may differ from `cue` (`cue` orders `ref & {own}` own-fields
  first; Kue is left-struct first). This is a byte-diffing concern, not a correctness or
  speed one (YAML maps are unordered).

## Reporting a slow case

1. Reduce to a **minimal repro** (smallest CUE that is still slow).
2. Record `kue export` wall-clock vs `cue` on the same input.
3. Note the shape (which expensive pattern above, or a new one).
4. File it in `docs/spec/plan.md` so it becomes a perf slice; if it is a new slow pattern,
   add it to the table here.
