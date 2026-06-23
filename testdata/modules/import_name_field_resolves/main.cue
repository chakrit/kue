package main

import "example.com/field/dep"

thing: {y: 2}
fromField: thing
fromPkg:   dep.Foo
