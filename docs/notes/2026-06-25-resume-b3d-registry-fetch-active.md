# RESUME HERE — B3d registry-fetch track ACTIVE (Lean-native, AFK run 2026-06-25)

Live START-HERE; supersedes `2026-06-25-resume-kue-complete-frankenstein-dropped-full-lean4.md`
(its "project complete, no autonomous leader, B3d deferred" framing is now OBE — B3d is the
active leader). Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Transport decision:
[`../decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`](../decisions/2026-06-25-registry-fetch-via-curl-subprocess.md).

## What this run is doing

chakrit took the **Registry / B3d** fork (the one real capability gap: kue READS modules but
can't FETCH them) under **`/ace-afk` "keep going"** — "do bigger tasks, unblock the most
first." B3d is the gate under the entire module-management half (`cue mod get/tidy`, MVS
solving, `cue.sum` verification all sit on "can pull a module from an OCI registry").

**Architecture DECIDED (resolve-by-philosophy):** HTTPS in Lean 4 via a **`curl` subprocess**,
NOT FFI. The Go-cgo frankenstein was rejected for the leaky *seam*; a subprocess is a clean
bytes-in/bytes-out process boundary (traceable, engine stays pure, no build-dep growth). This
decomposes B3d into a PURE protocol core (fixture/`native_decide`-testable offline) + a thin
impure curl edge — so ~80% is ordinary offline TDD. Authoritative protocol reference = cue's
own source, READ-ONLY at `~/go/pkg/mod/cuelang.org/go@v0.16.1/mod/{module,modregistry,modzip}/`
+ `internal/mod/modresolve/resolve.go`.

## Slice ledger (all on `main`, UNPUSHED — AFK envelope: commit, don't push)

- `1bd93d8` **decision** — curl-subprocess transport; B3d ACTIVE.
- `b1cfec7` **B3d-1** — `Kue/Registry.lean`: `CUE_REGISTRY` parse + module→OCI-ref resolution
  (PURE). Repo = UNescaped base path; tag = plain version; escaping is CACHE-dirs-only.
- `252b129` **B3d-3** — `Kue/Sha256.lean`: SHA-256 (FIPS 180-4) + `cue.sum` `h1:` dirhash
  (PURE). NIST vectors + 0/55/56/63/64/65 padding boundaries pinned; independent `h1:` cross-check.
  Reuses `Kue.base64Encode`. cue's modzip stores BARE (unprefixed) zip-entry paths → dirhash name.
- `fc5456d` **B3d-2** — `Kue/Oci.lean`: OCI image-manifest parse (PURE), via stdlib
  `Lean.Json.parse` (`Kue/Json.lean` is serialize-only). Layer-select BY mediaType, exactly-one
  (stronger than cue's index check). Config `application/vnd.cue.module.v1+json`; zip layer
  `application/zip`; modulefile `application/vnd.cue.modulefile.v1`.
- `11cfc77`,`9afd54c` **Phase A audit** (code-quality, batch `1bd93d8..fc5456d`) — **HEALTHY**,
  no violations; one doc-ref fix.
- `90aa8d5` **Phase B audit** (architecture, whole graph) — **HEALTHY**. Seam set:
  `Module → {Oci, Sha256, Registry}` (IO→pure, no cycle); `Eval`/`Resolve`/`Value` must NOT
  import the trio. Filed **B3d-5a** (cache-path DRY: unify `Module.locateModuleDir` read-path
  with `Registry.{extract,download}CachePath` write-path — do inside B3d-5). Shared-bytes-util =
  YAGNI (re-eval at B3d-4).
- **B3d-4** (curl IO edge) — IN FLIGHT as of this writing. Pure URL/argv builders + thin
  `IO.Process` curl runner; offline-verified via `file://` fixtures (incl. digest-mismatch
  rejection). Module.lean is the only IO edge; first `IO.Process` use in the codebase.

## Next (remaining B3d arc — AFK-tractability noted)

1. **B3d-5 — wire fetch into the resolver** (+ **B3d-5a** cache-path unification). Replace the
   `Module.lean:32` "registry fetch is B3d" error (declared dep absent from vendor+cache) with:
   resolve ref → fetchManifest → fetchBlob (digest-verified) → extract zip → write download +
   extract cache → existing read-path takes over; `cue.sum` verify. **AFK-PARTIAL:** wiring +
   offline tests land; the real missing-dep fetch needs network + a cache write OUTSIDE the tree
   → human-gated, LOG to `.afk.log`, don't cross.
2. **B3d-6 — MVS version *solving*** (Minimal Version Selection) + `cue mod get/tidy`. The
   SOLVER is PURE (given available versions + constraints → selected set) → **fully offline /
   AFK-testable**. Only "list versions from registry" (OCI tag-list) is network.

## AFK envelope reminder (this run)

Commit, do NOT push. NO network to real registries (`registry.cue.works`). NO writes outside the
repo tree (`~/Library/Caches/cue` is off-limits; tests use `file://` fixtures + repo-local temp via
`$CUE_CACHE_DIR`). Live-fetch verification is a logged BLOCKER, not a failure. prod9 + cue caches
READ-ONLY. No working-tree-overwriting git. kue binary: `.lake/build/bin/kue`. Orchestrator
verifies every subagent claim from git/build (`git rev-parse HEAD` vs `@{u}`), not its words.

## Durable findings (still valid; from the pre-B3d state)

- **Correctness DONE** — argocd + cert-manager byte-identical (`jq -S`) drop-ins; spec-conformance
  backlog EMPTY. **Perf CLOSED** — argocd ~52s floor-characterized. Shipped `v0.1.0-alpha.20260624`.
- **CUE loading is EVAL-FREE** — imports are static; module resolution is structural + parse only,
  never the evaluator. kue already splits this (pure `loadPackageFromParsed`/`bindImports`; IO in
  `Module.lean`). So registry fetch is an IO+protocol problem, not an engine one.
- A fresh alpha is owed (CLI entry-UX + the B3d foundation since 20260624) — but releases are
  PUSH-class, so AFK does NOT cut them; queued for an attended session.
