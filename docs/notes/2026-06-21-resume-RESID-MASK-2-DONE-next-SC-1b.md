# RESUME HERE — RESID-MASK-2 RESOLVED (2026-06-21); next code leader = SC-1b

Live START-HERE pointer; supersedes `2026-06-21-resume-AUDIT-COMPLETE-next-RESID-MASK-2.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog, audit
verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Consolidated
fix backlog + § Low/hardening.

## Audit state — counter = 1 (RESID-MASK-2 was slice 1 of the new batch; audit due after 2–3)

The prior two-phase round closed at `f716e38` (counter reset 0). **RESID-MASK-2 is slice 1** (a
spec-review slice, no code change). No audit yet — next two-phase audit falls due after 2–3 landed
slices (so after ~1–2 more).

## What just landed — RESID-MASK-2 (the disjunction eager-prune-vs-hold POLICY)

**Spec-review + soundness-verification slice. NO code change.** The sole open masking site from the
Phase-B `39e8af4` sweep. A non-default disjunction prunes a definitely-bottom arm (a held
`.structComp` residual whose RESOLVED fields hold a TERMINAL inline conflict, e.g. `a&{x:2}` with
`a.x:1` ⇒ `x:1&2=_|_`) and commits to a surviving arm that is itself STILL INCOMPLETE; cue HOLDS the
whole disjunction. **The MEET-RESID-1 ripple family is now CLOSED.**

- **★ SOUNDNESS VERDICT — CLEAN.** The prune gate `liveAlternatives`→`containsBottom`
  (`Lattice.lean:307/178`) drops an arm iff `containsBottom arm.snd`, which is `true` ONLY on a
  MATERIALIZED `.bottom`/`.bottomWith` node. Such a node arises only from an ALREADY-REDUCED conflict
  (concrete-vs-concrete `x:1&x:2`, concrete-vs-bound `x:1&x:>5`, disjoint-bound `x:>5&x:<3`) — every
  one TERMINAL (cannot un-bottom under refinement). It does NOT fire on a merely-incomplete arm: an
  arm bottom-NOW only because an abstract operand is unresolved (e.g. `a&{x:2}` with `a.x:int` →
  `{x:2,…}`, no bottom node) is NOT pruned and survives. Adversarially verified vs cue v0.16.1:
  abstract-operand → both arms kept; post-`&{x:2}`-narrowing → the abstract arm RESOLVES and wins;
  both-incomplete-no-conflict → both survive; concrete-narrowed bound disj (`({x:>5}|{x:<0})&{x:7}`)
  → kue and cue AGREE `{x:7}`. **No construction prunes a could-become-viable arm. No fix needed.**
- **SPEC-CONFORMANCE — eager prune is spec-consonant.** Spec (Disjunction) mandates *"eliminate
  bottom alternatives"* + `_|_`-as-`|`-identity → eager elimination of a definitely-bottom arm is
  spec-correct + the more precise lattice move. The spec does NOT pin the *timing* (also: *"Evaluation
  can retain unresolved disjunctions"*), so cue's hold is permitted laziness, NOT a violation.
- **RESOLUTION — recorded a `cue-spec-gap`** (`cue-spec-gaps.md` RESID-MASK-2 row), NOT a divergence
  (kue is MORE precise; cue less precise but not wrong). kue's behavior PINNED so it can't regress to
  cue's hold. 8 `native_decide` pins in `TwoPassTests.lean` (`### RESID-MASK-2` section): witness +
  4 soundness + 1 precision (kue exports `{plain:5}` where cue errors) + 2 `_|_`-identity regressions.
  CORRECTED the stale NOTE at the RESID-MASK-1 pins (it claimed the non-default residual arm "survives
  as a spurious arm" — FALSIFIED on HEAD: kue eager-prunes; RESID-MASK-1 closed that path).

### Verify (all green)

`lake build` 108 jobs (all pins `native_decide`); `scripts/check-fixtures.sh` → `fixture pairs ok`
(ZERO drift — no code change); `shellcheck` n/a (no shell); cert-manager export SEMANTICALLY identical
to cue on the disjunction path. Committed + pushed (attended).

## NEXT — the next code leader (correctness-first)

1. **SC-1b (closed×closed-pattern intersection) — the next CLEAN autonomous item.** See
   `spec-conformance-audit.md` § Consolidated fix backlog for the precise shape. Pickable without a
   human gate.
2. **AD2-1 (LOW-MED — disjunction-normalizer dedup; orchestrator-DEFERRED, surface don't do blind).**
   `normalizeEvaluatedDisj` (`Eval.lean`) vs `normalizeDisj` (`Lattice.lean`) near-identical, differ
   ONLY on the LONE-arm rule. Value-sound (display-only). Flips TWO NAMED theorem pins + the SC-3
   display contract — a human signs off the contract rename. Couples with SC-3. Full spec: plan.md
   § AD2-1.
3. **The increasingly user-gated tail** (flag, don't grind): AD2-1's display contract + **SC-3**
   (coupled with it) both want a human sign-off on the rename; **BI-2-residual** (Sqrt + neg/fractional
   Pow) is a large Float/NaN/Infinity numeric-model undertaking, its own subproject. Otherwise: the LOW
   cosmetic tail (plan item 6), **EvalOps extraction** (plan item 2 — parallel-safe mechanical carve).

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (semantically = cue; byte-differs only in JSON key ordering — pre-existing,
  NOT a regression). **Run cert-manager from the infra MODULE dir** (`cd .../prod9/infra &&
  {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path invocation errors `import failed:
  … no cue.mod` for BOTH binaries. Semantic compare: `/usr/bin/python3 -c "import
  json;print(json.load(open(a))==json.load(open(b)))"`.
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`). For source-level disjunction/eval pins prefer
  `evalSourceMatches` / `exportJsonMatches` / `exportJsonBottoms` `native_decide` theorems in
  `*Tests.lean` (e.g. the new `TwoPassTests` `resid_mask2_*`). Manifest ERROR-KIND pins
  (contradiction vs incomplete) → hand-built-AST `rfl` theorems in `ManifestTests.lean`.
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path.
- **Baseline-compare trick (no working-tree risk):** `git worktree add -d /tmp/kue-head HEAD` →
  `cd /tmp/kue-head && lake build` → compare its binary → `git worktree remove --force /tmp/kue-head`
  (run the remove from the kue repo dir, not prod9).

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on `main`
  when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** — EXCEPT the
  narrow oracle-as-data-source carve. Correctness-over-performance. **Unattended/AFK → commit, don't
  push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3 slices
  — **counter now 1** (RESID-MASK-2 = slice 1, a spec-review slice). Per-slice duties: tests-first; log
  `cue-divergences.md`; flag `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path.
