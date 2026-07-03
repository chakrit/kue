# struct-equality-quoted-labels-defers

**Source:** discovered 2026-07-04 while fixing AUDIT-QUOTED-BEQ. Filed by that fix as a
SEPARATE gap it does not close.

**Adjudication (spec-correct):** cue v0.16.1 evaluates `({x: 1}) == ({"x": 1})` → `true`
and `!=` → `false` (quoted `"x":` and bare `x:` are the same field; both structs concrete).

**Observed:** kue errors `incomplete value: {x: 1} == {x: 1}` (exit 1) — NOT the leftover
`quoted` bug. `Kue/EvalOps.lean:evalEq` handles only `.prim` operands and DEFERS every
struct/list comparison to `.binary .eq` before any `Value` `BEq` is consulted, so the
AUDIT-QUOTED-BEQ strip (which fixes the internal `BEq`/dedup path) does not reach this
operator at all. The all-bare `({x: 1}) == ({x: 1})` defers identically — the gap is
"struct/list `==` unimplemented", orthogonal to label quoting.

**Two entangled issues behind a green fix here:**
1. `evalEq`/`evalNe` must reduce concrete struct/list operands to a bool (deferring while
   non-concrete, e.g. `{x: int} == {x: int}`, which cue also leaves unreduced).
2. cue struct `==` is ORDER-INDEPENDENT (`{a:1,b:2} == {b:2,a:1}` → `true`). kue's struct
   equality is raw, order-SENSITIVE `Value` `BEq` (no canonical field sort) — the same model
   makes kue's disjunction dedup diverge on reordered fields
   (`{a:1,b:2} | {b:2,a:1}` → `ambiguous value`, cue collapses). A CUE-correct `==` needs
   order-independent, regular-fields-only, concreteness-guarded equality — which would also
   fix that dedup divergence.

**Status:** GREEN (graduated 2026-07-04 by AUDIT-STRUCT-EQ half-1). `Kue/EvalOps.lean` now
routes non-`prim`, non-`bottom` `evalEq` operands through `structEqConcrete?`, which compares
fully-concrete structs order-INDEPENDENTLY over regular output fields (quoted labels already
stripped to bare by AUDIT-QUOTED-BEQ) and lists order-SENSITIVELY, deferring when either operand
is non-concrete. Issue (2) — the disjunction dedup order-independence — remains the DEFERRED
half (unsafe, attended; `Value` global `BEq` still order-sensitive for cycle detection/dedup).
