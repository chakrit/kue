// missing-field-selection (deep): a missing field nested inside a concrete struct is absent too.
// `x.a` is itself a struct `{b: 1}`, so selecting the missing `c` routes through `selectFromDecls`
// (not the non-struct-carrier `.bottom` catch-all). cue: `eq true, neq false`.
x: {a: {b: 1}}
eq:  x.a.c == _|_
neq: x.a.c != _|_
