# RESUME HERE — AUDIT COMPLETE (2026-06-21); next code leader = RESID-MASK-2

Live START-HERE pointer; supersedes `2026-06-21-resume-A6-DONE-AUDIT-DUE.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog, audit
verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Consolidated
fix backlog + § Low/hardening.

## Audit state — **COMPLETE** (counter = 0; next audit after 2–3 new slices)

The two-phase audit round (opened at counter=2: MEET-RESID-1 slice 1, A#6 slice 2) is CLOSED.

- **Phase A — `383c1c6`.** RE-VERIFIED the batch. FALSIFIED MEET-RESID-1's "structural invariant"
  (a `.structComp` CAN hold an inner `.bottomWith [.fieldConflict]` field — Kue's deliberate
  inline-`_|_` convention), found + FIXED a CRITICAL masked bottom **RESID-MASK-1** (`containsBottom`
  did not descend `.structComp` resolved fields → a dead disjunction arm survived → wrong value;
  fixed by descending via `containsBottomFields`). A#6 VERIFIED SOUND. Filed RESID-MASK-2.
- **Phase B — `39e8af4` (the MASKING-SWEEP round).** Settled the two ★ rulings + swept all
  bottom-detection/concreteness consumers; found + FIXED INLINE one NEW masked bottom; left
  RESID-MASK-2 as the sole open masking site. Full verdict block in `plan.md`. Headlines:
  1. **★ RULING — consuming-layer (RESID-MASK-1) CORRECT; smart-constructor REJECTED (do not
     re-raise).** A smart constructor that bottoms a conflicting `.structComp` would VIOLATE Kue's
     uniform inline-`_|_` convention (`{x:_|_}`, not top-level `_|_` — empirically confirmed at eval,
     incl. inside a `.structComp`) and lose information (a struct-with-bottom-field is a representable,
     meaningful state cue has too). Detection descends; the VALUE keeps its inline bottom.
  2. **★ MASKING SWEEP — full consumer inventory:**
     - `liveAlternatives`→`containsBottom`, `resolveDisjDefault?`, `normalizeDisj`/
       `normalizeEvaluatedDisj` (has-default/residual paths) — DESCEND (via RESID-MASK-1). ✅
     - **Manifest `.structComp` arm (`Manifest.lean:116`) — WAS MASKING → FIXED INLINE.** Reported
       `incomplete value` where the resolved fields hold a TERMINAL inline conflict; cue reports
       `conflicting values` (a CONTRADICTION). Now descends via `containsBottomFields` →
       `.contradiction`, else `.incomplete`. Witness: `x: {for k in [string]{(k):1}, a:1, a:2}`.
     - `classifyArith`/`Guard`/`Definedness`/`DynLabel` — NOT masking (they classify concreteness
       STATUS; `.structComp → .incomplete` is correct regardless of an inner bottom). ✅
     - `join`/`joinValues` (all-regular disj) — agrees with cue (prunes only when the survivor is
       concrete). ✅
     - **RESID-MASK-2 — the SOLE remaining masking; NEXT LEADER.**
  3. Module boundaries / sizes / dead code HEALTHY; no `valueIsOrContainsBottom` super-predicate
     warranted (the consumers split into two legitimately different jobs — see plan.md).

### Phase-B verify (all green)

`lake build` 108 jobs (all `rfl`/`native_decide` modules incl. 4 new manifest pins); `check-fixtures.sh`
→ `fixture pairs ok` (zero drift); `shellcheck` clean; **cert-manager content-identical to the pre-fix
baseline `383c1c6` AND to cue** (semantic JSON compare). `manifestWithFuel` axiom-clean (`propext`
only). Manifest fix added NO import edge. Pushed (attended).

## NEXT — the next code leader (correctness-first)

1. **RESID-MASK-2 (MEDIUM correctness — the disjunction eager-prune-vs-hold POLICY; the
   residual-masking fix-slice).** PRECISELY CHARACTERIZED by Phase-B (see plan.md): a non-default
   disjunction where the residual arm carries a TERMINAL inline conflict and kue EAGERLY PRUNES it,
   committing to a survivor that is itself STILL INCOMPLETE; cue HOLDS the whole disjunction.
   Witness: `out: (a&{x:2}) | (a&{x:1,ok:true})` (a:`{for k in [string]{(k):1}, x:1}`) → kue
   `out: {x:1,ok:true,for…}` vs cue holds both arms (export → `2 errors in empty disjunction`).
   The pruned conflict IS terminal (a `for k in [string]` dyn field can't touch a static `x`), so
   kue's prune is the more precise lattice move and cue's hold is conservative — **resolve under the
   SPEC lens** (likely a `cue-spec-gaps.md` entry; the spec is silent on collapsing a one-terminal-
   bottom + one-incomplete-arm disjunction), do NOT just match cue. Needs BOTH arms residual.
2. **AD2-1 (LOW-MED — disjunction-normalizer dedup; FILE as a slice, DEFERRED/surface, do NOT pick
   up blind).** `normalizeEvaluatedDisj` (`Eval.lean`, EVAL) and `normalizeDisj` (`Lattice.lean`,
   LATTICE/meet) near-identical, differ ONLY on the LONE-arm rule. Value-sound (display-only). Flips
   TWO NAMED theorem pins + the SC-3 display contract — a human signs off the contract rename.
   Couples with SC-3. Full spec: plan.md § AD2-1.
3. Otherwise: SC-1b (closed×closed-pattern), BI-2-residual (Sqrt + neg/fractional Pow), the LOW
   cosmetic tail (plan item 6), **EvalOps extraction** (plan item 2, parallel-safe mechanical carve).

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (semantically = cue; byte-differs only in JSON key ordering — pre-existing,
  NOT a regression). **Run cert-manager from the infra MODULE dir** (`cd .../prod9/infra &&
  {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path invocation errors `import failed:
  … no cue.mod` for BOTH binaries. Semantic compare: `/usr/bin/python3 -c "import
  json;print(json.load(open(a))==json.load(open(b)))"`.
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`). FixturePorts lives at
  `Kue/Tests/FixturePorts.lean` (hand-built AST only — no source-string port; prefer
  `evalSourceMatches`/`exportJsonBottoms` `native_decide` theorems in `*Tests.lean` for new
  source-level pins). For manifest ERROR-KIND pins (contradiction vs incomplete), hand-built-AST
  `manifest (…) = .error (.contradiction/.incomplete …)` `rfl` theorems in `ManifestTests.lean` —
  `exportJsonBottoms` cannot distinguish the error kind.
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path.
- **Baseline-compare trick (no working-tree risk):** `git worktree add -d /tmp/kue-head HEAD` →
  `cd /tmp/kue-head && lake build` → compare its binary → `git worktree remove --force /tmp/kue-head`
  (run the remove from the kue repo dir, not prod9).
- **Lean note (A#6):** structural recursion over `Value`'s nested `List` children needs
  `termination_by structural` AND destructured list elements (an opaque `.fst`/`.snd`/callback
  projection is rejected). Structural ⇒ `rfl`-reducible; a `sizeOf` WF measure is NOT (breaks `rfl`
  proofs that unfold the function). This pattern is reusable for future total `Value` walkers.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on `main`
  when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** — EXCEPT the
  narrow oracle-as-data-source carve. Correctness-over-performance. **Unattended/AFK → commit, don't
  push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3 slices
  — **counter now 0, audit COMPLETE.** Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path.
