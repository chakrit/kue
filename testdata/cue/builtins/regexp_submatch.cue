import "regexp"

// RX-1c: submatch / Find* / ReplaceAll over the Pike-VM capture array. `ReplaceAll`
// expands the Go `Expand` template (`$n`/`${n}`/`$$`); the bare `$1suffix` names the
// (nonexistent) group `1suffix` while `${1}suffix` is group 1 then literal `suffix`.
// `ReplaceAllLiteral` splices verbatim. The `Find*` family raises `no match` in cue (a
// bottom in Kue), unlike Go's nil. All oracle-checked vs cue v0.16.1.
replaceLiteral:   regexp.ReplaceAll("a(x*)b", "-axxb-", "T")
replaceGroup:     regexp.ReplaceAll("a(x*)b", "-axxb-", "$1")
replaceBrace:     regexp.ReplaceAll("a(x*)b", "-axxb-", "${1}suffix")
replaceBareName:  regexp.ReplaceAll("a(x*)b", "-axxb-", "$1suffix")
replaceDollar:    regexp.ReplaceAll("a(x*)b", "-axxb-", "$$")
replaceMulti:     regexp.ReplaceAll("a(x*)b", "-axxb-axxxb-", "T")
replaceNoMatch:   regexp.ReplaceAll("a(x*)b", "-aQb-", "T")
replaceZeroWidth: regexp.ReplaceAll("x*", "abc", "-")
replaceLiteralFn: regexp.ReplaceAllLiteral("a(x*)b", "-axxb-", "$1")
prod9Filter:      regexp.ReplaceAll("([hb][^\\s]+)lo", "hello jello bello", "${1}ly")
findOne:          regexp.Find("a(x*)b", "-axxb-")
findSub:          regexp.FindSubmatch("a(x*)b", "-axxb-")
findAllSpans:     regexp.FindAll("ab", "abab", -1)
findAllSub:       regexp.FindAllSubmatch("a(x*)b", "-axb-axxb-", -1)
