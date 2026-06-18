# RESUME HERE — B6 PARTIAL (gaps 1+2 landed, one sub-gap DEFERRED) (2026-06-19)

Supersedes `2026-06-19-b2-5-pattern-tail-unify-landed.md`. Standing grant in effect (autonomy /
Lean-into-Lean-4 / commit-push freely / specs as restore point). Full record:
`docs/reference/implementation-log.md` ("B6 — def-body closedness through a regular field" entry);
plan: `docs/spec/plan.md` (B6 marked PARTIAL with the deferred sub-gap + design-spike).

Commits `3b2beb6` (design-spike) + `7da65d8` (implementation) on `main`. **NOT yet pushed** — push
`gh:main` is pending (see below).

## What landed — B6 gaps 1+2 (one commit + one design-spike commit)

A closed `#Def` nested under a REGULAR field now rejects undeclared use-site fields, matching cue
v0.16.1. `a: {#Inner: {x:int}}; out: a.#Inner & {x:1, extra:2}` → `out.extra` rejected (was
admitted). Eager `x.#Inner & {extra}` fixed by the same change. Open `#Inner: {x:int, ...}` still
admits the extra (no over-close).

- **`normalizeFieldWithFuel` (`Normalize.lean`)**: a non-hidden/non-let regular field's value now
  recurses through the SPINE walker `normalizeDefinitionsWithFuel` (preserves host openness, closes
  nested `#Def`s) instead of being returned unchanged. HIDDEN fields stay untouched → import
  bindings cue-lazy (A2 trap dodged; B6 decoupled from A2-followup).
- Gap 2 was the SAME root cause: once normalize closes the def, `selectEvaluatedField` returns the
  closed body verbatim and the existing `mergeStructN`/`applyStructClosedness` enforces it.

### Tests
- 2 fixtures `testdata/cue/definitions/nested_def_{,open_}under_regular_field` (+ FixturePorts).
- 3 `native_decide` pins in EvalTests (closed rejects, eager-selector rejects, open admits).

**Gate met:** `lake build` green (96 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok` (only
the 2 new pairs drift; `def_open_tail_addfield` over-close sentinel + all import/def-meet module
fixtures byte-identical → no over/under-close regression). All pins oracle-checked vs cue v0.16.1.

## DEFERRED sub-gap (the honest stop — read before reopening B6)

`#D.l[0] & {b}` / `#D.r & {b}` — selecting a nested REGULAR-field struct through a NON-instantiated
def LITERAL. cue closes these on the direct def-path but RE-OPENS them on ANY instantiation:
- `#D: {r: {a:int}}; #D.r & {a:1,b:2}` → cue REJECTS `b`.
- `z: #D & {}; z.r & {a:1,b:2}` → cue ADMITS `b`. Same for `y: #D; y.r & {...}`.

So nested-regular-struct closedness is a property of the literal def-path SELECTION, shed by
`&`-unification. Kue currently admits `b` in ALL three (under-close on the direct path). Enforcing it
needs the closing-vs-instantiation distinction in `mergeStructN`'s closedness composition — the meet
must RE-OPEN nested regular structs on instantiation (the `eval_def_with_self_ref_closes` EvalTests
pin at ~line 1075 DEPENDS on instantiated `out` staying `.regularOpen`). That is a value-representation
change (a "closed on this selection path" marker the meet clears on `&`), larger than one slice and
over-close-prone — STOPPED per correctness-over-performance rather than force it. NOT a cue
divergence (Kue is wrong, cue right).

## Next step

1. **PUSH** `3b2beb6`+`7da65d8` to `gh:main` (pending — green, ready).
2. **TWO-PHASE AUDIT is now OVERDUE.** Cadence: B2.5 closed the prior audit's batch; CP3-pre/flip
   were audited (#6). B6 is 1 slice past audit #6 → still within the 2–3 window, but B2.5's
   breadcrumb already flagged the audit due NOW (it counts CP3-pre+flip+B2.5). Run the two-phase
   audit per `docs/guides/slice-loop.md` (NOT `/ace-audit`) over CP3-pre/flip/B2.5/B6 before more
   feature slices — (A) code-quality then (B) architecture/refactor.
3. Then candidates: **B6 deferred sub-gap** (def-path-selection closed-marker design-slice) /
   **B2b** (structComp `open_`/`hasTail` collapse — design DONE, last of B2) / **A2-followup**
   (import-binding marker) / **item 1** (argocd full-app end-to-end, perf-bound) / **item 7**
   (perf wall). See plan.md backlog ordering: drain CORRECTNESS before CONSISTENCY before perf.
