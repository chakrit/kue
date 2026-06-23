// Bug2-14: the comprehension form (the argocd `#Mixin` shape). The embed declares `bk: string`
// abstractly while the host declares `bk: "X"`; a `for`/`if bk == "X"` guard inside the embed must
// fire against the host-narrowed value so the comprehension DRAINS. cue: `{bk:"X", hit:true}`; kue
// formerly left the `for`/`if` undrained → export incomplete.
host: {
	bk: "X"
	{
		bk: string
		for k, v in {p: 1} {
			if bk == "X" {
				hit: true
			}
		}
	}
}
