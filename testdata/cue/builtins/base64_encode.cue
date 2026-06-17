import "encoding/base64"

ascii:     base64.Encode(null, "hello")
empty:     base64.Encode(null, "")
multibyte: base64.Encode(null, "héllo")
pad1:      base64.Encode(null, "a")
pad2:      base64.Encode(null, "ab")
pad0:      base64.Encode(null, "abc")
overBytes: base64.Encode(null, 'hello')
nonNull:   base64.Encode("std", "hello")
