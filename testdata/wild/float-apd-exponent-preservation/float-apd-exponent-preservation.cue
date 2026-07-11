// apd (General Decimal Arithmetic) result-exponent preservation through float
// +, -, * — the operation's ideal exponent drives cue's rendered form (scientific
// notation, trailing zeros, .0 presence), which kue collapsed by normalizing the
// exponent into the DecimalValue coefficient. Division's ideal-exponent is DEFERRED
// (see docs/spec/cue-spec-gaps.md), so no division field here.
mulSci:    2e2 * 3
mulScale:  1.5e2 * 1e2
mulSmall:  1.0 * 1.0
addSci:    1e1 + 1e1
addTrail:  1.20 + 1.30
addWhole:  1.25e3 + 1
addLarge:  1e100 + 1
subSci:    1.5e3 - 1e3
