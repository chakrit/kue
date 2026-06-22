package lib

// A CLOSED definition that declares a PATTERN constraint. After the eager selector closes the
// body, the closedness check must consult the def's OWN patterns: a field matching `^x` is
// admitted, one that does not is rejected (the rejection is pinned by `native_decide`, since a
// fixture can only assert one outcome). Pre-fix the body was fully open so EVERY extra field was
// wrongly admitted — the pattern was never even consulted.
#Pat: {
	port:     int
	[=~"^x"]: string
}
