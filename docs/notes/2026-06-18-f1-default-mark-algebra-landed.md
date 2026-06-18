# START HERE — F1 default-mark algebra LANDED (audit #3 Violation cleared)

Supersedes `2026-06-18-argocd-disjsel-chain-landed.md`. Build 86 jobs, fixtures byte-identical
(+3 new), shellcheck clean. Pushed to `main`.

## What landed — F1 default-mark algebra (audit #3, baseline `db5ee90`)

The audit framed the fix as "combineMark OR→AND". Oracle probing (`cue` v0.16.1) overturned
the single-rule framing: **two operator classes, two distinct rules.**

- **Unification (`&`)** crosses value sets and **ANDs default sets** (`combineMark` now strict
  AND). A no-`*` operand contributes its WHOLE set as defaults (`withDefaultConvention`, applied
  before the cross) — that is what makes `(1|*2)&(1|2|3) → 2` keep its lone survivor's mark.
- **Arithmetic / comparison / unary** do NOT cross-product. CUE resolves each operand to its
  single default FIRST (`resolveOperand`), then applies the scalar op. `(int|*1)+1 → 2`;
  `(1|2)+10` stays the stuck `(1|2)+10` (cue "unresolved disjunction"). This REPLACED the old
  slice-C cross-product distribution (the real source of spurious defaults).

Three audit facets fixed: (1) `combineMark` OR→AND; (2) `flattenAlternatives` two-level
precedence — a `.default` outer arm carries the inner disjunction's OWN default set, a
`.regular` outer arm makes inner arms regular (`*d|5`, `d:1|2` → ambiguous `1|2`, NOT
`*1|2|5`); (3) `dedupAlternatives` (in `liveAlternatives`) merges equal-VALUED arms so
`*1|*1|2 → 1`.

### Files
- `Kue/Lattice.lean`: `combineMark` (AND), new `combineMarkOr`/`hasDefaultMark`/
  `withDefaultConvention`/`dedupAlternatives`, rewritten `flattenAlternatives`, dedup folded
  into `liveAlternatives`; unification disj-cross arms apply `withDefaultConvention`.
- `Kue/Eval.lean`: `distributeUnary`/`distributeBinary` → resolve-operand-first via new
  `resolveOperand`. (Old cross-product gone.)
- `Kue/Manifest.lean`: added total `instance [BEq ε] [BEq α] : BEq (Except ε α)` (stdlib lacks it).
- Tests: 12 `native_decide` pins added (`EvalTests.lean`); 12 existing `rfl` proofs converted to
  `(== ) = true` + `native_decide` (dedup's `Value`-`==` blocks `rfl`). 3 fixtures under
  `testdata/cue/disjunctions/` (`default_arithmetic_cross`, `default_dedup`, `default_unify_cross`).

### Verify
86 jobs green, `fixture pairs ok`, shellcheck clean. 32-case JSON+YAML oracle matrix byte-matches
`cue` on every RESOLVABLE case. Ambiguous cases differ ONLY in error-message text (kue "multiple
non-default disjuncts" vs cue "incomplete value …") — cosmetic, both correctly refuse.

### Out-of-scope note
`cue` rejects `*(1|2)` as a syntax error; kue's parser accepts it and mis-desugars to `*1|2`.
Pre-existing parser laxity, not the mark algebra (the ref form `*d`, `d:1|2`, is correct). For an
eventual parser-strictness pass.

## NEXT STEP — Phase B sequencing (in order)

F1 + F2 + `closure-import-selector-alias` all landed today. The orthogonal correctness slices
are done; remaining work is cleanup + the argocd chain + perf:

1. **Regex extraction (R3)** — parallel-safe, zero-conflict, quick. Pull regex out to its own
   module. Do this FIRST (cheap, unblocks parallelism).
2. **EvalOps extraction (R1) + `truncate-primitive` (F-B1)** — both `Eval.lean`, non-conflicting
   line ranges. F-B1 is the higher-value soundness hardening.
3. **`argocd-secret-data` (correctness, the live argocd chain link 2)** — `for k,v in Self.#data`
   in an embedded default arm runs against the arm's EMPTY `#data` before use-site narrowing
   reaches it → secret `data:{}` vs cue's payload. Repro `w3` (in prior breadcrumb
   `2026-06-18-argocd-disjsel-chain-landed.md`): `_#A:{#k:"a",#data:[string]:string,out:{for k,v
   in Self.#data {"\(k)":v}}}` + `_#B:{#k:"b",out:{}}` + `#S:{#data:[string]:string;
   (*_#A|_#B)}` + `out: #S & {#data: foo:"bar"}` → kue `out:{}`, cue `out:{foo:"bar"}`. Narrowing
   must flow INTO the embedded default arm before its comprehension expands.
4. **Field-ordering parity #3 (DEEP)** — per-`Field` provenance through meet/manifest for byte-
   exact `cue` field order. Deepest remaining; after the argocd chain.
5. **Test/fixture-organization slice** — when Phase B flags it.

Perf B (the heavy `argo` sub-package >200s wall) stays downstream — unreachable while argocd
still bottoms on link 2.

## Two-phase audit due
F1 is the 3rd slice since the last audit (F2, `closure-import-selector-alias`, F1). Run the
two-phase audit per `docs/guides/slice-loop.md` (A: code-quality over the batch; B: architecture/
refactor) BEFORE or interleaved with R3. Audit targets: the F1 mark-algebra rewrite (does the
two-rule split hold under more oracle cases? is `withDefaultConvention` applied at every cross
site?), the `Except` BEq instance, and the proof-form conversions.
