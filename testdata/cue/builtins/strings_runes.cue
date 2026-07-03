import "strings"

ascii:     strings.Runes("abc")
multibyte: strings.Runes("héllo")
emoji:     strings.Runes("a😀b")
empty:     strings.Runes("")
combining: strings.Runes("é")
