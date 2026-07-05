# Breadcrumb — 2026-07-06 — AUD-B6 landed (import package-name gate)

Clean tree after this slice; `./scripts/check.sh` GREEN. Committed on `main`.

## What landed this slice (AUD-B6)

- Closed AUD-B6 as the F-3 suffix-vs-declared-name MISMATCH gate — **NOT** the audit's
  assumed "give the parse-time check the `declaredName` arm / defer-and-accept". Cross-check
  showed `cue` v0.16.1 REJECTS the audit's repro program (`import ".../foo"` where the dir
  declares `package bar`, used as `bar.Field`) with `no files in package directory with
  package name "foo"`. The naive fix would have made Kue ACCEPT a `cue`-illegal import
  (wrong-direction divergence). Resolved by philosophy: conform to `cue`.
- `importBindName` is now one param-free lexical function in `Value.lean` (alias >
  qualifier > last-path-element); `Parse.importLocalBindName` and `Module.importBindName`'s
  two-arg form both deleted (DRY). `collectBindings` enforces the loaded `package` clause ==
  `expectedPackageName imp`, else a cue-shaped load error. Bind name can never be a post-load
  surprise, so the parse-time unused check can't mis-name a bound import.
- Fixtures: `import_bare_pkgname_mismatch` (expected.err, RED→GREEN) +
  `import_qualifier_pkgname_rescue` (`:bar` rescues, byte-identical to cue).
- Retraction sweep: plan.md AUD-B6 entries, spec-conformance-audit F-3 row,
  implementation-log F-3 residual note, cue-spec-gaps F-3 row — all annotated (residual
  CLOSED / premise corrected).

## Next steps (all LOW / fork-gated — none urgent)

1. **AUD-B5 (LOW)** — the two BFS graph builders (`buildDiskGraphAux` `Module.lean` vs
   `fetchGraphAux` `ModCmd.lean`) could DRY via a step-callback combinator. Non-sharing is
   defensible; deferred.
2. **B3d-B1 (LOW)** — `Digest`/`Hash1` newtype (type-leverage); the kue-performance B3d note.

## Standing pattern to hold

When a filed finding's premise rests on assumed `cue` behavior, VERIFY against `cue` before
implementing — AUD-B6's filed fix was inverted by cue's actual rejection. Default: drive;
escalate only genuinely-irreversible/outward-facing acts or philosophy-silent+expensive forks.
