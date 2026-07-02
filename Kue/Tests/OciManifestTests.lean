import Kue.Oci

--
-- # OCI image-manifest parsing tests (B3d-2)
--
-- `native_decide`/`#guard` pins for the PURE, offline OCI manifest parser. Expected behavior is
-- taken from cue v0.16.1's own source — the authoritative OCI protocol reference (NOT the language
-- spec, so cue's code IS the spec here):
-- `mod/modregistry/client.go` — `unmarshalManifest`, `isModule`, `isModuleFile`, the 2-layer
-- invariant in `GetModuleWithManifest`, and the manifest construction in `putCheckedModule`
-- (`config.mediaType == "application/vnd.cue.module.v1+json"`; `layers[0]` zip / `layers[1]`
-- `application/vnd.cue.modulefile.v1`).
--

namespace Kue
namespace Oci

-- ## Fixtures: representative OCI image-manifest JSON (cue's `putCheckedModule` shape)
--
-- These mirror the exact JSON `json.Marshal` produces for cue's `ocispec.Manifest`: a scratch
-- `{}` config tagged `application/vnd.cue.module.v1+json`, then two layers — the module zip and
-- the `cue.mod/module.cue` file. Digests are real `sha256:<hex>` strings (preserved verbatim so
-- B3d-4 can compare `Sha256.digestString blob` against them).

-- A well-formed 2-layer CUE module manifest.
private def goodManifest : String :=
  "{\"schemaVersion\":2," ++
  "\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\"," ++
  "\"config\":{\"mediaType\":\"application/vnd.cue.module.v1+json\"," ++
    "\"digest\":\"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\"," ++
    "\"size\":2}," ++
  "\"layers\":[" ++
    "{\"mediaType\":\"application/zip\"," ++
      "\"digest\":\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"," ++
      "\"size\":1234}," ++
    "{\"mediaType\":\"application/vnd.cue.modulefile.v1\"," ++
      "\"digest\":\"sha256:2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae\"," ++
      "\"size\":57}]}"

-- config mediaType is NOT the CUE module artifact type → not a module.
private def notAModuleManifest : String :=
  "{\"schemaVersion\":2," ++
  "\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\"," ++
  "\"config\":{\"mediaType\":\"application/vnd.oci.image.config.v1+json\"," ++
    "\"digest\":\"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\"," ++
    "\"size\":2}," ++
  "\"layers\":[" ++
    "{\"mediaType\":\"application/zip\"," ++
      "\"digest\":\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"," ++
      "\"size\":1234}," ++
    "{\"mediaType\":\"application/vnd.cue.modulefile.v1\"," ++
      "\"digest\":\"sha256:2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae\"," ++
      "\"size\":57}]}"

-- No `application/zip` layer (both layers are the modulefile type).
private def noZipManifest : String :=
  "{\"schemaVersion\":2," ++
  "\"config\":{\"mediaType\":\"application/vnd.cue.module.v1+json\"," ++
    "\"digest\":\"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"size\":2}," ++
  "\"layers\":[" ++
    "{\"mediaType\":\"application/vnd.cue.modulefile.v1\"," ++
      "\"digest\":\"sha256:2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae\",\"size\":57}," ++
    "{\"mediaType\":\"application/vnd.cue.modulefile.v1\"," ++
      "\"digest\":\"sha256:2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae\",\"size\":57}]}"

-- Two `application/zip` layers — ambiguous, must not silently pick one.
private def twoZipManifest : String :=
  "{\"schemaVersion\":2," ++
  "\"config\":{\"mediaType\":\"application/vnd.cue.module.v1+json\"," ++
    "\"digest\":\"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"size\":2}," ++
  "\"layers\":[" ++
    "{\"mediaType\":\"application/zip\"," ++
      "\"digest\":\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\",\"size\":1234}," ++
    "{\"mediaType\":\"application/zip\"," ++
      "\"digest\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"size\":99}]}"

-- ## Well-formed manifest: parse + typed descriptors

-- A well-formed manifest parses, and the parsed config mediaType is the CUE module artifact type.
theorem parses_good_manifest :
    (((parseManifest goodManifest).map (·.config.mediaType)).toOption
      == some "application/vnd.cue.module.v1+json") = true := by
  native_decide

-- `isModuleManifest` accepts it.
theorem good_manifest_is_module :
    (((parseManifest goodManifest).map isModuleManifest).toOption == some true) = true := by
  native_decide

-- `validateModuleManifest` accepts it (round-trips the parsed manifest).
theorem validate_accepts_good :
    (match parseManifest goodManifest with
      | .ok m => (validateModuleManifest m).toOption.isSome
      | .error _ => false) = true := by
  native_decide

-- The zip layer (selected BY mediaType `application/zip`) yields the right digest + size.
theorem zip_descriptor_digest_size :
    (match parseManifest goodManifest with
      | .ok m => (moduleZipDescriptor m).toOption
          == some ⟨"application/zip",
                   "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 1234⟩
      | .error _ => false) = true := by
  native_decide

-- The modulefile layer yields the modulefile descriptor (for fetching module.cue without the zip).
theorem modulefile_descriptor_digest_size :
    (match parseManifest goodManifest with
      | .ok m => (moduleFileDescriptor m).toOption
          == some ⟨"application/vnd.cue.modulefile.v1",
                   "sha256:2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae", 57⟩
      | .error _ => false) = true := by
  native_decide

-- The zip digest string is preserved VERBATIM (so B3d-4 can `Sha256.digestString blob ==` it).
theorem zip_digest_preserved_verbatim :
    (match parseManifest goodManifest with
      | .ok m => ((moduleZipDescriptor m).map (·.digest)).toOption
          == some "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      | .error _ => false) = true := by
  native_decide

-- ## config mediaType ≠ module type → typed "not a module" error

-- It still PARSES (it's valid JSON / valid manifest shape) ...
theorem not_a_module_parses :
    (parseManifest notAModuleManifest).toOption.isSome = true := by
  native_decide

-- ... but `isModuleManifest` rejects it ...
theorem not_a_module_is_not_module :
    (((parseManifest notAModuleManifest).map isModuleManifest).toOption == some false) = true := by
  native_decide

-- ... and `validateModuleManifest` errors.
theorem validate_rejects_non_module :
    (match parseManifest notAModuleManifest with
      | .ok m => (match validateModuleManifest m with | .error _ => true | .ok _ => false)
      | .error _ => false) = true := by
  native_decide

-- ## zip layer absent / duplicated → typed error (never silently pick one)

-- No `application/zip` layer → `moduleZipDescriptor` errors.
theorem no_zip_errors :
    (match parseManifest noZipManifest with
      | .ok m => (match moduleZipDescriptor m with | .error _ => true | .ok _ => false)
      | .error _ => false) = true := by
  native_decide

-- Two `application/zip` layers → `moduleZipDescriptor` errors (ambiguous, not first-wins).
theorem two_zip_errors :
    (match parseManifest twoZipManifest with
      | .ok m => (match moduleZipDescriptor m with | .error _ => true | .ok _ => false)
      | .error _ => false) = true := by
  native_decide

-- ## Malformed JSON → the parse error surfaces cleanly (total, no crash)

theorem malformed_json_errors :
    (match parseManifest "{not valid json" with
      | .error _ => true | .ok _ => false) = true := by
  native_decide

-- Valid JSON but a layer descriptor is missing its `digest` field → typed error, no crash.
theorem missing_digest_field_errors :
    (match parseManifest
        "{\"config\":{\"mediaType\":\"application/vnd.cue.module.v1+json\",\"digest\":\"sha256:x\",\"size\":2},\"layers\":[{\"mediaType\":\"application/zip\",\"size\":1}]}" with
      | .error _ => true | .ok _ => false) = true := by
  native_decide

-- Valid JSON but `size` is a string, not a number → typed error.
theorem non_numeric_size_errors :
    (match parseManifest
        "{\"config\":{\"mediaType\":\"application/vnd.cue.module.v1+json\",\"digest\":\"sha256:x\",\"size\":2},\"layers\":[{\"mediaType\":\"application/zip\",\"digest\":\"sha256:y\",\"size\":\"big\"}]}" with
      | .error _ => true | .ok _ => false) = true := by
  native_decide

-- ## Descriptor parsing in isolation

#guard (parseDescriptor (Lean.Json.mkObj
  [("mediaType", "application/zip"), ("digest", "sha256:ab"), ("size", (7 : Nat))])).toOption
    == some ⟨"application/zip", "sha256:ab", 7⟩

-- A config object with no `mediaType` field is a parse error (not a silent empty string).
#guard (match parseDescriptor (Lean.Json.mkObj [("digest", "sha256:ab"), ("size", (7 : Nat))]) with
  | .error _ => true | .ok _ => false)

-- ## OCI Distribution endpoints + curl argv (B3d-4 PURE builders)
--
-- Expected shapes from `ocirequest/create.go` (`/v2/<repo>/manifests/<tag>`,
-- `/v2/<repo>/blobs/<digest>`) and `client.go` `doRequest` (the `Accept` header set). The
-- `OciRef` inputs mirror what `Registry.resolve` produces.

-- A secure registry GETs the manifest over HTTPS at `/v2/<repo>/manifests/<tag>`.
theorem manifest_url_secure :
    (manifestUrl ⟨"registry.cue.works", false, "fruit.com/apple", "v1.2.3"⟩
      == "https://registry.cue.works/v2/fruit.com/apple/manifests/v1.2.3") = true := by
  native_decide

-- An insecure (loopback/+insecure) registry uses HTTP.
theorem manifest_url_insecure :
    (manifestUrl ⟨"localhost:5000", true, "fruit.com/apple", "v1.2.3"⟩
      == "http://localhost:5000/v2/fruit.com/apple/manifests/v1.2.3") = true := by
  native_decide

-- A repository carrying a registry path-prefix is kept whole in the URL path.
theorem manifest_url_path_prefix :
    (manifestUrl ⟨"reg.example.com", false, "offset/example.com/blah", "v0.0.1"⟩
      == "https://reg.example.com/v2/offset/example.com/blah/manifests/v0.0.1") = true := by
  native_decide

-- An IPv6 host (brackets preserved verbatim by the resolver) flows through unchanged.
theorem manifest_url_ipv6_host :
    (manifestUrl ⟨"[::1]:5000", true, "x.com/m", "v1.0.0"⟩
      == "http://[::1]:5000/v2/x.com/m/manifests/v1.0.0") = true := by
  native_decide

-- The blob endpoint is `/v2/<repo>/blobs/<digest>`, the digest verbatim in the path.
theorem blob_url_secure :
    (blobUrl ⟨"registry.cue.works", false, "fruit.com/apple", "v1.2.3"⟩
        "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      == "https://registry.cue.works/v2/fruit.com/apple/blobs/"
         ++ "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") = true := by
  native_decide

theorem blob_url_insecure :
    (blobUrl ⟨"localhost:5000", true, "x.com/m", "v1.0.0"⟩ "sha256:abcd"
      == "http://localhost:5000/v2/x.com/m/blobs/sha256:abcd") = true := by
  native_decide

-- Scheme selection: insecure → http, secure → https.
#guard scheme ⟨"h", true, "r", "t"⟩ == "http"
#guard scheme ⟨"h", false, "r", "t"⟩ == "https"

-- The Accept media types match cue's `knownManifestMediaTypes`, in order (image manifest first).
theorem accept_types_match_cue :
    (manifestAcceptTypes
      == [ "application/vnd.oci.image.manifest.v1+json",
           "application/vnd.oci.image.index.v1+json",
           "application/vnd.oci.artifact.manifest.v1+json",
           "application/vnd.docker.distribution.manifest.v1+json",
           "application/vnd.docker.distribution.manifest.v2+json",
           "application/vnd.docker.distribution.manifest.list.v2+json",
           "*/*" ]) = true := by
  native_decide

-- Each Accept type becomes one `-H "Accept: <type>"` pair (mirroring Go's multi-valued header).
theorem accept_header_args_one_H_each :
    (acceptHeaderArgs ["application/vnd.oci.image.manifest.v1+json", "*/*"]
      == ["-H", "Accept: application/vnd.oci.image.manifest.v1+json", "-H", "Accept: */*"])
      = true := by
  native_decide

-- Base flags: silent-but-show-errors, follow-redirects, fail-with-body.
#guard curlBaseFlags == ["-sSL", "--fail-with-body"]

-- The full manifest GET argv: base flags, every Accept header, then the URL (URL last).
theorem manifest_curl_argv_exact :
    (manifestCurlArgs ⟨"registry.cue.works", false, "fruit.com/apple", "v1.2.3"⟩
      == ["-sSL", "--fail-with-body",
          "-H", "Accept: application/vnd.oci.image.manifest.v1+json",
          "-H", "Accept: application/vnd.oci.image.index.v1+json",
          "-H", "Accept: application/vnd.oci.artifact.manifest.v1+json",
          "-H", "Accept: application/vnd.docker.distribution.manifest.v1+json",
          "-H", "Accept: application/vnd.docker.distribution.manifest.v2+json",
          "-H", "Accept: application/vnd.docker.distribution.manifest.list.v2+json",
          "-H", "Accept: */*",
          "https://registry.cue.works/v2/fruit.com/apple/manifests/v1.2.3"]) = true := by
  native_decide

-- The full blob GET argv: base flags then the URL — no Accept negotiation (content-addressed).
theorem blob_curl_argv_exact :
    (blobCurlArgs ⟨"localhost:5000", true, "x.com/m", "v1.0.0"⟩ "sha256:abcd"
      == ["-sSL", "--fail-with-body", "http://localhost:5000/v2/x.com/m/blobs/sha256:abcd"])
      = true := by
  native_decide


-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @zip_digest_preserved_verbatim   -- Well-formed manifest: parse + typed descriptors
#check @validate_rejects_non_module     -- config mediaType ≠ module type → typed "not a mod...
#check @two_zip_errors                  -- zip layer absent / duplicated → typed error (neve...
#check @non_numeric_size_errors         -- Malformed JSON → the parse error surfaces cleanly...
#check @blob_curl_argv_exact            -- OCI Distribution endpoints + curl argv (B3d-4 PUR...

end Oci

end Kue
