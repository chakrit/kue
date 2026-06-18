package lib

// An OPEN definition (`...`) that ALSO carries an embedding and a comprehension. The `...`
// makes the def admit fields a use site ADDS past its own declarations. The link-3/4 parser
// collapse dropped the `...` tail for such defs and `normalizeDefinitionValueWithFuel`
// hard-closed the `.structComp` arm, silently CLOSING the def — so `#OpenEmbed & {added: ...}`
// bottomed (cue accepts it). The fix records `...`-presence (`hasTail`) on `.structComp` and
// has normalize set the def body's openness from it; a regular struct stays open regardless.
#Base: {kind: "Service"}

#OpenEmbed: {
	#Base
	port: int
	if port > 0 {
		positive: true
	}
	...
}

// A CLOSED definition (no `...`) with the SAME embedding + comprehension shape. A use site that
// adds an undeclared field MUST be rejected — the fix must not over-open it.
#ClosedEmbed: {
	#Base
	port: int
	if port > 0 {
		positive: true
	}
}
