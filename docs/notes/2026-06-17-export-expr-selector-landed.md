# Breadcrumb: `kue export -e <expr>` selector landed (2026-06-17)

## What landed

`kue export -e <path> <file>` (and `--expression`) — select a dotted field path from the
evaluated root and export just that value, no wrapper, byte-matching `cue export -e` (JSON
+ YAML), file and stdin modes. Closes Phase-B-audit **item 1**, the real-file export
unblock. Commit on `gh:main`.

- `Kue/Cli.lean`: `ExportOpts.expr : Option String`; `parseExport` arms for
  `-e`/`--expression` (+ missing-value errors).
- `Kue/Runtime.lean`: `lookupField?`, `selectExprPath` (resolves between segments),
  `parseExprPath`, `exportValueSelecting`.
- `Main.lean`: `exportBoundValue` honors `opts.expr`; stdin path inlined so selection
  applies there too.
- Tests: 7 new `CliTests.lean` theorems; `testdata/export/select_common.*` with an `.args`
  sidecar convention (one arg/line) wired into `check_export_fixtures`; missing-field
  non-zero-exit assertion in `check_cli_behavior`.

## Scope / deferrals

Dotted field paths only. Deferred (clean later adds): index/slice (`a[0]`), repeated `-e`
→ multi-doc, arbitrary CUE expressions as the selector. See compat-assumptions for detail.

## Milestone — FLAG FOR ORCHESTRATOR

**A real self-contained prod9 app now exports cue-identically.** Read-only check:
`hatari/infra/apps/common.cue` → `kue export -e common` and `-e common.domains` JSON-match
`cue` v0.16.1 exactly. This is the "kue exports a real apps file" milestone the plan
targeted — **worth a fresh datestamped alpha** (latest is `v0.1.0-alpha.20260617.2`; next
would be `…20260617.3`). Cut via `scripts/release.sh` (alpha cadence ~1/day, NO CI).

## Known pre-existing divergence (NOT this slice, do not chase)

kue's YAML serializer quotes a dotted-numeric-looking string (`"34.142.159.249"`) where
`cue` emits it bare. JSON matches exactly. Reproduces on a whole-file `--out yaml` with no
`-e` — it's a YAML scalar-quoting policy gap in the serializer, independent of the
selector. Candidate cleanup if YAML byte-parity on real files is wanted.

## Next step (cleanup batch, then loader reach)

Drain the churn-heavy cleanup batch while the engine is quiet (plan items 2–4):
1. **tests-out reorg 2c** — move remaining `*Tests.lean` shape per plan.
2. **base64-out-of-Json** — encoding selector / base64 machinery off the `Json` module.
3. **`Field` → `structure`** — `Field = String × FieldClass × Value` tuple → named struct.
4. **`cacheRoot`** — factor the cache-root resolution helper.

Then the larger loader slices: **package-dir merge** (item 5 — `cue export ./apps` merges
sibling `*.cue` in a package; kue exports one file) and **registry/module fetch** (item 6,
B3d). Schedule those only for full `cue export ./apps` parity.

## Standing facts (carry forward)

- Alpha cadence: ~1 datestamped alpha/day via `scripts/release.sh`, **NO CI**. Latest
  `v0.1.0-alpha.20260617.2`.
- External repos (prod9 / cue cache) are **READ-ONLY**. Never mutate outside the repo
  tree.
- Verify gate: `lake build` + `scripts/check-fixtures.sh` + `shellcheck
  scripts/check-fixtures.sh`. Currently green (84 jobs, `fixture pairs ok`).
