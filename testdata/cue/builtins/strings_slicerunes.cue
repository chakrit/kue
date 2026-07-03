import "strings"

basic:   strings.SliceRunes("hello", 1, 3)
unicode: strings.SliceRunes("héllo", 1, 3)
astral:  strings.SliceRunes("a😀bc", 0, 2)
whole:   strings.SliceRunes("hello", 0, 5)
empty:   strings.SliceRunes("hello", 2, 2)
