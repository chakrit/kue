package p

import x "example.com/liba"

NestedField: {
	x:   "local-field"
	Got: x
}
Items: ["a", "b"]
ForVar: [for x in Items {x}]
CompLet: [for i in [1, 2] let x = i {x}]
ImportUse: x.Name
