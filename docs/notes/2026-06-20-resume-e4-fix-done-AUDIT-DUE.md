# RESUME HERE — E#4-fix DONE (2026-06-20); **two-phase AUDIT is DUE NEXT**

Live START-HERE pointer; supersedes
`2026-06-20-resume-ratifications-done-e4-fix-next.md` (deleted). Authoritative live
roadmap: [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities, non-spec roadmap, audit verdicts).

## Audit state — Counter = 3. **AUDIT DUE NOW (Phase A → Phase B, run BEFORE the next code slice).**

The prior two-phase audit closed at `4593185` (Phase B); counter reset 0. Three slices have
landed since:
1. **truncate-primitive** (slice 1, `4afc2e4`-era / see log) — soundness hardening, CLOSED.
2. **spec-gap ratifications** (slice 2, `8c839e0`) — 3 RATIFIED + 1 ESCALATED (became E#4-fix).
3. **E#4-fix** (slice 3, `02b8b9d`, pushed) — arithmetic operator domain.

→ Counter = **3 since `4593185`** ⇒ the two-phase audit is **DUE**. The orchestrator's next
action is the audit, NOT another code slice. Run it per
[`../guides/slice-loop.md`](../guides/slice-loop.md) (do NOT invoke `/ace-audit`):
**(A) code-quality audit** (correctness, totality, illegal-states, DRY, test strength, skill
compliance over the batch) **THEN (B) architecture/refactor/cleanup audit** (module
boundaries, layering, dead code, simplification, test/fixture org over the whole graph).
Sequential, A before B. Fold findings into the plan as fix-slices. Audit batch = the three
slices above; the highest-surface one is E#4-fix (new eval-path code + classifier + fixtures).

### Audit focus hints for E#4-fix (`02b8b9d`)

- **`classifyArithOperand` / `arithmeticDomainResult` (`Eval.lean`)** — verify totality (the
  classifier enumerates every `Value` ctor, no catch-all — like `classifyGuard`); confirm the
  incomplete-FIRST ordering in `arithmeticDomainResult` is sound (an incomplete operand must
  defer even when the partner is concrete-nonarith — this is the load-bearing correctness point,
  pinned by `eval_add_list_incomplete_partner_defers` + symmetric). Possible DRY flag:
  `classifyArithOperand` and `classifyDefinedness`/`classifyGuard` share the same big ctor
  enumeration over `Value` with different leaf verdicts — a Phase-B "three parallel classifiers"
  question (analogous to the A-EN3 fold family). Judge whether a shared fold is warranted or the
  three are genuinely distinct (they map to different verdict sums; likely leave separate, but
  flag it).
- **`evalMul` string/bytes repeat** — the four new arms + `evalRepeat`; check `String.join
  (List.replicate count.toNat text)` is total and the negative-count guard precedes `.toNat`.

## LAST SLICE — E#4-fix (arithmetic operator domain) — DONE, committed `02b8b9d`, PUSHED

A concrete operand outside an arithmetic op's domain (list/struct/bool/null for every op;
string/bytes for `- /`) now TYPE-ERRORS instead of leaving a held residual — Kue now conforms
to the spec (cue was already correct). `evalAdd`/`evalSub`/`evalMul`/`evalDiv` swapped their
`_,_ => .binary` catch-all for `arithmeticDomainResult op`, which DEFERS when either operand is
incomplete (may still resolve to a number — cue holds `[1] + x` while `x: int`) and type-errors
only a concrete-nonarith operand paired with a concrete partner. Sibling fix: `evalMul` now
does string/bytes `*` int **repetition** (`"ab"*2="abab"`, cue's behavior superseding
strings/bytes.Repeat; was a silent wrong-bottom). New `BottomReason`s `nonArithmeticOperand` +
`negativeRepeatCount`. Pins: 3 `numeric/*` fixtures + ~19 `EvalTests` theorems (incl. the
incomplete-still-defers regression). `cue-spec-gaps.md` E#4 row flipped MIS-FILED → RESOLVED;
NO `cue-divergence` (cue was right). Verify: `lake build` green (108 jobs); `check-fixtures.sh`
→ `fixture pairs ok` (zero drift); cert-manager content-identical to cue (module context, modulo
field-order #3).

## AFTER THE AUDIT — next code slices (spec-conformance backlog, ranked)

The audit may insert fix-slices ahead of these. Otherwise, the live ranked backlog
(`spec-conformance-audit.md` § Consolidated fix backlog + `plan.md` item #6):

- **BI-2-residual** (MED, LARGE) — `math.Sqrt` (IEEE-754 + `NaN`/`Infinity` + Go sci-notation
  formatter) and `math.Pow` neg/fractional exponent (apd 34-digit decimal Pow). Both BOTTOM
  honestly today; needs a Float/decimal-numeric design fork. No real app needs it.
- **SC-3** display-residual (LOW, spec-gap — cosmetic default-collapse; couples with AD2-1).
- **SC-4** (LOW, spec-gap-FIRST), **SC-1b** (closed×closed-pattern, MED).
- **A#6** (`containsBottom` fuel cap 100, `Lattice.lean:146` — STANDALONE soundness hardening;
  never implicated in a shipped path). LOW/contained.
- **EvalOps extraction** → `Kue/EvalOps.lean` (plan item 2, ACTIONABLE, PARALLEL-SAFE,
  mechanical — the standing first carve; `Eval.lean` ~3700 lines, under the ~4500 watch). NB:
  E#4-fix added the arithmetic classifier/gate to the same `evalAdd…evalBinary` region the
  EvalOps carve targets — fold the new defs into that carve when it runs.
- **Walker-dedup family** (post-argocd, gated behind correctness): AD4-1 → A-EN3+DRY-1 → AD2-1.
- **Periodic passes** (non-blocking): plan-hygiene; the deferred `testdata/cue/{definitions,
  comprehensions}` fixture-regroup (high blast radius via hand-maintained `FixturePorts`, low
  win — DEFERRED).

### Untracked capability surfaced by E#4-fix (low priority, NOT filed as a slice yet)

`*` string/bytes repetition is now done. No other arithmetic-domain gap remains. (cue's
`"ab" * 2.0` float-count → type error already matches Kue via the `prim,prim` bottom path.)

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets:
  `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (parked) and
  `.../cert-manager.cue` (content-identical to cue, ~12s export). **Run cert-manager from the
  infra MODULE dir** (`cd .../prod9/infra && {kue,cue} export ./apps/cert-manager.cue`); the
  bare absolute-path invocation errors `import failed: … no cue.mod` for BOTH binaries (a
  cue.mod-context artifact, not a Kue bug).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use
  `/usr/bin/python3` by absolute path for any generator/oracle scripting.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push
  on `main` when attended). **Spec is authority; `cue` is a fallible cross-check, never a
  gate** — EXCEPT the one narrow oracle-as-data-source carve governed by the ADR (data,
  never a gate). Correctness-over-performance. **Unattended/AFK → commit, don't push**.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2–3 slices — **DUE NOW**. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path.
