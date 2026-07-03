# quoted-label-nested-in-list-dedup

**Source:** AUDIT-QUOTED-BEQ regression coverage — the list-nested dual of
`quoted-label-breaks-value-equality`.

**Adjudication:** `[{x: 1}]` and `[{"x": 1}]` are the identical value (a quoted label
`"x":` and a bare `x:` name the same field). The disjunction of the two equal list arms
collapses to one. While `Field.quoted` leaked into `Value` `BEq` (f128600) the arms
compared UNEQUAL and kue errored `ambiguous value: multiple non-default disjuncts remain`;
after the strip normalizes `quoted → false` at the parse→eval seam they dedup.

Guards that the fix reaches struct equality nested inside a list, not only a bare
top-level struct.
