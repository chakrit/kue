# Breadcrumb: YAML scalar over-quoting fix landed (2026-06-17)

## What landed

The `-e` slice's noted divergence is fixed: `kue export --out yaml` now matches `cue`
v0.16.1 on scalar quoting. Dotted-numeric infra strings (IP `34.142.159.249`, semver
`1.2.3`, CIDR `10.0.0.0/8`, image tag `nginx:1.25`) emit **bare**, as cue does; genuine
numbers / bools / nulls / dates / base60 floats stay quoted. Commit on `gh:main`.

- `Kue/Yaml.lean`: replaced the over-broad `yamlLooksNumeric` with a total
  `wouldParseAsNonString` = the exact **union** of the two layers cue composes:
  1. cue's `shouldQuote` — a fixed YAML-1.1 legacy-token set + a date/time/base60/`0x`-hex
     regex (`yamlReservedWords`, `yamlCueShouldQuote` = `yamlCueDateLike` hand-NFA +
     `yamlCueHexLike`). The regex is not range-checked: `2024-13-40` quotes by it.
  2. go-yaml v3's emitter — resolves to int/float (`yamlStyleFloat` hand-NFA on the
     underscore-stripped form, subsuming decimal/legacy-octal ints; `yamlRadixInt` for
     `0x/0o/0b`) or base60 float (`yamlBase60Float`).
  A multi-segment token satisfies none → bare. Removed dead `yamlAsciiLower`/
  `yamlLowerString`. Single/double-quote selection (`yamlNeedsSingleQuote`) unchanged.
- Tests: 38 new `YamlTests.lean` theorems (bare infra tokens + still-quoted
  numbers/bools/nulls/dates/base60). New `testdata/export/infra.{cue,yaml,json}` fixture.
- JSON / internal `formatValue` / non-YAML paths untouched. Totality preserved.

## Oracle method (carry forward — this is how to nail YAML quoting)

The rule was reverse-engineered from the real Go sources in the read-only mod cache, then
every battery case confirmed against `cue export --out yaml`:
- cue: `~/go/pkg/mod/cuelang.org/go@v0.16.1/internal/encoding/yaml/encode.go`
  (`shouldQuote`, `useQuote`, `legacyStrings`).
- go-yaml: `~/go/pkg/mod/go.yaml.in/yaml/v3@v3.0.4/{resolve.go,encode.go}`
  (`resolve`, `stringv`, `isOldBool`, `isBase60Float`, `yamlStyleFloat`).
A 42-case Lean battery diffed `yamlScalarString` vs the oracle: 0 failures.

## Milestone — FLAG FOR ORCHESTRATOR

Whole-file `kue export --out yaml hatari/infra/apps/common.cue` is now **byte-identical**
to `cue` v0.16.1 (`diff` empty). Combined with the `-e` JSON milestone, a real prod9 app
now exports cue-identically in **both** JSON and clean YAML.

**This is the 2nd slice since the last audit (`-e`, then this YAML fix).** A two-phase
`/ace-audit` over the two slices is DUE NEXT before more feature work. After the audit
passes, a fresh datestamped alpha is warranted: **`v0.1.0-alpha.20260617.3`** (real-app
export in JSON + clean YAML). Cut via `scripts/release.sh` — do NOT touch `release.sh`,
`packaging/`, or the tap by hand.

## Next step (after the audit + alpha)

Point at the **cleanup batch** (plan items 2–4), engine-quiet:
1. **tests-out reorg 2c** — move `*Tests.lean` + `FixturePorts.lean` into `Kue/Tests/`
   via a `Kue/Tests.lean` aggregator; split the oversized ones by subsystem (`git mv`).
2. **base64-out-of-Json (3a)** — `base64Encode`/`Decode` → `Kue/Base64.lean`.
3. **`Field`→structure (3e)** — `Field = String × FieldClass × Value` tuple → named
   `structure { label, fieldClass, value }`, ~122 sites via existing accessors.
4. **`cacheRoot`** — Linux default branch on `System.Platform` (`Module.lean`).
Then the larger loader slices: package-dir merge (item 5), registry/module fetch (item 6).

## Standing facts (carry forward)

- Alpha cadence: ~1 datestamped alpha/day via `scripts/release.sh`, **NO CI**. Latest
  `v0.1.0-alpha.20260617.2`; next is `…3` (post-audit).
- External repos (prod9 / cue cache / go mod cache) are **READ-ONLY**. Never mutate
  outside the repo tree.
- Verify gate: `lake build` + `scripts/check-fixtures.sh` + `shellcheck
  scripts/check-fixtures.sh`. Currently green (84 jobs, `fixture pairs ok`).
