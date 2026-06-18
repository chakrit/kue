# RESUME HERE — Value.closure slice 4 (closure-meet) landed (2026-06-18)

START-HERE pointer; supersedes `2026-06-18-valueclosure-slice3-landed.md`. Tree clean,
pushed to `gh:main` at `fd06f70`.

## What just landed — THE unlock works

**Frontier #1 (`Value.closure`) slice 4 of 5 (`closure-meet`) is committed (`fd06f70`).**
A forced closure (deferred imported def, slice 3) met with a use-site struct now SPLICES
the use-site in as an extra conjunct BEFORE evaluating. `defs.#M & {#name:"keel"}` (where
`#M = {#name:string, out:#name}` is an imported def) resolves to `{"out":"keel"}` —
byte-matching `cue` — instead of slice-3's `conflicting values (bottom)`. Build 86 jobs,
`fixture pairs ok` (zero drift), shellcheck clean.

### Force point + splice (the mechanism)

The `.conj` eval-then-`meet` fallback `none` branch in `Eval.lean` is the ONLY site a
closure meets a struct. There `evalValuesWithFuel` yields `[.closure capEnv defBody,
.struct useSite]`; instead of the inert `foldl meet` (→ `.bottom`), `firstClosure?` pulls
the closure and `forceClosureWithConjunct fuel capturedEnv body useOperands` forces it
with the OTHER conjuncts' EVALUATED struct fields (`evaluatedStructOperand?`) spliced into
the def body's frame. `meet` stays pure — the eval lives in Eval, not `Lattice.meet`. The
splice reuses the same-package merge machinery, factored to a new pure
`mergeConjOperands (operands : List (List Field × Bool))` shared by `lazyConjMergedFields`
and the force. Cycle: fresh eval entry (`visited := []`), `slotVisited` catches self-refs
→ `.top`, no loop; `fuel` stays in `EvalKey`.

### Two latent bugs fixed (DO NOT relearn)

- **Imported-def closedness.** `normalizeDefinitions` only closes the TOP value's own `#`
  fields, NOT the hidden import binding's — so a forced cross-pkg def wrongly admitted
  use-site fields it doesn't declare. Fix: `importDefClosureBody?` now runs the captured
  body through `normalizeDefinitionValueWithFuel` (`open_ := false`, recursive) at capture.
- **Open-def (`.structTail`) support.** Slice-3 gate + force handled only `.struct`, so an
  OPEN self-ref imported def (`...`) collapsed even with no extra use field. Extended
  `defBodyHasSiblingSelfRef` + a `.structTail` arm in `forceClosureWithConjunct`.

### Tests (7 new pins + 1 committed fixture)

`closure_meet_splices_use_site` (THE unlock), `closure_meet_conflict_is_bottom`,
`closure_meet_empty_use_site`, `closure_meet_self_ref_terminates` (loop→`.top`),
`closure_meet_open_def_admits_extra`, `closure_producer_detects_structtail_sibling`, plus
`testdata/modules/crosspkg_defmeet/` (the regression fixture, cue-oracle `expected`). The
two slice-3 producer pins were updated for the now-closed body (`open_ := false`).

## CRITICAL — real apps still blocked; frontier #2 now REACHABLE

Slice 4's unlock works ONLY on its target shape (bare depth-0 sibling self-ref —
`{#name:string, out:#name}`). **Real prod9 defs do NOT use that shape.** Probed (read-only):

- `infra/apps/cert-manager.cue` (`defs.#ClusterIssuer & {…}`, smallest) → kue `bottom` in
  **11.7s** (cue: instant, correct).
- `infra/apps/argocd.cue` (`defs.#Secret`/`#ConfigMap`/`#TLSRoute & {…}`) → kue `bottom` in
  **55s** (cue: ~0.22s).

Real defs are `#Def: Self={ parts.#Metadata; #x:string; spec: Self.#x }` — value-alias
defs EMBEDDING cross-package defs. Two distinct, independent blockers (NOT the closure
path — same `Self={}` shape resolves in 0.016s when it has no embed):

1. **`closure-realapp-selfalias` (CORRECTNESS — the real blocker, do NEXT).** The embedded
   cross-package def (`parts.#Metadata` as a struct embedding inside the def body) doesn't
   resolve through the closure capture — a minimal embed+Self repro returns `incomplete
   value: string` (fast, 0.018s). Producer/force must defer + splice through an embedded
   imported def, not just a top-level selected one. Needs a design sub-spike. THIS makes
   real apps correct.
2. **`closure-perf` / frame-id-sharing (frontier #2 — now REACHABLE).** Independently, the
   real defs blow up super-linearly (11.7s → 55s) even while erroring — the parked
   exponential frame-id divergence (re-eval allocates fresh frame ids, defeating the memo
   `envIds` key). Audit-heavy. Profiling: scales with the embed/Self graph, NOT closures.

**Sequence: A (correctness) before B (perf)** — once real apps resolve, B has a working
target to profile.

## NEXT — slice 5 / re-plan

`plan.md` slice 5 (`closure-regression`) is PARTLY done early (the `crosspkg_defmeet`
fixture + the bare-self-ref edge audit landed in slice 4). REMAINING:
**`closure-realapp-selfalias`** (the `Self={…}` + embedded-def shape — the real blocker),
then **`closure-perf`** (frontier #2). Audit cadence: slices 3+4 are the two landed since
the last Phase-A/B pass (`a347386`/`31b329c`, slices 1-2 only) — a two-phase audit per
`docs/guides/slice-loop.md` is DUE around now (do NOT invoke `/ace-audit`; follow the
guide). Don't let it stall `closure-realapp-selfalias`.

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9` (NOT `~/prod9`). Cross-pkg
  def-meet apps under `infra/apps/`; defs under the cue cache
  `~/Library/Caches/cue/mod/extract/prodigy9.co/defs@…` and local `infra-defs/`. READ-ONLY.
- **Repro modules** live in `/tmp` only (rebuild if gone): `/tmp/cpdm`, `/tmp/ec`, `/tmp/sf`
  (Self alias, resolves), `/tmp/pf` (embed+Self, `incomplete` — the next blocker).
- **`fuel` is LOAD-BEARING** in `EvalKey` (263 fuel-truncation conflicts) — never drop it.
- **Release:** ~1 datestamped alpha/day, `scripts/release.sh` only — CI/Actions BANNED.
  Latest `v0.1.0-alpha.20260617.3`. Did NOT cut a release (mid-churn).
- **Safety:** prod9 + cue cache READ-ONLY. Session bash filter mangles piped/heredoc git
  input → `git commit -F /tmp/msg`. NO `git checkout`/`restore`/`reset --hard`.
- **cue oracle:** `/Users/chakrit/go/bin/cue` v0.16.1.
- **Field-ordering parity (#3)** surfaced again (EC1: open def + use extra — values match,
  byte order differs); orthogonal polish, out of scope.
