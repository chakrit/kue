# Breadcrumb: base64 out of `Json` → `Kue/Base64.lean` (2026-06-17)

## What landed (plan item 3a)

base64 is not JSON, so `base64Encode` + `base64Alphabet` moved out of `Kue/Json.lean` into a
new leaf module `Kue/Base64.lean`. Pure code move — identical output, no logic touched.
Commit on `gh:main`.

- **New `Kue/Base64.lean`** — imports nothing (depends only on `List UInt8`/`Char`/`Array`/
  `String`). Sits at the BOTTOM of the layer graph, below `Manifest`/`Json`/`Yaml`/`Builtin`
  — no cycle possible (Base64 imports nothing from them).
- **Consumers re-pointed** with explicit `import Kue.Base64`: `Json.lean` (bytes → base64
  JSON string), `Yaml.lean` (bytes scalar), `Builtin.lean` (`base64.Encode` builtin). Each
  uses `base64Encode` directly, so each imports it directly rather than leaning on the
  transitive `Json → Yaml → Builtin` chain.
- **`Kue.lean`** umbrella gained `import Kue.Base64`.
- **`Module.lean` untouched** — its `encoding/base64` is a recognized-import *string* in the
  builtin-import list, not a call into the function.

## Verify gate (all green)

- `lake build` → 86 jobs, success.
- `scripts/check-fixtures.sh` → `fixture pairs ok`. No `.expected` touched; base64/json/yaml
  fixtures (`base64_encode`, `encoding_infra_chain`) unchanged.
- `shellcheck scripts/check-fixtures.sh` → clean.

## Next step

Continue the cleanup batch (plan items 3–5), engine-quiet:

1. **`Field`→structure (3e)** — `Field = String × FieldClass × Value` tuple → named
   `structure { label, fieldClass, value }`, ~95–122 sites via existing accessors.
2. **`cacheRoot` (item 4)** — Linux default branch on `System.Platform` (`Module.lean`):
   `~/.cache/cue` not `~/Library/Caches/cue` absent `$CUE_CACHE_DIR`/`$XDG_CACHE_HOME`.
3. Then the larger loader slices: **package-dir merge (item 5)**, **registry/module fetch
   (item 6)**.

Optionally revisit the deferred `FixturePorts`/`FixtureTests`/`BuiltinTests` oversized-module
splits (subsumes-3d).

## Standing facts (carry forward)

- Alpha cadence: ~1 datestamped alpha/day via `scripts/release.sh`, **NO CI**. Latest
  `v0.1.0-alpha.20260617.3`. Do NOT touch `scripts/release.sh`, `packaging/`, or the tap.
- External repos (go mod cache, prod9 apps) are **read-only** oracles.
