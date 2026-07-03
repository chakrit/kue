# Breadcrumb — let/alias no-shadow validation, REVERSE direction landed (2026-07-04)

> SUPERSEDED by `2026-07-04-audit-quoted-beq-landed.md`. The "Next step" below listed
> AUDIT-QUOTED-BEQ (rank 0) as open — it is now DONE (strip route). Use the newer note as the
> live front.

## Where things stand

The `let`/alias no-shadow load validation is now COMPLETE — BOTH directions enforced. The three
reverse seeds `testdata/wild/let-shadowed-by-{nested-field,descendant-field-in-struct,
field-in-def-body}` are GRADUATED (kue rejects with cue's message). `./scripts/check.sh` GREEN;
cert-manager canary EMPTY (no over-rejection).

## What landed

- **`Field.quoted : Bool := false`** (`Kue/Value.lean`) — a parse-time provenance bit modeled on
  the `Value` layer, set `true` only for a genuinely-quoted `"x":` static label at
  `parseQuotedLabelField`. The `:= false` default kept the blast radius small: only the positional
  `⟨…⟩` `Field` constructions the compiler flagged needed touching (library reconstructions →
  `{ f with value := … }` to preserve provenance; parse mint sites → explicit `false`/`true`), plus
  a mechanical `, false` append over `Tests/` positional `Field` literals (Lean's `⟨⟩` requires all
  explicit fields even with a trailing default).
- **`checkLetFieldShadow` runs both directions** at every struct scope (`Kue/Parse.lean`):
  FORWARD = top-level field ∩ subtree `let`s; REVERSE = top-level `let` ∩ subtree fields
  (`collectFieldNames`, quoted-accurate). The former `collectLetNames`/`fieldLetNames`/
  `clauseLetNames` mutual is now ONE predicate-parameterised traversal `collectMemberLabels`
  (leaf predicates `letBinderLabel` / `collidableFieldLabel`) so the two sides can't drift.
- **Tests:** 8 new `noshadow_reverse_*` theorems in `ParseTests.lean` (3 reject + 5 accept-guards:
  quoted / definition / dynamic / non-shadowing / incomparable-sibling). 16 forward theorems intact.

## Why it's sound (no over-rejection)

Every descendant scope is comparable (ancestor-or-self) to the struct where the `let` is anchored,
and incomparable cousins anchor at DISTINCT structs — so neither direction fires across
incomparable scopes. The reverse quoted-guard (`let x=1; out:{"x":2}` must ACCEPT) holds only
because `Field.quoted` reaches the Value walk. cert-manager canary EMPTY confirms.

## Audit status (2026-07-04)

**Phase A DONE, Phase B OWED.** The 2026-07-04 Phase A code-quality audit of the batch
`a8d07b7..HEAD` (file-scoped imports `53fe3cc`, no-shadow forward `e20af9a` + reverse
`f128600`) found ONE HIGH regression + ONE LOW latent; the mechanical `Tests/` pass,
`Field.quoted` set-site, the unified shadow check, and file-scoped imports all verified CLEAN.
Phase B (architecture/refactor; infra-in-scope rotation is due — this is the 3rd cycle) is owed
NEXT before more slices. Details: `plan.md` § Audit status + implementation-log 2026-07-04.

## Next step (pick by rank)

1. **Phase B audit (owed)** — run before new feature slices.
2. **AUDIT-QUOTED-BEQ (HIGH, plan rank 0)** — `f128600` put `Field.quoted` into `Value`/`Field`
   derived `BEq`, so `{x:1}`/`{"x":1}` compare unequal → breaks disjunction dedup and the
   `==`/`!=` operators. Red seed committed + quarantined:
   `testdata/wild/quoted-label-breaks-value-equality/` (`.known-red`). Fix = exclude `quoted` from
   semantic equality (custom mutual `BEq`, or post-parse total strip-walk); graduate the seed.
3. **B3d-6b (NETWORK-GATED)** — `cue mod get/tidy` + requirement-graph fetch + `cue.sum` WRITE.
4. **B2-A1** — thread `tail` through the patterns-present meet (lands with typed-ellipsis).

If AFK/offline, B3d-6b is network-gated — prefer the Phase B audit or AUDIT-QUOTED-BEQ.
