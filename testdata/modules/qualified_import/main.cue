package main

// The `:math` qualifier names the package within the location; it is REQUIRED here because
// the last path element `math-utils` is not a valid identifier. The local binding defaults
// to the qualifier `math`.
import "qualified.example/lib/math-utils:math"

sin:   math.Sin
twice: math.twice
