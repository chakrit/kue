# Registry Fetch (B3d) Transport: `curl` Subprocess, Not FFI

- **Date:** 2026-06-25
- **PR:** in-flight (B3d slice series)
- **Status:** **DECIDED** (chakrit AFK grant, resolve-fork-by-philosophy). Opens the B3d
  track: Lean-native registry/OCI module fetch. Supersedes the "B3d deferred" footnote in
  [`plan.md`](../spec/plan.md) — B3d is now ACTIVE.

## Context

kue's on-disk module read-path is done and proven (argocd + cert-manager byte-identical
drop-ins). The one real capability gap is **B3d**: fetching a dependency the disk doesn't
already have. Today kue hard-errors `... registry fetch is B3d` the moment a declared dep is
absent from vendor + cache. B3d is the gate under the entire module-management half —
`cue mod get/tidy`, MVS version *solving*, and `cue.sum` verification all sit on top of
"can pull a module from an OCI registry."

CUE modules live in OCI registries (default `registry.cue.works`). Fetch =
HTTPS + the OCI distribution protocol. So B3d needs an HTTP transport in a Lean-4-native
codebase — and we just rejected the Go-via-cgo route (see
[`2026-06-25-lean-engine-embedded-in-go-via-cgo.md`](2026-06-25-lean-engine-embedded-in-go-via-cgo.md)).

## Decision

**Transport = a `curl` subprocess.** The Lean code builds the request (URL, headers, output
path) and shells out via `IO.Process`; curl does TLS + HTTP; bytes come back over the process
boundary. No FFI, no linked C, no new Lake/build dependency.

## Why (philosophy)

The cgo frankenstein was rejected for the **seam**, not the goal — shared refcounts,
owned-vs-borrowed traps, a dual-toolchain link line. A subprocess has *none* of that:

- **Process boundary, not memory boundary.** Bytes out (argv + URL), bytes in (response body
  to a file). No shared heap, no refcount contract, no marshaling invariant to keep exact.
- **Maximally traceable + debuggable** — kue's two reasons to exist. The exact `curl` command
  is printable and reproducible by hand; a failed fetch is a shell command a human can re-run.
- **Engine stays pure.** IO is already confined to `Module.lean`; the curl call is one more
  `IO` action on that same edge. `Eval`/`Resolve`/`Value` never see it.
- **No build-surface growth.** curl is ubiquitous (macOS + Linux ship it; it's already an
  implicit dep of the release tooling). No elan+Go dual toolchain, no static libc++.

Rejected alternatives: **libcurl FFI** (re-introduces the linked-C refcount seam we just
threw out); **pure-Lean HTTP+TLS** (a TLS stack is a multi-month project, absurd for this);
**Go-shell wrapper** (the rejected frankenstein).

## Consequence: the decomposition that makes B3d AFK-tractable

The win isn't just transport — it's that the OCI *protocol* splits cleanly into a **pure**
core + a **thin impure edge**:

- **PURE (fixture / `native_decide` testable, zero network):** `CUE_REGISTRY` parsing,
  module-path → OCI repo escaping, version → tag, OCI manifest JSON parsing (reuse the
  stdlib `Lean.Json.parse` — `Kue/Json.lean` turned out serialize-only, so B3d-2 reuses
  the toolchain's parser, no second JSON parser), digest + `cue.sum` dirhash,
  download/extract cache-path computation.
- **IMPURE (thin, in `Module.lean`):** the actual `curl` GET of manifest + blob, and the
  zip extraction. Network-tested; logged as needing network if unverifiable offline.

So ~80% of B3d is ordinary offline TDD. Authoritative protocol reference is cue's own source,
locally readable: `~/go/pkg/mod/cuelang.org/go@v0.16.1/mod/{modregistry,module}/*.go`
(`client.go` for the OCI flow, `escape.go` for path→repo escaping). Conform to *that* protocol
(it's tooling, not in the language spec); the language spec stays authority for everything the
fetched module then evaluates to.

## Slice plan (B3d-1 … B3d-6)

1. **B3d-1 — `CUE_REGISTRY` parse + module→OCI-ref resolution** (PURE). Simple-syntax registry
   config (default, host[:port], `/path` prefix, `+insecure`/`+secure`, `prefix=reg` longest-
   match, `none`); path-escape → repo; version → tag. `file:`/CUE-syntax config = footnote-deferred.
2. **B3d-2 — OCI manifest + blob-descriptor parse** (PURE, via the stdlib `Lean.Json.parse`;
   `Kue/Json.lean` is serialize-only): pull the module-content layer digest/size/mediaType
   from a manifest.
3. **B3d-3 — SHA-256 + `h1:` dirhash** (PURE): digest verification + `cue.sum`.
4. **B3d-4 — the `curl` IO edge** (`Module.lean`): GET manifest + blob, tag-list for version
   enumeration. Network.
5. **B3d-5 — wire into the resolver**: replace the `registry fetch is B3d` error with
   resolve→pull→verify-digest→write download cache→extract→read-path; `cue.sum` verify.
6. **B3d-6 — MVS version *solving* + `cue mod get/tidy`**.

Cache layout fetch must produce (Go-module-style, already what kue's read-path consumes):
`mod/download/<modpath>/@v/<ver>.{zip,mod,lock}` → extract → `mod/extract/<modpath>@<ver>/`.
