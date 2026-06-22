// Bug2-13 OVER-FIRE GUARD: a SET optional must stay PRESENT. Supplying `#opt: {a: 1}` for the
// optional `#opt?: {a: int}` downgrades optionality to `.regular` (`mergeFieldClass`'s
// `optional.meet regular = regular`), so the field is no longer `.optional` and keeps resolving
// to its value: `#opt == _|_` FALSE, `#opt != _|_` TRUE. The absent-for-unset-optional fix must
// NOT touch this — selecting a set optional reads `.defined`. cue AND kue agree here both before
// and after the fix; this pins that the fix did not regress the present case.
y: {
	#opt?: {a: int}
	#opt: {a: 1}
	set_eq:  #opt == _|_
	set_neq: #opt != _|_
}
