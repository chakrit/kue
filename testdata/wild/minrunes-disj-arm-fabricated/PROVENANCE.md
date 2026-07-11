# minrunes-disj-arm-fabricated  (string length validator × disjunction arm)

- **Source:** reproduced 2026-07-11 from the Phase-A audit of STDLIB-VALIDATORS (`5d9b65c`);
  HIGH-1 worst case — a fabricated DEFINITE answer.
- **CUE construct at fault:** `(string & strings.MinRunes(5)) | "hi"` — a disjunction whose first
  arm is an abstract constrained string.
- **Direction: SOUNDNESS / SILENTLY-WRONG (fabricated concrete).** kue bottomed the abstract arm
  (count-0 measure vs min 5), `liveAlternatives` pruned it, and the whole value collapsed to `"hi"`
  — a concrete answer invented from an incomplete input. Spec-correct: the constrained arm survives,
  so two live arms remain and the value is unresolved.
- **Root cause (kue):** same as `minrunes-abstract-incomplete` — the abstract-string measure
  fabricated a count-0 length; here it fired inside `finalizeDisjArm`.
- **Fix:** `LengthMeasure.unknown` ⇒ `finalizeLengthConj` returns `none` ⇒ the arm is not pruned.
- **Spec basis:** unification distributes over disjunction; the constrained arm is incomplete, not
  bottom, so it stays live. `cue` v0.16.1: `incomplete value strings.MinRunes(5) | "hi"`. kue
  renders a genuinely-unresolved multi-arm export as `ambiguous value: multiple non-default
  disjuncts remain` (a rendering divergence from `cue`'s `incomplete`, recorded in
  `cue-divergences.md`); the load-bearing fact — no fabricated `"hi"` — is what the `.expected.err`
  substring pins.
