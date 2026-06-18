# RESUME HERE — B2.1 (`StructOpenness` + `Value.structN` + `mkStruct`) LANDED (2026-06-19)

Supersedes the prior START-HERE pointer
(`2026-06-19-test-org-lattice-tests-landed.md`). Standing grant in effect (autonomy /
Lean-into-Lean-4 / commit-push freely / specs as restore point). Full record:
`docs/reference/implementation-log.md` ("B2.1 — introduce `StructOpenness` + `Value.structN`
+ `mkStruct`" entry); ranked work + the 5-slice B2 plan: `docs/spec/plan.md` (B2 entry, B2.1
now marked DONE).

## What landed — one commit on `main`

First step of the B2 struct-unification refactor. Introduces the TARGET representation
WITHOUT migrating any behavior — `structN` has no producer, so fixtures stay byte-identical.

- **`StructOpenness`** (`Value.lean`): `regularOpen | defClosed | defOpenViaTail`, deriving
  `Repr/BEq/DecidableEq`. Helpers `isOpen`, `ofBool` (the design's `boolOpen`), `meet`
  (the design's `meetOpenness`). Erases the conflated `open_`/`hasTail` nonsense pair.
- **`Value.structN fields openness tail patterns`** — new ctor after `structPatterns`,
  carrying `tail : Option Value` AND `patterns : List (Value × Value)` together (the
  orthogonality the old four forms could not express). `valueTag` = 31.
- **`mkStruct` in `Lattice.lean`** — only sanctioned builder. Enforces pattern dedup
  (`dedupPatterns`) + tail/openness coherence (`coherentTail`: `tail = some _ ↔
  defOpenViaTail`).

### Naming / coexistence choice

New ctor is `structN`, NOT `struct` (the old `struct` still exists). **B2.4 deletes the four
old forms and renames `structN → struct`.** All dead arms reference `.structN`.

### Design divergence (resolved by philosophy, recorded — do NOT re-litigate)

The design had `mkStruct` call `canonicalizeFields`, but that lives in `Eval` (downstream of
`Value` AND `Lattice`) — a layering violation. Kept field ordering as the CALLER's job
(callers already canonicalize before `patternStructValue` today); `mkStruct` owns only the
invariants enforceable without an upward dependency. **B2.2 must preserve the
caller-canonicalize contract.** The design's `meetTail` helper is a B2.4 merge concern — NOT
added dead in B2.1.

### Dead arms — 5 sites, ALL must be revisited in B2.3

`structN` has no producer in B2.1; each arm is dead-but-required (no `_` catch-all, per the
type-first rule), tagged `-- B2.1 dead arm … filled in B2.3`:
- `Lattice.meetCore` → `.bottom` (real `structN×structN` merge is ONE arm in `meetWithFuel`,
  landed in **B2.4**, not B2.3).
- `Format.formatValueWithFuel` → `{` fields ++ patterns ++ optional tail `}`.
- `Manifest.manifestWithFuel` → fields only (tail/patterns/openness dropped).
- `Eval.classifyDefinedness` → `.defined`. **B2.3 CAVEAT:** old `structPattern`/`structPatterns`
  are `.incomplete`, so a PURE pattern-struct `structN` (no fields) must be reconciled.
- `Eval.valueTag` → 31 (total tag table).

Every OTHER struct-family match site uses a catch-all and needed NO change — the B2.1/B2.3
boundary is clean (new-arm work did not bleed into B2.3).

### Theorems (`LatticeTests.lean`, `native_decide`, all via `BEq` `==`)

`Value` has no `DecidableEq` (perf carve-out) → propositional `=` is undecidable, so pins use
`==`. Cover: tail-forces-`defOpenViaTail`, closed-coerced, bare-`...`-defaults-`some .top`,
non-tail-stays-tailless, all-six-coherent (`structNTailCoherent`), pattern dedup +
idempotence + distinct-preserved, `StructOpenness.meet` closed-dominates / tail-preserved /
open-idempotent.

## Verify (all green)

`lake build` (all new theorems build-checked); `scripts/check-fixtures.sh` → `fixture pairs
ok` (ZERO byte-drift). No shell changed (shellcheck N/A). No producer on any hot path → perf
unchanged.

## Next step — B2.2 (migrate CONSTRUCTION sites to `mkStruct`)

Per `plan.md` B2 entry, the 5-slice sequence is B2.1 (DONE) → **B2.2** → B2.3 → B2.4 → B2.5,
with `structComp` collapse (B2b) split out as a separate follow-on.

**B2.2 — migrate CONSTRUCTION sites to `mkStruct`.** Move the `.struct…`/`.structTail…`/
`.structPattern…`/`.structPatterns…` BUILD sites to `mkStruct` (`patternStructValue`, the
merge helpers' result-emit, `Eval` re-emit, `Parse`). One module at a time, fixture-gated,
byte-identical each. Keep the caller-canonicalize contract (see divergence above). NOTE: B2.2
produces `structN`, so the B2.3 dead arms start firing — but B2.3 (migrate MATCH sites) is
what makes them CORRECT. Order matters: B2.2 construction before B2.3 match means `structN`
flows through the (currently mirror-of-legacy) dead arms; those arms were filled to be
plausibly-right precisely so B2.2 stays byte-identical. Watch fixtures closely at B2.2.

### Cadence note for the orchestrator

B2.1 is **1 slice since the last audit** (the two-phase audit came due at the test-org/
LatticeTests slice and was deferred to "after B2 start" — see prior breadcrumb). Counting:
the audit is now overdue-by-policy but deferred-by-plan; re-evaluate after B2.2/B2.3 whether
to interrupt the B2 sequence for it or let B2 finish first (B2.4/B2.5 are the behavioral
risk — auditing after B2.5 catches the cross-combination fix).

Then, ranked (plan.md Live Backlog): finish B2 → two-phase audit → B6 / A2-followup / item-1
follow-up → parallel-safe cleanups (items 3/4, B5, remaining test-org, `DecimalTests`/
`FormatTests`) → deeper parity/perf (items 2/6/7) → B3/item-8 ride-alongs.
