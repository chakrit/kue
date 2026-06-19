package main

import "regexp"

// End-to-end: the loader must resolve `import "regexp"` (F-1 allowlist) and the call-form
// dispatch must route `regexp.Match` to the engine. Unanchored search, same as `=~`.
isVersion: regexp.Match("^v[0-9]", "v1")
hasDigit:  regexp.Match("[0-9]", "abc7")
plainNo:   regexp.Match("z", "abc")
