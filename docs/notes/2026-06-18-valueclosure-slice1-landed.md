# RESUME HERE — Value.closure slice 1 landed (2026-06-18)

START-HERE pointer; supersedes `2026-06-18-session-resume.md` (the "holding on a decision"
breadcrumb — the decision is now MADE and slice 1 is landed). Tree clean, pushed to
`gh:main`.

## What just landed

**Frontier #1 (`Value.closure`) is GREEN-LIT and underway.** chakrit approved the big
churn; slice 1 of 5 (`closure-ctor`) is committed: the `Value.closure` constructor +
inert consumer wiring, ZERO behavior change. Build 86 jobs, `fixture pairs ok`, 7
`native_decide`/`rfl` pins in `EvalTests.lean`.

The constructor:

```
| closure (capturedEnv : List (Nat × List Field)) (body : Value)
```

`capturedEnv` is *defeq* to `Eval.Env` (layering-forced: `Value` can't carry an Eval
`Frame` without inverting the import graph, so the env is inlined as base-layer data). The
full id-stack travels (a def body's depth>0 cross-pkg refs walk the import chain). Forced
edit set was exactly five exhaustive (catch-all-free) consumers: `valueTag` (tag 29),
`evalValueCoreWithFuel` (passthrough), `manifestWithFuel` (`.incomplete`),
`formatValueWithFuel` (prints body), `meetCore` (`.bottom`). Order/Normalize/Resolve/
`meetWithFuel` absorbed it via their catch-alls — no edit.

## The Value.closure slice sequence (AUTHORITATIVE — full detail in `plan.md`)

`plan.md` § "Value.closure work plan (frontier #1 — chakrit-approved churn, 2026-06-18)"
is the authority. Ordered:

1. **closure-ctor** — constructor + inert wiring. ✅ LANDED this session.
2. **closure-eval** — `evalValueCoreWithFuel`'s `.closure` arm forces `body` under
   `capturedEnv` (rebased). Still no producer ⇒ dead code, but the semantic anchor.
   MECHANICAL. **← NEXT SLICE.**
3. **closure-producer** — import-selector / depth>0 `.conj` fallback emits a
   `.closure capturedPkgEnv defBody` instead of eagerly collapsing the body. FIRST
   behavior change. Needs a design sub-spike (exact trigger shape; must not regress
   same-package def-meet).
4. **closure-meet** — force a closure when met with a use-site struct: push `capturedEnv`,
   splice the use-site as an extra conjunct (reuse `lazyConjMergedFields`/`mergeConjFields`),
   eval. This is where "meet stops being pure over opaque refs" (`Lattice.lean:387`). The
   force MUST happen in `Eval` (meet is pure, no `EvalM`). Needs a design sub-spike: the
   force-and-splice point + the new cycle shape (closure capturing a self-ref frame → key
   `visited` by captured ids; `fuel` stays LOAD-BEARING in `EvalKey`).
5. **closure-regression** — add `testdata/modules/crosspkg_defmeet/` (`parts/m.cue` +
   `top.cue` + `cue.mod`, `expected` = `cue export` `{"out":"keel"}`), `native_decide`
   pins, edge-case audit (`Self={…}` alias form, two-decl form, nested import, closed/
   pattern interplay). Proves the unlock.

## Next step for the loop

Spawn slice 2 (`closure-eval`): wire `evalValueCoreWithFuel`'s `.closure capturedEnv body`
arm to evaluate `body` under `capturedEnv` (replace ambient env with captured, rebase
depth), pin with a hand-built `.closure` eval-theorem. MECHANICAL — no producer yet, so it
stays dead code but anchors slices 3-4. Then slices 3 & 4 each warrant a short design
sub-spike before code.

## Standing context (durable, do not relearn)

- **Release:** ~1 datestamped alpha/day, `0.1.0-alpha.YYYYMMDD[.N]`, **local
  `scripts/release.sh` only — CI/GitHub Actions BANNED**. Latest `v0.1.0-alpha.20260617.3`.
  Do NOT touch `scripts/release.sh`, `packaging/`, the tap. Did NOT cut a release this
  session (mid-churn).
- **Loop:** `docs/guides/slice-loop.md` — 2–3 slices → Phase A code-quality audit → Phase B
  architecture audit. Audit cadence: this is a CODE-landing slice; an audit pass is due
  around 1–2 more substantive slices (last audit-reference `b45848b`).
- **Safety:** prod9 + cue cache READ-ONLY (eval/probe only). The session bash output filter
  mangles piped/heredoc git input → use `git commit -F /tmp/msg`. Trust `lake build` as
  coverage ground-truth over grep/wc. NO `git checkout`/`restore`/`reset`.
- **`fuel` is LOAD-BEARING** in `EvalKey` (263 fuel-truncation conflicts) — never drop it
  from the memo key when adapting cycle/memo handling in slices 4-5.
- **Perf hang (frontier #2)** is downstream — real apps error at #1 (~0.9s) before the
  blowup, so unreachable until slice 5 lands; re-profile then, then frame-id sharing.
- **cue oracle:** `/Users/chakrit/go/bin/cue` v0.16.1.
