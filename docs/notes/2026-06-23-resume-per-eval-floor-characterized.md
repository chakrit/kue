# RESUME — per-eval-constant PROFILED + floor-characterized (perf frontier CLOSED) (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-release-tooling-hardened.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).
Served status page: [`../../www/index.html`](../../www/index.html).

## Just landed — per-eval-CONSTANT perf: profiled + empty-`cache`-skip + FLOOR characterized

The one remaining user-visible perf issue (argocd ~52.8s vs cue 0.03s) is now CLOSED as a
characterized floor. Profiled `evalValueWithFuel`'s cache-probe path (transient counters,
`KUE_PROFILE=1` env-gated stderr dump retained as a diagnostic):

- **Both apps FULLY SATURATING.** `evalCalls=486741` (argocd) / `317768` (cert-manager),
  `satMisses==evalCalls` (every core eval misses satCache), and **`fuelHits=fuelInserts=0`** —
  the fuel-keyed `cache` is NEVER inserted/read; it stays empty the whole run (zero truncation).
- **The waste found + fixed:** on every satCache miss the wrapper still built an `EvalKey` and
  probed the empty fuel-`cache`, recomputing the SAME depth-3 `valueDigest` the satCache probe
  just did. Landed the sound **empty-`cache`-skip**: probe only when `!cache.isEmpty` (empty
  HashMap → `get? = none` for every key → value/saturation-identical; `@[inline]` O(1)). The
  `EvalKey` is now built only in the `.truncated` insert arm. A truncating program is unchanged.
- **Measured win is at the noise floor — which IS the finding.** argocd ~52.8s → ~51.8–52.3s
  (~1-2%), cert-manager flat ~11.8s. The cache/hash machinery is ~2-3% of per-eval cost; the
  remaining ~97% is genuine `evalValueCoreWithFuel` meet/force/resolve work (tag histogram
  `.struct` 129K / `.refId` 108K / `.conj` 49K / `.selector` 39K) over a genuinely-distinct
  population. **argocd ~52s ≈ ~486K necessary core evals × the irreducible per-meet cost; no
  sound per-eval win exists without lowering the eval COUNT — which is content-irreducible**
  (cross-env sharing = false-share, perf #7 WON'T-FIX). Per-eval-constant frontier CLOSED.

Byte-identity argument (implementation-log): pure dead-branch elimination —
`cache.isEmpty → cache.get? key = none` is a HashMap invariant, so the value threaded onward is
identical for every input; digest stays a bucket selector, `BEq` the sole arbiter. Zero fixture
drift, full `native_decide` suite green, both canaries jq -S = 0.

## Verify

`lake build` clean (112 jobs, full suite incl. `EvalPerfTests` count + cross-fuel saturation pins
— the skip changes the PROBE path, not the eval COUNT or satCache serving). `check-fixtures.sh`
ZERO drift. Canaries from `prod9/infra`: **argocd jq -S = 0 (51178 B, ~52s)**, **cert-manager
jq -S = 0 (~11.8s)**. No shell touched (no `shellcheck` needed). No `partial`/`sorry`/axiom; no
`cue-divergences`/`cue-spec-gaps` (no value change).

## State — audit counter = 3. 🚨 TWO-PHASE AUDIT DUE before the next FORWARD slice.

Per [`../guides/slice-loop.md`](../guides/slice-loop.md): sequential **(A) code-quality**
(correctness, totality, illegal-states, DRY, test strength, skill compliance over the batch —
parser-strictness + release-tooling + this per-eval slice), then **(B) architecture/refactor/
cleanup** (module boundaries, layering, dead code, simplification over the module graph). The
`KUE_PROFILE` hook in `Main.lean` + the `evalStructRefsProfile`/`resolveAndEvalProfileString`
accessors are a legit retained diagnostic — audit may decide whether they belong in a test/CLI
seam vs Runtime. Fold findings into the plan as fix-slices; don't stall forward motion.

## NEXT — after the audit, pick the next leader (resolve by philosophy; none soundness-bearing)

Spec-conformance backlog EMPTY (every correctness item RESOLVED; argocd + cert-manager
content-identical drop-ins). Ranked candidates:

1. **item-6 LOW tail** in `plan.md` — A2-x/y (importBinding merge-asymmetry + import-name
   redeclaration check), B2 (typed-ellipsis tail thread + test-gap), `module-file-scoped-imports`
   (arch-sized per-file import scoping), `resolveEmbeddedDisjDefault` distribution check, DRY
   `selectEvaluatedField .disj`. None soundness-bearing.
2. **SC-3** display-gap (multi-arm-default display-collapse — cosmetic Format-layer projection).
3. ~~per-eval-CONSTANT perf~~ — **CLOSED this slice** (floor characterized; cache/hash ~2-3%,
   the rest is irreducible meet work). The only remaining perf lever is user-controllable
   (flatten/shorten chains, `kue-performance.md`).

## Release

`v0.1.0-alpha.20260623` is the latest cut. The parser-strictness + release-tooling + this
per-eval slice are candidates to ride the next datestamped alpha (per the slice-loop ~1/day
cadence). The empty-`cache`-skip is a sound speedup; the byte-identical canaries make it
release-safe.

## Live state end
