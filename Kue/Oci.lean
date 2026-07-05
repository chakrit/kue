import Lean.Data.Json
import Kue.Registry

/-!
# OCI image-manifest parsing (B3d-2, PURE, offline)

Parse a CUE module's OCI image manifest (`application/vnd.oci.image.manifest.v1+json`) into
typed descriptors. NO network, NO `curl`, NO IO — a total `String → Except String OciManifest`
over Lean's standard `Lean.Json` parser. The impure `curl` GET that produces the manifest bytes
is B3d-4's edge; this module is its pure, theorem-pinned core.

Authoritative protocol source (cue v0.16.1, OCI tooling — NOT the language spec, so cue's own
code IS the spec here): `mod/modregistry/client.go`.
- `unmarshalManifest` — JSON-decodes the manifest into `ociregistry.Manifest`.
- `isModule` — a manifest is a CUE module iff `config.mediaType == "application/vnd.cue.module.v1+json"`.
- `isModuleFile` — the modulefile layer iff its mediaType (or artifactType) is
  `"application/vnd.cue.modulefile.v1"`.
- `GetModuleWithManifest` — invariants: exactly TWO layers, `layers[1]` is the module file.
- `putCheckedModule` — the construction side: `layers[0]` is the module zip (`application/zip`),
  `layers[1]` is `cue.mod/module.cue` (`application/vnd.cue.modulefile.v1`).

## Layer selection rule

cue keys the zip off `layers[0]` and the modulefile off `isModuleFile(layers[1])` by INDEX.
We select both BY mediaType and require EXACTLY ONE match — strictly stronger than cue's index
check (it rejects a malformed manifest that cue's blind indexing would mis-read) while still
conforming to every well-formed manifest cue produces. `moduleZipDescriptor` errors if the
`application/zip` layer is absent or duplicated; never silently picks the first.

## A `Json.lean` note

`Kue/Json.lean` only SERIALIZES (`ManifestValue → String`); it has no parser. Rather than
hand-roll a second JSON parser, we reuse Lean's standard, total `Lean.Json.parse`
(`Lean.Data.Json`, shipped with the toolchain — no new Lake dependency). This is exactly the
"reuse, don't reinvent" intent of the slice: one JSON parser, and it's the stdlib's.
-/

namespace Kue
namespace Oci

/-! ## Media-type constants (cue's `client.go` consts) -/

/-- `moduleArtifactType` — the config mediaType that marks a manifest as a CUE module. -/
def moduleArtifactType : String := "application/vnd.cue.module.v1+json"

/-- `moduleFileMediaType` — the layer mediaType of the `cue.mod/module.cue` blob. -/
def moduleFileMediaType : String := "application/vnd.cue.modulefile.v1"

/-- The mediaType of the module-content zip layer (`putCheckedModule` `layers[0]`). -/
def moduleZipMediaType : String := "application/zip"

/-! ## Typed descriptors (illegal-states-unrepresentable) -/

/-- An OCI content descriptor: the `mediaType`, the `sha256:<hex>` content `digest` (preserved
    VERBATIM so a later slice can compare a freshly computed digest against it), and the blob
    `size` in bytes. A descriptor always carries all three — a manifest that omits any of them
    is a parse error, never a descriptor with an empty/zero placeholder. -/
structure Descriptor where
  mediaType : String
  digest : String
  size : Nat
deriving Repr, BEq, DecidableEq

/-- A parsed OCI image manifest: its `config` descriptor and ordered `layers`. (`schemaVersion`
    and the manifest-level `mediaType` are not load-bearing for descriptor extraction, so they
    are not retained; cue itself never re-checks `schemaVersion`.) -/
structure OciManifest where
  config : Descriptor
  layers : List Descriptor
deriving Repr, BEq, DecidableEq

/-! ## Parsing (over `Lean.Json`) -/

/-- Parse one OCI descriptor object: require `mediaType` (String), `digest` (String), and `size`
    (a JSON number, read as a `Nat` — OCI sizes are non-negative). A missing or wrong-typed field
    surfaces `Lean.Json`'s own typed error (`property not found: …` / `String expected` /
    `Natural number expected`); total, never panics. -/
def parseDescriptor (j : Lean.Json) : Except String Descriptor := do
  let mediaType ← (← j.getObjVal? "mediaType").getStr?
  let digest ← (← j.getObjVal? "digest").getStr?
  let size ← (← j.getObjVal? "size").getNat?
  .ok { mediaType, digest, size }

/-- Parse a list of descriptors from a JSON array, preserving order. Any element that is not a
    well-formed descriptor object fails the whole parse. -/
def parseDescriptors (arr : Array Lean.Json) : Except String (List Descriptor) :=
  arr.toList.foldr
    (fun j acc => do
      let rest ← acc
      let d ← parseDescriptor j
      .ok (d :: rest))
    (.ok [])

/-- Parse an OCI image manifest from its JSON text. Reuses `Lean.Json.parse`; a malformed JSON
    document surfaces that parser's error cleanly. On success, extracts the `config` descriptor
    and the `layers` array. Does NOT validate the CUE-module invariants — see
    `validateModuleManifest` / `isModuleManifest`. -/
def parseManifest (text : String) : Except String OciManifest := do
  let json ← Lean.Json.parse text
  let config ← parseDescriptor (← json.getObjVal? "config")
  let layersJson ← (← json.getObjVal? "layers").getArr?
  let layers ← parseDescriptors layersJson
  .ok { config, layers }

/-! ## CUE-module validation (`isModule` / `isModuleFile` / 2-layer invariant) -/

/-- `isModule`: a manifest is a CUE module iff its config mediaType is the module artifact type. -/
def isModuleManifest (m : OciManifest) : Bool :=
  m.config.mediaType == moduleArtifactType

/-- Whether `d` is the `cue.mod/module.cue` modulefile descriptor (`isModuleFile`). -/
def isModuleFileDescriptor (d : Descriptor) : Bool :=
  d.mediaType == moduleFileMediaType

/-- Select the single layer whose mediaType is `wanted`. Errors with `absent`/`duplicate` text if
    there is not exactly one — so an ambiguous manifest is rejected, never resolved first-wins. -/
def selectUniqueLayer (m : OciManifest) (wanted absent duplicate : String) :
    Except String Descriptor :=
  match m.layers.filter (fun d => d.mediaType == wanted) with
  | [d] => .ok d
  | [] => .error absent
  | _ => .error duplicate

/-- The module-content zip descriptor: the unique `application/zip` layer. B3d-4 GETs this blob
    and verifies `Sha256.digestString blob == d.digest`. -/
def moduleZipDescriptor (m : OciManifest) : Except String Descriptor :=
  selectUniqueLayer m moduleZipMediaType
    "module manifest has no application/zip (module content) layer"
    "module manifest has more than one application/zip layer"

/-- The `cue.mod/module.cue` descriptor: the unique `application/vnd.cue.modulefile.v1` layer.
    Used later to fetch just module.cue (for MVS dependency resolution) without the full zip. -/
def moduleFileDescriptor (m : OciManifest) : Except String Descriptor :=
  selectUniqueLayer m moduleFileMediaType
    "module manifest has no module-file (application/vnd.cue.modulefile.v1) layer"
    "module manifest has more than one module-file layer"

/-- Validate the CUE-module invariants `GetModuleWithManifest` enforces, conforming to cue's
    error phrasing: config mediaType is the module artifact type (`isModule`); exactly two
    layers; both the zip and the module-file layer are present and unique (which subsumes cue's
    `isModuleFile(layers[1])` check by mediaType). Returns the manifest unchanged on success. -/
def validateModuleManifest (m : OciManifest) : Except String OciManifest := do
  if !isModuleManifest m then
    .error s!"does not resolve to a module manifest (config media type is {m.config.mediaType})"
  else if m.layers.length != 2 then
    .error s!"module manifest should refer to exactly two blobs, but got {m.layers.length}"
  else
    let _ ← moduleZipDescriptor m
    let _ ← moduleFileDescriptor m
    .ok m

/-- Parse and validate in one step: `parseManifest` then `validateModuleManifest`. -/
def parseModuleManifest (text : String) : Except String OciManifest := do
  validateModuleManifest (← parseManifest text)

/-! ## OCI Distribution endpoints + curl argv (B3d-4, PURE)

    The HTTP request shapes cue's OCI client uses, built purely so the impure edge
    (`Kue/OciFetch.lean`) only runs `curl` against them. Authoritative protocol source
    (cue v0.16.1 — tooling, so the Go code IS the spec):
    - `cuelabs.dev/go/oci/ociregistry/ociclient/internal/ocirequest/create.go`: the URL paths
      `GET /v2/<repo>/manifests/<tag>` and `GET /v2/<repo>/blobs/<digest>`.
    - `ociclient/client.go` `doRequest`: a manifest GET sends a multi-valued `Accept` header
      with `knownManifestMediaTypes` (image manifest + index, the deprecated artifact type, the
      docker manifest types, and `*/*`).
    The scheme is `http` for an `insecure` (loopback/`+insecure`) registry, `https` otherwise. -/

/-- The request scheme for an `OciRef`: `http` when `insecure`, else `https`. -/
def scheme (ref : Registry.OciRef) : String :=
  if ref.insecure then "http" else "https"

/-- `GET /v2/<repository>/manifests/<tag>` — the manifest endpoint for a resolved module
    (`ocirequest` `ReqManifestGet`). The tag is the plain version (`v0.3.19`). -/
def manifestUrl (ref : Registry.OciRef) : String :=
  s!"{scheme ref}://{ref.host}/v2/{ref.repository}/manifests/{ref.tag}"

/-- `GET /v2/<repository>/blobs/<digest>` — the blob (zip / module-file) endpoint. `digest` is
    the descriptor's verbatim `sha256:<hex>` string (a content-addressed GET). -/
def blobUrl (ref : Registry.OciRef) (digest : String) : String :=
  s!"{scheme ref}://{ref.host}/v2/{ref.repository}/blobs/{digest}"

/-- `GET /v2/<repository>/tags/list` — the tag-enumeration endpoint (`ocirequest` `ReqTagsList`).
    The response is `{"name": …, "tags": […]}`; `ref.tag` is irrelevant to this URL (only host +
    repository matter), so any resolved ref for the module path suffices. -/
def tagsListUrl (ref : Registry.OciRef) : String :=
  s!"{scheme ref}://{ref.host}/v2/{ref.repository}/tags/list"

/-- The `Accept` media types cue's client sends on a manifest GET, in order
    (`client.go` `knownManifestMediaTypes`). Some registries withhold the manifest body without
    an explicit `Accept`, so all known kinds are offered (and `*/*` as a fallback). -/
def manifestAcceptTypes : List String :=
  [ "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.oci.artifact.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "*/*" ]

/-! ### curl argv

    Flags chosen by philosophy — fail loudly, never silently mis-succeed:
    - `-s` silent (no progress meter) + `-S` show-errors (a `-s`-suppressed error still prints to
      stderr) — quiet success, loud failure.
    - `-L` follow redirects: registries 307 a blob GET to backing object storage; without `-L`
      curl would return the redirect body, not the blob.
    - `--fail-with-body`: a non-2xx HTTP status makes curl exit non-zero (so the IO runner sees
      the failure) WHILE still writing the error body to stdout (`--fail` alone discards it), so a
      registry's JSON error is preserved for the diagnostic. An HTTP 404/401 must be a Lean
      `Except.error`, never a successful empty fetch.

    Output goes to stdout (`IO.Process.output` captures it as bytes); no `-o <file>`, so nothing
    is written to disk by the fetch itself (cache-write is B3d-5). -/

/-- The base curl flags every GET shares (silent-but-show-errors, follow-redirects, fail-loud). -/
def curlBaseFlags : List String :=
  ["-sSL", "--fail-with-body"]

/-- The `-H "Accept: <type>"` argv pairs for a manifest GET — one `-H` per media type, mirroring
    Go's multi-valued `Accept` header (`req.Header["Accept"] = knownManifestMediaTypes`). -/
def acceptHeaderArgs (types : List String) : List String :=
  types.flatMap (fun t => ["-H", s!"Accept: {t}"])

/-- Full curl argv for a manifest GET: base flags, the `Accept` headers, then the URL. -/
def manifestCurlArgs (ref : Registry.OciRef) : List String :=
  curlBaseFlags ++ acceptHeaderArgs manifestAcceptTypes ++ [manifestUrl ref]

/-- Full curl argv for a blob GET: base flags, then the URL. A blob is content-addressed, so no
    `Accept` negotiation — the digest fixes the bytes. -/
def blobCurlArgs (ref : Registry.OciRef) (digest : String) : List String :=
  curlBaseFlags ++ [blobUrl ref digest]

end Oci
end Kue
