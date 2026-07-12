# def-flatten-closedness-disj-multidisj

- **Source:** DEF-FLATTEN-CLOSEDNESS-DISJ-REF (2026-07-13 Phase A audit finding,
  re-ranked LOW→HIGH) — the multiple-disjunction residual scoped out of the parent
  DEF-FLATTEN-CLOSEDNESS-DISJ fix (`8a2dcd2`).
- **Defect:** `#X: {a:1} & (*{b:2}|{c:3}) & (*{d:4}|{e:5})` + `y: #X & {f:6}` — the close
  branch of `flattenConjDefRef` distributed the own-literal union across only a SINGLE
  disjunction (`[.disj alts]`); two or more disjunction conjuncts hit the `| _ => expanded`
  fall-through and flattened OPEN. The defaults then collapsed to one combination and kue
  SILENTLY exported `{a:1,b:2,d:4,f:6}`. cue v0.16.1 rejects `f`
  (`y.f: field not allowed`).
- **Fix:** distribute the own-literal union across the CROSS-PRODUCT of every closable
  disjunction conjunct (`disjArmCrossProduct`, `Kue/EvalBase.lean`), closing each
  combination together with the literals. A combination is a default iff EVERY component
  arm is a default (`*{b}` & `*{d}` → the default combination `{a,b,d}`), matching cue's
  product-of-defaults collapse. A single disjunction is the one-list cross-product
  (identity), so the prior per-arm behavior is unchanged.
- **Spec basis:** a closed definition has a fixed field set per reachable
  disjunction-arm combination; an undeclared field bottoms every combination → bottom.
