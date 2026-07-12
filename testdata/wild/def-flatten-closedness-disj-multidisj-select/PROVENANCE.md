# def-flatten-closedness-disj-multidisj-select

- **Source:** both-direction guard for DEF-FLATTEN-CLOSEDNESS-DISJ-REF's cross-product
  distribution — the admit direction.
- **Guards:** selecting a NON-default combination resolves to exactly that combination's
  closed field set. `#X: {a:1} & (*{b:2}|{c:3}) & (*{d:4}|{e:5})` unified with `{c:3, e:5}`
  picks the `{a,c,e}` combination; `c` and `e` are its own declared fields, so they are
  ADMITTED. Guards against over-closing a legitimately-selected arm.
- **Spec basis:** a use-site meet distributes across the disjunction and selects the
  combination whose closed field set it satisfies. cue v0.16.1 ⇒ `{a:1, c:3, e:5}`.
