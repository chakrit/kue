# RESUME HERE — B3d registry-fetch: offline track COMPLETE; B3d-6b is the one gated slice (AFK run 2026-06-25→26)

Live START-HERE. Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) (B3d entries + Live
Backlog item 7 = B3d-6b). Per-slice history: [`../reference/implementation-log.md`](../reference/implementation-log.md).
Transport decision: [`../decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`](../decisions/2026-06-25-registry-fetch-via-curl-subprocess.md).

## TL;DR for the next session

An unattended `/ace-afk` run built the **entire offline-tractable half of B3d** (Lean-native
registry/OCI module fetch — the one real capability gap: kue READS modules, now it can FETCH
them too). 18 commits, 8 new modules, all DONE + double-audited HEALTHY + **all UNPUSHED** (AFK).
The single remaining substantive slice, **B3d-6b**, is network/human-gated and was deliberately
NOT crossed (live registry egress + a resolver behavior-change that a green canary would mask).

**First two things to do attended:** (1) `git push` the 18 commits (AFK couldn't). (2) Run the
two live smokes logged in `.afk.log` (a real HTTPS fetch from registry.cue.works + the
remove-dep-and-`kue export` end-to-end) to confirm the curl edge against a real registry. Then
pick up B3d-6b.

## What landed (all on `main`, UNPUSHED — `8775ecc..f40dd9c`)

Architecture (decided by philosophy): HTTPS via a **`curl` subprocess**, not FFI — a clean
bytes-in/bytes-out process boundary, engine stays pure, no build-dep growth. This split B3d into
a PURE protocol core (offline `native_decide`-testable) + a thin curl IO edge.

- **B3d-1** `b1cfec7` — `Registry.lean`: `CUE_REGISTRY` parse + module→OCI-ref resolution.
- **B3d-2** `fc5456d` — `Oci.lean`: OCI manifest parse (stdlib `Lean.Json.parse`; layer-select by mediaType).
- **B3d-3** `252b129` — `Sha256.lean`: SHA-256 (FIPS 180-4) + `cue.sum` `h1:` dirhash.
- **B3d-4** `3e9f0cb` — `OciFetch.lean`: curl subprocess (manifest/blob GET, digest-verified); pure URL/argv builders. `file://`-fixture seam test.
- **B3d-5z** `8500c99` — `Inflate.lean` (RFC 1951 DEFLATE, total, fuel-proved) + `Zip.lean` (PKWARE + CRC-32). 69-file real cue zip golden, byte-identical vs `unzip`.
- **B3d-5** (+5a) `c9c8e30` — `Module.lean` wiring: fetch-on-missing replaces the `registry fetch is B3d` error; cache-path authority unified. argocd canary 0-diff (independently re-verified).
- **B3d-A1** `80f3ec2` — atomic cache write (temp-dir + `IO.FS.rename`): `atomicWriteBinFile`/`atomicExtractDir` (B3d-6b reuses these for `cue.sum` write).
- **B3d-6a** `00e288a` — `Semver.lean` (Go `x/mod/semver` port) + `Mvs.lean` (pure Minimal Version Selection solver). Canonical MVS worked-example pins.
- **4 audit phases** (2 full two-phase rounds) all HEALTHY. Phase A on 6a caught + fixed TWO real
  bugs (`e0d1156`): MVS fuel bound was unsound (silently truncated the build list on dense graphs)
  and semver accepted empty segments. Plan-hygiene distilled (`f40dd9c`).

**Three integrity gates enforced + unbypassable on the production path** (audit-traced): blob
`sha256:` digest, zip CRC-32+size, `cue.sum` `h1:`. Nothing unverified ever reaches the cache.
**Module graph:** clean DAG, no cycles; IO confined to `OciFetch` + `Module`; `Eval`/`Resolve`/
`Value` import zero B3d module.

## The one remaining slice — B3d-6b (network/human-gated; see plan.md Live Backlog item 7)

Five legs, all needing live registry egress and/or attended behavior-change verification:
1. **Requirement-graph fetch** — pull each dep's `module.cue` `deps` to build the `Mvs.RequirementGraph`.
2. **OCI `…/tags/list`** — version enumeration for latest/major resolution.
3. **`cue mod get` / `cue mod tidy`** — command parse + dispatch.
4. **Wire `Mvs.solve` into the resolver** — replaces kue's current lenient per-hop resolution with
   global MVS. This is a genuine BEHAVIOR change (per-hop vs max-of-mins differ on a transitive
   version-conflict diamond); the canaries don't exercise the difference, so a green canary would
   MASK it. **Gate on a deliberately-constructed diamond-divergence fixture before flipping.**
   The pure `Mvs.solve` is landed + tested but UNWIRED until this leg (intentional staged primitive).
5. **`cue.sum` WRITE** via `atomicWriteBinFile`. (Note: cue v0.16.1 ships no `cue.sum`; the OCI blob
   digest is its live gate — kue matches that and adds defensive cue.sum support.)

Smaller ranked open items (all in plan.md, none soundness-bearing): B3d-A2 (DEFLATE/ZIP reject-branch
test pins, LOW), B3d-B1 (digest/`h1:` newtype, rides 6b), `Mvs.solve` main-pin corner (LOW, rides 6b),
`Kue/ModuleFetch.lean` carve (conditional — if Module.lean's fetch cluster passes ~200 lines).

## STANDING CONTEXT

- AFK envelope governed this run: commit-don't-push, no network to real registries, no writes
  outside the tree (tests used `file://` fixtures + repo-local `CUE_CACHE_DIR`). Attended sessions
  lift this — push freely, run the live smokes.
- A fresh alpha is owed (CLI entry-UX + the whole B3d foundation since `v0.1.0-alpha.20260624`) —
  release is PUSH-class so AFK didn't cut it; cut one attended via `scripts/release.sh` (+ Linux).
- Spec is authority; `cue` (`~/go/bin/cue` v0.16.1) a fallible cross-check. Canary: argocd `jq -S`
  = 0 from `/Users/chakrit/Documents/prod9/infra` (`apps/argocd.cue`; cert-manager there is plain
  YAML, not CUE). prod9 + cue caches READ-ONLY. kue binary: `.lake/build/bin/kue`. Orchestrator
  verifies every subagent claim from git/build (`HEAD` vs `@{u}`), never its words.
- Pre-B3d durable findings: see the demoted [`2026-06-25-resume-kue-complete-frankenstein-dropped-full-lean4.md`](2026-06-25-resume-kue-complete-frankenstein-dropped-full-lean4.md)
  (correctness DONE, perf CLOSED, the dropped Go-cgo frankenstein, CUE-loading-is-eval-free).
