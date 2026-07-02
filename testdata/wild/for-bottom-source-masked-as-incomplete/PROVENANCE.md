# for-bottom-source-masked-as-incomplete

- **Source:** Phase A code-quality audit of the eval batch `4b64502..HEAD`, 2026-07-02.
  Found while scrutinizing the soundness-grade `classifyForSource` change (fix-slice (d),
  commit `4b8e6ac`).
- **Defect:** `classifyForSource` (Kue/Eval.lean) enumerates `.bottom`/`.bottomWith` into
  the `.incomplete` arm with the justification "Bottoms never reach here (the source is
  evaluated; a bottom would surface upstream)". False: the caller at the `.forIn` clause
  evaluates the source and matches `classifyForSource` directly with no bottom
  short-circuit, so a source that evaluates to bottom (`1 & 2`) reaches the classifier and
  is DEFERRED instead of propagated.
- **Impact:** soundness. A deferred (incomplete) arm is retained in a disjunction where a
  bottom arm would be eliminated (`⊥ | x = x`). `out: [for x in (1 & 2) {x}] | [5]` →
  cue `[5]`, kue "ambiguous value: multiple non-default disjuncts remain". The bare form
  `out: [for x in (1 & 2) {x}]` surfaces "incomplete value" where cue reports the conflict —
  the same bottom-masked-as-incomplete family as the TL-1 and missing-field-selection fixes.
- **Spec basis:** D#1a — a bottom comprehension source short-circuits (like a bottom `if`
  guard, which `classifyGuard` correctly routes through its `.bottom bot => .bottom` arm).
  `classifyForSource` should mirror that: propagate bottom, not defer.
- **cue:** v0.16.1 — `[5]` (disjunction form); `conflicting values 2 and 1` (bare form).
- **Fix:** give `ForSourceClass` a bottom-propagating verdict (or a 4th case) and route
  `.bottom`/`.bottomWith` to it in `classifyForSource`, mirroring `classifyGuard`. Filed as
  a fix-slice in `docs/spec/plan.md`. Quarantined `.known-red` until fixed.
