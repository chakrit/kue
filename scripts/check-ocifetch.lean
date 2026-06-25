import Kue.OciFetch
import Kue.Oci
import Kue.Sha256

/-!
# OCI-fetch curl seam check (B3d-4, offline via `file://`)

Drives the impure `Kue.OciFetch` edge against `file://` URLs over the committed fixtures in
`testdata/ocifetch/` — proving the WHOLE curl composition (subprocess spawn, raw-byte capture,
SHA-256 digest verification) works against `curl` WITHOUT a network or a real registry, and that
the digest-integrity gate REJECTS a tampered blob.

Run by `scripts/check-fixtures.sh` (so the loop's verify gate covers it):
  lake env lean --run scripts/check-ocifetch.lean <abs-path-to-testdata/ocifetch>

No network: every URL is `file://`. No out-of-tree writes: the script only READS the fixtures.
Exit 0 ⇒ all assertions pass; non-zero ⇒ a printed failure.
-/

open Kue

/-- The committed real sha256 of `module.zip` (the `application/zip` blob fixture). Recompute with
    `shasum -a 256 testdata/ocifetch/module.zip` if the fixture changes. -/
def zipDigest : String :=
  "sha256:ce6d98028c40a64f6efbb66c168f23996d035d1f254ab9ab0ba65e6c4bf3d67f"

/-- A WRONG digest for the same `module.zip` bytes — proves the integrity gate rejects a
    mismatch (a corrupt/tampered/wrong-content blob). -/
def wrongDigest : String :=
  "sha256:0000000000000000000000000000000000000000000000000000000000000000"

def fileUrl (dir : String) (name : String) : String :=
  s!"file://{dir}/{name}"

/-- Assert + report one named check; returns whether it passed. -/
def expect (name : String) (ok : Bool) : IO Bool := do
  if ok then
    IO.println s!"  ok: {name}"
    pure true
  else
    IO.eprintln s!"  FAIL: {name}"
    pure false

def main (args : List String) : IO UInt32 := do
  match args with
  | [dir] => do
      let mut allOk := true

      -- 1. curlGet over file:// returns the blob bytes (the subprocess seam works, no network).
      let zipResult ← OciFetch.curlGet (fileUrl dir "module.zip") []
      let zipBytes := zipResult.toOption.getD ByteArray.empty
      allOk := (← expect "curlGet reads a file:// blob"
        (zipResult.toOption.isSome && zipBytes.size > 0)) && allOk

      -- The bytes are byte-faithful: their freshly-computed digest equals the fixture digest
      -- (proves raw-byte capture did NOT mangle the content via UTF-8 decoding).
      allOk := (← expect "captured bytes hash to the fixture digest"
        (Sha256.digestString zipBytes == zipDigest)) && allOk

      -- 2. curlGetVerified (the fetchBlob integrity path) PASSES on the correct digest.
      let goodVerify ← OciFetch.curlGetVerified (fileUrl dir "module.zip") zipDigest
      allOk := (← expect "digest-verified fetch PASSES on the correct digest"
        goodVerify.toOption.isSome) && allOk

      -- 3. curlGetVerified REJECTS a wrong digest (the integrity gate — the whole point).
      let badVerify ← OciFetch.curlGetVerified (fileUrl dir "module.zip") wrongDigest
      allOk := (← expect "digest-verified fetch REJECTS a mismatched digest"
        (match badVerify with | .error _ => true | .ok _ => false)) && allOk

      -- 4. curlGet on a missing file:// errors (curl exits non-zero → Except.error), never a
      --    silent empty success.
      let missing ← OciFetch.curlGet (fileUrl dir "does-not-exist.zip") []
      allOk := (← expect "curlGet on a missing path errors (no silent empty success)"
        (match missing with | .error _ => true | .ok _ => false)) && allOk

      -- 5. The fixture manifest parses + validates as a 2-layer CUE module manifest, and its
      --    zip-layer descriptor digest matches the real module.zip digest — so a real
      --    fetchManifest → moduleZipDescriptor → fetchBlob chain would digest-verify in B3d-5.
      let manifestResult ← OciFetch.curlGet (fileUrl dir "manifest.json")
        (Oci.acceptHeaderArgs Oci.manifestAcceptTypes)
      let manifestOk : Bool :=
        match manifestResult with
        | .error _ => false
        | .ok bytes =>
            match String.fromUTF8? bytes with
            | none => false
            | some text =>
                match Oci.parseModuleManifest text with
                | .error _ => false
                | .ok m =>
                    match Oci.moduleZipDescriptor m with
                    | .error _ => false
                    | .ok d => d.digest == zipDigest
      allOk := (← expect "fixture manifest validates + its zip digest matches module.zip"
        manifestOk) && allOk

      if allOk then
        IO.println "ocifetch file:// seam ok"
        pure 0
      else
        IO.eprintln "ocifetch file:// seam FAILED"
        pure 1
  | _ =>
      IO.eprintln "usage: lake env lean --run scripts/check-ocifetch.lean <testdata/ocifetch dir>"
      pure 1
