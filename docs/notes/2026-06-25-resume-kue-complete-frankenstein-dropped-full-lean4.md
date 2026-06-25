# RESUME HERE — kue complete; Go-FFI frankenstein DROPPED; full Lean 4 (2026-06-25)

**SUPERSEDED (2026-06-26) by [`2026-06-25-resume-b3d-registry-fetch-active.md`](2026-06-25-resume-b3d-registry-fetch-active.md)**
— its "project complete, no autonomous leader" framing is OBE; B3d is now the active track.
Kept for the pre-B3d durable findings below. NOT the live START-HERE.

Prior-state note; supersedes the spike-COMMIT and CLI-entry-UX breadcrumbs (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — the project is comprehensively COMPLETE

- **Correctness: done.** Spec-conformance backlog EMPTY. argocd + cert-manager are
  byte-identical (`jq -S`) drop-ins. The whole Bug2-5→2-14c argocd chain + the closedness
  family (Bug2-12/12b/mutual, SC-4, embed-disj-arm-closedness), missing-field, A2-y (a latent
  wrong-value bug), aliased builtin imports + stdlib consts, parser strictness — all landed.
- **Perf: closed.** Floor-characterized — argocd ~52s ≈ 486K necessary evals × irreducible
  per-meet cost; frame-sharing WON'T-FIX (~0.05% ceiling); safe-wins + flatten-bound shipped.
- **Shipped + hardened.** Released `v0.1.0-alpha.20260624` (macOS arm64 + Linux x86_64/arm64)
  with race-safe idempotent tap tooling. Process hardened (resilience pass → `failure-modes.md`
  + `slice-loop.md`).
- **CLI entry-UX fixed** (`daacbf3`): bare `kue` → help (was a stdin HANG); empty `kue eval` →
  empty (the `printSmoke` demo reel + `Kue/Examples.lean` deleted as dead code). `kue <file>` /
  piped `kue eval` preserved. Help polished.

## The big arc this session: Go+Lean frankenstein — EXPLORED, SPIKED, DROPPED

Question chased: make kue a standalone cue replacement that can FETCH its own deps (the
registry/OCI/module half kue lacks — it has the on-disk read-path, proven on argocd; it
lacks fetch/manage/registry = `B3d`). Idea: Go outer shell (reuse cue's Go mod/OCI
ecosystem) + the Lean engine linked in, single binary.

- **Spiked it** (`6a32729`, artifacts in `spike/`): cgo, Go owns `main`, Lean engine linked
  as a guest. **Feasibility = COMMIT** — the real evaluator (GMP/`Decimal` + full runtime)
  links + runs in-process on macOS arm64 AND Linux x86_64, self-contained binary.
- **chakrit DROPPED it** (2026-06-25): the Lean↔Go **seam is too leaky** (owned-vs-borrowed
  refcount trap, an IO-boundary `Module.lean` refactor, dual-toolchain cgo build, static
  libc++ on Linux). A fragile FFI seam undercuts kue's correctness+traceability value. →
  **Full Lean 4.** Decision note corrected to "feasibility-proven, REJECTED":
  [`../decisions/2026-06-25-lean-engine-embedded-in-go-via-cgo.md`](../decisions/2026-06-25-lean-engine-embedded-in-go-via-cgo.md).
  `spike/` kept as a durable feasibility record (don't re-spike).

## Durable findings worth keeping (informed the above; inform any future module work)

- **CUE loading/importing is EVAL-FREE** — imports are static string literals (no dynamic
  imports), `module.cue` deps are concrete, import binding is reference/frame setup; value
  resolution (unification/closedness) is a separate pure phase over the EAGERLY-assembled
  graph (no lazy IO during eval). kue already splits this (`loadPackageFromParsed`/`bindImports`
  pure; IO in `Module.lean`'s discovery/read fns). So module resolution never needs the
  evaluator — only structural resolution + parsing.
- **CLI gap vs cue v0.16.1** (for the open CLI direction): kue has `eval`/`export`/`version`/
  `help`; cue adds `vet`/`def`/`fmt`/`import`/`trim`/`fix`/`mod`/`cmd`/`get`/`login`/`completion`,
  plus flags `-e`-on-eval (+repeatable), `-t/--inject` (`@tag`, the one semantic flag),
  `-c/--concrete`, `-a/-H/-O/-A`, `-l/-p/-o`. **`vet` is the high-leverage, low-cost one — the
  engine (unify + bottom-detect + `Order.lean` subsumption) already exists; vet is ~CLI
  plumbing.** Start there if the CLI track is taken up.
- **Module-infra status:** on-disk READ-path done + proven (discovery, in/cross-module
  resolution by deps prefix, vendor + extract-cache, version pinning, transitive loads,
  qualified imports, A2-y redeclaration check). MISSING = fetch/manage: registry/OCI (`B3d`,
  the gate), `cue mod` commands, MVS, per-file import scoping. Now a **Lean-native deferred**
  problem (NOT Go-FFI).

## Next /ace — the project is complete; open work is USER-DIRECTED, no autonomous leader

There is NO autonomous "next leader" — the substantive backlog, perf, process, and real
conformance gaps are all done. The open threads are all either user-scoped or deferred:

1. **CLI command surface** (`plan.md` item 7 — `vet`/`fmt`/`def`, `-e`-on-eval, `-`-stdin,
   flag parity) — USER-SCOPED. `vet` first if taken up. Do NOT self-start.
2. **Lean-native registry/module-fetch** (`B3d` + `cue mod` cmds + MVS) — big, deferred.
3. **Latent tail dregs** (none observable, none soundness-bearing): `module-file-scoped-imports`,
   B2-A1/A2, SC-3 (eval-only display gap), nested-disj-mark (DESIGNED-DEFERRED — needs a 3rd
   `Mark` state, ~8-file change; tripwire-pinned).

A fresh alpha is owed (CLI entry-UX + the soundness tail since 20260624) — auto-cuts on the
next daily cadence.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy/slice-loop grant in effect; commit/push/release freely (attended); auto-cut
  releases; never pause at milestones. AFK envelope for unattended.
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check.
  Canaries: cert-manager + argocd `jq -S` = 0, run FROM `/Users/chakrit/Documents/prod9/infra`
  (cwd matters; the apps may sit under `k8s/<app>` there, not `apps/<app>` — verify the path).
- prod9 + cue caches READ-ONLY. No working-tree-overwriting git. kue binary:
  `.lake/build/bin/kue`. Orchestrator verifies every subagent claim from git/canary, not its words.
