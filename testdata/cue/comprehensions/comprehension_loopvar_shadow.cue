v: "sibling"
out: {
	for v in [10, 20] {
		"k\(v)": v
	}
	keep: v
}
