# def-closedness-nested-conj-arm

- **Source:** DEF-CLOSEDNESS-NESTED-CONJ-ARM (2026-07-13 Phase A milestone-reconfirmation audit) —
  the CONJUNCT face of the nested-`.conj` closedness leak (the disjunction-arm face is
  `def-closedness-nested-conj-disj-arm/`).
- **Defect:** `#X: {a:1} & ({b:2} & {d:4})` + `y: #X & {z:9}` — the parens keep `{b:2} & {d:4}` a
  NESTED `.conj` conjunct, which `isUnionableDefValue` did not accept (it took `.struct`/`.structComp`
  only), so `ownLiteralUnion`'s `cs.all` gate failed and the def flattened OPEN — the undeclared `z`
  leaked (kue exported `{a,b,d,z}`; cue ⊥). The FLAT `#X: {a:1} & {b:2} & {d:4}` (a single
  already-merged `.conj [{a:1},{b:2},{d:4}]`) closed correctly.
- **Root cause (pinned):** neither closedness predicate accepted a nested `.conj` — the conjunct face
  failed `isUnionableDefValue`, the disjunction-arm face failed `disjArmClass` (`.blocking` for `.conj`).
- **Fix:** `normalizeDefBodyConjunct` (`Kue/EvalBase.lean`) normalizes a definition body BEFORE the
  closedness gate — a pure-struct-literal `.conj` conjunct is SPLICED into its struct members (so
  `{a:1} & ({b:2}&{d:4})` becomes the flat `{a:1},{b:2},{d:4}` the own-literal union already closes),
  and a `.disj` conjunct's pure-struct `.conj` arms are merged. Conjunction associativity makes the
  splice semantics-preserving; it fires only for a DEFINITION body and only for pure-struct-literal
  `.conj`s, leaving refs/scalars/self-refs/mixed conjs on their existing paths.
- **Spec basis:** a closed definition has a fixed field set regardless of `&`-grouping; unifying an
  undeclared field is `field not allowed` → bottom.
- **cue:** v0.16.1 ⇒ `y.z: field not allowed`. kue after fix ⇒ bottom.
