# def-flatten-closedness-disj-ref (QUARANTINED, .known-red)

- **Source:** DEF-FLATTEN-CLOSEDNESS-DISJ-REF (2026-07-13 Phase A audit) — the
  ref/scalar-arm residual, deferred from the multi-disjunction slice.
- **Defect:** `#X: {a:1} & ({z:9} | #Base)` with `#Base: {b:2}`. A `.disj` with a
  `.refId` (or scalar) arm fails `isClosableDisj` (which requires every arm to be a plain
  struct literal, `isUnionableDefValue`), so `ownLiteralUnion` is false, `#X` flattens
  OPEN, and `#X & {b:2, extra:7}` leaks `{a,z,b,extra}`. cue v0.16.1 ⇒ bottom
  (`3 errors in empty disjunction`): the `#Base` arm resolves to CLOSED `{a:1,b:2}` —
  `a` not allowed under `#Base`'s closedness bottoms that arm — and the `{z:9}` arm closes
  to `{a:1,z:9}`, which rejects `b`; both bottom.
- **Why deferred:** the fix needs per-arm RESOLUTION — resolve a `.refId` arm to its
  closed-or-open field set (and detect a scalar arm's type conflict) BEFORE the
  closability test. `flattenConjDefRef` operates on UNEVALUATED constraints; resolving an
  arm to a concrete closed struct is an eval, a representation change that risks the
  L-series/Bug2 closedness suite. Scoped out of the bounded multi-disjunction slice.
- **Over-close hazard (both directions):** an OPEN ref arm (`#Base: {b:2, ...}`) must stay
  OPEN — `#X: {a:1} & ({z:9} | #Base)` then admits `extra` on the `#Base` arm
  (cue v0.16.1 ⇒ `{a,b,extra}`). Any fix must resolve the arm's OPENNESS, not force-close.
- **Spec basis:** a closed def's field set is fixed per reachable arm; a def-ref arm
  contributes the (closed or open) field set the ref resolves to.
