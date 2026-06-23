// missing-field-selection: a genuinely-missing field of a CONCRETE struct selects to ABSENT
// (`_|_`), not an incomplete deferral. `x.b` is never declared, so `x.b == _|_` is TRUE and
// `x.b != _|_` is FALSE — cue treats absence from a concrete struct as a settled bottom. Formerly
// kue deferred the miss to a `.selector` residual (classified `.incomplete`) and `export` errored
// `incomplete value`. Fixed at `selectFromDecls` (the miss arm yields `.bottom`).
x: {a: 1}
eq:  x.b == _|_
neq: x.b != _|_
