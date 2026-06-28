import Lean.Data.Json
import Kue.Base64

/-!
# OCI Bearer-token auth (B3d-7, PURE core)

The Docker/OCI registry token flow, decomposed into a pure, `native_decide`-pinned core plus a
thin IO edge (`Kue/OciFetch.lean`). A bare GET against a real registry (`ghcr.io`,
`registry-1.docker.io`) returns `401 Unauthorized` with a `WWW-Authenticate: Bearer …` header that
names a token realm, a service, and a scope. The client mints a token (an HTTP Basic GET to the
realm with `service`+`scope` query params), then retries the original request with
`Authorization: Bearer <token>`.

Authoritative protocol source (the Docker Registry v2 token spec, which the OCI distribution spec
references; cue's client uses `cuelabs.dev/go/oci/ociregistry/ociauth`):
- The challenge header grammar: `Bearer realm="…",service="…",scope="…"` — params are
  comma-separated `key=value`, values optionally double-quoted, order is not significant.
- The token request: `GET <realm>?service=<service>&scope=<scope>` with HTTP Basic auth (when a
  credential exists) → a JSON body with a `token` (or, per the spec's compatibility note,
  `access_token`) field.

Everything here is PURE: header parsing, token-URL construction, token-JSON parsing, and the
docker `config.json` → credential-source decode. The IO (read the config file, run the
credential helper, run curl) lives in `Kue/OciFetch.lean`. No secret ever appears in this module —
the only credential-shaped value it handles is the SYNTHETIC base64 in `CredSource.inline`, parsed
to `(user, pass)` by the IO edge, never logged.
-/

namespace Kue
namespace OciAuth

/-! ## WWW-Authenticate challenge parsing -/

/-- A parsed `WWW-Authenticate: Bearer …` challenge: the token `realm` (an absolute URL), the
    `service` audience, and the requested `scope`. `service`/`scope` may be absent on some
    registries (anonymous/whole-registry tokens), so they are `Option`. `realm` is required — a
    Bearer challenge without one is unusable, so parsing fails. -/
structure Challenge where
  realm : String
  service : Option String
  scope : Option String
deriving Repr, BEq, DecidableEq

/-- Strip a single matched pair of surrounding double quotes, plus surrounding ASCII whitespace.
    `  "abc"  ` → `abc`; an unquoted token is returned trimmed. -/
private def unquote (s : String) : String :=
  let t := s.trimAscii.toString
  if t.length ≥ 2 && t.startsWith "\"" && t.endsWith "\"" then
    ((t.drop 1).dropEnd 1).toString
  else
    t

/-- Split a `key=value` parameter at the FIRST `=` (a quoted value may itself contain `=`, e.g. a
    scope with a base64 token, so only the first split point is structural). -/
private def splitParam (s : String) : Option (String × String) :=
  match s.splitOn "=" with
  | [] => none
  | [_] => none
  | key :: rest => some (key.trimAscii.toString.toLower, unquote (String.intercalate "=" rest))

/-- Split a challenge's parameter list on commas, but NOT on commas inside double quotes (a scope
    value may contain a comma-joined access list, e.g.
    `scope="repository:a:pull,repository:b:pull"`). A tiny quote-aware splitter — total, no regex. -/
private def splitParams (s : String) : List String := Id.run do
  let mut parts : Array String := #[]
  let mut cur : String := ""
  let mut inQuotes := false
  for c in s.toList do
    if c == '"' then
      inQuotes := !inQuotes
      cur := cur.push c
    else if c == ',' && !inQuotes then
      parts := parts.push cur
      cur := ""
    else
      cur := cur.push c
  parts := parts.push cur
  return parts.toList

/-- Parse a `WWW-Authenticate` header value into a `Challenge`. Tolerates: case-insensitive scheme
    (`Bearer`/`bearer`), arbitrary param order, optional double-quoting, surrounding whitespace,
    and unknown extra params (`error=…` etc. are ignored). Requires the `Bearer` scheme and a
    `realm`. Returns `none` for a non-Bearer scheme (e.g. `Basic`) or a missing realm. -/
def parseChallenge (header : String) : Option Challenge := Id.run do
  let h := header.trimAscii.toString
  -- Scheme is the first whitespace-delimited token; the rest is the param list.
  let afterScheme :=
    match (h.splitOn " ").filter (· ≠ "") with
    | scheme :: _ =>
        if scheme.toLower == "bearer" then
          some ((h.drop scheme.length).trimAscii.toString)
        else
          none
    | [] => none
  match afterScheme with
  | none => return none
  | some paramStr =>
      let mut realm : Option String := none
      let mut service : Option String := none
      let mut scope : Option String := none
      for part in splitParams paramStr do
        let p := part.trimAscii.toString
        if p ≠ "" then
          match splitParam p with
          | some (key, val) =>
              if key == "realm" then realm := some val
              else if key == "service" then service := some val
              else if key == "scope" then scope := some val
              else pure ()
          | none => pure ()
      match realm with
      | some r => return some { realm := r, service, scope }
      | none => return none

/-! ## Token-request URL construction -/

/-- Percent-encode a query-parameter VALUE per RFC 3986 — keep the unreserved set
    `A–Z a–z 0–9 - _ . ~`, percent-encode everything else (so `:`, `/`, `,`, space in a scope
    survive transport). Total. -/
def queryEncode (s : String) : String := Id.run do
  let hex : Array Char := "0123456789ABCDEF".toList.toArray
  let mut out : String := ""
  for c in s.toList do
    let isUnreserved :=
      ('A' ≤ c && c ≤ 'Z') || ('a' ≤ c && c ≤ 'z') || ('0' ≤ c && c ≤ '9')
        || c == '-' || c == '_' || c == '.' || c == '~'
    if isUnreserved then
      out := out.push c
    else
      -- Encode each UTF-8 byte of the character.
      for b in (String.toUTF8 (String.singleton c)).toList do
        let n := b.toNat
        out := out.push '%'
        out := out.push hex[n >>> 4]!
        out := out.push hex[n &&& 0x0f]!
  return out

/-- Build the token-request URL from a `Challenge`: `<realm>?service=…&scope=…`, query-encoding
    each value and including only the params the challenge supplied. A realm with no service/scope
    yields the bare realm (some registries issue a whole-registry token that way). -/
def tokenUrl (c : Challenge) : String := Id.run do
  let mut params : Array String := #[]
  match c.service with
  | some s => params := params.push s!"service={queryEncode s}"
  | none => pure ()
  match c.scope with
  | some s => params := params.push s!"scope={queryEncode s}"
  | none => pure ()
  if params.isEmpty then
    return c.realm
  else
    return s!"{c.realm}?{String.intercalate "&" params.toList}"

/-! ## Token-response JSON parsing -/

/-- Extract the bearer token from a registry's token-endpoint JSON response. Accepts both the OCI
    `token` field and the Docker-spec compatibility alias `access_token` (`token` wins when both
    are present, matching the spec's preference). `none` if neither is a non-empty string or the
    body is not a JSON object. Total over `Lean.Json.parse`. -/
def parseTokenResponse (body : String) : Option String :=
  match Lean.Json.parse body with
  | .error _ => none
  | .ok json =>
      let field (k : String) : Option String :=
        match json.getObjVal? k with
        | .ok v => match v.getStr? with
                   | .ok s => if s.isEmpty then none else some s
                   | .error _ => none
        | .error _ => none
      match field "token" with
      | some t => some t
      | none => field "access_token"

/-! ## docker config.json → credential source -/

/-- Where a registry's credential comes from, decoded purely from `~/.docker/config.json`:
    - `inline base64UserPass` — the `auths.<host>.auth` field, base64 of `user:pass` (the IO edge
      base64-decodes + splits it). The base64 string is kept verbatim, NOT decoded here, so this
      pure layer never materialises a secret.
    - `helper binaryName` — a credential helper to spawn (`docker-credential-<binaryName> get`),
      from `credHelpers.<host>` (per-host, wins) else the global `credsStore`.
    - `none` — no credential configured for this host (the IO edge then attempts an anonymous
      token, which public registries like ghcr issue for public repos). -/
inductive CredSource where
  | inline (base64UserPass : String)
  | helper (binaryName : String)
  | none
deriving Repr, BEq, DecidableEq

/-- A non-empty string from a JSON object field, else `none`. -/
private def strField (j : Lean.Json) (key : String) : Option String :=
  match j.getObjVal? key with
  | .ok v => match v.getStr? with
             | .ok s => if s.isEmpty then Option.none else some s
             | .error _ => Option.none
  | .error _ => Option.none

/-- Decode the credential source for `host` from the parsed docker `config.json`. Precedence
    matches docker's own resolution: a per-host `credHelpers.<host>` wins; else the global
    `credsStore` (a helper for every host, used here since the host has an `auths` entry — docker
    only consults the store for hosts that appear in `auths`, but a bare `credsStore` is also
    treated as covering listed hosts); else an inline `auths.<host>.auth`; else `none`.
    Pure over the file CONTENTS — the IO read is in `Kue/OciFetch.lean`. -/
def credSourceFor (configText : String) (host : String) : CredSource :=
  match Lean.Json.parse configText with
  | .error _ => .none
  | .ok json =>
      -- Per-host helper wins.
      let perHostHelper : Option String :=
        match json.getObjVal? "credHelpers" with
        | .ok hs => strField hs host
        | .error _ => Option.none
      match perHostHelper with
      | some h => .helper h
      | none =>
          let hasAuthsEntry : Bool :=
            match json.getObjVal? "auths" with
            | .ok auths => (auths.getObjVal? host).toOption.isSome
            | .error _ => false
          let globalStore : Option String := strField json "credsStore"
          -- The global store applies only when the host actually has an `auths` entry
          -- (docker behaviour); a store with no entry for the host means no credential here.
          match (if hasAuthsEntry then globalStore else Option.none) with
          | some store => .helper store
          | none =>
              let inlineAuth : Option String :=
                match json.getObjVal? "auths" with
                | .ok auths =>
                    match auths.getObjVal? host with
                    | .ok hostObj => strField hostObj "auth"
                    | .error _ => Option.none
                | .error _ => Option.none
              match inlineAuth with
              | some a => .inline a
              | none => .none

/-- Split an inline `user:pass` (the base64-decoded `auth` field) at the FIRST `:` — a password may
    itself contain colons. `none` if there is no colon. The IO edge calls this after
    `base64DecodeString`; kept here so it is pinned offline against synthetic inputs. -/
def splitUserPass (s : String) : Option (String × String) :=
  match s.splitOn ":" with
  | [] => Option.none
  | [_] => Option.none
  | user :: rest => some (user, String.intercalate ":" rest)

/-- Parse a credential-helper `get` response (`{"Username":"…","Secret":"…"}`) into `(user, pass)`.
    Docker's helper protocol capitalises the keys. `none` if either field is absent/non-string. A
    `Username` of the literal `"<token>"` means "use the Secret as an identity token" — surfaced as
    an empty username so the IO edge can send the secret as a bearer/refresh token; here we just
    return it faithfully. Total over `Lean.Json.parse`; the secret is never logged by callers. -/
def parseHelperResponse (body : String) : Option (String × String) :=
  match Lean.Json.parse body with
  | .error _ => Option.none
  | .ok json =>
      match json.getObjVal? "Username", json.getObjVal? "Secret" with
      | .ok u, .ok s =>
          match u.getStr?, s.getStr? with
          | .ok user, .ok secret => some (user, secret)
          | _, _ => Option.none
      | _, _ => Option.none

end OciAuth
end Kue
