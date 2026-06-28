import Kue.Oci
import Kue.OciAuth
import Kue.Base64
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

/-! ## Bearer-token auth (B3d-7)

The auth-aware fetch path. A bare GET against a real registry (`ghcr.io`) returns `401` with a
`WWW-Authenticate: Bearer …` header; we parse the challenge, resolve a credential for the host
(docker config → inline base64 or a credential helper), mint a token (an HTTP Basic GET to the
realm), and retry the original request with `Authorization: Bearer <token>`. The pure protocol
core is `Kue/OciAuth.lean`; this is its thin IO edge.

🔒 SECRET HYGIENE: a resolved credential and a minted token are passed only as curl argv for the
child process (argv is visible to the curl child, never echoed by us) and held in in-memory
`String`s. They are NEVER printed, logged, or written to disk. Errors report OUTCOMES (a `401`
that could not be satisfied, a helper non-zero exit) — never the secret. -/

/-- Run `curl` capturing its RESPONSE HEADERS as text (`-D -` dumped to stdout, body discarded via
    `-o /dev/null`). No `--fail-with-body`, so a `401`/`404` still returns its headers rather than
    a non-zero curl exit — we WANT the `WWW-Authenticate` header off a `401`. Follows redirects
    (`-L`) so the final response's headers are returned. `extraArgs` carries the `Accept` headers
    (a registry may 401 differently without them). Returns the header block text. -/
def curlHeaderProbe (url : String) (extraArgs : List String) : IO (Except String String) := do
  let args := ["-sSL", "-o", "/dev/null", "-D", "-"] ++ extraArgs ++ [url]
  let child ← IO.Process.spawn {
    cmd := "curl", args := args.toArray, stdout := .piped, stderr := .piped }
  let headerText ← child.stdout.readToEnd
  let exitCode ← child.wait
  let stderr ← child.stderr.readToEnd
  if exitCode == 0 then
    pure (.ok headerText)
  else
    pure (.error s!"curl header probe failed (exit {exitCode}) for {url}: {stderr.trimAscii.toString}")

/-- Extract the `WWW-Authenticate` header value from a raw HTTP header block (case-insensitive
    field name; a header may appear on any line; `-L` means the LAST response's block is what
    matters, so we take the LAST match). `none` if absent. -/
def wwwAuthenticateOf (headerText : String) : Option String := Id.run do
  let mut found : Option String := none
  for line in (headerText.splitOn "\n") do
    let l := line.trimAscii.toString
    match l.splitOn ":" with
    | name :: rest =>
        if name.trimAscii.toString.toLower == "www-authenticate" then
          found := some (String.intercalate ":" rest).trimAscii.toString
    | [] => pure ()
  return found

/-- Read `~/.docker/config.json`'s text, or `none` if absent/unreadable. Never logs contents. -/
def readDockerConfig : IO (Option String) := do
  match ← IO.getEnv "HOME" with
  | none => pure none
  | some home =>
      let path := s!"{home}/.docker/config.json"
      if ← System.FilePath.pathExists path then
        try pure (some (← IO.FS.readFile path))
        catch _ => pure none
      else
        pure none

/-- Resolve a `(user, pass)` credential for `host` from docker config: inline base64 → decode +
    split; helper → spawn `docker-credential-<helper> get` (feed `host` on stdin, parse
    `{Username,Secret}`); none → `none`. 🔒 The secret is never logged: a helper failure reports
    the helper's exit/stderr only (helpers print diagnostics, not secrets, to stderr), and a decode
    failure reports the failure mode, not the bytes. -/
def resolveCredential (host : String) : IO (Option (String × String)) := do
  match ← readDockerConfig with
  | none => pure none
  | some configText =>
      match OciAuth.credSourceFor configText host with
      | .none => pure none
      | .inline b64 =>
          match Kue.base64DecodeString b64 with
          | none => pure none   -- malformed config; treat as no credential (anon fallback)
          | some userPass => pure (OciAuth.splitUserPass userPass)
      | .helper bin =>
          let helperCmd := s!"docker-credential-{bin}"
          let child ← IO.Process.spawn {
            cmd := helperCmd, args := #["get"],
            stdin := .piped, stdout := .piped, stderr := .piped }
          let (stdin, child) ← child.takeStdin
          stdin.putStr host
          stdin.flush
          -- `takeStdin` moved the handle out; it is dropped here, closing stdin so the helper
          -- sees EOF and emits its response.
          let out ← child.stdout.readToEnd
          let exitCode ← child.wait
          if exitCode == 0 then
            pure (OciAuth.parseHelperResponse out)
          else
            -- Helper failed (e.g. no entry); fall through to anonymous-token attempt.
            pure none

/-- A session token cache: minted bearer tokens keyed by `(challengeKey)` so repeated blob GETs
    under one manifest reuse a single token. 🔒 IN-MEMORY ONLY — an `IO.Ref`, never persisted. -/
abbrev TokenCache := IO.Ref (List (String × String))

/-- A fresh, empty token cache. -/
def TokenCache.fresh : IO TokenCache := IO.mkRef []

/-- The cache key for a challenge: realm + service + scope uniquely identify a token's authority. -/
private def challengeKey (c : OciAuth.Challenge) : String :=
  s!"{c.realm}|{c.service.getD ""}|{c.scope.getD ""}"

/-- Mint a bearer token for `challenge` against `host`, caching it. Resolves a credential for the
    host (docker config/helper); if present, an HTTP Basic GET to the token realm; if absent, a
    tokenless GET (public registries like ghcr issue anonymous tokens for public repos). Parses the
    `token`/`access_token` field. 🔒 The credential is passed only via curl `-u user:pass` argv
    (consumed by the curl child); never printed. The token is returned in-memory and cached. -/
def mintToken (cache : TokenCache) (host : String) (challenge : OciAuth.Challenge) :
    IO (Except String String) := do
  let key := challengeKey challenge
  let cached := (← cache.get).lookup key
  match cached with
  | some t => pure (.ok t)
  | none =>
      let url := OciAuth.tokenUrl challenge
      let cred ← resolveCredential host
      let authArgs : List String :=
        match cred with
        | some (user, pass) => ["-u", s!"{user}:{pass}"]
        | none => []
      match ← runCurl (["-sSL", "--fail-with-body"] ++ authArgs ++ [url]) with
      | .error e => pure (.error s!"token mint failed for {host}: {e}")
      | .ok bytes =>
          match String.fromUTF8? bytes with
          | none => pure (.error s!"token response from {host} was not valid UTF-8")
          | some text =>
              match OciAuth.parseTokenResponse text with
              | none => pure (.error s!"token response from {host} had no token/access_token field")
              | some token => do
                  cache.modify (fun m => (key, token) :: m)
                  pure (.ok token)

/-- Auth-aware GET: try a bare GET; on a `401`, probe the response headers for a Bearer challenge,
    mint a token, and retry with `Authorization: Bearer <token>`. A `401` whose challenge can't be
    parsed or satisfied surfaces a clear typed error (never a hang, never a swallowed empty
    success). `extraArgs` (e.g. manifest `Accept` headers) is sent on every attempt. 🔒 The bearer
    header is built from the in-memory token and passed only as curl argv. -/
def authedGet (cache : TokenCache) (host : String) (url : String) (extraArgs : List String) :
    IO (Except String ByteArray) := do
  match ← curlGet url extraArgs with
  | .ok bytes => pure (.ok bytes)
  | .error firstErr =>
      -- A non-2xx (incl. 401) made curl exit non-zero. Probe headers to see if it's a Bearer
      -- challenge we can satisfy; if not, surface the original error.
      match ← curlHeaderProbe url extraArgs with
      | .error _ => pure (.error firstErr)
      | .ok headerText =>
          match wwwAuthenticateOf headerText with
          | none => pure (.error firstErr)
          | some headerVal =>
              match OciAuth.parseChallenge headerVal with
              | none => pure (.error s!"unsupported auth challenge from {host}: {headerVal}")
              | some challenge =>
                  match ← mintToken cache host challenge with
                  | .error e => pure (.error e)
                  | .ok token =>
                      let bearerArgs := ["-H", s!"Authorization: Bearer {token}"]
                      runCurl (Oci.curlBaseFlags ++ extraArgs ++ bearerArgs ++ [url])

/-- Decode response bytes as a UTF-8 `String` for the JSON parser. A manifest is always JSON
    text, so a valid one decodes cleanly; an invalid byte sequence surfaces as a parse error
    downstream rather than a crash (`String.fromUTF8?` is total). -/
private def bytesToText (bytes : ByteArray) : Except String String :=
  match String.fromUTF8? bytes with
  | some s => .ok s
  | none => .error "manifest response was not valid UTF-8 text"

/-- Fetch + parse + validate a module's OCI image manifest: `curl GET /v2/<repo>/manifests/<tag>`
    with the manifest `Accept` headers, then `Oci.parseManifest` and `validateModuleManifest`. The
    returned manifest is a confirmed 2-layer CUE module manifest. Goes through the auth-aware
    `authedGet`, so a `401`-gated registry (`ghcr.io`) is satisfied via the bearer-token flow; the
    `cache` is shared with the subsequent blob fetch so a token is minted once. -/
def fetchManifest (cache : TokenCache) (ref : Registry.OciRef) :
    IO (Except String Oci.OciManifest) := do
  match ← authedGet cache ref.host (Oci.manifestUrl ref)
      (Oci.acceptHeaderArgs Oci.manifestAcceptTypes) with
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

/-- Fetch a blob by descriptor (auth-aware) and verify its integrity against `descriptor.digest`:
    `curl GET /v2/<repo>/blobs/<digest>` through `authedGet` (reusing the cached token), then the
    SHA-256 digest check. A mismatch is rejected — the integrity gate the whole B3d-3 SHA-256 work
    exists to enforce. -/
def fetchBlob (cache : TokenCache) (ref : Registry.OciRef) (descriptor : Oci.Descriptor) :
    IO (Except String ByteArray) := do
  match ← authedGet cache ref.host (Oci.blobUrl ref descriptor.digest) [] with
  | .error e => pure (.error e)
  | .ok bytes =>
      let actual := Sha256.digestString bytes
      if actual == descriptor.digest then
        pure (.ok bytes)
      else
        pure (.error
          s!"blob digest mismatch for {descriptor.digest}: server bytes hash to {actual}")

/-- Compose the whole fetch: get + validate the manifest, select the `application/zip`
    module-content layer, fetch + digest-verify that blob, and return its bytes. A fresh per-fetch
    token cache is shared between the manifest and blob GETs so a `401`-gated registry mints one
    token for both. Stops at the verified zip bytes; extraction + cache-write are B3d-5. -/
def fetchModuleZip (ref : Registry.OciRef) : IO (Except String ByteArray) := do
  let cache ← TokenCache.fresh
  match ← fetchManifest cache ref with
  | .error e => pure (.error e)
  | .ok manifest =>
      match Oci.moduleZipDescriptor manifest with
      | .error e => pure (.error e)
      | .ok descriptor => fetchBlob cache ref descriptor

end OciFetch
end Kue
