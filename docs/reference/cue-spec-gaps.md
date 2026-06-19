# CUE spec gaps

Areas where the CUE language **spec itself is incomplete, ambiguous, or silent**, so
neither the written spec nor the reference `cue` binary's behavior is authoritative. Here
Kue makes a principled, mathematically-grounded choice and records *why*.

This is distinct from [`cue-divergences.md`](cue-divergences.md): a *divergence* is where
the correct behavior IS clear and the `cue` binary is wrong; a *spec gap* is where the spec
does NOT pin the behavior at all, so the binary's behavior is just an implementation
artifact.

A spec gap is worth recording **even when Kue matches the `cue` binary** — matching an
artifact is not the same as honoring a spec mandate. Such a match is lower-confidence (if
`cue` changes, the "oracle" moves under us), and the principled basis for the choice
belongs on the record, not buried in a fixture. The continuous slice loop appends an entry
whenever a slice's oracle-check surfaces behavior the binary exhibits but the spec does not
mandate (see `CLAUDE.md` → "Continuous slice loop" and
[`../guides/slice-loop.md`](../guides/slice-loop.md)).

## How to record an entry

When a slice grounds a fix against `cue` behavior, ask: **is this behavior spec-grounded,
or just what the binary does?** If the latter:

1. Check the CUE language spec (and, where useful, the upstream issue tracker) to confirm
   the spec is genuinely silent or ambiguous on the point — not that you misread it.
2. Record Kue's chosen behavior and its principled basis (the repo's philosophy: precise,
   total, illegal-states-unrepresentable, mathematically defensible — see `CLAUDE.md` →
   Project and the working agreement).
3. Note whether Kue's choice MATCHES or DIFFERS from the `cue` binary, and the confidence.
4. The fixture/pin is the executable record; this table is the human-readable index.

## Entry format

| Topic | `cue` ver | Spec status | `cue` binary behavior | Kue's choice + basis | Matches cue? | Fixture |
|-------|-----------|-------------|-----------------------|----------------------|--------------|---------|

## Recorded spec gaps

| Topic | `cue` ver | Spec status | `cue` binary behavior | Kue's choice + basis | Matches cue? | Fixture |
|-------|-----------|-------------|-----------------------|----------------------|--------------|---------|

_None recorded yet. The argocd narrowing chain (Gap-1/2/2b — disjunction-arm pruning,
structural discrimination, force-tier narrowing) is the first place to actively apply this
lens: confirm whether each `cue` behavior Kue matches is spec-mandated or a binary artifact,
and record the artifacts here._
