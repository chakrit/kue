import "strings"

// Unicode simple case mapping (BI-1). ToUpper/ToLower map the full BMP cased set via the
// oracle-derived table; ToTitle stays ASCII-bounded (non-ASCII word-initial unchanged).
upLatin:       strings.ToUpper("café")
loLatin:       strings.ToLower("CAFÉ")
upGreek:       strings.ToUpper("αβγ")
loGreek:       strings.ToLower("ΑΒΓ")
upCyrillic:    strings.ToUpper("я")
loCyrillic:    strings.ToLower("Я")
upMicro:       strings.ToUpper("µ")
upYdiaer:      strings.ToUpper("ÿ")
upSharpS:      strings.ToUpper("ß")
upUncased:     strings.ToUpper("中→")
upMixed:       strings.ToUpper("café 123 αβγ я 中")
loMixed:       strings.ToLower("CAFÉ 123 ΑΒΓ Я 中")
titleNonAscii: strings.ToTitle("über alles")
