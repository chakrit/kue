# RESUME HERE — A#6 DONE (2026-06-21); **AUDIT DUE** (Phase A → Phase B) before next code slice

Live START-HERE pointer; supersedes `2026-06-21-resume-MEET-RESID-1-DONE-next-AD2-1.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog, audit
verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Consolidated
fix backlog + § Low/hardening.

## SLICE (2026-06-21): A#6 — `containsBottom` made TOTAL/structural — ✅ DONE

`containsBottom` (`Lattice.lean:160`) was fuel-capped at 100: a `.bottom` nested deeper than 100
levels was MISSED → a dead disjunction arm survived `liveAlternatives` → a WRONG value (a spurious
unresolved `.disj`). Standalone soundness hole for genuinely-deep NON-cyclic bottoms (D#2b confirmed
structural cycles are NOT the cause — D#2a detection fires at depth ~2, always shallow).

**Fix = total structural recursion, fuel removed.** `Value` is a finite well-founded inductive (its
`refId`/`closure` ids are leaf data, never back-edges), so the walk terminates with no depth bound.
Rewrote as a `mutual` block (`containsBottom` + 4 list-helpers `containsBottomList`/`Alts`/`Fields`/
`Patterns`) via **`termination_by structural`** — chosen over a `sizeOf` WF measure SPECIFICALLY
because structural recursion stays `rfl`/`decide`-reducible in the kernel; a WF measure broke ~12
existing `meet`/manifest `rfl` proofs (they unfold through `containsBottom`). List-of-pair / -of-field
helpers destructure their element in the match so the recursed-on subterm is syntactic. Deleted
`fieldBottomCounts`; its optional-skip rule folded inline into `containsBottomFields` (one place, no
callback). Pre-eval/deferred ctors (`comprehension`, `structComp`, `listComprehension`,
`interpolation`, `dynamicField`, `closure`) stay un-descended (catch-all `false`) — unchanged.

### Verify (all green)

`lake build` 108 jobs; **axiom-clean** — `containsBottom` + all 4 helpers depend on `propext` ONLY
(no `sorryAx`/`partial`/`Classical.choice`; structural recursion is constructive). `check-fixtures.sh`
→ `fixture pairs ok` (ZERO drift). `shellcheck` clean (no shell touched). **cert-manager export
BYTE-IDENTICAL to pre-fix HEAD `3f085e1`** (throwaway worktree) AND = cue. NO observable behavior
changed (only latent deep-bottom cases flip wrong→right). 8 adversarial `native_decide` pins in
`LatticeTests.lean` (`a6_*`: deep-150/-500 bottom detected, shallow regression, deep no-bottom false,
deep `.bottomWith`, deep optional-skip, `liveAlternatives`/`normalizeDisj` end-to-end). No
`cue-divergences.md` / `cue-spec-gaps.md` / `kue-performance.md` change. Commit: see `git log` (pushed,
attended).

## Audit state — **AUDIT DUE** (counter = 2: MEET-RESID-1 slice 1, A#6 slice 2)

Two-phase, **sequential**, per [`../guides/slice-loop.md`](../guides/slice-loop.md) — do NOT invoke
`/ace-audit`; the procedure is written down in the guide.

- **Phase A — code-quality audit.** Adversarially RE-VERIFY the two high-risk soundness changes of
  this batch:
  1. **MEET-RESID-1 `meetCore`/`meetWithFuel` soundness gate** (slice 1) — the structural argument
     that a `.structComp` is, by construction, ALWAYS an unresolved conflict-free residual so the defer
     can never mask a field/scalar conflict. **Enumerate ALL `.structComp` production sites** (`grep
     '.structComp ' Kue/*.lean`) and confirm each either (a) emits only after a successful static merge
     (conflict → `.bottom` FIRST) or (b) is the unevaluated pre-eval form expanded before any meet. The
     log entry claims two sites; verify exhaustively, do not trust the claim.
  2. **A#6 `containsBottom` totality** (slice 2, THIS slice) — confirm the structural rewrite descends
     EVERY bottom-bearing constructor it should (no constructor silently dropped vs the old fuel
     version), the optional-skip fold is behavior-preserving, and `termination_by structural` genuinely
     bought `rfl`-reducibility (the `meet` `rfl` proofs are green — they are).
  Plus the usual: totality, illegal-states, DRY, test strength, skill compliance over both slices.
- **Phase B — architecture / refactor / cleanup audit** over the whole module graph (module
  boundaries, layering, dead code, simplification, test/fixture organization).

Fold findings into the plan as fix-slices. Mandatory at this 2-slice mark; don't let it stall forward
motion. After the audit, reset the counter to 0.

## NEXT — after the audit, the next code leader (correctness-first)

1. **AD2-1 (LOW-MED — disjunction-normalizer dedup; FILE as a slice, do NOT apply inline; DEFERRED /
   surface, do NOT pick up blind).** `normalizeEvaluatedDisj` (`Eval.lean:694`, EVAL) and
   `normalizeDisj` (`Lattice.lean`, LATTICE/meet) near-identical, differ ONLY on the LONE-arm rule.
   Value-sound (display-only). Flips TWO NAMED theorem pins + the SC-3 display contract — a human signs
   off the contract rename. Couples with SC-3. Full spec: plan.md § AD2-1.
2. Otherwise: SC-1b (closed×closed-pattern), BI-2-residual (Sqrt + neg/fractional Pow), the LOW
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
  source-level pins).
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
  — **counter now 2, AUDIT DUE.** Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path.
