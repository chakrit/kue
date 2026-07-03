# Breadcrumb: 2026-07-04 — AUDIT-QUOTED-BEQ fixed (strip route)

Supersedes `2026-07-04-let-alias-noshadow-reverse-landed.md` as the live front.

## What landed

**AUDIT-QUOTED-BEQ (HIGH, was plan rank 0) — DONE.** `Field.quoted` leaked into the derived
`Value`/`Field`/`ClosedClause` `BEq`, so `{x:1}` vs `{"x":1}` compared unequal and disjunction
dedup errored `ambiguous value`. Fixed via `Parse.stripFieldQuoting` — a total, enumerated
(no catch-all) `Value` walk that normalizes every `Field.quoted → false` at BOTH parse→eval seams
(`parseDocument`, `parseDocumentFile`), AFTER `checkLetFieldShadow` reads the true quoting. Derived
`BEq`/`DecidableEq` stay consistent (no custom instance). Seed graduated; dedup + nested-list +
necessary-quote fixtures + 4 `native_decide` theorems; all 24 `noshadow_*` intact; canary EMPTY.

**Discovered + split out — AUDIT-STRUCT-EQ (plan 0b, known-red seed committed).** The `==` symptom
bundled into AUDIT-QUOTED-BEQ was a DIFFERENT bug: `evalEq` defers all non-`.prim` before any
`BEq`, so struct `==` was never implemented (the strip cannot reach it). Compounded by kue's
struct equality being order-SENSITIVE raw `BEq` (no field sort), which also makes dedup diverge on
reordered fields. Seed: `testdata/wild/struct-equality-quoted-labels-defers/` (`.known-red`);
`cue-divergences.md` row added.

## Next step (pick by rank)

1. **Phase B audit (owed)** — architecture/refactor; infra-in-scope rotation due (3rd cycle). Run
   before new feature slices. Details: `plan.md` § Audit status.
2. **AUDIT-STRUCT-EQ (plan 0b)** — one order-independent, regular-fields-only, concreteness-guarded
   struct/list equality feeding BOTH `dedupAlternatives` and `evalEq`/`evalNe`. Graduates the
   `struct-equality-quoted-labels-defers` seed; also fixes reordered-field dedup. Soundness-
   sensitive — a real slice, not inline.
3. **B3d-6b (NETWORK-GATED)** — `cue mod get/tidy` + requirement-graph fetch + `cue.sum` WRITE.
4. **B2-A1** — thread `tail` through the patterns-present meet (lands with typed-ellipsis).

If AFK/offline, B3d-6b is network-gated — prefer the Phase B audit or AUDIT-STRUCT-EQ.
