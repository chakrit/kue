# Breadcrumb: 2026-07-04 — AUDIT-STRUCT-EQ half-1 landed (concrete struct/list `==`)

Supersedes `2026-07-04-audit-quoted-beq-landed.md` as the live front.

## What landed

**AUDIT-STRUCT-EQ half-1 (the SAFE half) — DONE.** `Kue/EvalOps.lean:evalEq` no longer defers
every non-`.prim` operand to `incomplete value`. New `structEqConcrete? : Value → Value →
Option Bool`, reachable ONLY from `evalEq`'s non-`prim`/non-`bottom` arm:

- Concreteness guard FIRST — `none` (defer) unless BOTH operands pass `isConcrete` and are
  bottom-free (`containsBottom`). Mirrors the manifest output-field filter: regular fields must be
  concrete; required → defer; hidden/def/`let`/import/optional/pattern ignored.
- `concreteEq` — structs ORDER-INDEPENDENT over regular output fields (equal count + label-matched
  equal values); lists ORDER- and LENGTH-sensitive; primitives reuse the decimal-aware leaf
  equality; cross-shape → `false`. `evalNe`/`.ne` inherit the negation.
- Both mutual blocks use `termination_by structural` (the `containsBottom` pattern) — total, no
  fuel, no `partial def`.

Probe matrix matches cue v0.16.1 on the tested cases (reordered/quoted/hidden-ignored/nested/
open-tail/cross-shape/lists/scalar `1==1.0`). Over-eager DEFER trap guarded: an incomplete operand
keeps `==` incomplete even when another field already differs.

> **RETRACTION (2026-07-04 Phase A audit):** the "matches EXACTLY" claim was overstated. The
> matrix MISSED int-vs-float leaves inside containers: `[1.0]==[1]` and `{a:1.0}=={a:1}` yield kue
> `true`, cue `false` (cue is type-sensitive on number leaves structurally, yet scalar `1.0==1` is
> `true` — cue's own inconsistency). Filed **STRUCT-EQ-LEAF-TYPESENSE** (plan 0d).

Seed `struct-equality-quoted-labels-defers` GRADUATED; new wild guard
`struct-equality-incomplete-defers` (`.expected.err`); 5 `testdata/export/structeq_*` fixtures; 14
`native_decide` theorems (`EvalTests eval_eq_*`/`eval_ne_*`). `./scripts/check.sh` GREEN;
cert-manager canary EMPTY. Committed on `main`, NOT pushed (AFK envelope).

Safe residual: nested `embeddedScalar` field values stay deferred (`isConcrete` → false) — exotic,
not a regression.

## Still open — AUDIT-STRUCT-EQ half-2 (deferred/attended)

`dedupAlternatives` still uses the order-SENSITIVE global `Value` `BEq`, so `{a:1,b:2} | {b:2,a:1}`
→ `ambiguous value` where cue collapses. Do NOT redefine the global `BEq` (cycle detection at
`Eval.lean:292 structStack.contains` relies on exact equality). Needs an order-independent equality
fed into `dedupAlternatives`, coupled with a broader disjunction-canonicalization pass — a
soundness-sensitive, ATTENDED slice. `cue-divergences.md` row narrowed to the dedup gap only.

## Next step (pick by rank)

1. **B3d-6b (NETWORK-GATED)** — `cue mod get/tidy` + requirement-graph fetch + `cue.sum` WRITE.
   Network-gated; skip if AFK/offline.
2. **AUDIT-STRUCT-EQ half-2 (attended)** — order-independent `dedupAlternatives`; couple with
   disjunction canonicalization. NOT for AFK (soundness-sensitive, touches global disjunction path).
3. **ARCH-QUOTED-STRIP (MEDIUM)** — parse-only quoting; drop `Field.quoted` from the eval layer,
   delete the `stripFieldQuoting` walk.
4. **B2-A1** — thread `tail` through the patterns-present meet (lands with typed-ellipsis).
5. **GATE-KNOWNRED-DRY (LOW)** — share a `.known-red` decision helper across the two fixture gates.

Two-phase audit: last full audit was the 2026-07-04 Phase B (this slice was one of its filings) —
next audit due in ~2–3 slices.
