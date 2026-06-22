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
- **Full `apps/argocd.cue` bottoms — a CORRECTNESS bug, NOT a perf/fuel limit
  (2026-06-19; supersedes the earlier "fuel-exhaustion-at-scale" and "cross-module
  import-laziness" readings, both DISPROVEN — fuel sweep 100/200/600 +
  `resolve`/`remapFuel` 100000 all still bottom; it reproduces SAME-MODULE).** Root cause:
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
  capture + a `.conj` force-fold arm, `bdced40` 2026-06-23) — all LANDED. Bug2-5 cut the
  argocd wall **153s → ~58s** but was NOT the final blocker; neither were Bug2-6/2-7/2-8/2-9
  /2-10/2-11. Bug2-11 advanced the real argocd `listener.yaml` subtree to FULLY narrow, but
  the full app STILL bottoms. The residual full-app blocker is now **Bug2-13** (a
  presence-test `#opt == _|_` / `!= _|_` on an UNSET OPTIONAL field returns the WRONG
  polarity — kue resolves the unset optional's reference to its declared TYPE, classifying it
  `.defined`, so `if #service != _|_ {…}` in `attr.#ServiceRef` fires when it must not,
  bottoming `#service_port` in `route.yaml`; see the Bug2-13 filing + DESIGN NOTE in
  `spec-conformance-audit.md`), PARKED as a stress-test finding — do NOT chase it with
  app-specific narrowing. **Perf takeaway:** this is a value-correctness divergence, not a
  fuel/perf cliff. The ~54s wall (vs cert-manager ~30.5s) is a separate downstream per-eval
  concern on the heavy `argo` sub-package, meaningful only once argocd actually exports —
  gated behind **Bug2-13**, not a fuel-axis problem. The per-eval constant (not the fuel
  ceiling) is the live perf frontier (item 7 residual).
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
