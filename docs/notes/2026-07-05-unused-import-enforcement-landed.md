# UNUSED-IMPORT enforcement landed (2026-07-05)

Sibling of BUILTIN-IMPORT-LENIENCY (landed earlier today, `1f292a8`). Together they close
cue's full import contract: `used ⇒ declared` (builtin slice) and now `declared ⇒ used`.

## What landed

An `import` a file never references is now cue's `imported and not used` build error — the
document collapses to a bottom. Enforced in `resolveImports` (`Kue/Parse.lean`), which wraps
the existing `applyBuiltinAliases` at both parse entry points (`parseDocument`,
`parseDocumentFile`):

1. `collectReferencedHeads` walks the parsed body BEFORE canonicalization, gathering every
   referenced package head (`.ref` labels — covering selector bases and deferred stdlib
   consts — plus `.builtinCall` name heads, aliased-as-written).
2. `unusedImports` filters imports whose `importLocalBindName` (alias > `:id` qualifier >
   last-path-element) is absent from that set.
3. Any unused → `.bottomWith [.importedNotUsed path alias]` (new `BottomReason` variant),
   one reason per unused import.

Detection only UNDER-reports (an unmodeled reference leaves the import counted as used), so a
genuinely-used import is never mis-flagged — the soundness direction that matters.

## Migration (Law: convention lands with its migration)

632-file scan: ZERO genuine unused imports. Two files flagged, both pre-existing ERROR
fixtures where a prior error supersedes (`import_name_redeclaration` → redeclaration error
wins; `qualified_import_invalid_id` → invalid-package-id parse error precedes). cert-manager:
no imports, export byte-identical. Two stale `ParseTests` that pinned the old leniency
retargeted to the enforced bottom.

No grep gate: same aliasing/qualifier/shadowing reasons BUILTIN-IMPORT found one infeasible;
the runtime enforces natively (stronger guard).

## Residual

CLI renders the bottom as generic `conflicting values (bottom)`, not cue's `imported and not
used: "<path>"` — same message-generality residual as the un-imported-builtin case. The
structured `.importedNotUsed` reason carries path+alias. Recorded `cue-spec-gaps.md`.

## Next

Two-phase audit window: this + recent slices (BUILTIN-IMPORT, GDA-FLOAT-RENDER, B3d-6b-leg2,
consolidation) since the last audit — check if one is due. Backlog per plan.md OPEN:
BYTES-SLICE-MISSING, BYTE-INTERPOLATION, B3d-6b network-gated legs.
