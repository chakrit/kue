# Breadcrumb — consolidation/hygiene: plan-mechanism sweep + AUD-B2/B4 (2026-07-05)

Restore-point hygiene slice closing out the batch-5 frontier run. All named batch work +
GDA-FLOAT-RENDER landed and pushed before this; this slice is committed on `main`, NOT pushed.

## What landed

- **Plan-mechanism sweep (Part 1).** Swept open `plan.md` items against actual code after two
  entries this session (0c, GDA-FLOAT-RENDER) proved to name stale data sources. Both big
  registry legs verified accurate: **leg 4** (export-path MVS) — `Mvs.solveChecked`,
  `ModCmd.fetchGraph`, `ModuleContext` all present as stated; version-override field is the work,
  not a false premise; disk-first builder genuinely new, `readModuleInfo` the reuse anchor.
  **leg 2** (`mod get`) — accurate; only fix was the `parseMod` file pointer (`Cli.lean:83`, not
  `ModCmd.lean`). No third stale mechanism.
- **AUD-B2 DONE.** `testdata/ocifetch/modtidy/*.zip` de-opaqued: `src/<name>/` trees +
  `scripts/gen-modtidy-fixtures.py` + `README.md`; deterministic, reproducible, gate green.
- **AUD-B4 DONE.** `Value.textBytes` kept in core with a documented test-support-in-core rationale
  (relocation would cost 7 imports for a one-liner).

## Next step (the frontier)

The two big registry legs are the next real slices, plan entries now verified-accurate:

1. **B3d-6b-leg4 (export-path MVS rewiring, MEDIUM+)** — wire the MVS build-list into the
   import-resolution loader so multi-version resolution affects evaluation (today: per-hop lenient).
   Touches the loader the cert-manager canary exercises → needs a canary re-run (the net, not a
   stop condition under the standing grant). Disk-first graph builder + version-override through
   `ModuleContext` + an on-disk diamond fixture.
2. **B3d-6b-leg2 (`mod get` + tags/list, MEDIUM)** — LANDED 2026-07-05 (deps-block emitter +
   tags/list latest resolution; B3d-6b fully closed). Historical below.

Lower tail: B3d-A2 (DEFLATE/ZIP adversarial reject pins), UNUSED-IMPORT enforcement (sibling of
BUILTIN-IMPORT-LENIENCY, documented in `compat-assumptions.md`).

## Attended-only, parked

`linux/amd64` (QEMU) release asset for `v0.1.0-alpha.20260705` — the `on_intel` tap block is stale
vs the bumped version; needs a per-run go-ahead (heavy build). macOS + linux/arm64 already published.
