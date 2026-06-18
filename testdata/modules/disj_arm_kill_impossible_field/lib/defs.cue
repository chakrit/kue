package lib

// The `defs.#ArgoRepo` shape (argocd link 5): a def embedding a DISJUNCTION of defs, each arm
// declaring the OTHER arm's selector hidden field as impossible (`#username?: _|_`). Supplying one
// selector field kills the arm whose `?: _|_` it lands on, leaving the other arm. Here `_#GitHubApp`
// requires `#gid` and forbids `#user` (`#user?: _|_`); `_#PAT` requires `#user` and forbids `#gid`.
// Setting `#user` kills `_#GitHubApp` (its `#user?: _|_` becomes regular-and-bottom) so `_#PAT` wins.
//
// Two link-5 sub-fixes meet here: (1) an UNSET impossible optional field must NOT prune its arm
// (else BOTH arms die unevaluated → `_|_`); (2) a SUPPLIED impossible field's bottom must surface
// (so the wrong arm dies and the right one wins). Pre-fix `containsBottom` pruned arms on the unset
// `?: _|_`, killing the whole disjunction.
_#GitHubApp: {
	#gid:   string
	#user?: _|_
	stringData: {type: "gh"}
}

_#PAT: {
	#user: string
	#gid?: _|_
	stringData: {type: "pat"}
}

#Repo: {
	#gid?:  string
	#user?: string
	(_#GitHubApp | _#PAT)
	kind: "Secret"
}
