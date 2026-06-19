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
| Unreferenced bottom def in an imported package | v0.16.1 | Silent. The recursive-bottom rule governs unification *results*; it does not say a package containing a standalone-bottom unreferenced definition is itself bottom. | Tolerates — `main` exports clean even when an unreferenced `dep.#Probe` is `_|_`. | Tolerate, as a **deliberate operational laziness gap** (real packages carry unused, not-fully-resolved defs; perf), NOT "because cue does". Lattice purist reading is the opposite (a bottom value is bottom whether selected or not). Decision pending — basis must be operational, recorded, not silent. Smell: behavior is reference-location-dependent (in-file conflict surfaces; imported does not). | yes (current) | `testdata/modules/unreferenced_import_conflict` |
| Un-narrowed struct-arm disjunction with no unique default (`{…} \| {…}`) | v0.16.1 | Silent on open-vs-error for an unresolved struct-shaped disjunction. | Keeps it open / `incomplete`. | Keep open — lattice: a join with no unique default *is* the join; erroring would over-commit. | yes | existing disjunction fixtures |
| Output field order of a struct meet | v0.16.1 | No mandated ordering (set-of-fields semantics). | Deterministic, declaration / first-seen-across-conjuncts (`{b}&{a}` → `a,b`). | Re-derive a principled order (declaration / first-seen — matches cue's *intra*-struct order and reading intuition); do NOT inherit cue's cross-conjunct order via byte-pins. Backlog #3. | partial — intra-struct yes; cross-conjunct Kue (`b,a`) ≠ cue (`a,b`) | backlog #3 |

