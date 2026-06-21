import "math"

powSquare:    math.Pow(2, 10)
powZeroExp:   math.Pow(5, 0)
powBaseZero:  math.Pow(0, 5)
powFloatBase: math.Pow(1.5, 3)
powNegBase:   math.Pow(-2, 3)
powNegBaseEv: math.Pow(-3, 4)
powFloatPow:  math.Pow(2.5, 4)
powWholeFlt:  math.Pow(3, 2.0)
powBig:       math.Pow(10, 20)
powDecExact:  math.Pow(0.1, 2)
powOne:       math.Pow(7, 1)

// BI-2-§3 — negative-integer exponent (exact rational, 1/x^n).
powNegInt:   math.Pow(2, -3)
powNegInt10: math.Pow(10, -2)
powNegOneBs: math.Pow(1, -5)
powNegRep:   math.Pow(3, -1)
powZeroNeg:  math.Pow(0, -1)

// BI-2-§3 — general non-integer fractional exponent (exp/ln, exact decimal).
powQuarter:   math.Pow(2, 0.25)
powTenth:     math.Pow(2, 0.1)
powThreeHalf: math.Pow(4, 1.5)
powCubeRoot:  math.Pow(8, 0.3333333333333333333333333333333333)

// BI-2-§3 — domain edges (Kue bottoms; cue errors / Infinity).
powNegBaseFr: math.Pow(-2, 0.25)
powZeroFr:    math.Pow(0, 0.25)
