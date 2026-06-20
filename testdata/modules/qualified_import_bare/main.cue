package main

// A bare location with no `:identifier` qualifier: the local binding defaults to the last
// path element `defs` (which is itself a valid identifier).
import "barequal.example/defs"

out: defs.Answer
