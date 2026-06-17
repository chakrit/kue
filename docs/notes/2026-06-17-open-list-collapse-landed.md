# Breadcrumb: open-list collapse on manifest/export landed (2026-06-17)

Audit item 2 closed. A bare open list now manifests/exports as its concrete prefix,
matching `cue export`.

## What landed

- `Kue/Manifest.lean` `listTail items tail` arm: was `.error (.incomplete (.listTail …))`;
  now recurses `manifestItemsWithFuel fuel items` and emits `.list items` (drops the
  open/typed tail), mirroring the existing `embeddedList` arm. A non-concrete prefix
  *element* still surfaces as `.incomplete` via the recursion.
- The INTERNAL `formatValue`/`embeddedList` open-list representation is UNCHANGED — this
  is a manifest/export-path fix only. `testdata/cue/list_embedding_open` fixture unchanged.

## Oracle rule (cue v0.16.1, `/Users/chakrit/go/bin/cue`)

On EXPORT the open tail is always dropped; the concrete prefix becomes a concrete list:
`[1,...]`→`[1]`, `[...]`→`[]`, `[1,2,...int]`→`[1,2]`, `[1,...string]`→`[1]`. No open-list
shape is incomplete because of its tail. Non-concrete prefix *element* IS incomplete:
`[int,...]`→`x.0: incomplete value int`. `cue eval` agrees (`[1,...]`→`[1]`).

## Tests added

- `Kue/ManifestTests.lean` — 6 `rfl` theorems (the four collapse shapes + non-concrete
  prefix incomplete + nested-in-struct).
- `testdata/export/open_lists.cue` + oracle-generated `.json` (bare, empty, typedTail,
  stringTail, closed baseline, nested struct), byte-matched by `check_export_fixtures`.

## Verify state (all green)

- `lake build` — 84 jobs.
- `scripts/check-fixtures.sh` — `fixture pairs ok` (internal-format open-list fixture
  unchanged — no regression).
- `shellcheck scripts/check-fixtures.sh` — clean.

## Next step

**A two-phase `/ace-audit` is due** — this is the 3rd slice since the Phase A/B audit
(int&>0, CLI subcommands, this open-list collapse). Run it over the recent landed work,
fold findings into the plan as fix-slices, then proceed.

After/alongside the audit: the **consolidation + test-reorg batch**:
- `base64` out of `Kue/Json.lean` (decode/encode is not JSON's concern).
- `testdata/` + test-module reorg (the `testdata/cue/` subsystem split).
- `Field` → `structure` (from the type-shape cleanup).
- `intGe`/`intGt`/`intLe`/`intLt` → unified `boundConstraint` (now also carrying the
  decimal/domain bound generalization — see the int-bound breadcrumb).
- Manifest-dispatch wildcard tighten (the long `_ + 1, .X => .incomplete (.X …)` ladder in
  `Manifest.lean` — make exhaustive / drop the wildcard fallthrough where possible).

## Carry-forward

- Alpha cadence: ~1 datestamped cut/day via `scripts/release.sh`, NO CI. Latest is
  `v0.1.0-alpha.20260617.2`. Do NOT touch `scripts/release.sh` / `packaging/` (beyond the
  in-repo formula `test` block) / release files / the tap repo.
- `Kue.version` (`Kue/Runtime.lean`) is where release.sh bumps the in-binary version.
- External repos (prod9, cue cache) are READ-ONLY.
- No tree-reverting git; revert via Edit; `/tmp` for experiments.
