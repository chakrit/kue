# Oracle as a Data Source (not a Correctness Gate)

- **Date:** 2026-06-20
- **PR:** manual
- **Status:** accepted

## Decision

The `cue` binary may be used to **generate committed data** for a domain that is
externally standardized and where `cue` faithfully implements that external standard —
the oracle is then a sound **data source**. It is NEVER a **correctness gate** for CUE
semantics, where `cue` is fallible and the CUE language spec rules (see
[the compatibility target](2026-06-14-cue-compatibility-target.md) and the
[slice-loop spec-authority section](../guides/slice-loop.md)). These are different uses
of the same binary and must not be conflated.

## The test (apply before deriving any data from the oracle)

Both must hold:

1. **The domain is externally standardized** — defined by a spec *other than* the CUE
   language spec (Unicode `UnicodeData.txt`, RFC base64 alphabet, an IETF grammar). The
   data is not a CUE-semantics decision.
2. **`cue` faithfully implements that external standard** — it is a conduit to the
   standard, not the authority for it. Unicode simple case mapping qualifies because
   `cue`'s `strings.ToUpper`/`ToLower` are Go's `unicode.ToUpper`/`ToLower`, a rune-wise
   read of the Unicode database. CUE *evaluation* (unification, defaults, disjunction
   resolution) does NOT qualify — there `cue` is the fallible thing Kue exists to correct.

If either fails, the oracle is a correctness gate in disguise — banned.

## Obligations when the test passes

- **Independently verify the derived data against the EXTERNAL standard**, not against a
  second `cue` run. BI-1 cross-checked all 2363 committed case-mapping entries against
  Python's UCD 15.0.0 and resolved every apparent divergence to the Unicode field
  semantics (simple vs full mapping) — confirming the table tracks the *standard*, not a
  `cue` quirk.
- **Record provenance** at the artifact: name the generator, the external standard, the
  exact scope, and how to regenerate. The generated file carries a `DO NOT EDIT` header;
  the generator carries a provenance docstring.
- **Never let it drift into a semantics gate.** The moment the derived data starts
  encoding a CUE *evaluation* outcome, it is wrong — re-derive from the spec, not the
  binary.

## Examples

- **OK — Unicode case table (BI-1).** `scripts/gen-case-table.py` queries the local `cue`
  oracle over the BMP and emits `Kue/CaseTable.lean`. The domain is the Unicode standard;
  `cue`/Go implement it faithfully; the table was independently verified against the UCD.
- **OK in principle — a base64 alphabet or an IETF-grammar character class** derived the
  same way, with the same external-standard verification and provenance.
- **NOT OK — deriving CUE unification / evaluation expected-outputs from `cue`.** Snapshot
  ting `cue eval`/`cue export` results as Kue's expected fixtures makes the oracle the
  correctness gate — structurally bug-replicating, suppressing the very divergences Kue
  exists to fix. Fixtures pin Kue's spec-conformant behavior, cross-checked against `cue`
  only as a fallible reference; where they disagree, `cue` is recorded as WRONG in
  `cue-divergences.md`.

## Committed generated data vs build-time generation (F-CASE-ARCH(a))

The case table is **committed** (49KB generated `Kue/CaseTable.lean`), not generated at
build time. This is the right artifact for a frozen leaf data table:

- **Reproducible** — re-running the generator is byte-identical (deterministic `sorted()`,
  one oracle round-trip); verified clean.
- **Reviewable + offline** — the data is in-tree, diffable, and the build needs no
  build-time `cue` dependency or network.
- **Cost accepted** — ~49KB of `DO NOT EDIT` generated source and a generator that runs
  only by hand. For a leaf table that changes only with a Unicode version bump, that is
  cheaper than a build-time codegen step and its toolchain dependency.

Regenerate only on a deliberate Unicode-version change; the header and generator docstring
document how.

## Rationale

Without this distinction the standing "NEVER byte-identical-to-`cue`" rule reads as "never
touch the oracle," which would force a from-scratch Unicode table for no benefit — the
oracle is a *faithful conduit* to an external standard there, not the CUE-semantics
authority. The load-bearing line is *what the data is*: an external standard `cue` happens
to implement (sound to derive, with verification) versus a CUE-evaluation outcome
(deriving it is the banned bug-replicating gate). Recorded so a future audit neither
re-flags the committed table nor mistakes a legitimate data-source derivation for the
banned gate.
