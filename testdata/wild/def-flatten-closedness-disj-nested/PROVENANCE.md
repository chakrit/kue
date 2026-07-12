# def-flatten-closedness-disj-nested (QUARANTINED, .known-red)

- **Source:** DEF-FLATTEN-CLOSEDNESS-DISJ-REF (2026-07-13 Phase A audit) — the
  nested-disjunction residual, deferred from the multi-disjunction slice.
- **Defect:** `#X: {a:1} & ({b:2} | ({c:3} | {e:5}))`. The nested `.disj` arm is not
  `isUnionableDefValue`, so `isClosableDisj` fails, `#X` stays OPEN, and `#X & {g:9}`
  leaks. cue v0.16.1 flattens to `{b:2}|{c:3}|{e:5}`, closes each to `{a}∪arm`, and
  bottoms `g` in every arm ⇒ bottom.
- **Why deferred:** needs the nested disjunction flattened before the closability test —
  and kue additionally reports `ambiguous` here (a distinct disjunction-resolution issue
  entangled with the closedness leak), so the repro is not a clean isolate. Scoped out of
  the bounded multi-disjunction slice.
- **Spec basis:** disjunction is associative/flat; a closed def closes each reachable
  (flattened) arm to its own field set. An undeclared field bottoms every arm → bottom.
