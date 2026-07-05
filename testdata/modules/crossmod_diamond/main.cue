package main

import (
	"a.example/pa"
	"b.example/pb"
)

// A diamond: `pa` requires c@v0.1.0, `pb` requires c@v0.2.0. MVS selects the max (v0.2.0)
// for BOTH sides, so `fromA` and `fromB` must agree on "c-v0.2.0". The old per-hop-lenient
// loader resolved `pa`'s import of c against pa's own deps → c@v0.1.0, making `fromA` disagree.
fromA: pa.#A
fromB: pb.#B
