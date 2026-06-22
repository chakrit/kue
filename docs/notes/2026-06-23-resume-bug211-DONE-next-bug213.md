# RESUME — Bug2-11 DONE; next = Bug2-13 (next on-path argocd blocker) (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug210-DONE-next-bug211.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) (§ Bug2-11
RESOLVED + Bug2-13 filed). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md) (Bug2-11 entry).

## State — audit counter = 2 (Bug2-10, Bug2-11). 🚨 TWO-PHASE AUDIT DUE.

**Bug2-11 RESOLVED (`bdced40`, on `main`; pushed if attended):** use-site narrowing of
a TWO-LEVEL cross-package def-of-def selector. `defaults.#ListenerSet & {#name,
#passthrough}` where `defaults.#ListenerSet = defs.#ListenerSet & {…}` now reaches the
embedded self-ref (`metadata.name` narrows) AND the sibling default disjunction narrows
— was `conflicting values`.

- **Mechanism (delivery, right-frame).** A `.conj` def-of-def body whose arm reaches a
  deferral-needing struct (`conjBodyHasDeferringArm`, recursing further `.conj` levels
  for the 3-level chain) is captured RAW over its OWN package frame in
  `importDefClosureBody?`; `forceClosureWithConjunctCore`'s new `.conj` arm re-folds
  `arms ++ narrowing` under `capturedEnv`, so each arm resolves its OWN import binding
  (the inlined `defs.#LS & {…} & {narrow}` meet) — NOT a use-site-frame splice.
  `resolveSelectorDefBody?` resolves a selector/ref arm to its def body for the check.
- **Wrong-frame hazard PINNED:** `crosspkg_defofdef_wrongframe_witness` (defs-local
  `_region:"US"` vs defaults-local `"EU"`) → kue yields `zone:"US"` (defs' frame). A
  use-site splice would mis-resolve to "EU"/bottom.
- **Verify (all green):** `lake build` (sentinels resolve); `check-fixtures.sh` zero
  drift; cert-manager content-identical (jq -S = 0); axiom-clean. 4 native_decide pins
  (`### Bug2-11`) + 4 module fixtures (`crosspkg_defofdef_*` + `crosspkg_singlelevel_
  narrowed` control) + 3 inlined `bug211_defofdef_*` pairs + FixturePorts.

## 🚨 ARGOCD MILESTONE — still bottoms; Bug2-11 was NOT the terminal blocker

`kue export apps/argocd.cue` (prod9 oracle at `/Users/chakrit/Documents/prod9/infra`,
READ-ONLY) STILL bottoms — `conflicting values`, ~54s (unchanged wall-time). **But
Bug2-11 is confirmed effective on the real app:** the `defaults.#ListenerSet`
`listener.yaml` subtree now FULLY narrows (metadata.name "argocd-ls",
#passthrough_hosts, all #additions resolved). The SOLE remaining `_|_` is in
`route.yaml` (`rt = defs.#TLSRoute & {…}`): `#service_port: _|_` (+
`#listenerset_name: _|_` downstream). Diagnosed + filed as **Bug2-13**.

HONEST DEPTH READ: **ONE empirically-confirmed remaining on-path layer (Bug2-13).**
Whether a further bug hides behind it is UNKNOWN until Bug2-13 is fixed and argocd
re-run. No "one fix away" over-claim — Bug2-13 is the only layer I have empirically
verified clears `route.yaml`.

## Next leader — Bug2-13 (HIGH, on-path argocd blocker)

**Presence-test on an UNSET OPTIONAL field returns the WRONG POLARITY.** For
`#opt?: {a:int}` unset: cue gives `#opt == _|_` ⇒ TRUE, `#opt != _|_` ⇒ FALSE; kue
gives the OPPOSITE. So a `if #opt != _|_ {…}` arm fires when it must NOT.
**Self-contained 2-line repro:**

```cue
x: {#opt?: {a: int}, eq_bottom: #opt == _|_, neq_bottom: #opt != _|_}
// cue: eq_bottom true, neq_bottom false.  kue: opposite (WRONG).
```

**On-path argocd impact:** `defs.#TLSRoute` embeds `attr.#ServiceRef` (READ-ONLY at
`~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/attr/service_ref.cue`),
which declares `#service_port` ONLY inside `if #service == _|_ {…}` (with `#service?`
unset). kue fires the `if #service != _|_` arm → `#service_port: #service.#ports[0]` =
`[...int][0]` (out-of-bounds on the empty list TYPE) → meeting use-site `443` bottoms.
**Fix on the presence-test / optional-field-presence path** (general — NOT comprehension-
or def-of-def-specific). Spec basis: CUE — an optional field not present is absent; a
presence-test against an absent field is `_|_`/false. Find where kue evaluates
`== _|_` / `!= _|_` against an unset optional and flip the polarity. Over-fire guard: a
SET optional, and a SET regular field, must keep their current (correct) presence
behavior — cert-manager MUST stay content-identical.

## After Bug2-13 (ranked)

1. **🚨 TWO-PHASE AUDIT (DUE NOW — counter = 2).** Spawn audit subagents per
   `docs/guides/slice-loop.md`: (A) code-quality over the Bug2-10 + Bug2-11 batch (the
   `conjBodyHasDeferringArm`/`.conj`-refold seams; the `resolveSelectorDefBody?` vs
   `followAliasDefBody?` overlap — is the new helper DRY against the chain-walkers?;
   test strength), then (B) architecture/refactor (`importDefClosureBody?` /
   `forceClosureWithConjunctCore` are growing many arms — boundaries, gate cohesion).
2. **Perf frontier (#7 / item-5)** — STILL GATED; un-gates only once argocd EXPORTS.
3. **`TwoPassTests` SPLIT** (`plan.md` item 3) — carve `bug2x_*` into `Bug2xTests.lean`;
   the 2000+-line file is the demonstrated silent-failure surface. Each new file gets the
   `#check` tripwire + `--` headers.
4. **Bug2-12** (LOW, self-recursive closed-def closedness leak — spec-check first) +
   item-6 tail.

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is **cadence-available, awaits user
greenlight** — Bug2-11 (`bdced40`) + Bug2-10..Bug2-5 + test-health hardening unreleased
in-tree. A fresh alpha would be notable IF argocd exported — it does NOT yet (Bug2-13
pending). CI/Actions banned; release = local `scripts/release.sh` +
`scripts/release-linux.sh`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main`
  (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 (`/Users/chakrit/Documents/prod9/infra`) + cue caches READ-ONLY. NO
  `git checkout`/`restore`/`reset --hard` on the main tree. argocd oracle = `kue export
  apps/argocd.cue` from the infra root; localize bottoms with `kue apps/argocd.cue`
  (validate text mode surfaces per-field `_|_`, rc=0 — NOT `export`, which bottoms the
  whole doc).
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
- **TWO-PHASE AUDIT DUE after this batch (counter = 2).** Do it before/with Bug2-13.
