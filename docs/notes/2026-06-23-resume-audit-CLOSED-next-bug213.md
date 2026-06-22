# RESUME — two-phase audit CLOSED; next = Bug2-13 (on-path argocd blocker) (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug211-DONE-next-bug213.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) (Bug2-13 filing +
DESIGN NOTE). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — audit counter = 0 (RESET). Two-phase audit CLOSED.

**Batch audited: `b913ae6`..`a4c33cf` (Bug2-10 + Bug2-11).**

- **Phase A — HEALTHY (`a4c33cf`).** All three risk areas clean: over-fire negatives
  byte-identical, `.conj` termination fuel-bounded, cross-package frames correct under hard
  attack, no over-close. 3 fixtures + 1 pin added.
- **Phase B — HEALTHY (this round, docs-only, no commit yet on `main` — see below).** Module
  graph ACYCLIC + strictly layered; Bug2-10/2-11 additions sit correctly in the Eval
  def-deferral tier; cleanliness sweep clean. Verdict + both headlines folded into the durable
  docs.

## Phase-B headline rulings (this round)

1. **`resolveDefField?` delivery-family DRY — RULED OUT, keep separate.** The full-family
   extraction is the `mergeFieldsWith` trap: the FRAME each function captures (selector's pkg /
   terminal-after-alias-follow / raw-`.conj`) is soundness-load-bearing and irreducibly
   different (the `crosspkg_defofdef_wrongframe_witness` hazard), the return types differ
   (`Value` / `Bool` / `(frame, body)` / 3-way), and the variation point is FRAME + RECURSION,
   NOT a pure leaf (so NOT the `embedChainAny`-SHARE shape). The only frame-safe share — a narrow
   selector-head helper — is too thin to name and FRAGMENTS each function (selector arm via
   helper, refId/disj arm hand-written). Full basis in `plan.md` § Resolved/ruled-out.
2. **Bug2-13 DESIGN NOTE — written (design only, NO code).** The polarity bug lives in field
   SELECTION, NOT the `classifyDefinedness` classifier: an unset optional field reference resolves
   to its declared TYPE (`findEvalField`/`selectFromDecls` carry no optionality distinction), so
   it classifies `.defined` → `!= _|_` wrongly true. Fix = treat an unset optional SELECTION as
   absent — the selection-time analog of `containsBottomFields`'s existing optional-skip
   (`Lattice.lean:224`). Must-pin witnesses enumerated (unset/set optional both polarities, unset
   non-def, required-when-supplied, direct-select, the argocd `attr.#ServiceRef` shape). Empirically
   re-confirmed: unset optional `eq true/neq false` (cue) vs OPPOSITE (kue); SET optional AGREES
   (over-fire guard). Full note in `spec-conformance-audit.md` Bug2-13.

## Phase-B findings by category

- **File sizes:** `Eval.lean` **3965** (+185, Bug2-10/2-11 growth) — under the ~4500 re-split
  watch but APPROACHING; the `Eval.DefDeferral`-first-carve (`Eval.lean:2160–2670`, ~510 lines)
  is the named next carve IF the next 1–2 narrowing slices cross ~4500. Bug2-13 is a
  SELECTION-time fix and will NOT grow that tier, so the threshold is not imminent.
- **Type-leverage:** NO high-value next tightening (`DeclProvenance`/`ConjOperand` exemplary). The
  one structural gap (Bug2-13: `findEvalField`/`selectFromDecls` carry no optionality
  distinction) is filed AS Bug2-13.
- **Module boundaries / cleanliness:** ACYCLIC, layered, no `sorry`/`panic!`/dead-code/stale-TODO;
  `partial def`s are the standing carve-outs only.
- **TwoPassTests split (item 3):** DUE (now **2048** lines, past 2000) but RANKED BELOW Bug2-13 —
  the on-path correctness blocker stays the leader; the split is org-only, zero behavior change,
  guarded by the coverage tripwire + line-comment headers.
- **Closedness error-MESSAGE imprecision (Bug2-12 family):** noted as diagnostic quality, NOT
  filed as its own slice (Bug2-12 already filed LOW/spec-check; the message-precision is folded
  there, not worth a separate slice yet).

## APPLIED INLINE (docs-only, low-risk)

- **`kue-performance.md`** argocd-bottoms entry de-staled — said the blocker is "now **Bug2-10**"
  (STALE: Bug2-10 `aa4172b` + Bug2-11 `bdced40` both LANDED); corrected the chain to Bug2-10/2-11
  LANDED + gating to **Bug2-13**, wall ~54s.
- **`plan.md`** — Phase-B verdict + `resolveDefField?` RULE-OUT + Bug2-13 design pointer; item-3
  TwoPassTests updated (1879→2048, "DUE, ranked below Bug2-13").
- **`spec-conformance-audit.md`** — Bug2-13 DESIGN NOTE appended.

**Verify (all green):** `lake build` 110 jobs; `check-fixtures.sh` "fixture pairs ok" (zero
drift); `shellcheck scripts/*.sh` clean; cert-manager canary content-identical (jq -S diff = 0).
No code changed this round (docs-only), so the gate confirms no regression.

## Next leader — Bug2-13 (HIGH, on-path argocd blocker; design in place)

Presence-test on an UNSET OPTIONAL returns the WRONG polarity. Fix at the SELECTION boundary
(`selectFromDecls`/`findEvalField` consumer): an unset optional selects to ABSENT (`.bottom`), not
its declared type. SET optional + regular field MUST keep present behavior (cert-manager
content-identical). Self-contained 2-line repro + full design in `spec-conformance-audit.md`
Bug2-13.

## After Bug2-13 (ranked)

1. **`TwoPassTests` SPLIT** (item 3) — DUE (2048 lines); carve `bug2x_*` into `Bug2xTests.lean`,
   each file gets the `#check` tripwire + `--` headers.
2. **Perf frontier (#7 / item-5)** — STILL GATED; un-gates only once argocd EXPORTS.
3. **Bug2-12** (LOW, self-recursive closed-def closedness leak — spec-check first) + item-6 tail.

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is **cadence-available, awaits user greenlight** —
notable only IF argocd exports (it does NOT yet — Bug2-13 pending). CI/Actions banned; release =
local `scripts/release.sh` + `scripts/release-linux.sh`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check, never the
  gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 (`/Users/chakrit/Documents/prod9/infra`) + cue caches READ-ONLY. NO
  `git checkout`/`restore`/`reset --hard` on the main tree. argocd oracle = `kue export
  apps/argocd.cue` from the infra root; localize bottoms with `kue apps/argocd.cue`.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
- **Audit counter = 0 (RESET).** Next two-phase audit due after the next 2–3 slices.
