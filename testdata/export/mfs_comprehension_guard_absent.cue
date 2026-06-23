// missing-field-selection (comprehension guard): a guard over a missing concrete field now
// RESOLVES (absent reads `.error`, not `.incomplete`), firing the `== _|_` arm. Pre-fix the
// deferred `.selector` made the guard incomplete and BOTH arms dropped. cue: `{out: {absent: true}}`.
x: {a: 1}
out: {
	if x.b != _|_ {present: true}
	if x.b == _|_ {absent: true}
}
