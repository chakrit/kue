# def-comprehension-conjunct-usesite-bottom

- **Source:** Phase A MILESTONE-CONFIRMATION audit (2026-07-13, post-`3e8c7c8`). Orthogonal to the
  closedness-leak class — a spurious over-rejection, LIKELY PRE-EXISTING.
- **Defect:** `#X: {for k, v in {p:1} {"\(k)": v}} & {b:2}` + `out: #X & {}` — a DEFINITION whose
  body conjoins a comprehension embedding with a struct literal bottoms on ANY use-site unification,
  even with an EMPTY struct. kue export ⇒ ⊥; cue v0.16.1 ⇒ `{out:{b:2,p:1}}`. Same for `#X & {b:2}`,
  `#X & {p:1}`, `#X & {c:3}`; order-independent (`{b:2} & {for…}`).
- **Root cause (to pin in fixing slice):** `& {}` bottoming rules out a closedness/field-allowed
  cause — the def re-resolution chokes when a `.structComp` conjunct sits alongside a struct literal
  in a definition body, re-resolved at a use-site (candidate: double comprehension eval, or a
  closedness clause rejecting the comprehension-produced field on the second unification pass). The
  comprehension body takes `flattenConjDefRef`'s `defBodyConjuncts` `| _ => none` path; NOT a
  nested-conj leak.
- **Spec basis:** unifying a resolved struct value with `{}` is the identity; a
  comprehension-produced field composes like any static field.
- **cue:** v0.16.1 ⇒ `{out:{b:2,p:1}}`. Expected (post-fix): admit.
- **Controls that WORK (must stay green):** comprehension-ALONE def `#X: {for…}` + `#X & {}` ⇒
  `{p:1}` (matches cue); the NON-def form `X: {for…} & {b:2}` + `X & {b:2}` ⇒ `{p:1,b:2}` (matches
  cue). The pure-comprehension use-site-field-add `#X: {for…}` + `#X & {b:2}` MATCHES cue (both ⊥).
