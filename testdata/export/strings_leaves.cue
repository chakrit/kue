import "strings"

// STDLIB-STRINGS-LEAVES: the plain `strings` functions completed this slice —
// byte-indexed (ByteAt/ByteSlice), rune-set index/contains (*Any), separator-keeping
// splits (SplitAfter/SplitAfterN), and word-initial lower-casing (ToCamel). Byte-vs-rune
// is exercised with the two-byte `é`. ByteSlice returns bytes (base64 in JSON export).
byte_at:          strings.ByteAt("héllo", 1)
byte_slice:       strings.ByteSlice("héllo", 0, 3)
contains_any:     strings.ContainsAny("hello", "xyz e")
contains_any_no:  strings.ContainsAny("hello", "xyz")
index_any:        strings.IndexAny("héllo", "l")
index_any_miss:   strings.IndexAny("hello", "xyz")
last_index_any:   strings.LastIndexAny("héllo", "l")
split_after:      strings.SplitAfter("a,b,c", ",")
split_after_tail: strings.SplitAfter("a,b,c,", ",")
split_after_n:    strings.SplitAfterN("a,b,c,d", ",", 2)
to_camel:         strings.ToCamel("Hello World")
to_camel_mixed:   strings.ToCamel("CamelCase")
