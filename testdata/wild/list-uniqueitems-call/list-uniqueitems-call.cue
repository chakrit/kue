package repro

import "list"

// `list.UniqueItems(x)` with a LIST argument (the `(list)` CALL form) was unhandled: only the
// `[]`-args validator form (`| "list.UniqueItems", [] => .uniqueItems`) and the bare-reference
// form existed, so the call form fell to `unresolvedOrBottom` ⇒ ⊥ (kue **bottom**, cue `true`).
// Fix: a call-form arm beside the validator, deciding structural uniqueness via `hasGroundDup`
// (the SAME predicate the `.uniqueItems` validator's meet uses) over the carrier-normalized
// operand (`openListOperand`, so embedded/open-tail lists descend). Spec-adjudicated: applied
// to a concrete list, yields whether its items are structurally unique.
//
// `dupValueEq: [1, 1.0]` is DUP → `false`: `hasGroundDup` uses `structuralEq` (value-based prim
// leaves, int→float), so `1` and `1.0` are equal — spec-correct and consistent with kue's
// scalar `1 == 1.0` and `list.Contains`. cue v0.16.1 DIVERGES here (returns `true`; its
// STRUCT-EQ-LEAF-TYPESENSE bug), logged in docs/spec/cue-divergences.md.
//
// Provenance: 2026-07-13 Phase A carrier re-sweep (pre-existing, not in the audited batch).

unique:     list.UniqueItems([1, 2, 3])
dup:        list.UniqueItems([1, 1])
dupValueEq: list.UniqueItems([1, 1.0])
embedded:   list.UniqueItems({[1, 2, 3], _y: 9})
openTail:   list.UniqueItems([1, 2, 3, ...int])
