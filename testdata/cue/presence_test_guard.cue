concrete: 1 != _|_
missing:  1 == _|_
streq:    "a" == _|_
present: {
	f: 3
	if f != _|_ {
		seen: f
	}
}
absent: {
	base: {f: 3}
	if base.g != _|_ {
		seen: true
	}
}
ordinary: 1 != 2
