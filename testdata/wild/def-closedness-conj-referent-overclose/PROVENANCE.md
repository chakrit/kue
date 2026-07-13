# def-closedness-conj-referent-overclose

- **Source:** DEF-CLOSEDNESS-NONDEF-REFERENT MILESTONE-VERDICT audit (2026-07-13),
  full cross-surface sweep of the `f0382cc..68c4879` batch.
- **Defect:** A definition whose body is a conjunction reaching non-def struct
  referents (`#X: a0 & b0`) closes each referent SEPARATELY under the 68c4879
  `underDef` indirection-close path, yielding two independent closedClauses
  (`{a}` AND `{b}`). A use-site meet then requires every field in BOTH sets, so a
  legitimately-declared field is rejected (`y.b` ⇒ bottom). An OVER-REJECTION
  (completeness bug): valid configs are rejected. Likely a regression introduced
  by 68c4879 following non-def referents that previously stayed open.
- **Spec basis:** CUE closedness — a definition composed from a conjunction of
  structs has the UNION of their fields as its allowed set (`{a,b}`), exactly as
  the single-decl `#X: {a:1, b:2}` or the direct literal conj `#X: {a:1} & {b:2}`.
  Meeting `& {a:1}` re-declares an allowed field; the result is `{a:1, b:2}`.
- **cue:** v0.16.1 ⇒ `y: {a:1, b:2}`. kue ⇒ `y.b: _|_` (export: "conflicting
  values (bottom)").
- **Related faces (same root — separate-close vs union-close-once):**
  - mixed ref+literal conj `#X: a0 & {b:2}`, `y: #X & {a:1}` ⇒ kue bottoms `b`.
  - `.selector`-to-disjunction `#X: w.inner` (`w.inner: {a:1}|{b:2}`),
    `y: #X & {z:9}` ⇒ kue bottoms the WHOLE value; cue rejects only `z`.
- **Contrast (correct):** the DIRECT literal conj `#X: {a:1} & {b:2}` closes once
  over `{a,b}` (Bug2-12b) and admits both.
- **Status:** QUARANTINED (`.known-red`). Filed as fix-slice
  DEF-CLOSEDNESS-INDIRECT-DISJ-CONJ (face B).
