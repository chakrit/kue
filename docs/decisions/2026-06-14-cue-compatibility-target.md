# CUE Compatibility Target: Correct v0.15 Semantics

- **Date:** 2026-06-14
- **PR:** manual
- **Status:** accepted

## Decision

Kue targets **CUE v0.15 language semantics, implemented correctly**. Where the official
`cue` v0.15 binary diverges from the specified/intended semantics because of a bug, Kue
implements the correct behavior — it does **not** reproduce the bug for the sake of
matching the reference binary. The target is the language as specified, not bug-for-bug
parity with the reference implementation. Kue does not chase v0.16+; the local toolchain
being newer (currently v0.16.1) does not move the target.

## Rationale

The obvious default for a reimplementation is bit-exact behavioral parity with the
reference binary — generate fixtures from `cue eval`, match its output, done. We
deliberately reject that here: the motivating reason for Kue is that the official v0.15
implementation is itself buggy, so bug-for-bug parity would bake those defects into Kue
and defeat the purpose. Correctness against the intended semantics is the goal; the
reference binary is evidence, not ground truth.

Consequences:

- **Fixtures are not an oracle.** `testdata/cue/*.expected` outputs cross-checked against
  `cue eval` are a strong signal but not authoritative. When the binary's output is
  wrong, the fixture encodes the *correct* expected value and a note records the
  divergence. `scripts/check-fixtures.sh` compares `kue` against the curated `.expected`
  files (and runs `cue fmt --check`), not against live `cue eval`, so day-to-day checks
  do not silently inherit reference bugs.
- **Version pin stays at v0.15.** References to v0.15.4 in the docs are intentional. The
  installed `cue` (v0.16.1) is used only for `cue fmt` and ad-hoc cross-checks, not as the
  semantic target.
- **Divergences must be explicit.** Each place Kue knowingly differs from the reference
  binary's behavior should be recorded (in `spec/compat-assumptions.md` or a follow-up
  decision) with the reason, so "Kue and cue disagree" is never assumed to be a Kue bug.

## Alternatives considered

- **Bug-for-bug parity with `cue` v0.15.4** — rejected: reproduces known defects, which is
  the exact problem Kue exists to avoid.
- **Track latest `cue` (v0.16+)** — rejected: a moving target while the core semantics are
  still being modeled; v0.15 is the chosen baseline.
