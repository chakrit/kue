l: [1, 2, 3, 4]

// `x[lo:hi]` is half-open (hi exclusive), 0-based; bounds are optional
// (omitted low = 0, omitted high = len). Slicing is list-only.
mid:      l[1:3]
empty:    l[2:2]
whole:    l[0:4]
fromZero: l[:2]
toEnd:    l[1:]
all:      l[:]
nested:   l[1:3][0]
