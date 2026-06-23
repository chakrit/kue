// Bug2-14: an embed declares a label ABSTRACTLY (`bk: string`) which the host declares
// CONCRETELY (`bk: "X"`); the embed's plain sibling read `echo: bk` must resolve against the
// host-narrowed value, not the embed-local abstract type. Fixed by `injectEmbedSiblingNarrowings`
// (meet the host narrowing into the embed body's same-label read-and-declared slot before the
// embed evaluates). cue: `{bk:"X", echo:"X"}`; kue formerly `echo: string` (export incomplete).
host: {
	bk: "X"
	{
		bk:   string
		echo: bk
	}
}
