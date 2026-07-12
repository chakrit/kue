# def-flatten-closedness-disj-multidisj-open

- **Source:** both-direction guard for DEF-FLATTEN-CLOSEDNESS-DISJ-REF's cross-product
  distribution — the over-close direction.
- **Guards:** a `...`-tailed arm in the cross-product keeps its combination OPEN.
  `closeLiteralUnion` unions openness (a `...` in any component literal keeps the merged
  combination open), so the default combination `{a,b,...,d}` admits the use-site's `f`.
  A cross-product that force-closed every combination would wrongly bottom here.
- **Spec basis:** an open-tailed struct admits arbitrary extra fields; unioning it into a
  combination carries that openness into the closed field set. cue v0.16.1 agrees.
