// Bug2-13 GENERALITY: the absent-for-unset-optional rule is GENERAL to all optional fields, not
// definition-specific. A plain (non-`#`) unset optional `opt?: {a: int}` reads the SAME as the
// definition form: `opt == _|_` TRUE, `opt != _|_` FALSE. The discriminator is the `.optional`
// presence rung, orthogonal to definition-ness — so `findEvalField`/`selectedFieldValue` need no
// hidden/definition special-case. cue: `eq_bottom true, neq_bottom false`.
z: {
	opt?: {a: int}
	eq_bottom:  opt == _|_
	neq_bottom: opt != _|_
}
