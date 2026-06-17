# Breadcrumb: boundConstraint fold + canonical conj sort landed (2026-06-17)

Plan authoritative items **1 + 2a** landed together (they share `meetConjValueWith`'s
re-wrap + the canonical comparator). Both **behavior-preserving**: no `.expected` file
changed, every theorem value identical, no `rfl`→`native_decide` switch needed. The
decimal/number-domain bound *semantics* change (item **2b**) is the explicit next bound
item and is NOT in this slice.

## What landed

- **`intGe/Gt/Le/Lt` → one `boundConstraint (bound : Int) (kind : BoundKind)`.**
  `BoundKind = ge|gt|le|lt` in `Value.lean` with helpers `lower`/`strict`/`symbol`/`rank`/
  `admits`. Representation chosen **extensible toward 2b** (widen `bound` to `Decimal`, add
  a domain tag) without reshaping the arms — but `Int`-valued and int-only-accepting now.
- **Meet machinery folded** in `Lattice.lean`: `meetIntGe/Gt/Le/Lt`/range-prim →
  `meetBoundPrim` (one `BoundKind.admits` comparator) + `meetRangePrim`; pairwise bound
  arms → `meetTwoBounds` (`tightenSameSide` + `rangeFeasible` → canonical `lower & upper`
  conj); `join` → one same-kind-widens arm.
- **Canonical `.conj` member sort.** `conjMemberKey` (kind by `kindRank`, then bounds by
  `(BoundKind.rank, limit)`, then `notPrim` by excluded-prim string, then `stringRegex` by
  pattern length-then-string, then residual) + `conjKeyLe` + `sortConjMembers`, applied in
  `meetConjValueWith`'s re-wrap. `meet a b == meet b a` now holds on the canonical form;
  matches cue's kind-first display order. Closes the Phase-A `a & b ≠ b & a` hazard.
- **Migrated:** `Order.lean` (`boundSubsumesBound`, same-comparator-only), `Format.lean`
  (one arm via `BoundKind.symbol`), `Parse.lean` (`parseIntBoundValue` takes a `BoundKind`),
  `Manifest.lean`, `Eval.lean` (`valueTag`, renumbered contiguous 7→28), `Examples.lean`,
  all 7 test modules (perl rewrite of `.intGe N`→`.boundConstraint N .ge` etc.).
- **Commutativity theorems** added in `BoundTests.lean`: bound-pair, strict-pair,
  kind+bound, 3-way conj, bound+notPrim, canonical-member-order — `native_decide` over the
  `==`/`= true` BEq form (`Value` has `BEq`, not `DecidableEq`, so `=` isn't decidable).

## How coverage was verified

The ~130 migration sites were NOT chased by grep/wc (the session filter flip-flops).
Instead: **removed the old four ctors entirely, let `lake build` error on every unmigrated
site, iterated build→fix to green.** That is the exhaustive coverage proof. Final
`grep intG* Kue/` → NONE REMAIN, but the build is the ground truth.

## Behavior-preserving evidence

- int-bound behavior identical: `int & >0` stays `int & >0`; `(int&>0)&1.5`→⊥; `>0 & 1.5`→⊥
  (still stricter than cue — 2b territory, NOT touched).
- **No `.expected` file changed** (`git diff --name-only -- 'testdata/**/*.expected'`
  empty) — the conj-sort matched cue's existing kind-first order everywhere observable, so
  no oracle-confirmed `.expected` order-updates were needed.

## Verify state (all green)

- `lake build` — 84 jobs.
- `scripts/check-fixtures.sh` — `fixture pairs ok`.
- `shellcheck scripts/check-fixtures.sh` — clean.

## Next step

**Item 2b — decimal/domain-tagged bound semantics.** Add a numeric domain tag to
`boundConstraint` (bare `>0` becomes number-typed, admits `1.5` matching cue; `int & >0`
narrows to int) + a `Decimal`-valued bound (`>0.5` parses, float-domain comparison). This
is where bare `>0 & 1.5` starts matching cue. Same `meetBound*`/`Format`/`Parse` arms; the
2a fold left the rep one field short on purpose.

Then the remaining item-3 deferred sub-tasks: **base64-out-of-`Json`** (3a),
**`Field`→`structure`** (3e, ~95 sites), **module splits** (3d: `FixturePorts` 2293 /
`FixtureTests` 1033 / `BuiltinTests` 735 — use the Edit tool, not bash text surgery), then
**item 4 Linux `cacheRoot` default**.

## For the orchestrator

This is the **~2nd slice since the last `/ace-audit`** (test-reorg, then this).
**Audit due in ~1–2 more slices** — fold its findings into the plan as fix-slices.

Carry forward: **alpha cadence** ~1 datestamped release/day via `scripts/release.sh`, NO
CI (latest `v0.1.0-alpha.20260617.2`); **external repos read-only** (prod9/infra etc.).
