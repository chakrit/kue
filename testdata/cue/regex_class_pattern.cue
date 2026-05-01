x: {
	[=~"^[ab]cz$"]: int
} & {
	acz: 1
	bcz: 2
	ccz: "skip"
}
y: {
	[=~"^a[0-9]z$"]: int
} & {
	a5z: 1
	axz: "skip"
}
