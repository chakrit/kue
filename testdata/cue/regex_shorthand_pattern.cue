package test

x: {
	[=~"^a\\dz$"]: int
	a5z:           "bad"
	adz:           "skip"
}

y: {
	[=~"^a\\Dz$"]: int
	a5z:           "skip"
	adz:           1
}
