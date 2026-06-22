package defaults

import "example.com/parts"

// Termination witness: a SELF-referential `.conj` def-of-def (`#ListenerSet: #ListenerSet &
// {…}`). `conjBodyHasDeferringArm` recurses through `.conj` arms and the force `.conj` arm
// re-enters eval — both fuel-bounded. The structural cycle on `#ListenerSet` must BOTTOM
// (collapse to its non-recursive content), not loop. cue agrees.
#ListenerSet: #ListenerSet & {
	parts.#Meta
	#gateway_name: "nginx"
}
