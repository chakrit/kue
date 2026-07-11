# minrunes-abstract-incomplete  (string length validator × abstract string)

- **Source:** reproduced 2026-07-11 from the Phase-A code-quality audit of the
  STDLIB-VALIDATORS slice (`5d9b65c`); HIGH-1 soundness finding.
- **CUE construct at fault:** `string & strings.MinRunes(2)` — a length validator met with an
  ABSTRACT string whose rune count is unknown.
- **Direction: SOUNDNESS / SILENTLY-WRONG (fabricated bottom).** kue collapsed the abstract
  string to a count-0 measure, declared `MinRunes(2)` violated, and returned a bound-conflict
  bottom. Spec-correct: the length is UNKNOWN (not 0), so the residual is RETAINED and the value
  is incomplete.
- **Root cause (kue):** `measureForLength .runes (.kind .string)` returned `.lowerBound 0`, and
  `measuredLength?` collapsed `lowerBound → some 0` at manifest — conflating "structurally decided"
  with "final". `finalizeLengthConj` then computed count 0 < 2 → bottom.
- **Fix:** a distinct `LengthMeasure.unknown` for abstract string/regex; `measuredLength?` maps it
  to `none`; `finalizeLengthConj` retains a genuine incomplete residual (`Kue/Value.lean`,
  `Kue/Lattice.lean`).
- **Spec basis:** an abstract `string` is incomplete; `MinRunes(2)` cannot be adjudicated until a
  concrete string arrives. `cue` v0.16.1 agrees: `incomplete value strings.MinRunes(2)`. The pinned
  `.expected.err` (`incomplete value`) is that spec-adjudicated verdict.
