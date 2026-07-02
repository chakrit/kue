# CUE Language Guide for Kue

This guide records the CUE language findings that matter for reimplementing CUE
in Kue. It is not a beginner tutorial. It is a compact semantic map for future
agents that need to make implementation decisions quickly.

## Core Identity

CUE is a constraint language where types and values are the same kind of thing.
Every CUE value participates in a single value lattice:

- top `_` means unconstrained / any value;
- bottom `_|_` means contradiction / error;
- more specific values are lower in the lattice;
- concrete data values are also values in the same lattice;
- schemas, policies, and data are unified with the same operation.

The central implementation problem is preserving this lattice model while still
supporting practical language features: structs, lists, references, defaults,
closedness, comprehensions, imports, and export-time concreteness.

## Semantic North Star

Implementation choices should be judged by whether they preserve these facts:

- unification `a & b` is greatest lower bound / meet;
- disjunction `a | b` is least upper bound / join;
- unification is commutative, associative, and idempotent;
- disjunction is commutative, associative, and idempotent;
- unification distributes over disjunction;
- evaluation order should not affect the final value;
- bottom is a normal semantic result, not merely an exception;
- export requires concrete values, while evaluation may leave values incomplete.

If a representation makes these laws hard to state or prove, treat that as a
design smell.

## Values, Types, and Bounds

CUE has primitive concrete values such as null, bools, numbers, strings, bytes,
lists, and structs. It also has type-like values and constraints:

```cue
_
_|_
null
bool
int
float
string
number
>=0
>0 & <=65535
"tcp" | "udp"
```

Do not model "type" and "value" as unrelated implementation categories. Use one
semantic value domain, with predicates or constructors for concreteness, bounds,
kind constraints, and compound values.

## Unification

Unification combines constraints and moves downward in the lattice.

```cue
port: int & >0 & <=65535
port: 8080
```

The result is `8080` if all constraints agree. Conflicts yield bottom:

```cue
x: "a" & "b" // _|_
```

For structs, successful unification merges fields. If both sides define the same
field, their values are unified:

```cue
{a: int, b: string} & {a: 1}
// {a: 1, b: string}
```

Implementation note: preserve source/conjunct provenance. It becomes important
for diagnostics, closedness, defaults, and later compatibility with official CUE.

## Disjunction

Disjunction is join / least upper bound.

```cue
proto: "tcp" | "udp"
kind: int | string
```

When a disjunction is unified with another value, distribute the unification over
the alternatives and eliminate bottom alternatives:

```cue
(int | string) & "foo" == "foo"
("a" | "b") & "c" == _|_
```

Export generally requires a disjunction to resolve to a single concrete value.
Evaluation can retain unresolved disjunctions.

Implementation note: naive expansion can explode. Start semantically simple, but
keep a path open for normalized disjunction sets, sharing, or delayed choice.

## Defaults

Defaults are marked disjunction alternatives:

```cue
mode: *"prod" | "dev"
```

A default is not just syntactic sugar. CUE models a value as optionally carrying a
default: `v` or `(v, d)` where `d` is an instance of `v`.

Important behavior:

- defaults are introduced by starred disjuncts;
- defaults are selected only when a value is needed in a concrete context;
- non-default unification can override a default;
- both required and optional fields may contain defaults;
- optional-field defaults only matter if the field is also unified with a regular
  field.

Keep marked/unmarked disjunction structure intact until the default rules have
been applied. Nesting can matter when outer and inner disjunctions are marked.

## Bottom

Bottom `_|_` represents failed constraints and other semantic errors.

Treat bottom as data in the semantic layer:

- field-level bottom should be representable;
- whole-value bottom should be representable;
- diagnostics should attach to bottom when possible;
- bottom participates in lattice laws.

Do not collapse bottom into `Except` too early. Use `Except` for implementation
failures or top-level diagnostics plumbing, but keep CUE bottom inside `Value`.

## Incompleteness and Concreteness

CUE distinguishes evaluation from manifestation/export.

Examples of incomplete but valid evaluated values:

```cue
x: int
y: string | int
z: >0 & <10
```

These may be valid under `cue eval` but invalid under `cue export` if a concrete
data value is required.

Implementation rule:

- evaluation computes constraints;
- manifestation/export selects defaults, rejects unresolved non-concrete values,
  and emits JSON/YAML/etc.

Do not force concreteness during core evaluation.

## Structs and Fields

Structs are central. They may include:

- regular fields: `a: int`;
- optional fields: `a?: int`;
- required fields: `a!: int`;
- hidden fields: `_a: int`;
- definitions: `#Schema: {...}`;
- pattern constraints: `[string]: int`;
- dynamic fields: `"\(name)": value`;
- embeddings;
- ellipses: `...` or `...T`.

Field classes are semantically different. Preserve them explicitly.

Regular fields contribute to output. Optional fields constrain a field if present.
Required fields demand a value. Hidden fields participate in evaluation but are
excluded from normal export. Definitions are schemas and are implicitly closed.

## Closedness

Open structs allow additional fields by default. Closed structs reject fields that
are not explicitly allowed by declared fields or pattern constraints.

Closedness can arise from:

- the `close` builtin;
- definitions such as `#Name`;
- recursively through definitions;
- unification with closed structs.

Ellipsis can open a struct or define what additional fields must satisfy:

```cue
open: {
  a: int
  ...
}

typedTail: {
  a: int
  ...string
}
```

The spec describes closing a struct as equivalent to adding `..._|_`.

Implementation note: closedness is one of the hardest practical algorithms. Do
not represent it as only a boolean on a final struct. You will likely need
provenance: which conjuncts introduced which fields, patterns, embeddings, and
closedness constraints.

## Definitions

Definitions are fields whose labels start with `#`.

```cue
#Port: int & >0 & <=65535
#Server: {
  host: string
  port: #Port
}
```

Definitions are not emitted as regular data. Struct definitions are implicitly
closed and recursively close nested structs unless opened explicitly.

Implementation rule: definitions are schema values with visibility/export
behavior plus closedness behavior. Avoid treating them as mere named aliases.

## References and Scoping

CUE uses lexical scoping. A reference resolves to the nearest enclosing binding
with the referenced name. Package clauses identify files in a package; the package
name itself is not a declaration in scope.

Important binding forms:

- fields;
- aliases;
- `let`;
- comprehension variables;
- imports;
- package-level declarations.

Implementation note: use an explicit resolver phase that records binding
identities. Do not resolve references by repeated string lookup during evaluation
unless the model is only a temporary prototype.

## Cycles

CUE permits some reference cycles and rejects or bottoms out others.

Examples:

```cue
x: x          // should evaluate like `_`

b: c
c: d
d: b          // reference cycle
```

The spec requires implementations to interpret or reject cycles according to its
cycle rules. Some cycles can be broken by postponing validation, especially when
an atom is unified with an expression.

Implementation note: cycle handling should be designed together with references,
normalization, and bottom. Do not rely on host-language recursion failure.

## Lists

Lists can be closed or open:

```cue
[1, 2, 3]
[1, 2, ...int]
```

Open list tails constrain additional elements. Fixed indices and tail constraints
need separate representation. List export requires concrete element values and a
known finite shape unless the target operation explicitly supports incompleteness.

## Comprehensions

CUE has list and field comprehensions with `for`, `if`, and `let` clauses.

Important behavior:

- clause sequences nest left to right;
- `for` over lists iterates over elements after closing the list;
- `for` over structs iterates over non-optional regular fields;
- guards skip iterations when false;
- `let` creates scoped intermediate bindings;
- field comprehensions can introduce dynamic fields.

Implementation rule: comprehensions are not just syntax expansion. Their behavior
interacts with scoping, optional fields, dynamic labels, and closedness.

## Packages, Instances, and Modules

CUE configurations are built from instances. An instance is built from one or more
files in the same package. Files in a package are combined; source file ordering
should not matter.

Source files may contain:

- an optional package clause;
- imports;
- declarations;
- embeddings.

Imports expose exported identifiers from imported packages through qualified
identifiers. It is illegal for a package to import itself directly or indirectly.

Modules manage dependency versions. Modern CUE modules are distributed through
OCI-compliant registries and use `cue.mod/module.cue`.

Implementation staging:

1. Implement package-free core expressions and values.
2. Add file/package merging.
3. Add imports and module resolution.
4. Add registry/module compatibility later.

## Builtins

CUE has predeclared identifiers and builtins, including primitive type values and
functions such as `len`, `close`, `and`, and `or`.

Implement builtins as semantic functions with clear totality/error behavior.
Avoid hard-coding builtin behavior into unrelated evaluator paths.

## Compatibility Test Targets

The CUE spec is the authority; the `cue` binary (v0.16.1) is a fallible cross-check,
not an oracle. Byte-parity with `cue` is never the gate — where `cue` disagrees with
the spec it is wrong, and the disagreement is recorded in
[`cue-divergences.md`](cue-divergences.md) (spec-silent points go to
[`cue-spec-gaps.md`](cue-spec-gaps.md)). Cross-check against `cue` to surface
candidate divergences, then adjudicate each against the spec. Build tests in layers:

- spec examples for unification and disjunction;
- default selection examples;
- closed struct typo examples;
- optional and required field examples;
- reference cycle examples;
- comprehension examples;
- package merge examples;
- export vs eval differences;
- historical evalv3 regression cases when available.

Each test should record whether it targets `eval`, `export`, validation, or error
diagnostics. These are different observable surfaces.

## Implementation Risks

High-risk areas:

- defaults inside nested disjunctions;
- disjunction explosion;
- closedness and embeddings;
- optional fields combined with defaults;
- cycles involving arithmetic or references;
- dynamic fields and comprehensions;
- incomplete values at export boundaries;
- diagnostics that depend on provenance.

Design the Lean model so these areas are explicit, not hidden in helper code.

## External References

- CUE language specification: https://cuelang.org/docs/reference/spec/
- The logic of CUE: https://cuelang.org/docs/concept/the-logic-of-cue/
- Upgrading from evalv2 to evalv3: https://cuelang.org/docs/concept/faq/upgrading-from-evalv2-to-evalv3/
- CUE modules reference: https://cuelang.org/docs/reference/modules/
- Default values how-to: https://cuelang.org/docs/howto/specify-a-default-value-for-a-field/
- Reference cycles tour: https://cuelang.org/docs/tour/references/cycle/
