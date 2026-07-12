# def-flatten-closedness-disj-ref (GREEN guard)

- **Source:** DEF-FLATTEN-CLOSEDNESS-DISJ-REF (2026-07-13 Phase A audit) — the
  ref/scalar-arm residual, graduated 2026-07-13.
- **Defect:** `#X: {a:1} & ({z:9} | #Base)` with `#Base: {b:2}`. A `.disj` with a
  `.refId` (or scalar) arm fails `isClosableDisj` (which requires every arm to be a plain
  struct literal, `isUnionableDefValue`), so `ownLiteralUnion` is false, `#X` flattens
  OPEN, and `#X & {b:2, extra:7}` leaks `{a,z,b,extra}`. cue v0.16.1 ⇒ bottom
  (`3 errors in empty disjunction`): the `#Base` arm resolves to CLOSED `{a:1,b:2}` —
  `a` not allowed under `#Base`'s closedness bottoms that arm — and the `{z:9}` arm closes
  to `{a:1,z:9}`, which rejects `b`; both bottom.
- **Fix:** no per-arm eval-resolution is needed. The distribution splits each cross-product
  combination: an all-struct-literal combo unions+closes (existing path); a combo carrying a
  non-struct pick (a `.refId`, a scalar) is emitted as an OPEN `.conj [own-literals, ...picks]`,
  UNCHANGED, so normal eval composes it — a closed ref rejects a foreign literal field, an
  open ref admits it, a scalar dies against the struct literal. The own literal stays open under
  the ref (independently closing it would reject a field the ref DOES allow).
- **Over-close hazard (both directions):** an OPEN ref arm (`#Base: {b:2, ...}`) stays OPEN —
  `#X & {b:2, extra:7}` admits `extra` on the `#Base` arm (cue v0.16.1 ⇒ `{a,b,extra}`). Pinned
  by `defflatten_refarm_open_admits`; the open-compose path resolves the arm's OPENNESS, it does
  not force-close.
- **Spec basis:** a closed def's field set is fixed per reachable arm; a def-ref arm
  contributes the (closed or open) field set the ref resolves to.
