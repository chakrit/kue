# BUILTIN-IMPORT-LENIENCY — landed 2026-07-05

## What

A package-qualified stdlib builtin reference now resolves ONLY when its package is imported,
matching cue v0.16.1. `strings.ToUpper("x")` / `list.Ascending` with no `import "<pkg>"` is
`reference "<pkg>" not found` (bottom); imported (directly or aliased) → resolves. Closes the last
standing leniency observation (was: kue resolved stdlib builtins by package name regardless of
import state).

## How

Enforcement lives in the import-aware post-parse pass — the single choke point both `parseDocument`
(single-file/inline eval) and `parseDocumentFile` (module load) flow through, so per-file import
scope is honored exactly as cue's file-scoped imports:

- `applyBuiltinAliases` (`Kue/Parse.lean`) now ALWAYS walks (was a no-op absent a builtin alias);
  threads `importedBuiltinPackages imports` into `canonicalizeBuiltinCalls`.
- `gateBuiltinImport` — a qualified `.builtinCall` head whose package ∈ `builtinPackageNames`
  (`Kue/Value.lean`) but ∉ imported → `.bottomWith [.unresolvedReference pkg]`.
- `resolveBuiltinConstSelector` — the constant form (`list.Ascending`) is no longer resolved in the
  parser (it defers as `.selector (.ref pkg) label`); resolved here, gated on import. Replaces the
  old `canonicalizeBuiltinConst?` (aliased-only, ungated).

Slice-operator collision: cue exposes a real import-gated `list.Slice(...)`, but kue also desugared
the operator `x[lo:hi]` to `list.Slice`. Fixed by desugaring the operator to a NEW import-exempt
core `slice` builtin (distinct from the gated public `list.Slice`). Slicing needs no import;
explicit `list.Slice(...)` does. Deferred-slice residuals render `slice(...)` now.

## Migration (the Law)

ZERO fixtures migrated — the whole `.cue` corpus already imported (cue-oracle-derived), and the
one parse-driven builtin test suite (SortTests) already carried `import "list"`. Inline
BuiltinTests/StringsTests hit the dispatch functions directly (bypass parse), unaffected. No grep
gate wired: a robust one is infeasible (aliases / local-field shadowing / user packages named like
a builtin defeat a naive `pkg.` scan) AND the runtime now enforces it natively — stronger than a
grep. cert-manager canary uses no builtins; byte-identical.

## Verify

`./scripts/check.sh` GREEN. `ImportEnforcementTests.lean` = 17 native_decide theorems (call/const
forms, aliased/wrong/missing/multiple/nested imports, slice-operator exemption vs public
`list.Slice`, local-field shadow). `ParseTests` const-resolver test migrated;
`SliceTests`/`cue-spec-gaps`/`plan.md`/`compat-assumptions.md` retractions same slice.

## Next

Backlog per plan.md OPEN: BYTES-SLICE-MISSING, BYTE-INTERPOLATION, B3d-6b (network-gated).
Separate remaining leniency (NOT this slice, recorded in compat-assumptions): UNUSED-IMPORT — kue
does not flag an imported-but-unused package (cue errors `imported and not used`); same
dead-binding-detection family as unreferenced-`let`. [Retraction 2026-07-05: UNUSED-IMPORT has
since LANDED — enforced in `resolveImports`; see `2026-07-05-unused-import-enforcement-landed.md`
and compat-assumptions UNUSED-IMPORT → CLOSED.] **Two-phase audit window**: check whether one
is due (this + recent slices since the last audit).
