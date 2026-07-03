# Breadcrumb — let/alias no-shadow validation, REVERSE direction landed (2026-07-04)

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

## Next step (open fork — pick by rank)

The no-shadow work is fully closed; `cue-spec-gaps.md` row is CLOSED, forward-log section
retracted. The ranked OPEN backlog (`docs/spec/plan.md`) now leads with:
1. **B3d-6b (NETWORK-GATED)** — `cue mod get/tidy` + requirement-graph fetch + `cue.sum` WRITE.
2. **B2-A1** — thread `tail` through the patterns-present meet (lands with typed-ellipsis).
3. scalar-embed provenance pins + a LOW opportunistic tail.

B3d-6b is network-gated (needs a live registry); if AFK/offline, prefer B2-A1 or the LOW tail
(timeless-comment sweep of `Tests/`).
