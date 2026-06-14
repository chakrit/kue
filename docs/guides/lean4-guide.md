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

Lean projects are normally managed with Lake.

Common commands:

```sh
lake init kue
lake build
lake test
lake exe kue
lake update
```

Expected shape after initialization:

```text
lakefile.lean        # package, libraries, executables
lean-toolchain       # exact Lean toolchain version
Kue.lean             # top-level library module
Kue/                 # library modules
Main.lean            # executable entry point, if any
```

Use `lean-toolchain` to pin the Lean version. Do not rely on a globally floating
toolchain for semantic work.

If Mathlib is added later, use the cache before building:

```sh
lake exe cache get
lake build
```

## File Organization

Start with this layout unless the codebase establishes something better:

```text
Kue/
  Syntax.lean        # parsed/abstract CUE syntax
  Value.lean         # semantic value domain
  Order.lean         # subsumption / partial order
  Lattice.lean       # meet, join, top, bottom laws
  Default.lean       # marked/unmarked default semantics
  Eval.lean          # evaluator / normalization
  Closedness.lean    # closed structs, definitions, field admissibility
  Cycle.lean         # cycle detection and recursive values
  Examples.lean      # tiny executable examples
  Tests.lean         # theorem-style and executable checks
```

Keep parser concerns separate from semantic concerns. A mathematically clean value
domain is more important than accepting all source syntax early.

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

This is an AST-like value representation, not yet the final normalized semantic
domain. That is acceptable early. The first milestone is to make operations total
and laws explicit.

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

## Executable Tests

Lean proofs are not a substitute for compatibility tests against CUE. Use both.

Use `#eval` for tiny checks during development:

```lean
#eval add1 41
```

For durable tests, add theorem checks for laws and executable examples for expected
normal forms. Later, add golden tests comparing Kue output with the official CUE
implementation on selected examples.

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

- Lean 4 home and overview: https://lean4.dev/
- Lean 4 language guide: https://lean4.dev/language
- Lake build system: https://lean-lang.org/doc/reference/latest/Build-Tools-and-Distribution/Lake/
- Functional Programming in Lean: https://docs.lean-lang.org/lean4/doc/fplean.html
- Theorem Proving in Lean 4: https://leanprover.github.io/theorem_proving_in_lean4/
- CUE language spec: https://cuelang.org/docs/reference/spec/
- CUE logic overview: https://cuelang.org/docs/concept/the-logic-of-cue/
