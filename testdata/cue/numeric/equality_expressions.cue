same:       1 == 1
diff:       1 != 2
text:       "a" == "b"
precedence: 1+1 == 2

// int-vs-float leaves compare BY VALUE, recursively inside containers too
// (CUE spec: list/struct `==` is recursive element equality; number `==` converts
// int to float). `cue` v0.16.1 wrongly returns false for the container cases — see
// docs/reference/cue-divergences.md (STRUCT-EQ-LEAF-TYPESENSE).
scalarIntFloat: 1 == 1.0
listIntFloat: [1] == [1.0]
structIntFloat: {a: 1} == {a: 1.0}
nestedList: [[1]] == [[1.0]]
