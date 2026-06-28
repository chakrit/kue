# RESUME HERE — B3d fetch DONE + live-proven; EVAL-CONFORMANCE front now active (AFK run 2026-06-28→29)

Live START-HERE. Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Transport decision:
[`../decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`](../decisions/2026-06-25-registry-fetch-via-curl-subprocess.md).
AFK run state + blockers: [`../../.afk.log`](../../.afk.log).

## TL;DR for the next session

**B3d module-fetch is DONE end-to-end, including auth, and LIVE-PROVEN.** B3d-7 (`6e6d52b`, OCI
bearer-token auth over curl + the Docker credential-helper) landed attended; kue fetched the real
private `prodigy9.co/defs@v0.3.19` from **ghcr.io** with an empty cache — auth→fetch→digest→inflate→
cache→resolver, verified independently. The prod9 registry is `CUE_REGISTRY="prodigy9.co=ghcr.io/prod9"`
(simple prefix syntax kue already parses; private → Docker-keychain PAT, sourced via the cred helper).
B3d-6b (MVS resolver-wiring + `cue mod get/tidy`) is still the remaining module-MGMT piece but is
NOT needed for the single-pinned-dep fetch real apps use.

**⚠️ "Correctness DONE" is RETRACTED.** Proving the fetch end-to-end let the *broader* prod9 app
corpus load — and it exposed that kue mis-evaluates real apps. The old canary (argocd) is GONE from
the infra checkout; "correctness done" had held only on a 2-app sample (cert-manager = trivial). The
**eval-conformance front is now the active work** (see below). New `testdata/wild/` regression
category added (CLAUDE.md + slice-loop.md): real-world bugs captured as failing fixtures FIRST,
spec-adjudicated (cue is fallible — a `bottom`-vs-cue may be cue's bug; adjudicate vs SPEC).

## Eval-conformance front (the active work)

kue exported 4 of 5 real apps (`lem`/`n8n`/`x9`/`typesense`) to `bottom` where cue is clean
(`cert-manager` clean both; `gateway` bad-input both). Peeled THREE distinct eval bugs:

- **Layer 1 — FIXED** (`f6fc514`): `Self.#hidden` read *inside a list embedding* resolved to `_|_`
  (the embedding-`Self` two-pass re-evaluated only static fields, never embedding values). Fix:
  `embeddingsReadEmbeddedSelf` gate. Wild fixture `testdata/wild/self-hidden-in-list-embed/`.
- **Layer 2 — FIXED** (`4b24902`): a defaulted disjunction (`string | *"x"`) as an interpolation
  operand stayed incomplete. Fix: `collapseDefaultDisjunction` over interpolation parts (reuses the
  shared default-shed path). Wild fixture `testdata/wild/default-disj-in-interpolation/`.
- **Layer 3 — OPEN**: the 4 apps STILL bottom on a HARD `conflicting values` in
  `packs.#WebApp & parts.#UseKeel` (defs@v0.3.19) — distinct from L1/L2. **No faithful minimal repro
  yet** (only reproduces in the full app graph; reductions flip polarity). Next slice's first job =
  isolate a faithful repro, then fix. Logged in `.afk.log` + plan.md "Layer 3 — OPEN".

Verify the front by re-sweeping (cd+relative, NEVER absolute paths — those make `cue` resolve the
module wrong → false diffs): `( cd /Users/chakrit/Documents/prod9/infra && CUE_REGISTRY=prodigy9.co=ghcr.io/prod9 \
diff <(kue export apps/<app>.cue|jq -S .) <(cue export apps/<app>.cue|jq -S .) )`.

**Attended TODO:** `git push` (AFK can't); cut the owed alpha; then resume Layer 3 + B3d-6b.

## (historical) B3d offline-track summary — the fetch arc, all done

All on `main`, UNPUSHED. Offline half = `8775ecc..f40dd9c`; auth (B3d-7) `6e6d52b`; eval fixes
`f6fc514`/`4b24902`.

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
