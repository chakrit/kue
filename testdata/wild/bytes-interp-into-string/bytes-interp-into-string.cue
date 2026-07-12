package repro

// A bytes value interpolated into a STRING literal `"\(b)"` renders the bytes'
// content as its UTF-8 string form. The CUE spec lists `bytes` among the
// interpolatable operand types (bool|string|bytes|number); the enclosing literal
// kind (a double-quoted string here) fixes the result type, and the bytes operand
// is coerced to string. kue previously DEFERRED every bytes interpolation hole
// (`classifyInterpolationPart` returned `.incomplete` for `.prim (.bytes …)`), so
// the whole interpolation stayed an unresolved residual and export errored
// "incomplete value". Spec-correct verdict: decode the (valid-UTF-8) bytes to text.
// cue v0.16.1 agrees: `x` renders "ab".
b:      'ab'
x:      "\(b)"
inline: "p=\('yz')-q"
multi:  "\('a')\('b')"

// Multi-byte valid UTF-8 (`\xc3\xa9` = "é"): pins the `String.fromUTF8?` DECODE, which
// an ASCII-only case can't distinguish from a naive byte-copy.
mb:     "\('\xc3\xa9')"
