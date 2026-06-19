import "regexp"

// `regexp.Match(pattern, string)` is an UNANCHORED search (matches anywhere in the
// string), identical to CUE's `=~` and Go's `regexp.MatchString`. It dispatches to the
// same engine entrypoint as `=~`. The engine is not yet RE2-conformant (RX-1), so these
// pins use simple anchored/literal patterns the current engine handles correctly;
// grouped/`\b`/lazy patterns are deliberately avoided here (they belong to RX-1).
anchoredStart: regexp.Match("^x", "xyz")
unanchored:    regexp.Match("y", "xyz")
midMatch:      regexp.Match("b", "abc")
noMatch:       regexp.Match("q", "xyz")
anchoredEnd:   regexp.Match("z$", "xyz")
charClass:     regexp.Match("[0-9]", "a1b")
