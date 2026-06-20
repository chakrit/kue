# RESUME HERE — BI-1 LANDED (slice 2 of batch); two-phase AUDIT now DUE (2026-06-20)

Live START-HERE pointer; supersedes the prior `…test-org-next` breadcrumb content (rewritten in
place — same file). Authoritative live roadmap:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Consolidated fix backlog
(ranked spec-conformance fixes) + [`../spec/plan.md`](../spec/plan.md) (capabilities + non-spec
roadmap).

## Audit state — counter = 2 of the new batch. **TWO-PHASE AUDIT IS NOW DUE** (before the next code slice).

New batch: **slice 1 = test-org carve `4b25cef`** (org-only, zero behavior change), **slice 2 = BI-1
Unicode case mapping** (this slice, below). That's the 2-slice mark → the two-phase audit (A then B,
sequentially) is DUE now per `docs/guides/slice-loop.md` — do NOT invoke `/ace-audit`; the procedure
is written down in that guide. Scope the recent batch (test-org + BI-1) for Phase A; whole module
graph for Phase B. Fold findings into the plan as fix-slices. The prior batch's two-phase audit
closed at `7ee15d8`+`457a165` (counter reset to 0); this is a fresh cadence.

## Slice 2 DONE — BI-1: Unicode case mapping for `strings.ToUpper`/`ToLower` (CONFORMS across the BMP)

Was ASCII-only (wrong on every non-ASCII letter). Now maps the full BMP cased set; byte-identical to
cue across the BMP. Two commits: **spike `6065380`** (data-approach decision, committed before code)
+ **impl** (see git log HEAD).

- **Spike decision = (c) oracle-generated table.** (a) UNAVAILABLE (zero external deps; Lean core
  case maps are ASCII-only). (b) algorithmic ranges REJECTED — the oracle shows the BMP mapping is
  overwhelmingly IRREGULAR (632/674 ToUpper offset-runs are singletons; only ~13 regular runs), so
  ranges would leave all of Latin Extended wrong. (c) CHOSEN: generate a BMP **simple 1:1** table
  from the local `cue` oracle (READ-ONLY, NO network) — `scripts/gen-case-table.py` →
  `Kue/CaseTable.lean` (1190 + 1173 sorted `(src,dst)` pairs, chunked-array to dodge elaboration
  recursion). cue's ToUpper/ToLower are pure rune-wise SIMPLE mapping (verified: BMP round-trip is
  1:1; `ToUpper("ß")=="ß"`, no SS-expansion), so a 1:1 table is faithful.
- **Impl (`Kue/Builtin.lean`):** total binary search `caseTableSearch` (`termination_by hi - lo`, no
  `partial`) → `caseTableLookup` → `caseMapChar` (identity on miss) → `unicodeToUpper`/`Lower`. ASCII
  is IN the table (`a`→`A` −32), so `asciiToUpper`/`Lower` DELETED — one mechanism.
- **ToTitle deliberately NOT folded in** (BI-1 scoped to ToUpper/ToLower). Stays ASCII-bounded — its
  Unicode TITLE-case mapping (`ǆ`→`ǅ`, ≠ upper) + `unicode.IsSpace` boundary are a separate slice.
  `ToTitle("über alles")` Kue `"über Alles"` vs cue `"Über Alles"` = the ONE remaining case-builtin
  divergence (Kue does LESS → compat-assumptions + spec-gaps, NOT cue-divergences).
- **Tests:** NEW `Kue/Tests/StringsTests.lean` (case pins moved out of BuiltinTests + Unicode
  round-trips/singletons/`ß`-boundary/CJK-boundary/mixed + `case_table_lookup_*` unit pins) + fixture
  `testdata/cue/builtins/strings_case_unicode.{cue,expected}` + FixturePorts entry. Every mapping
  oracle-cross-checked. `lake build` 108 jobs green; `check-fixtures.sh` → `fixture pairs ok`.
- **Durable record updated:** spec-conformance-audit BI-1 → DONE (item 15); implementation-log slice
  entry; compat-assumptions "String case folding" rewritten; 2 spec-gap rows (ToUpper/Lower coverage
  boundary + ToTitle deferral); plan.md backlog line. NO cue-divergences row (ToUpper/Lower CONFORM).

## Slice 1 DONE (prior) — test-org carve `4b25cef`

EvalTests 1593→1246 lines, carved into `ComprehensionTests.lean` (29 pins) + `SortTests.lean` (13
pins); pin-count conserved EXACTLY (179). **Fixture regroup DEFERRED** (a remaining sub-item, NOT a
blocker): sub-grouping `testdata/cue/{definitions (50), comprehensions (27)}` into nested subdirs is
high-blast-radius because `FixturePorts.lean` (3049 lines) is HAND-MAINTAINED source — each fixture
move is a multi-file `git mv` + an exact FixturePorts string edit, ~77 fixtures, one typo silently
breaks the diff. Pick up only as a dedicated careful slice, or drop (marginal win).

## AFTER THE AUDIT — next code-slice candidates (ranked; see audit doc § backlog)

1. **Periodic passes** (DUE-but-non-blocking per last Phase B): **plan-hygiene** (distill plan.md +
   audit doc to the live set; refresh `docs/www/index.html`) and the **test-org fixture-regroup**
   (the deferred sub-item above) — either is a clean post-audit slice.
2. **BI-2-residual** (MED): `math.Sqrt` (IEEE-754 float64 + `NaN`/`Infinity` + Go sci-notation
   formatter Kue lacks) and `math.Pow` neg/fractional exponent (apd 34-digit decimal Pow + Infinity).
   Both BOTTOM honestly today. Needs a Float/decimal-numeric design fork. No real app needs it.
3. **SC-3 display-residual** (LOW/spec-gap — cosmetic default-collapse), **SC-4** (LOW,
   spec-gap-FIRST), **SC-1b** (closed×closed-pattern), the **4 spec-gap ratifications**, **A#6**
   (`containsBottom` fuel cap, STANDALONE), **DRY-1** (LOW let-walker refactor).

## Phase-B rulings to carry forward (do NOT re-litigate — confirmed intact)

- **BI-EFF (effectful-builtin seam): SCOPED, TRIGGERED, not now.** `list.Sort`/`SortStable` live as
  ONE inline `runSort` case in `evalValueWithFuel`'s `.builtinCall` arm — the RIGHT layer. Do NOT
  abstract yet; a name→`EvalM`-closure registry is REJECTED. TRIGGER at the SECOND effectful builtin
  (`list.IsSorted` or a validator) — extract a named `evalEffectfulBuiltin?` seam AS that slice's
  first step. Forward-pointing comment already at the site.
- **Walker/normalizer dedups are FOUR distinct mechanisms**, sequenced AD4-1 → A-EN3+DRY-1 → AD2-1,
  all post-argocd, gated behind correctness. AD3-4 (bottom-payload newtype) RULED OUT.
- **EvalOps extraction** (plan item 2) stays the right first `Eval.lean` carve; no second extraction
  justified yet.

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (parked) and
  `.../cert-manager.cue` (fully correct).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  (3.9.6) by absolute path for any generator/oracle scripting.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on `main`
  when attended). **Spec is authority; `cue` is a fallible cross-check, never the gate.**
  Correctness-over-performance. **Unattended/AFK → commit, don't push** (CLAUDE.md).
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3
  slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag `cue-spec-gaps.md`; keep
  `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path.
