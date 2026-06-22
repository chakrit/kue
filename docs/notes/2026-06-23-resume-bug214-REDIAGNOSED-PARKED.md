# RESUME — Bug2-14 RE-DIAGNOSED + PARKED; next = embed-merge fix OR split (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug213-DONE-next-bug214.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) (Bug2-14
RE-DIAGNOSED block). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — audit counter = 2. Bug2-14 slice landed NO CODE (negative result).

The Bug2-14 slice tried the FILED fix (drain-on-select), proved it UNSOUND, REVERTED it,
and re-diagnosed the TRUE root. Tree is at `3e0f396` + doc updates only. **Two-phase audit
is now DUE** (counter hit 2: `7e69e43` Bug2-13 + this doc-only slice) — but this slice
shipped no code, so the audit batch is effectively just Bug2-13's `7e69e43`. Run A-then-B
per `slice-loop.md` before/around the next code slice, OR fold into its batch.

## Bug2-14 — RE-DIAGNOSED, the filed root was WRONG (do NOT re-try drain-on-select)

The original filing blamed `selectEvaluatedField`'s missing `.structComp` arm. That arm IS
missing, but it is a SHALLOW symptom. A drain-on-select (re-eval the base before the
select) was implemented + tested and is UNSOUND — it forces a residual `.structComp` to a
plain `.struct` that DROPS comprehension content (`ls.metadata` loses
`metadata.annotations.issuer`). Reverted.

**TRUE root (6-line minimal "case D", oracle-confirmed):** an embed declaring a field
ABSTRACTLY which the host declares CONCRETELY leaves the embed's comprehension reading the
EMBED-LOCAL abstract value (ref not re-based to the merged host frame) → guard incomplete →
never drains.

```cue
host: { bk: "X", { bk: string, for k, v in {p: 1} { if bk == "X" { hit: true } } } }
// cue: {bk:"X", hit:true}    kue eval: leaves the `for` residual (UNDRAINED)
```

Isolation: an embed-comprehension reading an embed-OWN concrete field DRAINS; a HOST-only
field DRAINS; a field in BOTH (embed-abstract × host-concrete) does NOT. = the argocd
`#Mixin` shape (`let _patch` has `kind: string`; host `defs.#ListenerSet` has `kind:
"ListenerSet"`; the `for _, add in Self.#additions { if kind == add.#kind {…} }` guard reads
the embed-local `kind`).

**Two compounding layers:** (1) embed-merge frame-binding (case D — but a DIRECT inline
embed still drains under export's re-eval); (2) the CROSS-PACKAGE DEF-OF-DEF FORCE path
(`forceClosureWithConjunct`) produces a residual that can't drain EVEN on export → bare
`ls` exports silently-incomplete, `[ls]` (the `listener.yaml: [ls]` shape) → `conflicting
values`.

## Next leader — pick one (resolve by ranking, not by asking)

1. **Bug2-14 embed-merge fix (HIGH, on-path argocd; the real blocker).** Re-bind /
   re-expand the embed-contributed comprehension against the POST-MERGE host frame so
   sibling-field refs see host-narrowed values. Tier: `forceClosureWithConjunct` /
   `meetEmbeddingsWithFuel` / `.structComp`-fold; lever: existing `remapConjValues` /
   `remapConjRefs` ref-rebase. NOT a `selectEvaluatedField` change. Deep live Bug2-x
   machinery — TDD from case D upward (case D first, then the 5-pkg force-path layer), pin
   cert-manager content-identical at every step (it uses the SAME mixin via the direct
   struct-shape and MUST stay green).
2. **`TwoPassTests` SPLIT (item 3) — DUE (~2135 lines).** Mechanical, autonomous, safe;
   reasonable to do FIRST to de-risk the test surface before the deep Bug2-14 slice. Carve
   `bug2x_*` into `Bug2xTests.lean`; each file gets the `#check` tripwire + `--` headers.
3. **Perf frontier (#7 / item-5)** — STILL GATED; un-gates only once argocd EXPORTS.

## THE MILESTONE — argocd does NOT export yet

`kue export apps/argocd.cue` STILL bottoms (~54s, `conflicting values`). NOT a drop-in.
Standing Capabilities unchanged (cert-manager remains the only real-app drop-in). Perf #7
STAYS GATED. A fresh alpha is cadence-available but NOT notable (argocd does not export).

## Repro (reconstruct during the next slice)

5-package faithful at `/tmp/b214` this slice (`cue.mod` module `ex.com/b214`; `defs/` +
`defs/parts/` + `defaults/` + `main.cue`). `kue export . -e bare` (= `ls`) drops
`metadata.annotations`; `-e wrapped` (= `[ls]`) → `conflicting values`; cue exports both
with annotations. Plus the 6-line inline "case D" above (eval-level, no module needed).
Mixin source of truth (READ-ONLY):
`/Users/chakrit/Documents/prod9/infra-defs/parts/{mixin,use_cert_manager}.cue` +
`listener_set.cue`.

## Audit cadence

**Audit counter = 2.** Two-phase audit DUE (A code-quality then B architecture,
sequential, per `slice-loop.md` — do NOT invoke `/ace-audit`). Batch = `7e69e43`
(Bug2-13) + this doc-only slice. Fold findings into `plan.md` as fix-slices.

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is cadence-available, awaits user
greenlight — NOT notable (argocd does NOT export; cert-manager remains the only real-app
drop-in). CI/Actions banned; release = local `scripts/release.sh` + `release-linux.sh`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue` (kue's
  own `eval` has NO `-e`; `kue export -e X` IS supported via the export path).
- prod9 (`/Users/chakrit/Documents/prod9/infra` + sibling `infra-defs` source) + cue
  caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree. argocd
  oracle = `kue export apps/argocd.cue` from the infra root.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
