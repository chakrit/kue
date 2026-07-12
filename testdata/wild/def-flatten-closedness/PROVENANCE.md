# def-flatten-closedness

- **Source:** DEF-FLATTEN-CLOSEDNESS (2026-07-12 Phase A audit finding; root-caused by
  Phase B) — MEDIUM soundness over-acceptance in `flattenConjDefRef`.
- **Defect:** `#X: {a:1} & {b:3}` + `y: #X & {c:4}` yields `y: {a:1,b:3,c:4}` in kue
  (closedness dropped ENTIRELY); cue v0.16.1 rejects `c` (`#X.c: field not allowed`). The
  single-decl `#X: {a:1, b:3}` shape is already CORRECT in kue (rejects `c`) — only the
  multi-conjunct-of-struct-literals shape leaked.
- **Root cause (pinned):** `flattenConjDefRef`'s close gate was
  `field.fieldClass.isDefinition && (isSelfRef || inCycle)`. A def whose body is a `.conj`
  of its OWN struct literals is neither self-ref nor in-cycle ⇒ `close=false` ⇒ the
  literals flatten OPEN and union into the use-site meet WITHOUT closing.
- **Fix:** widen the close gate with `ownLiteralUnion` — fires when every non-`.refId`
  conjunct is `isUnionableDefValue` and no `.refId` conjunct targets a DIFFERENT slot (own
  struct literals, no cross-def ref composition). `#Base & {extra}` (a ref conjunct to a
  different slot) stays OPEN, deferring to the outer close-once fold (Bug2-6..9).
- **Spec basis:** a closed definition has a fixed field set; unifying an undeclared field
  is `field not allowed` → bottom. cue is spec-correct here.
- **cue:** v0.16.1 ⇒ `#X.c: field not allowed`. kue after fix ⇒ bottom.
