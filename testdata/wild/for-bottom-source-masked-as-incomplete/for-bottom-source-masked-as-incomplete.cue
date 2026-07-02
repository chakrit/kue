package repro

// A `for` source that evaluates to BOTTOM (a conflict) must propagate the bottom
// (D#1a: a bottom source short-circuits the comprehension), NOT defer as though it
// were an incomplete source that may still resolve to a list/struct.
//
// classifyForSource (Eval.lean) classes `.bottom`/`.bottomWith` as `.incomplete`
// with the comment "Bottoms never reach here" — but an evaluated source CAN be
// bottom (`1 & 2` conflicts), so the comprehension wrongly DEFERS. Masking a
// bottom as incompleteness is a soundness bug: in a disjunction the dead arm is
// retained instead of eliminated (⊥ | x = x), producing "ambiguous value" where
// cue correctly resolves to the surviving arm.
//
//   bare:  out: [for x in (1 & 2) {x}]        cue: conflict bottom ; kue: "incomplete value"
//   disj:  out: [for x in (1 & 2) {x}] | [5]  cue: [5]             ; kue: "ambiguous value"
//
// The disjunction form below pins the VALUE divergence (not merely the diagnostic):
// the bottom arm must drop, leaving [5].
out: [for x in (1 & 2) {x}] | [5]
