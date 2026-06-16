# Language-choice investigation: Lean 4 vs ML-family / type-system alternatives

**Status:** Investigation findings for review — NOT a decision. Prepared 2026-06-17 by a
read-only research agent at chakrit's request ("would Haskell/OCaml or attacking via the
type system yield better/faster results?"). No code changed. Promote to a `decisions/`
ADR if/when acted on.

## TL;DR / Recommendation

**Stay on Lean 4 for the semantic core. Do NOT rewrite. Confidence: high (~80%).**

Biggest reason: **the proof power that would justify Lean over an ML language is, in this
codebase, entirely unused — but so is its cost.** There are 572 "theorems" and **zero**
are algebraic proofs; every one is a `native_decide`/`rfl` behavior pin (441
`native_decide`, 130 `rfl`, **0 `induction`, 0 `omega`**). That cuts both ways:

- A migration to OCaml/Haskell would **not discard any proof asset** — there is none. The
  "theorem-backed core" is a **property/example-test-backed core**; QuickCheck (Haskell)
  or `qcheck` (OCaml) reproduce that style directly.
- But Lean is **not currently costing** the team the thing people fear (fighting the
  prover). They write Lean as a strict, total FP language with a fast compiled test
  oracle. That's a fine language for this; the core works, ships as a clean single
  binary, and a rewrite buys nothing the goal needs.

The goal is explicit and near-term: **evaluate real `prod9/infra` CUE to replace `cue`,
fast** (`plan.md` Current Focus). Today **zero** real manifest files evaluate; 85/92
sampled files fail at the *parser* on trivial syntax. The bottleneck is **parser breadth +
encoders + import resolution (B1–B6)** — none of which is a type-system problem, and all
of which a rewrite would reset to zero. A rewrite is strictly negative against the goal.

**The one condition that flips it:** if the true north star reasserts as **proving CUE's
lattice laws** (meet/join comm/assoc/idem) as machine-checked theorems, Lean is the *only*
candidate that keeps that on the table — recommendation hardens toward Lean. ML languages
cannot do it at all.

## Criteria & weights (tied to ship-fast-for-prod9-infra)

| # | Criterion | Weight | Why |
|---|-----------|:------:|-----|
| 1 | Dev velocity to "usable for infra" | 35% | The stated goal: parser breadth, encoders, imports, CLI. |
| 2 | Ecosystem fit | 20% | YAML/JSON, parsing, CLI, module resolution, property testing. Gates #1. |
| 3 | Correctness leverage | 15% | Matters, but evidence shows the project pins behavior, not proves laws. |
| 4 | Performance + single-binary distribution | 10% | Ships via Homebrew; eval not perf-bound for infra configs. |
| 5 | Migration cost | 15% | A rewrite competes with shipping; ~11.6k LOC working core is sunk value. |
| 6 | Maintainability / hiring | 5% | Effectively solo dev now; would rise if the team grew. |

Front-loads velocity + ecosystem (55%) — where the goal lives and where Kue is blocked.

## Per-candidate verdicts

- **Lean 4 (incumbent):** Strong where it sits (total core, clean static binary, fast
  compiled test oracle that has caught real bugs). Weak exactly at the next slices: the
  parser is **entirely `partial def`** (~60), and there is **no YAML/JSON/CLI ecosystem**
  — regex is hand-rolled (200+ lines in `Value.lean`); B5/B3 built from scratch. Proof
  capability is unique but unused.
- **OCaml:** Strongest *greenfield* choice. Fast compile loop; sum types + exhaustive
  match are the right parser/AST tools, total without ceremony; `yojson`/`yaml`/`cmdliner`/
  `qcheck` cover B3–B6 as library calls. As a *migration target*, rewrite cost dominates.
- **Haskell:** Richest non-dependent types (GADTs); `aeson`/`yaml`/`megaparsec`/QuickCheck
  (a better fit for Kue's behavior-pinning style than `native_decide`). Fussier binary
  story; steeper ramp. Same rewrite-cost verdict.
- **Dependently-typed tier (Idris 2 / Agda / F\*):** Same proof ceiling as Lean, worse on
  everything the goal needs. None strictly better-suited than Lean. No reason to move
  within the proof tier.
- **Rust (not ML):** **Best ecosystem + binary + perf + hiring + Go-proximity.** If a
  rewrite were ever on the table *and* cross-platform distribution mattered, **Rust is the
  target, not OCaml/Haskell.** Gives up only pattern-match elegance (marginal) and proofs
  (currently unused). Still loses to "stay" on the migration axis given the goal.
- **Scala 3 / others:** JVM startup + fat runtime breaks single-binary distribution. Not
  competitive.

## The core tension

**Proof-power/totality ⟂ ecosystem/velocity** — and Kue currently sits on neither end as
designed. Its *philosophy* (CLAUDE.md "Lean into Lean 4"; guide's "CUE Laws to Encode")
points at proofs. Its *practice* sits in the middle: total functions + a compiled
behavior-test oracle, laws **never actually proven** (0 induction proofs) — QuickCheck-grade
assurance in a theorem-prover's clothes. Its *goal* (Current Focus) points hard at
ecosystem/velocity. So: Kue is using a proof assistant as a strict total FP language with a
great test runner, to build a config interpreter whose remaining work is 100% parser/encoder/
import plumbing. An ML language serves the *goal* better and the *practice* equally; only
the *philosophy* needs Lean — and the philosophy is aspirational, not realized.

Decide which the project is:
- **Correctness research artifact** (prove CUE semantics) → stay Lean, lean harder.
- **`cue` replacement for infra** (the stated focus) → language barely matters for the
  remaining work; staying avoids a pointless rewrite; the only pull to move is
  distribution/ecosystem (→ Rust), not types.

## Where Lean has helped vs hurt this codebase

**Helped:** total-by-default semantic core (`Value`/`Lattice`/`Decimal`), illegal-states-narrow
ADTs (`FieldClass`/`BottomReason`/`BindingId`); a fast trustworthy compiled test oracle (the
`/ace-audit` cadence caught the over-emitting int divider and the `divisionDigits`
totalization); clean static single binary.

**Hurt:** totality friction lands exactly on the velocity-critical layer — the parser
(blocking 85/92 files) is all `partial def`, so the discipline is suspended where the work
is, while still taxing adjacent string/regex helpers with fuel ceremony. No ecosystem =
hand-rolled everything (regex 200+ lines; YAML/JSON/imports from nothing) — the single
largest concrete velocity cost, and structural. Proof power paid for but unused (`Value`
omits `DecidableEq` because the kernel reduces it slowly — the team already routes around
the proof kernel via `native_decide`).

## Migration cost

A rewrite (OCaml/Haskell/Rust) costs **~6–10 weeks to re-reach current parity** (lattice
with fuel recursion, struct field classes, comprehensions, dynamic fields, exact-decimal
with 34-sig-digit division + integral-collapse, the regex subset, manifestation — the
decimal layer alone is subtle oracle-tuned work), re-ports ~11.6k LOC (~3.5k of it the hard
semantic core), and re-validates the whole fixture corpus against the oracle. It discards
**nothing** on the proof axis (none exists) and the 572 behavior pins are mechanically
re-expressible as QuickCheck/proptest properties. It does **not** save the B1–B6 work —
that's ahead of the project in every language. Net: **6–10 weeks of negative progress** to
buy ecosystem conveniences worth perhaps 1–2 weeks across B3–B6. The arithmetic doesn't
close.

## What would change the recommendation

1. **Proofs become the priority** → stay Lean, harder (ML drops out; strengthens incumbent).
2. **Cross-platform distribution becomes urgent** (Linux/x86, Windows, CI matrices) →
   Lean's lack of a cross-compiler (host-arm64-only releases) becomes a real wall; a
   **Rust** rewrite gets seriously arguable — target Rust, not ML.
3. **Team grows beyond chakrit** → raises maintainability weight; long-horizon pull to
   OCaml/Rust, never urgent.
4. **Import resolution (B3) proves architecturally painful in Lean** (file IO, module
   graphs, multi-package merge) → partial signal toward a move; but B3 is mostly IO + graph
   plumbing Lean can do — verify before treating as decisive.

If none fire, stay.

## Concrete next step (decide on evidence, not taste)

Do **not** authorize a rewrite. Time-box a **weekend spike** to convert the question to
data: reimplement two slices in **OCaml** (most velocity-favorable; note what **Rust** would
look like) — (1) the value lattice core (`Value` ADT + `meet`/`join` with the same fuel
recursion) and (2) a CUE-faithful YAML encoder over a manifested value (this is B5, the next
real deliverable and the clearest ecosystem test). Measure head-to-head vs the Lean
equivalents: LOC + wall-clock to parity; how much the encoder shrinks with `yaml`/`yojson`
vs hand-rolling; whether `qcheck` properties feel like an upgrade over `native_decide`;
cross-compile the binary to Linux/x86 to size the distribution gap. If the encoder collapses
and cross-compile is trivial and parity lands in <2 days, the ecosystem case is real (with
Rust as the actual target). If not — likely — the spike confirms "stay Lean" cheaply.

## Load-bearing evidence (file paths)

- 0 algebraic proofs / 572 behavior pins: `Kue/*.lean` — 441 `native_decide`, 130 `rfl`,
  0 `induction`, 0 `omega`. `meet_comm`/`meet_assoc` appear only in
  `docs/guides/lean4-guide.md` as aspirations, never proven.
- Parser all `partial def`: `Kue/Parse.lean` (~60), documented standing exception.
- No external deps / hand-rolled regex: `lake-manifest.json` (`packages: []`); regex in
  `Kue/Value.lean` ~179–419.
- Zero prod9 files evaluate; 85/92 fail at parser: `docs/spec/plan.md` Current Focus.
- Clean static binary, host-arm64-only releases: `docs/notes/2026-06-16-release-and-homebrew-setup.md`.
- Decimal subtlety: `Kue/Decimal.lean` (362 LOC); `compat-assumptions.md` "Arithmetic".
- `DecidableEq` omitted for kernel-reduction perf: `docs/guides/lean4-guide.md`.
