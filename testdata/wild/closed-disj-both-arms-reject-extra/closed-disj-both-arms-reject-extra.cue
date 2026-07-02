package repro

// Both arms of the disjunction are close()d, and the meet adds a field `r`
// declared in NEITHER arm: close({p: int}) rejects `r`, close({q: int})
// rejects both `p` and `r` → every arm is bottom → the disjunction is empty
// → `out` is bottom. cue: "2 errors in empty disjunction: field not allowed".
// The spec-adjudicated outcome is BOTTOM (export fails).
out: (close({p: int}) | close({q: int})) & {p: 1, r: 9}
