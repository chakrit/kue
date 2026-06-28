import Kue.OciFetch
import Kue.Oci
import Kue.Registry
import Kue.Sha256

/-!
# Live ghcr.io bearer-auth proof (B3d-7, NETWORK + CREDS — NOT part of the offline gate)

Drives kue's OWN auth-aware fetch path (`OciFetch.fetchManifest` / `fetchBlob`) against the REAL
`ghcr.io` for `prodigy9.co/defs@v0.3.19` (CUE_REGISTRY=prodigy9.co=ghcr.io/prod9). Proves the
whole bearer-token flow end-to-end: bare GET → 401 → WWW-Authenticate parse → docker-cred resolve
→ token mint → authed retry → digest-verified blob.

🔒 SECRET HYGIENE: this asserts on OUTCOMES only — the manifest's 2-layer shape and the zip blob's
PUBLIC content address (digest + size). No token, PAT, or keychain secret is printed or persisted.

This is a NETWORK test, deliberately excluded from `scripts/check-fixtures.sh`. Run manually:
  lake build Kue.OciFetch && lake env lean --run scripts/check-ghcr-live.lean

The asserted blob digest + size are public content addresses, safe to commit.
-/

open Kue

/-- The public content address of the module-content zip layer for `prodigy9.co/defs@v0.3.19`. -/
def expectedZipDigest : String :=
  "sha256:b5de5cb543c043ec2fd41d96f47d76eb68ce5eb71bc240be8aac421192ffa2fb"
def expectedZipSize : Nat := 109225

def expect (name : String) (ok : Bool) : IO Bool := do
  if ok then IO.println s!"  ok: {name}"; pure true
  else IO.eprintln s!"  FAIL: {name}"; pure false

def main : IO UInt32 := do
  let cueRegistry := "prodigy9.co=ghcr.io/prod9"
  let resolution := Registry.resolveFromConfig cueRegistry "prodigy9.co/defs" "v0.3.19"
  match resolution with
  | .found ref => do
      IO.println s!"resolved → host={ref.host} repo={ref.repository} tag={ref.tag}"
      let cache ← OciFetch.TokenCache.fresh
      let mut allOk := true

      -- 1. Auth-aware manifest fetch: 401 → bearer flow → 200 → validated 2-layer manifest.
      match ← OciFetch.fetchManifest cache ref with
      | .error e =>
          allOk := (← expect s!"fetchManifest against ghcr.io (got error: {e})" false) && allOk
      | .ok manifest =>
          allOk := (← expect "fetchManifest returns a validated 2-layer module manifest"
            (manifest.layers.length == 2)) && allOk
          match Oci.moduleZipDescriptor manifest with
          | .error e =>
              allOk := (← expect s!"manifest has a unique zip layer (got: {e})" false) && allOk
          | .ok zipDesc =>
              allOk := (← expect "zip-layer descriptor digest matches the public content address"
                (zipDesc.digest == expectedZipDigest)) && allOk
              allOk := (← expect "zip-layer descriptor size matches"
                (zipDesc.size == expectedZipSize)) && allOk

              -- 2. Auth-aware blob fetch (reusing the cached token): DIGEST-VERIFIES.
              match ← OciFetch.fetchBlob cache ref zipDesc with
              | .error e =>
                  allOk := (← expect s!"fetchBlob digest-verifies the zip (got error: {e})" false)
                    && allOk
              | .ok bytes =>
                  allOk := (← expect "fetchBlob returns digest-verified zip bytes"
                    (Sha256.digestString bytes == expectedZipDigest)) && allOk
                  allOk := (← expect "fetched zip byte count matches the public size"
                    (bytes.size == expectedZipSize)) && allOk

      if allOk then IO.println "live ghcr.io bearer-auth proof ok"; pure 0
      else IO.eprintln "live ghcr.io bearer-auth proof FAILED"; pure 1
  | .noRegistry =>
      IO.eprintln "resolution produced no registry"; pure 1
  | .error e =>
      IO.eprintln s!"registry config error: {e}"; pure 1
