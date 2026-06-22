// Bug2-13 ARGOCD PATH: the on-path failure shape — a comprehension guard testing an UNSET
// optional. `attr.#ServiceRef` declares `#service_port` ONLY inside `if #service == _|_ {…}`
// with `#service?` unset; kue formerly fired the `if #service != _|_` arm instead (the wrong
// polarity), pulling `#service.#ports[0]` out of an empty list type → bottom. Here, the
// `if #opt == _|_` arm MUST fire and the `if #opt != _|_` arm MUST NOT: cue emits
// `{out: {absent: true}}`. This is the witness that the fix lands the correct comprehension arm,
// not merely the scalar presence test.
x: {
	#opt?: {a: int}
	out: {
		if #opt == _|_ {
			absent: true
		}
		if #opt != _|_ {
			present: true
		}
	}
}
