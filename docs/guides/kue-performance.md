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

— the per-level cost is paid only up to the depth where the value converges, independent of
the fuel ceiling above it. A value that settles at shallow depth is cheap. A value that only
stabilizes after many fuel levels — deep self-reference, long indirection chains — pays its
per-level cost up to the depth where it converges; once a subtree converges it is cached
*fuel-independently* and never re-derived at higher fuel.

**Saturation caching collapses fuel to convergence depth.** Any result whose entire subtree
never ran out of fuel (never hit the `fuel = 0` base nor a cycle cut) is *saturated* — proven
fuel-insensitive — and cached under a fuel-free key, so it is computed ONCE regardless of the
ceiling. A deeply self-referential config that converges at a shallow fuel level is therefore
evaluated a flat number of times at any ceiling. Results that genuinely *do* depend on fuel
(cycle-truncated values) stay fuel-keyed and are served only at their own fuel level, so the
caching is purely a speedup — byte-identical output.

## Expensive patterns (minimize these)

| Pattern | Why it is slow | Faster shape |
|----------------------------------|--------------------------------------|----------------------------------|
| Deep self-referential defs — `#D: Self={ … Self.#x … }` chained many levels | Raises the *convergence depth* (the per-level cost is paid only up to the depth where it settles) | Flatten; resolve shared values once at a shallow level and reference them |
| Long alias / selector chains — `#A: parts.#M`, `#B: #A`, `#C: #B`, … | Each hop adds convergence depth (still paid once per level up to convergence) | Reference the terminal value directly where practical |
| Deep cross-package embed chains — `#Outer{ pkg.#Mid{ pkg.#Inner } }` | Correct, but each embedded level adds convergence depth | Keep embedding shallow; prefer a few wide defs over many nested ones |
| Gratuitously duplicating a large sub-expression across fields | Historically caused exponential blow-up | Mitigated by frame-id sharing (see below); still cheaper to bind once and reference |
| A field reading `Self.<label>` where `<label>` comes from an EMBEDDING (`type: Self.#type` with `#type` from an embedded `(*_#A \| …)` or `parts.#X`) | Triggers a second pass over the struct's static fields (the embedded label is not in the frame on the first pass) — cost ~2x for that struct only, gated so it fires solely on a genuine such selection | Read the embedded field directly where the embed declares it, or lift the shared value to a sibling field of the host |
| An EMBEDDING VALUE reading `Self.<label>` where `<label>` comes from a SIBLING embedding (`[{name: Self.#name}]` with `#name` from a `#Meta` embed — the list-embed analog of the row above) | Re-evaluates the struct's EMBEDDINGS (not just static fields) against the label-augmented frame — both `evalEmbeddingFieldsWithFuel` and the `meetEmbeddingsWithFuel` re-run, so the cost is ~2x the embedding fold for that struct. Gated on `embeddingsReadEmbeddedSelf` (fires only when an embedding genuinely reads a sibling-embedded `Self.<L>`); byte-identical no-op otherwise. On an embedding-heavy struct (many/large list embeddings) the doubled fold is the dominant cost, not the cheaper static-field re-pass | Read the embedded field directly inside the embedding where the embed declares it, or lift the shared value to a sibling static field of the host so the static-field two-pass (cheaper) handles it instead |
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
  under multiple fields (`{a: B, b: B}`) is linear: frame-id sharing reuses one frame for
  structurally-identical pushes under the same scope. You still pay convergence depth, so
  deep duplicated nesting is cheaper avoided, but flat duplication is fine.
- **Forced cross-package def-meet is memoized**, so repeated use of the same imported def
  with the same use-site does not re-evaluate from scratch.
- **Converged subtrees are cached fuel-independently** (fuel-saturation caching). Once a
  value settles below the fuel ceiling it is served from cache at any higher fuel. The only
  values that re-derive per fuel level are genuinely fuel-sensitive ones (cycle-truncated),
  which is correct, not waste.
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
  reverse-declaration, an unordered-map detail, not correctness.) The bound fires only on
  closed multi-ref cycle re-entry, so ordinary configs are byte-identical before and after
  and the single-ref cycle is unchanged. The multi-ref cases (2/3/4-way, genuine-extra-reject,
  open-tail, split-literal, duplicated back-ref) are fast `native_decide` pins.
- **Env-independent leaves skip the cache entirely** (perf-#7 leaf fast path). A scalar/closed
  constant (`.prim`/`.kind`/`.top`/`.bottom`/`.notPrim`/`.stringRegex`/`.boundConstraint`/
  `.thisStruct`) is the identity of evaluation, so `evalValueWithFuel` returns it directly
  without an env-keyed cache probe+insert. On a deep app these are ~37% of all core evals (each
  re-reached under many distinct frame envs); bypassing them is a pure, value-identical speedup.
  Only the fuel-TRUNCATED population now occupies the fuel-keyed `cache`; everything saturated
  lives solely in the fuel-free `satCache`.

## Known limitations (current)

- **Absolute per-eval cost on deep configs.** A deeply self-referential config with long
  `Self=` def chains exports correctly at the production fuel ceiling, but the absolute eval
  count (hundreds of thousands of core evals) × the per-eval constant still costs ~tens of
  seconds. An open definition that embeds a self-ref def (`{ embed; …; ... }`) routes through
  the single-`.structComp` two-pass embed-re-evaluation path — sound and correctness-required,
  more expensive than a flat representation. The perf lever here is the per-eval constant and
  the eval count, not the fuel ceiling. The practical advice above (flatten, shorten chains →
  lower convergence depth → fewer evals) is the lever you control.
- **The embedding-`Self` two-pass is bounded (Pass-2 selective re-eval).** When a definition
  reads `Self.<label>` for a label supplied by an embedding, Kue runs a second pass over an
  augmented frame. Pass 2 re-evaluates ONLY the fields that depend (directly or transitively via
  a sibling `Self.<L>` read) on an embedded label — the rest reuse their Pass-1 value, byte-identical
  (a non-dependent field's value is frame-id-independent under the augment). This helps defs with
  dozens of fields and a handful of `Self.<embed>` reads; on a deep config whose cost is dominated
  by broader frame-id divergence (see below) it does not move the wall-clock.
- **Cache-key hash deepened to a bounded-depth digest — O(N²) memo lookups FIXED (item 7,
  landed 2026-06-19).** The `EvalKey`/`SatKey` hashes used to key on `valueTag` (the top
  constructor tag only) + `envIds.LENGTH`, so at a deep config's steady state every distinct
  `.struct`/`.selector` value at the ceiling fuel collided into ONE hash bucket; each
  `cache.get?` then ran structural `BEq` over the full value tree against every colliding
  entry → O(N) per lookup, O(N²) total. The fix swaps in `valueDigest DIGEST_DEPTH` (depth 3)
  — a TOTAL, fuel-free, bounded-depth structural digest mixing each constructor's tag with its
  field labels + child digests — and hashes the FULL `envIds` (not `.length`). It is provably
  sound by construction: a hash only selects a bucket, `BEq` (UNCHANGED) is the sole
  equality arbiter, so a lossy digest can only cause a recompute-miss or collide-scan
  (slower), never a wrong value — proven by zero fixture byte-drift. On a deep real config the
  measured effect is roughly a 4× speedup. A bucket-distribution `native_decide` pin witnesses
  1000 distinct k8s-shaped structs → 1000 distinct buckets at depth 3 (vs 1 under the old
  `valueTag` hash). `FrameKey`'s hash was profiled with the same deepening and showed ZERO
  change (frame sharing + `parentIds` already discriminate the table), so it was left shallow.
- **A large real config's residual wall (~tens of seconds) is the per-eval-constant
  frontier, not fuel and not a subtree hot spot.** Profiling (instrumented cache probes,
  `KUE_PROFILE=1`) characterizes it:
  - **The cache/hash machinery is ~2-3% of per-eval cost.** A fully-saturating program never
    inserts into or reads the fuel-keyed `cache` (it stays empty); the sound empty-`cache`-skip
    (probe only when `!cache.isEmpty`, eliding a redundant `valueDigest` traversal per core
    eval) moved the wall ~2%. The remaining ~97% is genuine `evalValueCoreWithFuel` work —
    struct/ref force-closures, conj meets, selectors — over a genuinely-distinct-content
    population.
  - **The shape re-eval factor is REAL but NOT content-redundant.** The same value *shape* is
    reached under many distinct frame envs; those envs carry genuinely-different observable
    bindings (distinct resource fields, distinct use-site narrowings), so they are distinct
    evaluations that share a top shape but not a resolved value. A content-addressed shadow
    measured the share ceiling at <0.1% — collapsing these envs would be a FALSE SHARE (serve
    one value for another → wrong value). No sound frame-sharing widening can reclaim the
    factor; it is the irreducible cost of distinct content, not id-divergence waste. Cross-env
    sharing is WON'T-FIX.
  - **Sound speedups landed** (all byte-identical, zero fixture drift): a self-evaluating-leaf
    fast path (env-independent leaves skip the digest-hashed cache probe), saturated-only
    `satCache` insert (the fuel-keyed `cache` holds only the truncated population), and the
    empty-`cache`-skip above.
  - **The only lever left is the eval COUNT** — flatten / shorten chains (the expensive-patterns
    table above). The floor is the genuine meet work, not recoverable cache/hash overhead.
- **Regex matching is linear (RX-1a/b LANDED 2026-06-19).** The `=~`/`regexp.Match` engine
  is now a Thompson-NFA + Pike-VM in `Kue/Regex.lean` (replaced the old backtracking
  fuel-matcher, which is deleted): LINEAR in `input.length × NFA.size`, NO backtracking
  blowup, NO fuel-out-reads-as-non-match soundness hole — the ε-closure dedups by pc over a
  fixed-size program (fuel = `insts.size`, exact, never spuriously reached). Deeply-nested
  quantifiers (`(a*)*`) terminate and match correctly; there is no regex perf cliff. Remaining
  regex work is feature coverage — RX-1c submatch/`ReplaceAll`, RX-2a in-class perl negation —
  not perf.
- **Field ordering** in output may differ from `cue` (`cue` orders `ref & {own}` own-fields
  first; Kue is left-struct first). This is a byte-diffing concern, not a correctness or
  speed one (YAML maps are unordered).

## Reporting a slow case

1. Reduce to a **minimal repro** (smallest CUE that is still slow).
2. Record `kue export` wall-clock vs `cue` on the same input.
3. Note the shape (which expensive pattern above, or a new one).
4. File it in `docs/spec/plan.md` so it becomes a perf slice; if it is a new slow pattern,
   add it to the table here.
