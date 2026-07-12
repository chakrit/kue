# def-flatten-closedness-disj

- **Source:** DEF-FLATTEN-CLOSEDNESS-DISJ (2026-07-13 Phase A audit finding, CONFIRMED
  by repro) — soundness under-close in `flattenConjDefRef`, sibling to
  DEF-FLATTEN-CLOSEDNESS.
- **Defect:** `#X: {a:1} & ({b:2}|{c:3})` + `y: #X & {d:4}` — the `.disj` conjunct is not
  `isUnionableDefValue`, so the `ownLiteralUnion` close-gate fails and the def flattens
  OPEN. Both disjunction arms then admit the undeclared `d`, so kue keeps both arms alive
  ("ambiguous value: multiple non-default disjuncts remain") — and with a default arm
  (`*{b:2}`) it silently EXPORTS `{a:1,b:2,d:4}`. cue v0.16.1 rejects `d`
  (`y.d: field not allowed`).
- **Root cause (pinned):** `flattenConjDefRef`'s `ownLiteralUnion` required every
  non-self-ref conjunct to be `isUnionableDefValue`; a `.disj` conjunct is neither a
  struct literal nor a self-ref, so the whole gate fails ⇒ `close=false` ⇒ the arms
  flatten OPEN and leak the use-site's extra field.
- **Fix:** treat a `.disj` whose every arm is `isUnionableDefValue` as closable in the
  gate, and — when closing — wrap each such `.disj` conjunct as an embedding-only
  `structComp` so `mergeDefinitionDecls` folds it into the merged literal as an EMBEDDED
  disjunction. This reconstructs the already-correct embedded shape
  (`#X: {a:1, {b:2}|{c:3}}`), whose close path distributes closedness into the arms. A
  `.disj` with a non-struct arm (a `.refId`, a scalar) is NOT closable this way, so the
  gate stays false and the def stays OPEN (existing behavior — no over-close).
- **Spec basis:** a closed definition has a fixed field set per disjunction arm; unifying
  an undeclared field is `field not allowed` → every arm bottoms → bottom.
- **cue:** v0.16.1 ⇒ `y.d: field not allowed`. kue after fix ⇒ bottom.
