# START HERE — Perf B partial landed; the REAL blocker is fuel multiplication

Supersedes `2026-06-18-valueclosure-import-selector-alias-landed.md`. Commit `4dbc62c`,
pushed. Tree clean. Build 86 jobs, tests 40 jobs (8 new perf-B pins), fixtures byte-
identical, shellcheck clean.

## What landed (perf B — PARTIAL, two SOUND memos)

Both are pure perf — every fixture byte-identical, `fuel` kept load-bearing in every key.

1. **Canonical frame-id sharing.** `pushFrame` (`Kue/Eval.lean`) reuses the id of a
   structurally-identical earlier push under the same parent id-stack (`FrameKey =
   (parentIds, fields)`). The `EvalKey` (keyed on `env.ids`) then hits the memo. Synthetic
   deep-INLINE `{a: B, b: B}` (each level inlines the same body twice): **exponential →
   linear** — depth 8 `767 → 18` evals (42×), depth 12 `12287 → 26` (472×).
2. **Closure-force memo.** `forceClosureWithConjunct` split into a cached wrapper +
   `...Core`, keyed on `ForceKey = (fuel, capturedEnv.ids, body, useOperands)`. It bypassed
   `EvalKey` entirely before, so a `pkg.#Def` referenced N times re-forced N times.

8 pins in `Kue/Tests/EvalTests.lean`: 4 perf/value (`eval_deep_inline_*`), 4 soundness
(`frame_share_identical`, `frame_no_share_different_fields`, `_different_parent`,
`_closed_vs_open`). Transient instrumentation: `evalCalls`/`cacheHits` in `EvalState`,
`evalStructRefsCalls`/`runEvalStats` — cheap, used by the perf pin; do not remove.

## THE REAL BLOCKER — fuel multiplication (NEXT SLICE)

The recon's "exponential frame-id divergence" was ONE component (~30%), not the whole. The
dominant real-app cost is FUEL MULTIPLICATION. Re-profiled cert-manager.cue (read-only):

- Value CONVERGES at fuel ~16: at fuel 16 → CORRECT output, byte-matches `cue` except
  field-ordering #3. Fuel 8/12 → `incomplete value` (chain ~16 deep).
- `evalFuel = 100` re-derives the converged value across 84 wasted levels at ~1.35×/level
  → effectively infinite (full-fuel run killed at 8 min CPU, never finished).
- The two memos cut ~30% (fuel 8: `84.5k → 60.3k` evals) but CANNOT touch the fuel axis:
  `fuel` is in every key, load-bearing (the 263 fuel-truncation cases).

**HEADLINE:** cert-manager produces the CORRECT value but only at lowered fuel; at production
fuel 100 it is still too slow → Kue is NOT yet a `cue` drop-in for these apps. argocd: same
wall, worse (larger). The fuel-saturation slice is the gate.

### Next slice: fuel-saturation caching (DESIGN in plan.md "Perf B" section — has a HOLE)

INVARIANT: a result whose subtree never hit `fuel = 0` (nor a cycle-bound `.top`) is fuel-
INSENSITIVE — identical at all higher fuel. So track a "saturated" bit and cache saturated
results FUEL-INDEPENDENTLY (key `(env.ids, visited, value)`), collapsing the 84 re-derivations
to one. Sound BECAUSE it keys apart exactly the 263 truncation cases (those are unsaturated).
**THE HOLE (close in a spike before implementing):** the saturated bit must thread through the
ENTIRE eval-core return type; one arm forgetting to propagate `unsaturated` silently caches a
truncated value → corruption. This IS the "behavior-changing perf hack you cannot guarantee"
the brief says to STOP on — its own slice, own TDD. Pin: a value that genuinely differs by fuel
must NOT be saturation-cached; a converged value MUST be. Do NOT fold into a sharing slice.

## Then (after perf is usable, or in parallel if perf stalls)

- **F1 default-mark `Violation`** (orthogonal correctness; audit #3). Independent.
- **Two BORDERLINE arch gaps** (audit #4): `module-file-scoped-imports` (kue merges sibling
  files' imports into one frame — cross-file leak; arch-sized) and `import-eager-closedness`
  (imported+closed+no-sibling-self-ref+plain-`.struct` def admits extra fields; MEDIUM).
- **Field-ordering parity #3** (DEEP) — the only thing between cert-manager-at-fuel-16 and
  byte-exact `cue`. Per-`Field` provenance through meet/manifest.
- Cleanups: `audit4-test-gaps` (LOW).

## Audit cadence — OVERDUE

Slices A/C/E/F2/import-alias/perf-B have landed since the last Phase-A/B pass. The two-phase
audit per `docs/guides/slice-loop.md` (do NOT invoke `/ace-audit`; follow the guide) is well
past the 2-3-slice mark. Run it before/interleaved with the fuel-saturation slice.

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9`. Module root `infra/`; apps
  `infra/apps/*.cue`. defs pinned `prodigy9.co/defs@v0.3.19` in cue cache. READ-ONLY.
- **`fuel` is LOAD-BEARING** in `EvalKey`/`ForceKey` (263 fuel-truncation cases). NEVER drop it.
- **Profiling:** set `evalFuel` (`Kue/Eval.lean:76`) low (8/12/16) for fast iteration, ALWAYS
  restore to 100. `runEvalStats` returns `(result, evalCalls, cacheHits)`. cert-manager
  converges at 16. A scratch driver calling `loadEntry "<path>"` + `runEvalStats
  (evalStructRefsM (resolveStructRefs value))` localizes blowup; run via `LEAN_PATH=.lake/
  build/lib/lean lake env lean --run scratch.lean`. Delete scratch when done.
- **Release:** ~1 alpha/day, `scripts/release.sh` only — CI/Actions BANNED. Did NOT cut one.
  **Safety:** prod9 + cue cache READ-ONLY. `git commit -F /tmp/msg`. NO working-tree-overwriting
  git. cue oracle: `/Users/chakrit/go/bin/cue` v0.16.1 (note: earlier notes say v0.16.1; the
  installed binary reported in this session matched fixtures).
