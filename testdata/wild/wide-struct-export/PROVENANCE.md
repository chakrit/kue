# wide-struct-export  (manifest — field-count fuel cliff)

- **Source:** found 2026-07-11 by a repo audit (HIGH). `kue export` failed ENTIRELY on any
  struct with ≥99 top-level fields — `export error: incomplete value: <value>` — on a
  TRIVIAL input (plain int fields, no refs/arithmetic/deferral). Real CUE configs routinely
  exceed 98 fields, so this broke real exports. Reproduced RED on the pre-fix binary: 98
  fields OK, 99 FAIL (value of the 99th field, list-index 98); a 500-field struct failed
  identically at index 98 (a constant bump would only move the cliff, not remove it).
- **CUE construct at fault:** a wide flat struct `{ r0: 0, r1: 1, …, r109: 109 }`. This
  fixture carries 110 fields — past the old 98/99 cliff.
- **Direction: UNDER-ACCEPT** — kue errored on input the spec exports cleanly.
- **Root cause (kue):** `manifestFieldsWithFuel`/`manifestItemsWithFuel` (`Kue/Manifest.lean`)
  peeled one unit of `manifestFuel` (=100) per SIBLING — the `| fuel + 1, field :: fields =>`
  cons-match decremented before both the value-manifest and the tail recursion. That coupled
  the fuel budget to field COUNT: the field at list-index `i` was manifested at fuel
  `manifestFuel - 2 - i`, hitting 0 (→ `.incomplete`) at `i = 98`. Fuel is meant to bound
  nesting DEPTH (for totality), not sibling BREADTH. Fix: thread `fuel` UNCHANGED across
  siblings; only `manifestWithFuel`'s own `fuel + 1` descent into a value spends a unit —
  mirroring `evalFieldRefsListWithFuel`, which already passes fuel undecremented across
  siblings. Termination moves from structural-on-fuel to a lexicographic `(fuel, phase, len)`
  well-founded measure.
- **Spec basis:** a concrete struct of concrete fields is fully concrete and manifests to
  JSON regardless of field count; the CUE spec places no field-count bound on export. `cue`
  v0.16.1 exports all 110 fields. kue output is now byte-identical to `cue export --out json`.
