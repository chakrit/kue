import "strings"

lt:        strings.Compare("a", "b")
eq:        strings.Compare("abc", "abc")
gt:        strings.Compare("b", "a")
lastIdx:   strings.LastIndex("abcabc", "bc")
lastNone:  strings.LastIndex("abc", "z")
lastEmpty: strings.LastIndex("abc", "")
