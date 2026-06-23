package main

import (
	j "encoding/json"
	s "strings"
)

// Aliased builtin imports must dispatch identically to their unaliased form: the parser
// lowers `j.Marshal`/`s.ToUpper` to `.builtinCall "j.Marshal"`/`"s.ToUpper"`, and the
// post-parse alias canonicalization rewrites the head to the dispatchable `json.Marshal`/
// `strings.ToUpper` before the alias-blind `BuiltinFamily.ofName?` dispatch. This pins the
// fix end-to-end through the module loader (file load + import binding).
out: {
	enc: j.Marshal({b: 2, a: 1})
	upper: s.ToUpper("hi")
}
