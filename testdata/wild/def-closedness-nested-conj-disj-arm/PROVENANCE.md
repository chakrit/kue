# def-closedness-nested-conj-disj-arm

- **Source:** DEF-CLOSEDNESS-NESTED-CONJ-ARM (2026-07-13 Phase A milestone-reconfirmation audit) —
  the DISJUNCTION face of the nested-`.conj` closedness leak (the conjunct face is
  `def-closedness-nested-conj-arm/`).
- **Defect:** `#X: {a:1} & (({b:2}&{d:4}) | {c:3})` + `y: #X & {z:9}` — a `.conj`-of-struct-literals
  disjunction arm was `disjArmClass` `.blocking`, so `isDistributableDisj` reported the WHOLE
  disjunction non-distributable → the def flattened OPEN and the undeclared `z` leaked in both arms
  (kue exported an ambiguous disjunction admitting `z`; cue ⊥).
- **Root cause (pinned):** neither closedness predicate accepted a nested `.conj`. The conjunct face
  failed `isUnionableDefValue`; the disjunction-arm face failed `disjArmClass` (which returned
  `.blocking` for `.conj`).
- **Fix:** `normalizeDefBodyConjunct` (`Kue/EvalBase.lean`) normalizes a definition body BEFORE the
  closedness gate — a pure-struct-literal `.conj` conjunct is SPLICED into its members, and a `.disj`
  conjunct's pure-struct `.conj` arms are MERGED (normalized-to-closed, then `mergeDefinitionDecls`)
  into the single struct they denote. The merged arm is then `fieldCarryingClosed`, so the existing
  cross-product distribution closes each combination. A `.conj` arm mixing a ref/scalar is NOT merged
  (the ref governs closedness), so it stays on its existing compose path.
- **Spec basis:** a closed definition has a fixed field set per surviving disjunction arm regardless of
  `&`-grouping inside the arm; unifying an undeclared field is `field not allowed` → every arm bottoms
  → bottom.
- **cue:** v0.16.1 ⇒ `y.z: field not allowed`. kue after fix ⇒ bottom.
