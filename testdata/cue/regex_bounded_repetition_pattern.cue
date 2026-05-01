package test

x: {
	[=~"^a\\d{2,3}z$"]: int
	a12z:               2
	a123z:              "bad"
	a1z:                "skip"
}
