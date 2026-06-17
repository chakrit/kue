package test

x: {
	[=~"^a\\sz$"]: int
	"a z":         "bad"
	a_z:           "skip"
}

y: {
	[=~"^a\\Sz$"]: int
	"a z":         "skip"
	a_z:           "bad"
}
