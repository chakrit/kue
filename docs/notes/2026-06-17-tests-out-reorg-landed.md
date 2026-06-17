# Breadcrumb: tests-out reorg landed — `Kue/Tests/` (2026-06-17)

## What landed (plan item 2c, tests-out part)

Engine and checks are now separated. All 21 `*Tests.lean` + `FixturePorts.lean` `git mv`'d
out of the flat `Kue/` into `Kue/Tests/`, module paths `Kue.Foo` → `Kue.Tests.Foo`.
Purely organizational — zero behavior/theorem-content change. Commit on `gh:main`.

- **Moved (21):** `BoundTests BuiltinTests BytesTests CliTests EvalTests ExclusionTests
  FixturePorts FixtureTests FloatTests ListTests ManifestTests ModuleTests NormalizeTests
  NumberTests OrderTests ParseTests PresenceTests ResolveTests RuntimeTests StructTests
  YamlTests` → `Kue/Tests/`. Namespaces (`Kue` / `Kue.Cli`) unchanged — they're namespace
  decls, not file paths. Test modules import only engine modules (which did NOT move), so
  the only test→test import rewired was `FixtureTests`'s `Kue.FixturePorts` →
  `Kue.Tests.FixturePorts`.
- **Aggregator:** `Kue/Tests.lean` (was the lattice-theorem module) now imports all 21
  `Kue.Tests.*` and keeps its own theorems. `Kue.lean` imports only `Kue.Tests` (replacing
  ~20 direct test imports) + the 16 engine modules.
- **Scripts:** `scripts/write-fixture-ports.lean` + `scripts/check-fixtures.sh` rewired to
  `Kue.Tests.FixturePorts`.
- **16 engine modules stay in `Kue/`** — source-layering deferred (plan default).

## Silent-test-loss guard (the whole point)

Every test module stays transitively imported: `Kue → Kue.Tests → {21}`. Build is **84
jobs, unchanged vs baseline** (file count didn't change — no split landed), and every
`Kue.Tests.*` module shows as elaborated in the build log. No module compiles-but-unimported.

## Deferred: oversized-module splits (subsumes-3d still open)

`FixturePorts` (2314) / `FixtureTests` (1033) / `BuiltinTests` (735) splits NOT done — landed
the SAFE-FAILURE partial (moves + rewire, fully green) instead. `FixturePorts` is one
monolithic `def fixturePorts : List FixturePort`; its 145 entries are heavily interleaved by
subsystem (54 runs across 11 prefixes: numeric/bounds/disjunctions/structs/definitions/lists/
refs/comprehensions/builtins/multiline/manifest). A "by subsystem" split = brace-block
extraction + reorder of a generated list literal (define `numericPorts`/… then
`fixturePorts := … ++ …`), not a contiguous line cut — the interleaved-surgery risk the
slice flags, against a cosmetic-only payoff on a generated file. The fixture gate WOULD catch
a dropped entry (`missing Lean fixture port`) and order is irrelevant (writer maps by each
entry's own `fileName`), so a future split is safe to attempt — just not worth the churn now.

## Verify gate (all green)

- `lake build` → 84 jobs, all theorems elaborated.
- `scripts/check-fixtures.sh` → `fixture pairs ok` (145 fixture entries unchanged, no
  `.expected` touched).
- `shellcheck scripts/check-fixtures.sh` → clean.

## Next step

Point at the **cleanup batch** (plan items 3–4), engine-quiet:
1. **base64-out-of-Json (3a)** — `base64Encode`/`Decode` → `Kue/Base64.lean` (decode/encode
   is not JSON's concern; `Json`/`Builtin` import it).
2. **`Field`→structure (3e)** — `Field = String × FieldClass × Value` tuple → named
   `structure { label, fieldClass, value }`, ~122 sites via existing accessors.
3. **`cacheRoot`** — Linux default branch on `System.Platform` (`Module.lean`):
   `~/.cache/cue` not `~/Library/Caches/cue` absent `$CUE_CACHE_DIR`/`$XDG_CACHE_HOME`.
Then the larger loader slices: package-dir merge (item 5), registry/module fetch (item 6).
Optionally revisit the deferred FixturePorts/FixtureTests/BuiltinTests splits.

## Standing facts (carry forward)

- Alpha cadence: ~1 datestamped alpha/day via `scripts/release.sh`, **NO CI**. Latest
  `v0.1.0-alpha.20260617.3`. Do NOT touch `scripts/release.sh`, `packaging/`, or the tap.
- External repos (go mod cache, prod9 apps) are **read-only** oracles.
