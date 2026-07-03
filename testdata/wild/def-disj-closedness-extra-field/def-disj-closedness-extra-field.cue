package repro

// A disjunction of two definition REFERENCES (#A | #B). Definitions close their
// values, and that closedness must survive being referenced into a disjunction:
// meeting with {p: 1, r: 9} must reject `r` in the #A arm and both `p` and `r`
// in the #B arm → every arm bottoms → empty disjunction → bottom.
// cue: "2 errors in empty disjunction: field not allowed"; kue renders the
// bottom as "conflicting values (bottom)". The carrier is a HIDDEN def (#M) so
// the observed export result is `out`'s value, not the disjunction carrier's
// own (inherent) incompleteness — see PROVENANCE.md.
#A: {p: int}
#B: {q: int}
#M: #A | #B
out: #M & {p: 1, r: 9}
