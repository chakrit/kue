# Lean 4 Guide for Kue

This guide is for future agents working in this repository. It is intentionally
compact and action-oriented: read it before writing Lean code for the CUE
reimplementation.

## Why Lean 4

Kue's core problem is semantic correctness, not raw parsing speed. CUE values form
a lattice; unification is meet, disjunction is join, defaults use rewrite rules,
and evaluator order should not change results. Lean 4 lets us implement the model
and prove the important laws in the same language.

Use Lean 4 for:

- the executable semantic model;
- value and constraint data types;
- normalization and evaluator rules;
- proofs of lattice, unification, disjunction, default, closedness, and cycle laws;
- small CLI or test executables when useful.

Use another language later only around the Lean core when there is a concrete
product reason, such as packaging, LSP integration, or high-performance frontend
parsing.

## Mental Model

Lean is both a functional programming language and a theorem prover.

- `def` defines executable functions.
- `inductive` defines sum types and recursive syntax trees.
- `structure` defines named product types.
- `theorem` and `lemma` define propositions with checked proofs.
- `Prop` is the universe of logical propositions.
- `Type` is the universe of computational data.
- proofs are terms; tactics are scripts that build proof terms.

For this project, prefer a small executable model first, then strengthen it with
proofs as invariants stabilize.

## Project Setup

The project is already initialized. The toolchain is pinned in `lean-toolchain` to
`leanprover/lean4:v4.29.1`; `lake` follows it via `elan`. There are no external
dependencies (`lake-manifest.json` lists none) — no Mathlib, no cache step.

`lakefile.lean` defines one library (`Kue`) and one default executable (`kue`, rooted at
`Main`). Test modules are ordinary library modules, not a `lake test` target; they are
checked by `lake build` (`native_decide`/`decide`/`rfl` theorems run at elaboration).

Build and run:

```sh
lake build              # builds the Kue library + the kue exe; checks all theorems
lake build Kue.Builtin  # build a single module while iterating
.lake/build/bin/kue     # the built CLI; reads CUE from stdin, prints to stdout
```

Bare `kue` (no args) prints the top-level help (`Kue/Cli.lean`); subcommands read
source from stdin or from each path argument as a source file. The fixture check
drives the stdin path.

## File Organization

The library aggregator `Kue.lean` imports every module. The stable structure: core
semantic modules live directly under `Kue/` (parser, resolver, value domain, lattice,
evaluator, manifest, format, runtime, CLI, modules/registry), test modules under
`Kue/Tests/` (aggregated by `Kue/Tests.lean`), and shell gates under `scripts/`. The
per-module inventory and layer diagram live in
[`../spec/architecture.md`](../spec/architecture.md) — consult that, not a re-listing
here.

Keep parser concerns separate from semantic concerns. A mathematically clean value
domain is more important than accepting all source syntax early.

### Module layering and the import-cycle constraint

The decimal-lift refactor put exact-decimal machinery in `Kue/Decimal.lean`, below both
the builtin and evaluator layers. The load-bearing edges:

- `Decimal` imports only `Value`.
- `Builtin` imports `Decimal` and `Lattice` — **never `Eval`.**
- `Eval` imports `Builtin`, `Decimal`, `Lattice`, `Normalize` — it sits above `Builtin`.

So builtins are usable from the evaluator's dispatch without a cycle. When a builtin
needs decimal arithmetic, add it to `Decimal`; do not reach up into `Eval`.

## Syntax Essentials

Definitions:

```lean
def add1 (n : Nat) : Nat :=
  n + 1

structure Field where
  name : String
  value : Nat
deriving Repr, BEq

inductive Scalar where
  | null
  | bool (b : Bool)
  | int (n : Int)
  | string (s : String)
deriving Repr, BEq
```

Pattern matching:

```lean
def Scalar.isConcrete : Scalar -> Bool
  | .null => true
  | .bool _ => true
  | .int _ => true
  | .string _ => true
```

Namespaces:

```lean
namespace Kue
namespace Value

-- definitions here

end Value
end Kue
```

Use namespaces aggressively. They keep theorem names readable, for example
`Kue.Value.meet_assoc`.

## Modeling CUE Values

Start with an explicit semantic domain. Avoid encoding too much into Lean's own
type system before the CUE model is clear.

A first sketch might look like:

```lean
namespace Kue

inductive Prim where
  | null
  | bool (b : Bool)
  | int (n : Int)
  | string (s : String)
deriving Repr, BEq

inductive Value where
  | top
  | bottom
  | prim (p : Prim)
  | kind (name : String)
  | meet (a b : Value)
  | join (a b : Value)
  | struct (fields : List (String × Value)) (open_ : Bool)
deriving Repr, BEq

end Kue
```

This is an illustrative sketch, **not** the current domain. The real `Value` lives in
`Kue/Value.lean` and has diverged: meet/join are `conj`/`disj` (n-ary), bottom carries
provenance (`bottomWith (reasons : List BottomReason)`), and there are dedicated arms for
bounds, regex, struct patterns, comprehensions, builtin calls, references, and
interpolation. Read `Kue/Value.lean` before adding a constructor — do not model from this
sketch.

## CUE Laws to Encode

Treat these as design targets:

- `meet` is commutative, associative, and idempotent.
- `join` is commutative, associative, and idempotent.
- `bottom` is absorbing for `meet`.
- `bottom` is identity for `join`.
- `top` is identity for `meet`.
- `top` is absorbing for `join`.
- `meet` distributes over finite disjunctions.
- defaults are compatible with CUE's marked/unmarked rewrite rules.
- evaluation is independent of field/source order.
- normalization preserves denotation.

Prefer theorem names that read like the law:

```lean
theorem meet_comm (a b : Value) : meet a b = meet b a := by
  -- proof
  sorry
```

Short-term use of `sorry` is acceptable while exploring. Before treating a module
as stable, remove `sorry` from its core laws.

Find unfinished proof work with:

```sh
rg "sorry|admit" Kue
```

## Proof Workflow

The fastest Lean workflow is incremental.

1. Write the datatype.
2. Write the executable function.
3. State the law as a theorem.
4. Try `simp`, `rfl`, `cases`, and `induction`.
5. If proof pressure is high, simplify the datatype or function.

Useful tactics and terms:

```lean
rfl           -- definitional equality
simp          -- simplify using definitions and simp lemmas
cases h       -- split on a value/proof
induction x   -- structural induction
constructor   -- build conjunctions/structures/proofs
exact h       -- provide exact proof term
omega         -- arithmetic over Nat/Int when available
```

Use theorem failures as design feedback. If a basic law is painful to prove, the
representation may be wrong for the semantic layer.

### Proof idiom: `native_decide` vs `rfl` vs `decide` (project convention)

`Value` (and `Clause`) derive `BEq` but **not** `DecidableEq` — the type is large and
the comparison kernel-reduces slowly. This dictates how results are asserted:

| Result shape                              | Assertion form                            |
| ----------------------------------------- | ----------------------------------------- |
| Two `Value`s (any builtin/eval output)    | `(a == b) = true := by native_decide`     |
| A fully-reducing literal (e.g. `.int 3`)  | `result = .prim (.int 3) := by rfl`        |

Use `==` + `native_decide` for `Value` comparisons — `a = b := by decide` fails for lack
of `DecidableEq`, and kernel `rfl` on a structural `Value` equality is slow or stalls.
Reserve `:= by rfl` for cases where the function reduces all the way to a literal with no
residual `Value` comparison (`lenValue (.list [..]) = .prim (.int 3)` is the canonical
one). `native_decide` compiles the decision procedure to native code, so it is the
default for anything touching `Value`.

### Totality idiom: fuel over `partial def`

Prefer total functions. When recursion is not obviously structural, use a fuel-bounded
loop (a `Nat` argument that strictly decreases, with the `fuel + 1` match arm) instead of
`partial def` — see `stringReplaceLoop`/`listFlattenFuel` in `Builtin.lean`, where the
fuel is a real structural bound (UTF-8 byte length, nesting depth). Compute the fuel from
the input so it cannot under-run.

`partial def` is acceptable only where a total encoding is genuinely impractical (the
recursive-descent parser in `Parse.lean` is the standing exception). Anywhere else,
`partial def` is a debt slated for fuel conversion — document the rationale at the
definition site if you must introduce one.

## Executable Tests

Lean proofs are not a substitute for compatibility tests against CUE. Use both. `#eval`
is fine for scratch checks during development; durable tests are theorems in the
`*Tests.lean` modules plus the fixture corpus below.

### Fixture dual-entry

A test fixture is verified along **two** paths that must agree, so a new fixture needs
both entries:

1. `testdata/cue/<subsystem>/<name>.cue` + `testdata/cue/<subsystem>/<name>.expected` —
   the source and KUE's expected output, under a subsystem subdir (`numeric/ structs/
   definitions/ …`). `.expected` is **Kue's** output format, not raw CUE's.
2. A hand-built entry in `Kue/Tests/FixturePorts.lean` whose `fileName` is the
   `<subsystem>/<name>.expected` relative subpath — the same value constructed directly as
   a Lean `Value` and formatted.

`scripts/check-fixtures.sh` diffs the CLI path (`kue < <name>.cue`) against the
Lean-port path; a missing entry on either side fails the run. For `manifest` output, use
the `<name>.manifest.expected` suffix and the manifest helpers in `FixturePorts.lean`.

### The full verify gate

A slice is not done until the single entrypoint passes:

```sh
./scripts/check.sh   # lake build + every scripts/check-*.sh gate (glob) + shellcheck scripts/*.sh
```

`check.sh` runs `lake build` (builds + checks every theorem), then every `check-*.sh` gate
by glob — fixture pairs (`check-fixtures.sh`), test-file health (`check-test-health.sh`), and
the real-config regression fixtures (`check-realworld.sh`, self-contained under
`testdata/realworld/`) — then `shellcheck scripts/*.sh`. It collects all failures and prints
a PASS/FAIL summary. A new gate needs zero wiring: drop a `scripts/check-*.sh` and the glob
picks it up.

### Oracle-checking against `cue`

Behavior is validated against the reference `cue` binary at `/Users/chakrit/go/bin/cue`,
**v0.16.1**. (Target semantics are CUE v0.15 — Kue chases *correct* v0.15 behavior, not
bug-for-bug parity; see
[`../decisions/2026-06-14-cue-compatibility-target.md`](../decisions/2026-06-14-cue-compatibility-target.md).)

Mechanics that bite:

- `cue` needs file arguments, and builtin-using fixtures need an `import` line
  (`import "list"`, `import "math"`, `import "strings"`).
- `scripts/check-fixtures.sh` runs `cue fmt --check`, so format the fixture first:
  `cue fmt --files testdata/cue/<subsystem>/<name>.cue` (or `--files testdata/cue` to
  recurse the whole corpus).
- `kue` reads stdin; `cue` reads files — keep that asymmetry in mind when comparing.
- A useful kind probe: `(<expr> & int) != _|_` tells you whether `cue` collapsed a
  result to `int`-kind (e.g. the numeric-`list`-builtin integral-collapse rule).

When `cue` is buggy or surprising and Kue does the correct thing, log it in
[`../spec/cue-divergences.md`](../spec/cue-divergences.md) (claim, `cue`
output, Kue output, why Kue is right, `cue` version).

## Design Rules for This Repo

- Model semantics before optimizing representation.
- Keep syntax, semantic values, normalization, and pretty-printing separate.
- Prefer total functions returning explicit results over partial functions.
- Use `Except Error α` when evaluation can fail with user-facing diagnostics.
- Use `Option α` only for true absence, not errors.
- Avoid clever dependent types in the first model; introduce them when they remove
  real invalid states or make proofs shorter.
- Make laws executable where practical, then prove them.
- Preserve CUE behavior intentionally; document deliberate incompatibilities.

## Common Pitfalls

- Do not confuse Lean's type lattice with CUE's value lattice. CUE's lattice is
  data modeled inside Lean.
- Do not let parser shape dictate semantic shape.
- Do not hide bottom/error behavior in `Option.none`; bottom is a semantic value.
- Do not use theorem statements as comments. If a law matters, prove it or mark it
  explicitly with `sorry` and track it.
- Do not import Mathlib casually. It is valuable, but it changes build weight.
  Add it when order/lattice libraries will save more time than they cost.

## External References

- Lean 4 home: https://lean-lang.org/
- Lean 4 language reference: https://lean-lang.org/doc/reference/latest/
- Lake build system: https://lean-lang.org/doc/reference/latest/Build-Tools-and-Distribution/Lake/
- Functional Programming in Lean: https://lean-lang.org/functional_programming_in_lean/
- Theorem Proving in Lean 4: https://lean-lang.org/theorem_proving_in_lean4/
- CUE language spec: https://cuelang.org/docs/reference/spec/
- CUE logic overview: https://cuelang.org/docs/concept/the-logic-of-cue/
