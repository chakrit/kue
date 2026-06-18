# RESUME HERE — A2 + A3 audit fix-slices landed (2026-06-18)

Newest START-HERE; supersedes `2026-06-18-catchall-soundness-sweep-landed.md` as the
pointer. Tree clean, pushed to `gh:main` (HEAD `96bef05`). Live roadmap:
[`../spec/plan.md`](../spec/plan.md) (authoritative). Full slice detail:
[`../reference/implementation-log.md`](../reference/implementation-log.md) entry
"A2 + A3 audit fix-slices".

## What just landed

The two remaining MEDIUM Phase-A correctness findings. **A3 DONE**; **A2 BLOCKED** on a
representation change — its diagnosed fix proved unsound, reverted to the sound baseline,
proper design filed.

- **A3 — disjunction definedness by LIVE arms (`96bef05`).** `classifyDefinedness`
  (Eval.lean) now classifies a `.disj` by its `liveAlternatives`: no live arm ⇒ `.error`
  (the disjunction IS bottom), ≥1 live arm ⇒ `.defined`. The "≥1 live arm" runtime
  invariant was NOT type-enforced; a `.disj []` / `.disj [all-bottom]` reaching a presence
  test (`X != _|_`) would misclassify absent as present. Now checked at the one site
  soundness depends on it. Chose this defensive classification over a blanket smart
  `mkDisj` (option a): several sites build a `.disj` where pruning is WRONG
  (`remapConjAlternatives` alpha-renaming, conj-distribution), so a universal
  `normalizeDisj` route is not semantics-preserving in one slice. Pins (PresenceTests):
  live disj `.defined`; empty + all-bottom disj `.error`; presence test over all-bottom
  disj reports absent. Live default/plain-disj guard regression-checked byte-identical to
  cue v0.16.1.

- **A2 — hidden-field deep bottom: unsound fix reverted (`46bd161`).** Implemented the
  diagnosed output-spine recurse, then DISPROVED it with a 3-file local repro (a `main`
  importing a `dep` package whose unreferenced fields hold both a derived conflict AND an
  explicit `_|_` literal): cue exports `main` cleanly — cue's laziness tracks
  OUTPUT-REACHABILITY (referenced via `pkg.#X`), NOT field class, and is equally lazy on an
  explicit `_|_` literal as on a derived conflict. `bindImports` (Module.lean:160) binds
  each imported package as an ordinary `FieldClass.hidden` field, indistinguishable from a
  real in-file `#u`; the recurse re-bottomed cert-manager + the repro. Reverted to the
  SOUND shallow `isBottom` (per correctness-over-perf), documented the hole in the code
  comment + plan.

## Known gap (tracked, NOT a cue bug — Kue wrong)

`{#u: {x: _|_}}` exports `{}` where cue errors. The reached-vs-unreferenced predicate is
not locally reconstructible at manifest with the current representation. **A2-followup**
(the real fix, a design-slice in plan.md): add an import-binding marker — a distinct
`FieldClass` axis (e.g. `packageBinding`) or a value wrapper on the synthetic hidden field
— so manifest treats bound packages as cue-lazy while still recursing real in-file hidden
fields' output spines. Then ship the `{#u: {x: _|_}}` → error fix + fixture.

## Verify (both commits)

`lake build` 86 jobs green; `scripts/check-fixtures.sh` → `fixture pairs ok` (zero
byte-drift); no shell scripts changed (shellcheck N/A); cert-manager import laziness
confirmed unchanged via the local repro (kue `{out:{ok:1}}` = cue).

## Next step

**TWO-PHASE AUDIT IS NOW DUE.** 2 slices have landed since the last audit: the A1+B1
catch-all sweep, and this A2+A3 slice. Run [`../guides/slice-loop.md`](../guides/slice-loop.md)
audits sequentially — **(A) code-quality** over `46bd161..96bef05`, then **(B)
architecture/refactor/cleanup** over the whole module graph. Do NOT invoke `/ace-audit`;
follow the guide. Fold findings into `plan.md` as fix-slices.

After the audit, the ranked frontier (plan.md Live Backlog): **A2-followup** design-slice
(the import-binding marker — also subsumes the B2 struct-constructor unification's interest
in tightening field representations), **B6** definition-body closedness design-spike, **B2**
headline struct-constructor refactor, **item 1** follow-up.
