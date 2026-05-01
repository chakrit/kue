package test

x: {
	[=~"^a\\wz$"]: int
	a_z:           "bad"
	"a-z":         "skip"
}

y: {
	[=~"^a\\Wz$"]: int
	a_z:           "skip"
	"a-z":         "bad"
}
