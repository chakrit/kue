// Bug2-13: a presence-test on an UNSET OPTIONAL field reads as ABSENT (`_|_`), not its
// declared TYPE. `#opt?: {a: int}` unset → `#opt == _|_` is TRUE, `#opt != _|_` is FALSE
// (cue: an optional declaration is a CONSTRAINT, not a value; until unification SUPPLIES the
// field it is absent, and a reference to it is `_|_`). kue formerly resolved `#opt` to its
// declared type `{a: int}` (`.struct`) → classified `.defined` → the OPPOSITE polarity. Fixed
// at the selection/resolution boundary (`selectedFieldValue` + the `.refId` eval arm): an
// `.optional`-rung field selects to `.bottom`. The argocd `attr.#ServiceRef` `#service?` shape.
x: {
	#opt?: {a: int}
	eq_bottom:  #opt == _|_
	neq_bottom: #opt != _|_
}
