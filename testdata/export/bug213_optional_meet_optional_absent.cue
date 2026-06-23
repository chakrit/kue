// Bug2-13 DISCRIMINATOR: optional-meet-optional stays ABSENT. A second OPTIONAL conjunct
// (`#opt?: 5` over `#opt?: int`) NARROWS the constraint but does NOT supply the field —
// `optional.meet optional = optional`, so the rung stays `.optional` and `#opt` reads ABSENT.
// This is the boundary a "declared value is concrete ⇒ present" heuristic would wrongly fire on:
// the discriminator is the PRESENCE RUNG (the over-fire guard fires only on a `.regular`
// downgrade from a real supplying conjunct), never concreteness or a mere second conjunct.
// cue: `eq_bottom true, neq_bottom false` — the field never materializes from two optionals.
n: {
	#opt?:      int
	#opt?:      5
	eq_bottom:  #opt == _|_
	neq_bottom: #opt != _|_
}
