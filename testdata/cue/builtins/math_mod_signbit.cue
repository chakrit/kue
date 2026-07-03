import "math"

modPos:      math.Mod(5, 3)
modNegDiv:   math.Mod(-5, 3)
modNegBy:    math.Mod(5, -3)
modBothNeg:  math.Mod(-5, -3)
modFloat:    math.Mod(5.5, 2)
modIntFloat: math.Mod(7, 2.5)
signNegInt:  math.Signbit(-3)
signPosInt:  math.Signbit(3)
signZero:    math.Signbit(0)
signNegFlt:  math.Signbit(-3.5)
signNegZero: math.Signbit(-0.0)
