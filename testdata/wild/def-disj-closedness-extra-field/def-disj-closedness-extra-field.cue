package repro

// A disjunction of two definition REFERENCES (#A | #B). Definitions close their
// values, and that closedness must survive being referenced into a disjunction:
// meeting with {p: 1, r: 9} must reject `r` in the #A arm and both `p` and `r`
// in the #B arm → every arm bottoms → empty disjunction → bottom.
// cue: "2 errors in empty disjunction: field not allowed". kue LOSES the
// definitions' closedness through the disjunction distribution: both arms
// survive → "ambiguous value" instead of bottom (over-accept in structure).
#A: {p: int}
#B: {q: int}
M: #A | #B
out: M & {p: 1, r: 9}
