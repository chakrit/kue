# Implementation Language: Stay on Lean 4

- **Date:** 2026-06-17
- **PR:** manual (ratified from the 2026-06-17 language investigation; promoted from notes
  2026-06-19)
- **Status:** accepted

## Decision

Keep the semantic core in **Lean 4**. Do not rewrite in an ML-family language
(OCaml/Haskell) or Rust. Confidence ~80%.

## Rationale

Why not the obvious "reach for a mainstream FP/systems language with a real ecosystem":

- **The proof power that would justify Lean over ML is currently unused — but so is its
  cost.** The 572 "theorems" are all behavior pins (441 `native_decide`, 130 `rfl`, **0
  `induction`, 0 `omega`**): a property/example-test-backed core, not an
  algebraic-proof-backed one. A rewrite would discard **no** proof asset (there is none),
  and the pins re-express directly as QuickCheck/proptest properties. But Lean is *not*
  costing us the feared prover-fighting — it is used as a strict, total FP language with a
  fast compiled test oracle that has caught real bugs.
- **The near-term work is not a type-system problem.** The goal is parser breadth +
  encoders + import resolution (the B-series) so real `prod9/infra` CUE evaluates. All of
  that resets to zero on a rewrite. Estimated ~6–10 weeks of negative progress to re-reach
  parity (fuel-recursive lattice, field classes, exact-decimal, regex subset,
  manifestation), to buy ecosystem conveniences worth perhaps 1–2 weeks. The arithmetic
  does not close.

## Consequences — what would flip this (decide on evidence, not taste)

1. **Proofs become the priority** (machine-check the lattice laws — meet/join
   comm/assoc/idem) → stay Lean, harder. ML languages cannot do it at all; this only
   strengthens the incumbent.
2. **Cross-platform distribution becomes urgent** (Linux/x86, Windows) → Lean's lack of a
   cross-compiler (host-arm64-only releases — see the
   [distribution decision](2026-06-16-distribution-prebuilt-local-release.md)) becomes a
   real wall, and a **Rust** rewrite gets seriously arguable. Target Rust, not ML.
3. **Team grows beyond solo** → raises the maintainability weight; a long-horizon pull
   toward OCaml/Rust, never urgent.
4. **Import resolution (B3) proves architecturally painful in Lean** → a partial signal;
   but B3 is mostly file IO + module-graph plumbing Lean handles. Verify before treating
   as decisive.

If none fire, stay.

## Alternatives considered

- **OCaml** — strongest *greenfield* choice (sum types + exhaustive match, fast compile,
  `yojson`/`yaml`/`cmdliner`/`qcheck`); as a *migration target*, rewrite cost dominates.
- **Haskell** — richest non-dependent types (GADTs) + QuickCheck (a better fit for the
  behavior-pinning style than `native_decide`); fussier binary story, steeper ramp; same
  rewrite-cost verdict.
- **Rust** — best ecosystem + binary + perf + hiring + Go-proximity; the *actual* target
  if a rewrite ever happens **and** cross-platform matters. Still loses to "stay" on the
  migration axis given the current goal.
- **Dependently-typed tier (Idris 2 / Agda / F\*)** — same proof ceiling as Lean, worse on
  everything the goal needs.

The full investigation — weighted criteria, per-candidate verdicts, the migration-cost
arithmetic, and the recommended time-boxed OCaml spike to convert the question to data —
is preserved in git history at `docs/notes/2026-06-17-language-choice-investigation.md`.
