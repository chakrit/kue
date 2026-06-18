# START HERE — fuel-saturation LANDED; cert-manager is a `cue` drop-in now

Supersedes `2026-06-18-perfb-framesharing-forcememo-landed.md`. The real-app PERF gate is
through. Tree clean, pushed. Build 86 jobs, tests 40 jobs (9 new pins), fixtures byte-
identical (+2 new export fixtures), shellcheck clean.

## What landed — fuel-saturation caching (the fuel-multiplication fix)

A result whose ENTIRE transitive eval never hit a `fuel = 0` base nor a cycle `.top` is
SATURATED — fuel-insensitive — and cached FUEL-FREE (`satCache`, key `(envIds, visited,
value)`). TRUNCATED results (the 263 fuel-truncation cases) stay fuel-keyed in `cache`
(`EvalKey`, `fuel` retained), never served across fuel. Pure perf — every fixture byte-
identical.

**Hole closed by construction (bracketing, NOT a per-arm bit).** `EvalState.truncCount` is a
monotonic counter bumped ONLY at the two truncation arms. `evalValueWithFuel` (the single
cached wrapper) brackets it: snapshot before/after the core eval, `saturated := (after ==
before)`. Every transitive truncation flows through the counter, so the bracket sees them all
— no arm classifies, so no arm can forget. Cache value is `(Value × Saturation)`; a truncated
cache/force hit re-bumps the counter (cache-hit honesty) so a truncated value can never
masquerade as saturated to a parent. `satCache` insert is gated to the `saturated` bracket arm
(the single insertion site). `forceCache` is bracketed identically. See `Kue/Eval.lean`
(`Saturation`, `SatKey`, `EvalState`, `evalValueWithFuel`, `forceClosureWithConjunct`).

## REAL-APP VERDICT (the headline)

- **cert-manager: DROP-IN for content.** Exports CORRECTLY at production fuel 100 in ~30 s
  (was: unbounded, killed at 8 min). JSON + YAML both byte-match `cue` modulo field-ordering
  #3 (`jq -S` IDENTICAL). Eval count FLAT across fuel (~290k at any fuel) vs the old 583k→1.05M
  →unbounded growth.
- **argocd: STILL BLOCKED — but by a SEPARATE correctness gap, not perf/fuel.** It produces
  `bottom` (`conflicting values`) at EVERY fuel (8/12/16/20), `mlen=0`. Genuine eval gap, NOT a
  saturation regression (cert-manager stays correct, all fixtures byte-identical). Eval count
  also bounded now (447k→502k fuel 16→20), the ~97 s wall is absolute count × per-eval cost.

## Residual / next levers

- **cert-manager at 30 s is correct but not single-digit-seconds.** Fuel axis solved; residual
  is absolute eval count (~290k) × per-eval constant. Next PERF lever is the per-eval cost (not
  fuel) — profile the hot per-eval path (HashMap ops, struct rebuild, valueTag) if perf is
  pushed further.
- **argocd `bottom`** is the next CORRECTNESS frontier — likely one of the borderline arch
  findings: `module-file-scoped-imports` (sibling-file import merge → cross-file leak; arch-
  sized) or `import-eager-closedness` (MEDIUM), or field-ordering. Bisect which conjunct
  bottoms (reduce argocd to a minimal repro).

## Then (unchanged backlog, pick by philosophy)

- **F1 default-mark `Violation`** (orthogonal correctness; audit #3). Independent.
- **Field-ordering parity #3** (DEEP) — the last thing between cert-manager and byte-EXACT
  `cue`. Per-`Field` provenance through meet/manifest. (cert-manager content already matches;
  this is the byte-order tail.)
- Cleanups: regex / EvalOps / test-org (LOW); `audit4-test-gaps` (LOW).
- **Audit cadence:** fuel-saturation + perfb-soundness-pins landed since the last Phase-A/B.
  The two-phase audit (`docs/guides/slice-loop.md`; do NOT invoke `/ace-audit`) is due — run it
  before/interleaved with the next slice. It should adversarially re-hunt the satCache for a
  cross-fuel false-share (the new soundness-critical surface) on top of the perf-B memos.

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9`. Module root `infra/`; apps
  `infra/apps/*.cue`. defs pinned `prodigy9.co/defs@v0.3.19` in cue cache. READ-ONLY.
- **`fuel` is LOAD-BEARING** in `EvalKey`/`ForceKey` (263 fuel-truncation cases). NEVER drop
  it. The NEW `satCache`/`SatKey` are fuel-FREE but ONLY hold SATURATED results (proven fuel-
  insensitive); a truncated result CANNOT enter them (gated by the bracket). `truncCount` is
  now LOAD-BEARING (drives saturation classification), not transient instrumentation.
- **AUDIT #6 (2026-06-18) found + FIXED a VIOLATION in this slice:** the truncation arms are SIX,
  not two. The four comprehension/embedding-expansion helpers (`expandClausesWithFuel`,
  `expandComprehensionWithFuel`, `evalEmbeddingFieldsWithFuel`, `meetEmbeddingsWithFuel`) each have
  a `fuel=0` arm that drops fields WITHOUT bumping `truncCount` — so a low-fuel comprehension
  truncation was misclassified saturated and served fuel-free at higher fuel (concrete repro:
  `.structComp [] [if true {x:1}] true` served `{}` at fuel 20 after a fuel-2 eval). Fixed by
  bumping all four arms (strict tightening; fixtures byte-identical). 2 regression pins added. See
  plan audit #6. If you add a NEW fuel-threaded helper with a `fuel=0` drop, it MUST bump
  `truncCount` or it reopens this hole.
- **Profiling:** the prof harness is removed; to re-profile, re-add a fuel-parameterized
  `evalFieldRefsListWithFuel fuel topEnv (indexedFields top)` driver over `loadEntry` +
  `resolveStructRefs` + `normalizeDefinitions` and read `EvalState.{evalCalls, satCache.size,
  truncCount}`. Use the COMPILED binary (`kue prof` style), not `lean --run` (interpreter is
  too slow for real apps). `evalFuel = 100` (`Kue/Eval.lean:75`); cert-manager converges at 16.
- **Release:** ~1 alpha/day, `scripts/release.sh` only — CI/Actions BANNED. Did NOT cut one.
  **Safety:** prod9 + cue cache READ-ONLY. `git commit -F /tmp/msg`. NO working-tree-overwriting
  git. cue oracle: `/Users/chakrit/go/bin/cue` (fixtures match).
