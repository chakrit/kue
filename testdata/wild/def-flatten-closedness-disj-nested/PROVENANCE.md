# def-flatten-closedness-disj-nested (GREEN guard)

- **Source:** DEF-FLATTEN-CLOSEDNESS-DISJ-REF (2026-07-13 Phase A audit) — the
  nested-disjunction residual, graduated 2026-07-13.
- **Defect:** `#X: {a:1} & ({b:2} | ({c:3} | {e:5}))`. The nested `.disj` arm was not a
  plain struct literal, so the closability test failed, `#X` stayed OPEN, and `#X & {g:9}`
  reported `ambiguous` (both inner arms survived the open meet). cue v0.16.1 flattens to
  `{b:2}|{c:3}|{e:5}`, closes each to `{a}∪arm`, and bottoms `g` in every arm ⇒ bottom.
- **Fix:** `flattenNestedDisjArms` splices a nested `.disj` arm's own arms into the flat
  arm-list (disjunction is associative) before the cross-product close — a nested arm is
  `default` only when both outer and inner marks are `default`. The flattened struct arms
  then close through the existing distribution.
- **Spec basis:** disjunction is associative/flat; a closed def closes each reachable
  (flattened) arm to its own field set. An undeclared field bottoms every arm → bottom.
