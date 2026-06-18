# RESUME HERE — B2b DONE, B2 struct-family unification COMPLETE (2026-06-19)

Supersedes `2026-06-19-b6-regular-field-closedness-landed.md`. Standing grant in effect (autonomy /
Lean-into-Lean-4 / commit-push freely / specs as restore point). Full record:
`docs/reference/implementation-log.md` ("B2b — structComp two-bool → StructOpenness" entry);
plan: `docs/spec/plan.md` (B2b marked DONE; B2 marked COMPLETE).

## What landed — B2b (the last `(open_, hasTail)` two-bool)

Collapsed `Value.structComp`'s two-bool into one `StructOpenness` (arity 4→3), completing the B2
struct-family unification. The whole struct family — 1 unified meet-bearing `struct` + 1 pre-eval
`structComp` — now carries ZERO `open_`/`hasTail` two-bools. Byte-identical (pure representation
change): the reachable two-bool states map 1:1 onto the three `StructOpenness` states.

- **`Value.structComp (fields) (comprehensions) (openness : StructOpenness)`** — KEPT a DISTINCT
  pre-eval ctor (option (a)), NOT folded into the meet-bearing `struct` (option (b) rejected: it
  never reaches meet — the eager arm expands it into `struct` first — so a `comprehensions` field on
  `struct` would re-introduce a nonsense state). `structComp` has no tail VALUE, so `defOpenViaTail`
  means "open via bare `...`, no stored tail" — coherent.
- **The one semantic site:** `normalizeDefinitionValueWithFuel`'s `open_ := hasTail` → the total
  `StructOpenness.closeDefBody` (`regularOpen ↦ defClosed`, `defOpenViaTail` fixed, `defClosed`
  fixed). Parse: `hasTail` → `defOpenViaTail` else `regularOpen`. Eval consumers pass
  `openness.isOpen` where they passed `open_`/`defOpen`.
- **62 test literals migrated** (`true false → .regularOpen`, `false false → .defClosed`,
  `true true → .defOpenViaTail`) across 7 test files, compiler-driven; the `.field (hidden
  definition)` same-shape two-bool guarded against (left untouched).
- **Pins:** `closeDefBody` (3 arms) + a `normalizeDefinitionValue` end-to-end pin in `LatticeTests`.

**Gate met:** `lake build` green (96 jobs incl. all `native_decide`), `scripts/check-fixtures.sh` →
`fixture pairs ok` ZERO byte-drift, `shellcheck` clean. No perf change (pure rep; cert-manager/
`packs.#Argo` covered by the zero-drift suite — no `kue-performance.md` edit).

## Next step

1. **TWO-PHASE AUDIT is now DUE.** B2b is 2 slices since audit #6 (B6 + B2b). Run the two-phase
   audit per `docs/guides/slice-loop.md` (NOT `/ace-audit`) over the recent batch — (A) code-quality
   then (B) architecture/refactor — before more feature slices. Mandatory at the 2–3-slice mark.
2. Then candidates (drain CORRECTNESS before CONSISTENCY before perf; B2/consistency now closed):
   - **B6 deferred sub-gap** (CORRECTNESS) — the closing-vs-instantiation distinction
     (`#D.r & {b}` direct-path closedness shed by `&`); needs a value-representation design-slice
     (a "closed on this selection path" marker the meet clears on `&`). See the prior breadcrumb +
     plan B6. Over-close-prone; design first.
   - **A2-followup** (CORRECTNESS, narrow) — `{#u:{x:_|_}}` shape, needs the import-binding-marker
     representation spike; pairs with B6's normalize work.
   - **item 7** (PERF wall) — frame-id canonical identity; gates FULL argocd (cert-manager ~92s,
     `argo` >200s). Audit-heavy/risky; wants a clear runway after the correctness backlog drains.
   See `docs/spec/plan.md` "Post-B2 re-ranking".
