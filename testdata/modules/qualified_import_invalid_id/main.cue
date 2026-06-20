package main

// A `:identifier` qualifier with a leading digit is not a valid CUE identifier; the spec
// grammar mandates `[ ":" identifier ]`, so Kue rejects it at parse time.
import "badid.example/lib/math:2bad"

out: 1
