staging: bool | *false
out: {
	if !staging {
		prod: true
	}
	if staging {
		dev: true
	}
}
