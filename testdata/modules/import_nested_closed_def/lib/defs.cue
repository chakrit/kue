package lib

// A closed def whose field is ITSELF a closed def (`#Inner`). The eager selector must close
// `#Outer`'s body AND, when `inner` is selected, close `#Inner` — so a use-site field matching
// the nested def is admitted but an undeclared one would be rejected (nested closedness).
#Outer: {
	inner: #Inner
}

#Inner: {
	a: int
}
