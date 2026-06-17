import "strings"

remainder: strings.SplitN("a,b,c", ",", 2)
zero:      strings.SplitN("a,b,c", ",", 0)
negative:  strings.SplitN("a,b,c", ",", -1)
exceed:    strings.SplitN("a,b,c", ",", 5)
exact:     strings.SplitN("a,b,c", ",", 3)
one:       strings.SplitN("a,b,c", ",", 1)
absent:    strings.SplitN("xyz", ",", 2)
emptyStr:  strings.SplitN("", ",", 2)
emptySepN: strings.SplitN("abc", "", 2)
emptySepA: strings.SplitN("abc", "", -1)
emptyBoth: strings.SplitN("", "", -1)
