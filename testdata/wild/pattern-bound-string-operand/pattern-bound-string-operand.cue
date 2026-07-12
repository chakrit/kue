package repro

// Comparator-bound pattern operands that are STRING/BYTES literals, not numbers:
// `[>"m"]` matches field names lexicographically greater than "m". CUE's grammar
// allows an ordered STRING (or bytes) literal as a bound operand, and cue applies
// it as a lexical bound. kue's parser accepts ONLY numeric literals after a
// comparator (`parseBoundValue` calls `parseNumberToken`), so `>"m"` fails to
// parse: "expected number digits". Same root cause as
// `pattern-bound-reference-operand` (the bound Value repr is numeric-only), a
// distinct facet: literal string/bytes operands, no deferral needed.
//
// Spec-correct: `zebra` > "m" so it is admitted and constrained to `int`
// (satisfied by 1); `apple` < "m" so it is unconstrained (stays "keep").
//
//   kue: parse error: expected number digits
//   cue: {"out":{"apple":"keep","zebra":1}}   (v0.16.1)
out: {[>"m"]: int, apple: "keep", zebra: 1}
