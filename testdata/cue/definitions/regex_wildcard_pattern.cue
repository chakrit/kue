x: {
	[=~"^a.*z$"]: int
} & {
	abcz: 1
	abcy: "skip"
}
y: {
	[=~"^a.+z$"]: int
} & {
	az:  "skip"
	abz: 2
}
