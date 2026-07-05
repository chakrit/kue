# Breadcrumb: 2026-07-05 — ARCH-QUOTED-STRIP DONE (Option B, `Quoted` newtype)

Plan 0c closed. `Field.quoted` no longer needs a strip pass to stay inert to equality.

## What changed

`Field.quoted : Bool` → `Field.quoted : Quoted`, a newtype (`structure Quoted where value : Bool
:= false`) whose `BEq` IGNORES its payload (`instance : BEq Quoted := ⟨fun _ _ => true⟩`). With
`deriving Repr, BEq for Value, Field` staying automatic, label-quoting is now inert to every
`Value`/`Field` equality BY CONSTRUCTION — the AUDIT-QUOTED-BEQ leak is type-unrepresentable. A
`Coe Bool Quoted` keeps the ~20 eval-layer field constructions writing plain `false`/`true`.

Deleted (not bypassed): `Parse.stripFieldQuoting` (def + where-clause) + both parse→eval seam
calls. The sole reader, `collidableFieldLabel` (reverse no-shadow check), keeps the provenance via
`field.quoted.value`. BEq is now consistent with `valueDigest` (which already omitted `quoted`) —
the inconsistency the strip masked.

## Why not the filed mechanism

Plan 0c's "drop `quoted` entirely; bubble a collidable-label set up through `parsedFieldsValue`"
was infeasible in-slice: `parsedFieldsValue` is NOT recursive over the subtree, and there is no
`ParsedField` subtree — nested structs are already built `Value`s (with `Field.quoted`) by the
time they arrive from expression parsing. The reverse check walks the built `Value`, including
structs embedded deep inside expressions, so dropping the field needs a provenance set threaded
through the WHOLE expression parser (parser-wide return-type change). Reported the fork; Option B
sanctioned. It supersedes AUDIT-QUOTED-BEQ's "no custom instance" cleanly — B keeps *derived* BEq
(one-line inert `BEq Quoted`, not a hand-rolled mutual instance).

## Verify

TDD red→green: payload-respecting `BEq Quoted` ⇒ `LatticeTests quoted_inert_*` equality pins +
`ParseTests quoted_label_inert_*` dedup pins RED; the digest-consistency pin stays green (proving
BEq was the sole leak). Inert instance ⇒ all green. 6 new `native_decide` theorems.
`./scripts/check.sh` GREEN; cert-manager canary byte-identical.

## Next

Backlog per plan.md ranked OPEN: PRIM-FLOAT-PARSED (0e), GDA-FLOAT-RENDER, BYTES-SLICE-MISSING,
BYTE-INTERPOLATION, BUILTIN-IMPORT-LENIENCY, B3d-6b (network-gated). Two-phase audit due soon
(this is within the 2–3-slice window since the last).
