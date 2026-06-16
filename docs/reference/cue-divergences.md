# CUE divergences

Cases where Kue's output **intentionally differs** from the reference `cue` binary
because `cue` is buggy, surprising, or under-specified and Kue does the correct thing.
This is a living reference: the continuous slice loop appends an entry whenever a slice's
oracle-check against `cue` surfaces a genuine divergence (see `CLAUDE.md` →
"Continuous slice loop").

This is **not** for behavior we haven't implemented yet (that's the plan's Later Slices)
nor for fixtures where Kue matches `cue` (the default — those need no entry). Only record
deliberate, defensible disagreement with the reference binary.

## How to record an entry

When a slice finds `cue` doing the wrong thing:

1. Confirm it is a real `cue` defect, not a Kue bug or a misread spec — check the CUE
   language spec and, where useful, the upstream `cue` issue tracker.
2. If Kue's behavior is the corrected one, **do not** edit the fixture `.expected` to match
   buggy `cue`. Encode the correct value, and add an entry below.
3. Keep the fixture pair as the executable record; this table is the human-readable index.

## Entry format

| Topic | `cue` ver | Claim / input | `cue` output | Kue output | Why Kue is right | Fixture |
|-------|-----------|---------------|--------------|------------|------------------|---------|

## Confirmed divergences

_None yet._ Every slice through `8af9e2f` (comprehensions, dynamic fields + string
interpolation, struct-embedding scope, `strings`/`list` builtins, decimal-lift refactor)
oracle-checked clean against `cue` v0.16.1 — Kue matches the reference on all implemented
behavior so far.
