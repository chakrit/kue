import (
	j "encoding/json"
	s "strings"
	m "math"
	l "list"
	b "encoding/base64"
	y "encoding/yaml"
)

jsonMarshal: j.Marshal({a: 1})
jsonList: j.Marshal([1, 2, 3])
strUpper:    s.ToUpper("hello")
strLower:    s.ToLower("WORLD")
strContains: s.Contains("foobar", "oob")
mathPow:     m.Pow(2, 10)
mathSqrt:    m.Sqrt(144)
listSum: l.Sum([1, 2, 3, 4])
listConcat: l.Concat([[1, 2], [3]])
b64Encode: b.Encode(null, "hi")
yamlMarshal: y.Marshal({a: 1})
