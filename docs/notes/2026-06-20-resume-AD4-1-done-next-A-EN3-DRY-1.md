# RESUME HERE — AD4-1 DONE (2026-06-20); next code slice = **A-EN3 + DRY-1** (locality batch)

Live START-HERE pointer; supersedes `2026-06-20-resume-audit-round-CLOSED-next-AD4-1.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog,
audit verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog.

## Audit state — counter = **1**. NOT due. Next audit after ~1–2 more NEW slices.

The two-phase audit closed (Phase A `8be4457` + Phase B `6b51db1`/`f9c1e56`, counter reset 0).
**AD4-1 was slice 1 of the new batch (counter now 1).** No audit until ~2–3 NEW slices land —
do NOT spawn an audit next; spawn the next CODE slice.

## Last landed — AD4-1 (comprehension-walker dedup), DONE

Behavior-preserving DRY refactor (byte-identical fixtures = proof). The four `expand*` comprehension
clause-walkers collapsed to ONE generic `ClauseOutcome β` (ctors `payload`/`bottom`/`deferred`;
`ClauseExpansion`/`ListClauseExpansion` are now `abbrev`s) + ONE generic driver pair
`expandClauseChain` + `expandForPairs` (`[EmptyCollection β] [Append β]`), parameterized solely by
the `[]`-arm body→outcome handler. The two `*ClausesWithFuel` defs are thin β-wrappers; the two
`*ForPairsWithFuel` defs were DEAD after the dedup and DROPPED (net four walkers → two combinators +
two wrappers).

- **`[_|_]`≠`_|_` asymmetry PRESERVED + newly PINNED** — it lives entirely in `onExhausted` (struct
  short-circuits a bare-bottom body to `.bottom`; list wraps any body as `.payload [body]`). Four
  new `native_decide` pins in `ComprehensionTests` (struct → `_|_`, list → `[_|_]`, both → `export`
  error). Existing D#1a/b/c pins unchanged.
- **`termination_by` PRESERVED** — combinators keep the `match fuel with | 0 | fuel+1` skeleton +
  recursive self-calls lexically visible (`onExhausted` is pure/non-recursive — the
  truncate-primitive Step-2 lambda trap avoided). Wrappers carry measure tag 2 (between the tag-0
  chain and the tag-3 `evalListItemsWithFuel` caller). No `partial`/`sorryAx` — axiom-clean.
- Gate met: `fixture pairs ok` (zero drift), cert-manager content-identical to cue v0.16.1.
  Commit + log entry landed. Full writeup: implementation-log § "AD4-1".

## NEXT CODE SLICE — **A-EN3 + DRY-1** (locality batch; the dedup family's next leader)

Why this leads: AD4-1 (FIRST in the settled sequence) is DONE; the sequence is **A-EN3+DRY-1
locality batch → AD2-1** (plan § walker/normalizer dedup family). A-EN3 + DRY-1 are bundled by
edit-LOCALITY — both CALL `defFrameRefIndices`, so doing them together avoids touching that callee +
its theorems twice. They produce TWO combinators, not one.

- **A-EN3 (LOW)** — `defFrameRefIndices`/`selfReferencedLabels`/`refsSelfEmbeddedLabel`
  (`Eval.lean`, re-confirm line-refs) are three structural folds over the full `Value` ctor tree,
  `+1`-per-frame-pusher depth, `descendClauses` for comprehension arms; differ ONLY in leaf
  (`.refId`/`.selector`) + monoid (`List Nat`/`List String`/`Bool`). Abstraction:
  `foldValueWithDepth` parameterized on monoid + leaf (the B7 shape). `closeDefFrameReadIndices`
  REUSES `defFrameRefIndices`; `embedDisjArmDeclLabels` is a shallow one-hop ref-follow — so A-EN3
  is exactly those three. Gate: B7-style agreement theorems + totality preserved.
- **DRY-1** — the let-walker extraction sibling; see the Phase-A audit doc. Bundle with A-EN3.

## ALTERNATE leaders (if A-EN3+DRY-1 set aside)

- **AD2-1** (LOW-MED — disjunction-normalizer dedup; **FILE as a slice, do NOT apply inline** — it
  flips two NAMED theorem pins + the SC-3 display contract; a human signs off). Full spec in plan.
- **A#6** (`containsBottom` fuel cap 100, `Lattice.lean`) — standalone soundness hardening, LOW.
- **SC-1b** (closed×closed-pattern, MED) / **SC-3** display-residual (LOW, spec-gap; couples AD2-1).
- **EvalOps extraction** (`Kue/EvalOps.lean`, plan item 2) — parallel-safe mechanical carve.

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (content-identical to cue). **Run cert-manager from the infra MODULE dir**
  (`cd .../prod9/infra && {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path
  invocation errors `import failed: … no cue.mod` for BOTH binaries (a cue.mod-context artifact).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path for any generator/oracle scripting.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on `main`
  when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** — EXCEPT the
  narrow oracle-as-data-source carve (data, never a gate). Correctness-over-performance.
  **Unattended/AFK → commit, don't push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3
  slices — **counter now 1, next audit after ~1–2 more NEW slices.** Per-slice duties: tests-first;
  log `cue-divergences.md`; flag `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path; may never un-park.
