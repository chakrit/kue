// missing-field-selection (open tail): an `...`-open struct still reads a not-yet-declared field
// as ABSENT at selection time — the open tail does NOT make the field provisional. cue: `eq true,
// neq false`.
x: {a: 1, ...}
eq:  x.b == _|_
neq: x.b != _|_
