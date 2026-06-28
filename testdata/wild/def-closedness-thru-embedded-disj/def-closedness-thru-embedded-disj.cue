package repro

// A definition closes its value, and closedness must propagate into an embedded
// disjunction's arms. cue: `#M`'s `{a: int}` arm is closed, so `& {kind: "k"}`
// rejects the extra `kind` field → that arm is bottom; the `{kind: string}` arm
// survives → the disjunction resolves to a concrete `{kind: "k"}`. kue LOSES the
// definition's closedness through the embedded disjunction → both arms survive →
// "ambiguous value" (an over-accept: kue admits what cue closes-and-rejects).
// This is a SOUNDNESS bug (kue accepts where cue/spec reject).

#M: {{a: int} | {kind: string}}
out: #M & {kind: "k"}
