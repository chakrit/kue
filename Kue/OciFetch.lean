import Kue.Oci
import Kue.Sha256
import Kue.Registry

/-!
# OCI fetch over a `curl` subprocess (B3d-4, IMPURE edge)

The thin IO runner that turns the pure OCI builders (`Kue/Oci.lean`) into actual bytes off a
registry. Decision: `docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md` — transport
is a `curl` subprocess (process boundary, not memory boundary), so the engine stays pure and the
exact request is a shell command a human can re-run.

This is the FIRST `IO.Process` user in the codebase. It imports only the pure trio
(`Oci`/`Sha256`/`Registry`) — never `Eval`/`Resolve`/`Value` (the Phase-B seam: IO depends on the
pure protocol core, never the reverse). Each function is a total `IO (Except String _)`: a curl
failure, an HTTP error, a parse failure, or a digest mismatch is an `Except.error` with a clear
message, never an exception or a silent empty success.

Wiring this into the resolver (replace `Module.lean`'s `registry fetch is B3d` error with
resolve → fetch → verify → cache-write → extract) is B3d-5; B3d-4 only PROVIDES the capability.

## Why `spawn` + `readBinToEnd`, not `IO.Process.output`

`IO.Process.output` decodes the child's stdout as a UTF-8 `String`, which corrupts a binary blob
(a module zip is not valid UTF-8) and would make digest verification compare against mangled
bytes. So we `spawn` with `stdout := .piped` and `readBinToEnd` the raw bytes. stdout (the body,
possibly large) is drained BEFORE `wait` so a full pipe never deadlocks the child; stderr stays
small because `--fail-with-body` routes HTTP error bodies to stdout, not stderr.
-/

namespace Kue
namespace OciFetch

/-- Run `curl <args>` and capture its stdout as RAW bytes. On exit 0, `Except.ok` the body; on a
    non-zero exit (curl transport error, or a non-2xx HTTP status via `--fail-with-body`),
    `Except.error` carrying the exit code and curl's stderr (the diagnostic), plus the body bytes
    decoded best-effort for context. Total — the only outcomes are ok-bytes or a described error.

    stdout is drained before `wait` (deadlock-safe for a large body); stderr is read after. -/
def runCurl (args : List String) : IO (Except String ByteArray) := do
  let child ← IO.Process.spawn {
    cmd := "curl",
    args := args.toArray,
    stdout := .piped,
    stderr := .piped }
  let body ← child.stdout.readBinToEnd
  let exitCode ← child.wait
  let stderr ← child.stderr.readToEnd
  if exitCode == 0 then
    pure (.ok body)
  else
    let cmdline := String.intercalate " " args
    pure (.error s!"curl failed (exit {exitCode}) for {cmdline}: {stderr.trimAscii.toString}")

/-- GET `url` with `extraArgs` (e.g. the manifest `Accept` headers), returning the response body
    bytes or a clear error. The single curl seam every fetch routes through. -/
def curlGet (url : String) (extraArgs : List String) : IO (Except String ByteArray) :=
  runCurl (Oci.curlBaseFlags ++ extraArgs ++ [url])

/-- Decode response bytes as a UTF-8 `String` for the JSON parser. A manifest is always JSON
    text, so a valid one decodes cleanly; an invalid byte sequence surfaces as a parse error
    downstream rather than a crash (`String.fromUTF8?` is total). -/
private def bytesToText (bytes : ByteArray) : Except String String :=
  match String.fromUTF8? bytes with
  | some s => .ok s
  | none => .error "manifest response was not valid UTF-8 text"

/-- Fetch + parse + validate a module's OCI image manifest: `curl GET /v2/<repo>/manifests/<tag>`
    with the manifest `Accept` headers, then `Oci.parseManifest` and `validateModuleManifest`. The
    returned manifest is a confirmed 2-layer CUE module manifest. -/
def fetchManifest (ref : Registry.OciRef) : IO (Except String Oci.OciManifest) := do
  match ← curlGet (Oci.manifestUrl ref) (Oci.acceptHeaderArgs Oci.manifestAcceptTypes) with
  | .error e => pure (.error e)
  | .ok bytes =>
      pure do
        let text ← bytesToText bytes
        let manifest ← Oci.parseManifest text
        Oci.validateModuleManifest manifest

/-- GET `url` and VERIFY the body against `expectedDigest`: require
    `Sha256.digestString bytes == expectedDigest`, else error. The integrity gate, expressed at
    the URL level so it is exercisable against a `file://` fixture offline (the curl subprocess +
    raw-byte capture + digest check, no registry). A mismatch (corrupt/tampered/wrong content) is
    rejected — the whole point of computing the digest. -/
def curlGetVerified (url : String) (expectedDigest : String) :
    IO (Except String ByteArray) := do
  match ← curlGet url [] with
  | .error e => pure (.error e)
  | .ok bytes =>
      let actual := Sha256.digestString bytes
      if actual == expectedDigest then
        pure (.ok bytes)
      else
        pure (.error
          s!"blob digest mismatch for {expectedDigest}: server bytes hash to {actual}")

/-- Fetch a blob by descriptor and verify its integrity against `descriptor.digest`:
    `curl GET /v2/<repo>/blobs/<digest>`, then the `curlGetVerified` digest check. A mismatch is
    rejected — the integrity gate the whole B3d-3 SHA-256 work exists to enforce. -/
def fetchBlob (ref : Registry.OciRef) (descriptor : Oci.Descriptor) :
    IO (Except String ByteArray) :=
  curlGetVerified (Oci.blobUrl ref descriptor.digest) descriptor.digest

/-- Compose the whole fetch: get + validate the manifest, select the `application/zip`
    module-content layer, fetch + digest-verify that blob, and return its bytes. Stops at the
    verified zip bytes; extraction, cache-write, and resolver wiring are B3d-5. -/
def fetchModuleZip (ref : Registry.OciRef) : IO (Except String ByteArray) := do
  match ← fetchManifest ref with
  | .error e => pure (.error e)
  | .ok manifest =>
      match Oci.moduleZipDescriptor manifest with
      | .error e => pure (.error e)
      | .ok descriptor => fetchBlob ref descriptor

end OciFetch
end Kue
