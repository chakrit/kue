# RESUME HERE — Value.closure slice 2 landed (2026-06-18)

START-HERE pointer; supersedes `2026-06-18-valueclosure-slice1-landed.md`. Tree clean,
pushed to `gh:main`.

## What just landed

**Frontier #1 (`Value.closure`) slice 2 of 5 (`closure-eval`) is committed.**
`evalValueCoreWithFuel`'s `.closure capturedEnv body` arm now FORCES the body — it was an
inert passthrough after slice 1. Build 86 jobs, `fixture pairs ok` (zero drift — still dead
code from the producer's view), 6 `native_decide` pins in `EvalTests.lean`.

The arm:

```
| fuel + 1, .closure capturedEnv body =>
    evalValueWithFuel fuel capturedEnv [] body
```

**Env semantics chosen (lexical, not dynamic, scope):** the body evaluates under
`capturedEnv` ALONE — the call-site `env` is fully DISCARDED, not appended/prefixed. A
closure resolves against its definition site; that's why the full id-stack is captured
(plan §"The shape"). `visited` resets to `[]` (call-site slot markers index call-site
frames, not captured ones — mirrors the depth>0 ref arm that resets visited on crossing
into an outer frame). `fuel` decrements `fuel+1 → fuel` exactly as every arm — NEVER
dropped (LOAD-BEARING in `EvalKey`). At `fuel = 0` the closure degrades through the generic
`| 0, value => pure value` arm: pass-through, no crash/loop. Termination unchanged.

## The Value.closure slice sequence (AUTHORITATIVE — full detail in `plan.md`)

`plan.md` § "Value.closure work plan (frontier #1 …)" is the authority. Ordered:

1. **closure-ctor** — constructor + inert wiring. ✅ LANDED (`26a2040`).
2. **closure-eval** — `.closure` arm forces body under captured env. ✅ LANDED this session.
3. **closure-producer** — import-selector / depth>0 `.conj` fallback EMITS a
   `.closure capturedPkgEnv defBody` instead of eagerly collapsing the body. FIRST behavior
   change. Needs a design sub-spike. **← NEXT SLICE.**
4. **closure-meet** — force a closure when met with a use-site struct (splice use-site as an
   extra conjunct, eval). "Meet stops being pure over opaque refs" (`Lattice.lean:387`).
   Force MUST happen in `Eval` (meet is pure, no `EvalM`). Needs a design sub-spike.
5. **closure-regression** — `testdata/modules/crosspkg_defmeet/` + pins, edge-case audit.

## Next step for the loop — slice 3 (`closure-producer`) DESIGN SUB-SPIKE FIRST

This is the FIRST behavior-changing slice; the plan flags it as needing its own design
sub-spike before code. What the spike must pin down (discovered this slice + carried from
recon):

- **Exact trigger site.** The eager-collapse happens because `conjStructOperand?`
  (`Eval.lean:816-831`) has NO `.selector` arm — an import-selector conjunct
  (`parts.#M`) falls through to the eval-then-`meet` path (`Eval.lean:931-933`,
  `lazyConjMergedFields` returns `none`), so the def body evaluates in the package frame
  (collapsing `out:#name`→`string`) BEFORE the use-site `#name:"keel"` unifies. The
  producer branch belongs at the `.selector (.refId id) label` arm (`Eval.lean:958-963`)
  and/or the `.conj` fallback: when the base resolves to an imported def struct reached
  through a **depth>0** binding, yield `.closure capturedPkgEnv defBody` instead of the
  eager `selectEvaluatedField`.
- **Same-package def-meet NON-REGRESSION constraint (hard).** Same-package `#Def & {…}`
  still wants the existing lazy-conj merge (`lazyConjMergedFields`/`conjStructOperand?`
  depth==0 path) — do NOT route it through a closure. Gate the closure emission STRICTLY on
  the depth>0 / cross-package import-selector shape. The depth==0 boundary in
  `conjStructOperand?` (`:822`) is already the safety line; the producer must respect it.
- **The (a)-narrowed trap (do NOT take it).** A selector arm that splices only depth-0-ref
  def bodies fixes a toy fixture but provably does NOT unblock real `#ServiceAccount`/
  `#Deployment` (their bodies have depth>0 cross-package embeds → need the full captured
  env). Only the env-carrying closure (option b) unblocks the real apps. Recon detail in
  `plan.md` §"DECISION NEEDED" item 1 and `docs/notes/2026-06-17-realapp-eval-crosspkg-defmeet-diagnosis.md`.
- **What `capturedEnv` must be at emit time.** The full id-stack of the imported package's
  eval env (the frame chain the def body resolves against), captured at the resolution
  point — so the body's own depth>0 cross-package embeds still walk the import chain when
  forced. Slice 2's eval arm already consumes exactly this shape.
- The slice-2 eval arm is the consumer; slice 3 only needs to CONSTRUCT a `.closure` whose
  `capturedEnv` is the package env and whose `body` is the unevaluated def struct, then the
  meet/force (slice 4) splices the use-site in.

## Standing context (durable, do not relearn)

- **Release:** ~1 datestamped alpha/day, `0.1.0-alpha.YYYYMMDD[.N]`, **local
  `scripts/release.sh` only — CI/GitHub Actions BANNED**. Latest `v0.1.0-alpha.20260617.3`.
  Do NOT touch `scripts/release.sh`, `packaging/`, the tap. Did NOT cut a release (mid-churn).
- **Loop:** `docs/guides/slice-loop.md` — 2–3 slices → Phase A code-quality audit → Phase B
  architecture audit. Audit cadence: slices 1 (`closure-ctor`) and 2 (`closure-eval`) are
  both landed — an audit pass is DUE before/around slice 3 (last audit-reference `b45848b`).
- **Safety:** prod9 + cue cache READ-ONLY (eval/probe only). The session bash output filter
  mangles piped/heredoc git input → use `git commit -F /tmp/msg`. Trust `lake build` as
  coverage ground-truth over grep/wc. NO `git checkout`/`restore`/`reset`.
- **`fuel` is LOAD-BEARING** in `EvalKey` (263 fuel-truncation conflicts) — never drop it
  from the memo key when adapting cycle/memo handling in slices 4-5.
- **Perf hang (frontier #2)** is downstream — real apps error at #1 (~0.9s) before the
  blowup, so unreachable until slice 5 lands; re-profile then, then frame-id sharing.
- **cue oracle:** `/Users/chakrit/go/bin/cue` v0.16.1.
