# Breadcrumb: `int & >0` kind-retention landed (2026-06-17)

## What landed

The #1 known wrong-output on the supported subset is fixed. `int & >0` now retains the
`int` conjunct (prints `int & >0`, oracle-matching `cue` v0.16.1) instead of collapsing to
`>0` and dropping the load-bearing kind.

- **MEET, not format.** `Lattice.meetCore`'s eight `kind k & intGe/Gt/Le/Lt` arms discarded
  the kind. New `meetKindWithIntBound`: `int` → `.conj [.kind .int, bound]`; `number` → bare
  `bound` (cue drops the redundant implicit kind); else `kindConflict`.
- **Flat conjunction reduction.** The eager conj-injection broke multi-bound int ranges
  (`int & >=0 & <=65535` nested into `.conj`-in-`.conj` → `_|_`). `meetConjValueWith` was
  rewritten to reduce over a flat constraint set (`flattenConj` + `addConstraintWith`):
  flatten both sides, fold pairwise, merge-or-append, re-fold simplified members. Source
  order preserved, idempotent.
- **boundConstraint refactor (plan item 3) FOLDED** — high blast radius (96 `intG*` in
  `Lattice` + ~70 in tests); the plan sequences it as the consolidation-batch lead.

## Verify state (all green)

- `lake build` — 80 jobs, 706 theorems.
- `scripts/check-fixtures.sh` — `fixture pairs ok`.
- `shellcheck scripts/check-fixtures.sh` — clean.
- CLI oracle-matched: `int & >0`, `>0 & int`, `(int&>0)&1.5`→`_|_`, `(int&>0)&5`→`5`,
  `int & >0 & <10`, `#Port: int & >=0 & <=65535`, `number & >0`→`>0`.

## Read-only real-file check

No `int & >bound` usage found in the sampled `infra-defs`/`prodigy9.co` files — the bug was
a latent correctness gap, not an active blocker in those files. `infra/apps/*.cue` weren't
present in this clone's path (likely a remote-session fs-view difference per the global
note); rely on the oracle-confirmed semantics + green fixtures for signal.

## Deeper divergence discovered + FOLDED (NOT closed here)

kue's bounds are **integer-restricted**: `>0` parses to `intGt 0`, `>0.5` is a parse error,
and bare `>0 & 1.5` → `_|_` where **cue gives `1.5`** (CUE's `>0` is a *number* bound that
admits floats). Closing this needs decimal-valued, domain-tagged bounds —
`boundConstraint (bound : Decimal) (cmp : BoundKind) (domain : Kind)` — which is now the
content of plan item 3. Recorded in `compat-assumptions.md` (numeric-bounds section). Infra
uses int bounds (`int & >0`, `>=0 & <=N`), so kue is correct on the real workload.

## Next step

Plan item 2: **open-list collapse on Manifest** (`[1,...]` → concrete `[1]` at manifest
time; `Manifest` currently returns `.incomplete` for a bare `listTail`). Confirm cue's exact
collapse rule against the oracle, then fix `Manifest`'s `listTail`/`embeddedList`-with-tail
arm. After that, the consolidation+test-reorg batch (items 3–4): the `boundConstraint`
refactor (now also carrying the decimal/domain bound generalization), base64-out-of-`Json`,
`testdata/cue/` subsystem reorg, `Field`→`structure`, Manifest-dispatch tighten.

## Carry-forward

- Alpha cadence: ~1 datestamped cut/day via `scripts/release.sh`, NO CI. Latest is
  `v0.1.0-alpha.20260617.2`. Do NOT touch `scripts/release.sh`/`packaging/`/release files.
- External repos (prod9, cue cache) are READ-ONLY.
- No tree-reverting git; revert via Edit; `/tmp` for experiments.
