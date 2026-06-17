# Breadcrumb: decimal/domain-tagged bound semantics (item 2b) landed (2026-06-17)

Plan authoritative item **2b** landed. Closes the last known bound divergence: a bare
`>0` is now a *number* bound (admits int AND float, matching cue), decimal bound literals
parse, and `int & >0` stays int-only. The pre-2b over-strict `>0 & 1.5` → `_|_` is fixed
(now `1.5`).

## Oracle rule (cue v0.16.1, evidence)

- Bare bound = NUMBER domain (admits int+float): `>0 & 1.5` → `1.5`, `>0 & 1` → `1`,
  `>=0 & <=10 & 5.5` → `5.5`.
- `int &` narrows: `(int&>0)&1.5` → ⊥ (int/float conflict), `(int&>0)&5` → `5`. Displays
  `int & >0` (kind conjunct kept).
- `float &` narrows the other way: `float & >0 & 1.0` → `1.0`, `float & >0 & 1` → ⊥.
- Decimal literals parse + compare exactly: `>0.5` parses, `>0.5 & 1.0` → `1.0`,
  `>0.5 & 0.25` → ⊥. `>-1.5 & 0` → `0`, `<3.14 & 3` → `3`.
- `number & >0` → `>0` (redundant kind dropped).

## What landed

- **`boundConstraint (bound : Int) (kind : BoundKind)` → `(bound : DecimalValue) (kind :
  BoundKind) (domain : NumberDomain)`.** `NumberDomain = number | int | float` (proper sum).
  `BoundKind.admits` decimal-compares via `decimalLeValues`/`decimalLtValues`.
- **`DecimalValue` + its parse/compare/format helpers moved `Decimal.lean` → `Value.lean`**
  (so `Value` can carry one; `Decimal.lean` keeps arithmetic/division and reuses via the
  existing import). Added `intDecimal`, `formatBoundLimit`.
- **`meetKindWithBound`** (was `meetKindWithIntBound`): `int`/`float` retain the kind
  conjunct WITHOUT narrowing the bound's domain — the kept kind is the load-bearing guard,
  and leaving the bound at `number` keeps **meet commutative** (a pairwise-reduced range
  can't narrow every member uniformly; it need not — the kind conjunct guards them all).
  This is the key design call: the domain tag is load-bearing only for a *bare* bound.
- **Parse:** `parseBoundValue` via `parseDecimalText` (decimals/negatives parse).
- **conj-sort:** `conjMemberKey`/`conjKeyLe` → `conjMemberLe` (direct value comparator;
  equal-kind bounds compare by `decimalLeValues` so different scales order right).
- Migrated Order/Format/Manifest/Eval + all test/example refs (perl:
  `.boundConstraint N kind` → `.boundConstraint (intDecimal N) kind .number`). Removed dead
  `minInt`/`maxInt`.

## Tests / fixtures

- 7 new `BoundTests.lean` theorems (bare-admits-float, int-rejects-float,
  float-rejects-int, decimal admits/rejects, decimal format, negative-decimal). All
  `native_decide` over the `== … = true` BEq form (`Value` has `BEq`, not `DecidableEq` —
  pure `=` on `Value` fails to synthesize `Decidable`; this bit once, watch for it).
- 3 new fixtures: `bounds/number_bound_float` (`>0 & 1.5`→`1.5`),
  `bounds/decimal_bound_float` (`>0.5 & 1.0`→`1.0`), `bounds/number_range_float`
  (`>=0 & <=10 & 5.5`→`5.5`) — all cue-confirmed, with matching `FixturePorts.lean` entries.
- **No existing `.expected` changed** — no committed fixture hit the over-strict path.

## Verify state (all green)

- `lake build` — 84 jobs.
- `scripts/check-fixtures.sh` — `fixture pairs ok`.
- `shellcheck scripts/check-fixtures.sh` — clean.
- kue CLI matches cue v0.16.1 on every probed case.

## For the orchestrator

This is the **3rd slice since the last `/ace-audit`** (test-reorg, boundConstraint fold,
now 2b). **A two-phase audit is DUE next** — spawn `/ace-audit` over the recently landed
bound/decimal work before more slices; fold findings into the plan as fix-slices.

Then the remaining items, in order: **2c Kue/ reorg (tests-out** — move `*Tests.lean` +
`FixturePorts.lean` into `Kue/Tests/`, subsumes the 3d module-splits of the oversized
`FixturePorts`/`FixtureTests`/`BuiltinTests`), **base64-out-of-`Json`** (3a),
**`Field`→`structure`** (3e), **item 4 Linux `cacheRoot` default**.

Carry forward: **alpha cadence** ~1 datestamped release/day via `scripts/release.sh`, NO
CI (latest `v0.1.0-alpha.20260617.2`); **external repos read-only** (prod9/infra etc.).
