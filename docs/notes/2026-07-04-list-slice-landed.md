# Breadcrumb: 2026-07-04 — LIST-SLICE-MISSING landed

Supersedes `2026-07-04-phase-b-audit-complete-batch2.md` as the live front. That note's
ranked backlog is UNCHANGED except LIST-SLICE-MISSING is now DONE.

## What landed

**LIST-SLICE-MISSING — DONE.** List slicing `x[lo:hi]` now parses (was "expected ']' after
index"). Parser branch in `parseSelectorRest` + new `parseSliceRest` (`Kue/Parse.lean`):
after the first sub-expr inside `[`, a `:` means slice, `]` means index. Bounds optional —
omitted low = `0`, omitted high = `len(base)`.

**Design: desugar, not a new `Value` ctor.** A slice desugars to
`.builtinCall "list.Slice" [base, low, high]`. A dedicated `.slice base lo hi` ctor would
have touched ~11 files (every structural traversal + catch-all enumeration listing
`.index`), with real risk a `_`-arm silently mishandles it. The desugar reuses the tested
`listSlice` (already cue's exact bounds) + builtin arg-eval + `unresolvedOrBottom` defer for
free. Total, no `partial def` outside the parser.

**Semantics — kue == cue v0.16.1, canary EMPTY.** `[1:3]`→`[2,3]`; `[2:2]`/`[0:0]`→`[]`;
`[0:4]`/`[:]`→whole; `[:2]`,`[1:]` honor defaults; nested `l[1:3][0]`→`2`; single-index
`x[i]` unchanged. Errors → bottom: high-oob, negative low, `lo>hi`, string operand.
Incomplete bound (`l[x:2]`) DEFERS to residual `list.Slice(…)` (not bottom), errors as
incomplete only at export — like cue.

**Deferred: BYTES-SLICE-MISSING (filed, plan.md).** cue slices bytes byte-indexed
(`'hello'[1:3]`→`'el'`); kue bottoms (desugar is list-only). Reusing `list.Slice` for bytes
would corrupt the user-facing `list.Slice('bytes',…)` signature — needs its own slice
dispatch (internal `__slice`/slice-family builtin). Its own slice, own byte-indexed
fixtures. cue is spec-correct here → tracked as unimplemented, NOT a divergence.

Tests: `testdata/export/list_slice.{cue,json}` (byte-identical to cue) + `SliceTests.lean`
(14 `native_decide`). Recorded the residual-display artifact in `cue-spec-gaps.md`.
`./scripts/check.sh` PASS. Committed on `main`, NOT pushed (AFK).

## Open / next (ranked backlog, plan.md § "Ranked OPEN backlog")

- **BYTES-SLICE-MISSING** (new, this slice) — self-startable code slice; needs a slice
  dispatch decision (internal `__slice` builtin over list + bytes).
- 0c **ARCH-QUOTED-STRIP**, 0e **PRIM-FLOAT-PARSED** — self-startable code slices.
- 0b AUDIT-STRUCT-EQ half-2 (dedup, attended), GDA-FLOAT-RENDER; B3d-6b registry
  NETWORK-GATED.
- Two-phase audit is due again in ~2 slices (this is 1 code slice since the last).
- Periodic: plan.md ~680 lines — plan-hygiene approaching, not yet due.
