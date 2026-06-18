package lib

// A cross-package structComp definition carrying BOTH an `if`-guard and a `for`-comprehension
// whose conditional fields depend on a hidden field the use-site narrows. Selecting `lib.#M`
// defers it to a `.closure`; meeting `& {#port: 8080, #names: [...]}` splices the narrowing
// into the def frame BEFORE the guards expand, so `enabled` and the `name_*` fields appear.
// Before F2 the force arm dropped every comprehension → the guards silently vanished.
#M: {
	#port: int
	#names: [...string]

	if #port > 0 {
		enabled: true
		bound:   #port
	}

	for n in #names {
		"name_\(n)": n
	}
}
