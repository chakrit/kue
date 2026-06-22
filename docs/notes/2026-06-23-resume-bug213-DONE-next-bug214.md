# RESUME — Bug2-13 DONE; next = Bug2-14 (on-path argocd blocker) (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-audit-CLOSED-next-bug213.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) (Bug2-13 RESOLVED
+ Bug2-14 filing). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — audit counter = 1. Bug2-13 LANDED (`7e69e43`).

**Bug2-13 — RESOLVED (`7e69e43`).** Unset optional selection reads as ABSENT. An unset
optional field reference resolved to its declared TYPE → `classifyDefinedness` read
`.defined` → `== _|_` wrongly false / `!= _|_` wrongly true. Fixed at TWO selection
sites that both produce the value the presence-test classifies: `selectedFieldValue`
(direct-select `x.#opt`) AND the `.refId` eval arm (the sibling-ref path the `== _|_`
operand actually takes — the design note named only the first). Both resolve an
`.optional`-rung field to `.bottom`. The over-fire guard is STRUCTURAL: a set optional
downgrades to `.regular` via `mergeFieldClass`, so it is no longer `.optional`. 7
native_decide pins + 4 export fixture pairs (`bug213_*`). cert-manager identical (jq -S).
Spec-grounded — no divergence/gap recorded (kue == cue, no residual).

## THE MILESTONE — argocd does NOT export yet

`kue export apps/argocd.cue` STILL bottoms (~54s, `conflicting values`). Bug2-13 cleared
`route.yaml`'s `#service_port: _|_` but was NOT the terminal blocker. The SOLE remaining
`_|_` is now `route.yaml`'s `#listenerset_name: _|_` (= `ls.#name`). **NOT a Bug2-13
over-fire** (selecting `kind`, a regular field, also bottoms). argocd is NOT a drop-in;
Standing Capabilities unchanged (cert-manager remains the only real-app drop-in). Perf #7
STAYS GATED.

## Next leader — Bug2-14 (HIGH, on-path argocd blocker; filed this slice)

Field selection from a `.structComp` bottoms. `selectEvaluatedField` has an arm
for `.struct`/`.embeddedList`/`.embeddedScalar`/`.disj` but NONE for `.structComp` → a
field select on one falls to `| _ => .bottom`. `ls = defaults.#ListenerSet & {…}` (where
`defaults.#ListenerSet = defs.#ListenerSet & parts.#UseCertManager & {…}` co-embeds the
`#Mixin` `listShape | structShape | error` disjunction with a `for _, add in #additions`
`_patch` comprehension) resolves to a `.structComp` whose `for`-comprehension is left
UNDRAINED even though `#additions` is concrete (cue drains it to a plain struct). So
`#listenerset_name: ls.#name` selects `#name` from a `.structComp` → `_|_` (every field
select on `ls` bottoms; `ls` itself exports fine in `listener.yaml`).

**Two candidate fixes:** (a) ROOT CAUSE — drain the `#Mixin` comprehension through the
def-of-def force path so `ls` becomes a plain `.struct` (the diagnostic question: why does
cross-pkg + disjunction force leave it undrained where the inline form drains?);
(b) FALLBACK — add a `.structComp` arm to `selectEvaluatedField` selecting from the static
`fields` bucket while preserving the residual. (a) is the proper fix; (b) may be needed
regardless as selection-time safety. Start by diagnosing WHY the comprehension stays
undrained (compare the inline vs cross-pkg force path).

**Repro:** 5-package faithful argocd composition (during the slice at `/tmp/b213x`:
`defs/`+`defs/attr/`+`defs/parts/`+`defaults/`+`main`). The INLINE single-file collapse
does NOT reproduce — it needs the cross-pkg def-of-def + mixin disjunction. Full filing in
`spec-conformance-audit.md` Bug2-14. HONEST depth: ONE empirically-confirmed remaining
layer; a further bug behind it is unknown until Bug2-14 is fixed + argocd re-run.

## After Bug2-14 (ranked)

1. **`TwoPassTests` SPLIT** (item 3) — DUE (~2135 lines, grew with the Bug2-13 section);
   carve `bug2x_*` into `Bug2xTests.lean`, each file gets the `#check` tripwire + `--`
   headers.
2. **Perf frontier (#7 / item-5)** — STILL GATED; un-gates only once argocd EXPORTS.
3. **Bug2-12** (LOW, self-recursive closed-def closedness leak — spec-check first) + the
   missing-field-selection observation (`x.a.missing != _|_` → kue incomplete vs cue
   false) + item-6 tail.

## Audit cadence

**Audit counter = 1** (Bug2-13 landed since the last reset). Next audit due after
the next 1–2 slices (per the 2–3-slice cadence). Batch to audit when due: `7e69e43`
(Bug2-13) + the next slice(s).

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is **cadence-available, awaits user
greenlight** — but NOT notable yet (argocd does NOT export; cert-manager remains
the only real-app drop-in). A fresh alpha becomes notable when argocd exports. CI/Actions
banned; release = local `scripts/release.sh` + `scripts/release-linux.sh`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 (`/Users/chakrit/Documents/prod9/infra` + sibling `infra-defs` source) + cue
  caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree. argocd
  oracle = `kue export apps/argocd.cue` from the infra root; localize bottoms with
  `kue apps/argocd.cue | grep _|_`.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
