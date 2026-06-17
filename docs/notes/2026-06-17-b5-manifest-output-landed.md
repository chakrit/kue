# Session 2026-06-17 — B5 manifest output landed

Latest resume breadcrumb. Supersedes
[`2026-06-17-b6-encoding-builtins-landed.md`](2026-06-17-b6-encoding-builtins-landed.md).
Resuming **implementation** next session at **B3 — module/import resolution** (the big
one, LAST in the prod9/infra roadmap).

## What was done

Landed **B5 — manifest output**: the first time Kue can EMIT a real manifest. Full record
in [`../reference/implementation-log.md`](../reference/implementation-log.md) ⇒ "Completed
Slice: B5 — Manifest Output". Summary:

- **`kue export [--out yaml|json] [file]`** — additive `cue export`-style CLI mode (default
  `--out json`, file arg or stdin). The no-flag path (`kue < file` / `kue file…` → internal
  `formatValue`) is **unchanged** — no fixture regression.
- **New `Kue/Yaml.lean`** — total `manifestToYaml` + `valueToYaml` matching `cue`'s go-yaml
  v3 emitter on the infra core (2-space nesting, `- ` sequences incl. `- - 1`, `|-` block
  scalars, empty `{}`/`[]`, the exact bare/single/double scalar-quoting decision).
- **`Kue/Json.lean`** — added pretty-JSON (`valueToJsonPretty`, 4-space, source-order),
  the `cue export` default, alongside B6's compact `manifestToJson`.
- **`yaml.Marshal`** builtin via the `yaml.` dotted dispatch (shared `unresolvedOrBottom`).
- 33 `YamlTests.lean` `native_decide` theorems + 4 oracle-matched `testdata/export/` CLI
  fixtures, checked by a new isolated `check_export_fixtures` in `check-fixtures.sh`.

**Milestone proof:** on a k8s Deployment, `kue export --out yaml`/`--out json` are
byte-identical to `cue export`. Verify gate green (`lake build` 74 jobs, `fixture pairs
ok`, `shellcheck` clean).

### Oracle-confirmed (`cue` v0.16.1)

- Default `--out` = json (pretty, 4-space). Scalar quoting matrix as in compat-assumptions.
- **No `---` multi-doc** — top-level list = single YAML sequence; `---` only via
  `yaml.MarshalStream` (deferred). The plan's `---`-for-lists hypothesis was wrong;
  oracle-corrected (cue-correct, not a `cue-divergence`).
- `yaml.Marshal` + `cue export --out yaml` both emit a trailing newline.

### Deferred from B5 (documented in compat-assumptions, not bugs)

- `-e`/`--expression` selection; `yaml.MarshalStream`/`Unmarshal`/`Validate`.
- Exotic go-yaml: flow style, anchors/aliases, complex keys, line folding/wrapping, `>`
  folded style, sexagesimal (cue treats `1:2:3` as bare string — Kue matches).

## Next session — implementation focus: B3 — module/import resolution (THE BIG ONE)

Per `plan.md` Current Focus, B1/B2/B4/B6/B5 are done; **B3 is the final and largest
blocker** — it gates every real `infra/apps/*.cue`. Scope: `cue.mod` deps, loading
`prodigy9.co/defs*` packages from disk, cross-package symbols, multi-file package merge.
"Packages last" = packages are the final and largest blocker, NOT optional. Today builtins
work via implicit dotted names with real `import`s parsed-and-ignored; B3 is the actual
import/module mechanism.

### Carry-forward boundaries (UNCHANGED — all still owed)

- **prod9/infra roadmap:** the real goal is replacing `cue` for `prod9/infra` (and
  `infra-defs`, `infra-stage9`). B3 unblocks the real manifest-producing files. External
  repos (prod9/infra etc.) are **read-only**.
- **PENDING AUDIT — parser+alias batch** (`0795530`/`7ec51a4`/`f6c18b5`/`804f1ca`): the
  `/ace-audit` depth pass over the B1/B2 batch failed 3× on transient API 500s and never
  completed. Orchestrator spot-check cleared the #1 risk (`Value.thisStruct`). A full audit
  is still owed — **re-run when the API is stable**. Do not let it block forward slices.
- **Surfaced candidate gaps (after B3 or interleaved):**
  - **Hidden-field references do not resolve** (`y: _a` where `_a` hidden → bottom; `cue`
    resolves it) — a pre-existing reference-resolution gap.
  - **Open-list `[...]` expressions** — parser gap (also blocks a top-level list literal).
  - **Non-string label patterns `[string]: string`** — parser gap (blocks `secret.cue`).
- **Separators stay permissive** — `a: 1 b: 2` parses as two fields, no error.
- **No `list.Sort`/`SortStable`**; **non-ASCII case folding** passes through; remaining
  `strings`/`math` funcs parked per Current Focus (core-language over stdlib).
- **Multiline bytes interpolation deferred** (B4).

## Alpha status

v0.1.0 staged; cut locally via **`scripts/release.sh`** on chakrit's "cut a slice" command
(**NO GitHub Actions — banned**; there is no `.github` dir, do not create one; release
tooling owned elsewhere — do **not** touch `scripts/release.sh` / `packaging/`).
