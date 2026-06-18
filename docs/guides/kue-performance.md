# Writing Kue-Friendly CUE (Performance Guide)

Kue prioritizes **correctness over speed** (see
[the decision](../decisions/2026-06-18-correctness-over-performance.md)). It is usable for
ordinary configs, but some CUE patterns cost far more in Kue than in `cue`. This guide
lists what is expensive, *why*, and how to structure CUE so Kue evaluates it fast.

**Living doc.** The engine is actively optimized and these characteristics shift as
sound optimizations land. Treat specific timings as snapshots, not guarantees. If you hit
a slow case not covered here, file it (see "Reporting a slow case" below).

## How Kue evaluates (the cost model)

Kue uses **fuel-bounded, total evaluation**: every value is reduced under a fuel budget
(no host-language recursion, so termination is guaranteed). `fuel` is *load-bearing* — it
is what tells a real value apart from a cycle-truncated one — so it cannot simply be
lowered to go faster.

The cost of evaluating a value is roughly:

```
per-level work  ×  the fuel depth at which the value converges
```

A value that settles at shallow depth is cheap. A value that only stabilizes after many
fuel levels — deep self-reference, long indirection chains — pays its per-level cost over
and over until it converges, and (today) re-derives the already-converged result across
the remaining fuel levels up to the ceiling. That re-derivation, **fuel multiplication**,
is the dominant real-world cost. (A measured example: a real `#ClusterIssuer`-style app
converges to the correct value at fuel ~16, but the default ceiling re-derives it across
~84 further levels at ~1.35× each — effectively unbounded. A sound *fuel-saturation
caching* optimization to stop re-deriving converged subtrees is planned.)

## Expensive patterns (minimize these)

| Pattern | Why it is slow | Faster shape |
|----------------------------------|--------------------------------------|----------------------------------|
| Deep self-referential defs — `#D: Self={ … Self.#x … }` chained many levels | Raises the convergence depth → fuel multiplication | Flatten; resolve shared values once at a shallow level and reference them |
| Long alias / selector chains — `#A: parts.#M`, `#B: #A`, `#C: #B`, … | Each hop adds indirection that must re-resolve per fuel level | Reference the terminal value directly where practical |
| Deep cross-package embed chains — `#Outer{ pkg.#Mid{ pkg.#Inner } }` | Correct, but each embedded level adds convergence depth | Keep embedding shallow; prefer a few wide defs over many nested ones |
| Gratuitously duplicating a large sub-expression across fields | Historically caused exponential blow-up | Mostly mitigated now (see below), but still cheaper to bind once and reference |

## Cheap patterns (prefer these)

- **Concrete values and shallow structs** — nothing to converge.
- **References that resolve in a few steps** — short indirection, shallow nesting.
- **Flat definitions** over deep self-referential nesting — lower convergence depth is the
  single biggest lever.
- **Binding a shared sub-value once** and referencing it, rather than re-inlining it.

## What the engine already handles for you

- **Structurally-identical re-pushes share work.** Duplicating the same sub-expression
  under multiple fields (`{a: B, b: B}`) used to blow up exponentially (each copy pushed a
  fresh evaluation frame). Frame-id sharing now reuses one frame for structurally-identical
  pushes under the same scope, so this is no longer exponential. You still pay convergence
  depth, so deep duplicated nesting is cheaper avoided, but flat duplication is fine.
- **Forced cross-package def-meet is memoized**, so repeated use of the same imported def
  with the same use-site does not re-evaluate from scratch.

## Known limitations (current)

- **Fuel multiplication is not yet eliminated.** Apps that converge correctly but at
  moderate depth (e.g. real prod9 infra apps using deep `Self=` def chains) are correct but
  currently slow. The sound fix (fuel-saturation caching) is designed and pending; until it
  lands, the practical advice above (flatten, shorten chains) is the lever you control.
- **Field ordering** in output may differ from `cue` (`cue` orders `ref & {own}` own-fields
  first; Kue is left-struct first). This is a byte-diffing concern, not a correctness or
  speed one (YAML maps are unordered).

## Reporting a slow case

1. Reduce to a **minimal repro** (smallest CUE that is still slow).
2. Record `kue export` wall-clock vs `cue` on the same input.
3. Note the shape (which expensive pattern above, or a new one).
4. File it in `docs/spec/plan.md` so it becomes a perf slice; if it is a new slow pattern,
   add it to the table here.
