import Kue.OciAuth
import Kue.Base64

/-!
# OCI Bearer-token auth tests (B3d-7, PURE, offline)

`native_decide`/`#guard` pins for the pure auth core in `Kue/OciAuth.lean` + the base64 DECODE
added to `Kue/Base64.lean`. All inputs are SYNTHETIC — no real token, PAT, or keychain secret
appears here (a leaked secret is a slice failure). Expected behavior is taken from the Docker
Registry v2 token spec (the OCI distribution spec references it) and docker's `config.json`
credential-resolution precedence.

Ground truth for the base64 vectors: the system `base64` tool (an independent implementation), so
these are a genuine cross-check of `base64Decode`, not a self-consistency test.
-/

namespace Kue

/-! ## base64 decode (the inline `auth` field is base64 of `user:pass`) -/

-- Round-trips against the system `base64` tool's output (independent ground truth).
#guard base64DecodeString "dXNlcjpwYXNz" == some "user:pass"
#guard base64DecodeString "aGVsbG8=" == some "hello"           -- one `=` pad (5 bytes)
#guard base64DecodeString "TQ==" == some "M"                   -- two `=` pad (1 byte)
#guard base64DecodeString "TWE=" == some "Ma"                  -- one `=` pad (2 bytes)
#guard base64DecodeString "Zm9vOmJhcjpiYXo=" == some "foo:bar:baz"
#guard base64DecodeString "YWxpY2U6cEBzczp3b3Jk" == some "alice:p@ss:word"

-- Encode∘decode round-trips for representative bytes (synthetic).
theorem base64_roundtrips_user_pass :
    (base64Decode (base64Encode "user:pass".toUTF8.toList)
      == some "user:pass".toUTF8.toList) = true := by native_decide

theorem base64_roundtrips_empty_password :
    (base64DecodeString (base64Encode "u:".toUTF8.toList) == some "u:") = true := by native_decide

-- Malformed base64 is rejected (total, no panic): bad length, non-alphabet char, lone char.
#guard base64Decode "abc" == none          -- length not a multiple of 4
#guard base64Decode "ab*d" == none          -- non-alphabet char
#guard base64Decode "" == none              -- empty
#guard base64Decode "====" == none          -- all padding, no data

/-! ## WWW-Authenticate challenge parsing -/

namespace OciAuth

-- The canonical ghcr challenge (param order realm/service/scope, all double-quoted).
private def ghcrChallenge : String :=
  "Bearer realm=\"https://ghcr.io/token\",service=\"ghcr.io\"," ++
  "scope=\"repository:prod9/prodigy9.co/defs:pull\""

#guard parseChallenge ghcrChallenge == some
  { realm := "https://ghcr.io/token", service := some "ghcr.io",
    scope := some "repository:prod9/prodigy9.co/defs:pull" }

-- Case-insensitive scheme (`bearer`).
#guard parseChallenge "bearer realm=\"https://r/token\",service=\"r\"" == some
  { realm := "https://r/token", service := some "r", scope := none }

-- Param order is not significant (scope first).
#guard parseChallenge "Bearer scope=\"s\",realm=\"https://r/t\",service=\"svc\"" == some
  { realm := "https://r/t", service := some "svc", scope := some "s" }

-- Unquoted values are tolerated.
#guard parseChallenge "Bearer realm=https://r/t,service=svc" == some
  { realm := "https://r/t", service := some "svc", scope := none }

-- Surrounding whitespace + extra unknown params (`error=…`) are tolerated/ignored.
#guard parseChallenge "  Bearer  realm=\"https://r/t\" , error=\"invalid_token\" , service=\"s\" "
  == some { realm := "https://r/t", service := some "s", scope := none }

-- A scope containing a comma-joined access list (commas INSIDE quotes are not split points).
#guard parseChallenge
  "Bearer realm=\"https://r/t\",service=\"s\",scope=\"repository:a:pull,repository:b:pull\""
  == some { realm := "https://r/t", service := some "s",
            scope := some "repository:a:pull,repository:b:pull" }

-- A challenge with no scope/service (whole-registry/anon token) parses with just the realm.
#guard parseChallenge "Bearer realm=\"https://r/token\"" == some
  { realm := "https://r/token", service := none, scope := none }

-- A non-Bearer scheme (`Basic`) is rejected.
#guard parseChallenge "Basic realm=\"https://r/t\"" == none

-- A Bearer challenge missing the realm is unusable → rejected.
#guard parseChallenge "Bearer service=\"s\",scope=\"x\"" == none

/-! ## token-request URL construction -/

private def ghcrParsedChallenge : Challenge :=
  { realm := "https://ghcr.io/token", service := some "ghcr.io",
    scope := some "repository:prod9/prodigy9.co/defs:pull" }

#guard tokenUrl ghcrParsedChallenge
  == "https://ghcr.io/token?service=ghcr.io&scope=repository%3Aprod9%2Fprodigy9.co%2Fdefs%3Apull"

-- No service/scope ⇒ the bare realm.
#guard tokenUrl ({ realm := "https://r/token", service := none, scope := none }) == "https://r/token"

-- A comma in a scope is percent-encoded (`%2C`); `:` → `%3A`, `/` → `%2F`.
#guard tokenUrl ({ realm := "https://r/t", service := some "s", scope := some "a:pull,b:pull" })
  == "https://r/t?service=s&scope=a%3Apull%2Cb%3Apull"

-- queryEncode keeps the RFC 3986 unreserved set verbatim.
#guard queryEncode "Az0-_.~" == "Az0-_.~"
#guard queryEncode "a b" == "a%20b"

/-! ## token-response JSON parsing (`token` vs `access_token`) -/

#guard parseTokenResponse "{\"token\":\"abc123\"}" == some "abc123"
#guard parseTokenResponse "{\"access_token\":\"xyz789\"}" == some "xyz789"
-- `token` wins when both are present (spec preference).
#guard parseTokenResponse "{\"access_token\":\"old\",\"token\":\"new\"}" == some "new"
-- Extra fields (`expires_in`, `issued_at`) are ignored.
#guard parseTokenResponse "{\"token\":\"t\",\"expires_in\":300,\"issued_at\":\"now\"}" == some "t"
-- Neither field / empty token / malformed JSON ⇒ none.
#guard parseTokenResponse "{\"foo\":\"bar\"}" == none
#guard parseTokenResponse "{\"token\":\"\"}" == none
#guard parseTokenResponse "not json" == none

/-! ## docker config.json → CredSource -/

-- Inline `auths.<host>.auth` (synthetic base64).
private def inlineConfig : String :=
  "{\"auths\":{\"ghcr.io\":{\"auth\":\"dXNlcjpwYXNz\"}}}"
#guard credSourceFor inlineConfig "ghcr.io" == .inline "dXNlcjpwYXNz"

-- A global `credsStore` over a host that has an `auths` entry → helper.
private def storeConfig : String :=
  "{\"auths\":{\"ghcr.io\":{}},\"credsStore\":\"osxkeychain\"}"
#guard credSourceFor storeConfig "ghcr.io" == .helper "osxkeychain"

-- A per-host `credHelpers` entry WINS over a global store.
private def perHostConfig : String :=
  "{\"auths\":{\"ghcr.io\":{}},\"credsStore\":\"osxkeychain\"," ++
  "\"credHelpers\":{\"ghcr.io\":\"ghcr-login\"}}"
#guard credSourceFor perHostConfig "ghcr.io" == .helper "ghcr-login"

-- A host absent from the config → none (the IO edge then tries an anonymous token).
#guard credSourceFor inlineConfig "docker.io" == .none
#guard credSourceFor "{}" "ghcr.io" == .none

-- A `credsStore` but NO `auths` entry for the host → none (docker only consults the store for
-- listed hosts).
#guard credSourceFor "{\"credsStore\":\"osxkeychain\"}" "ghcr.io" == .none

-- Malformed config text → none (total, no panic).
#guard credSourceFor "not json" "ghcr.io" == .none

/-! ## inline user:pass + credential-helper response parsing -/

#guard splitUserPass "user:pass" == some ("user", "pass")
-- A password containing colons splits only at the FIRST colon.
#guard splitUserPass "alice:p@ss:word" == some ("alice", "p@ss:word")
-- No colon ⇒ none.
#guard splitUserPass "nouserpass" == none

-- A docker credential-helper `get` response → (Username, Secret). SYNTHETIC.
#guard parseHelperResponse "{\"Username\":\"alice\",\"Secret\":\"s3cr3t\"}"
  == some ("alice", "s3cr3t")
-- The `<token>` identity-token convention is returned faithfully (IO edge interprets it).
#guard parseHelperResponse "{\"Username\":\"<token>\",\"Secret\":\"refreshtok\"}"
  == some ("<token>", "refreshtok")
-- Missing a field / malformed ⇒ none.
#guard parseHelperResponse "{\"Username\":\"alice\"}" == none
#guard parseHelperResponse "garbage" == none

end OciAuth
end Kue
