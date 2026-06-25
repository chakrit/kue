/-!
# Registry config + module → OCI-ref resolution (B3d-1, PURE)

The fully offline foundation of the B3d registry-fetch track (decision note
`docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`): given a `CUE_REGISTRY`
config string + a module path + a version, compute the OCI location (host, secure-flag,
repository, tag) — with NO network, NO `curl`, NO IO. `cue` guarantees this is computable
offline; this module is its Lean-native, total, theorem-pinned port.

Authoritative protocol source (cue v0.16.1, OCI tooling — NOT the language spec, so cue's
own code IS the spec here):
- `internal/mod/modresolve/resolve.go` — `ParseCUERegistry` (simple-syntax parse),
  `parseRegistry` (one registry spec), `ResolveToLocation` (prefix match → host/repo/tag).
- `mod/modconfig/modconfig.go` — `CUE_REGISTRY` `file:`/`inline:`/`simple:` kind split and
  the `registry.cue.works` catch-all default.
- `mod/module/escape.go` — `EscapePath`/`EscapeVersion` (on-disk cache-layout escaping).
- `mod/modcache/cache.go` — the `download`/`extract` cache-path layout the escaping feeds.

Two things in `cue`'s OCI pipeline that surprised and are pinned below:
- The OCI **repository name is NOT escaped** — `ResolveToLocation` joins the raw base module
  path (`m.BasePath()`, major-version suffix stripped) under the registry path-prefix via
  Go `path.Join`. `EscapePath`/`EscapeVersion` apply ONLY to the on-disk download/extract
  cache directory layout (`modcache/cache.go`), never the OCI repo. Both are modelled here;
  later slices consume the cache form.
- The **tag is the plain version** (`v0.3.19`) in the simple syntax — `PrefixForTags` and the
  hash encodings are CUE-syntax-config-file only (deferred, see compat-assumptions).

Scope deferrals (footnoted in `docs/spec/compat-assumptions.md`): the `file:`/`inline:` kinds
and the full CUE-syntax config-file form (`pathEncoding`, `stripPrefix`, `prefixForTags`,
`hashAsRepo`/`hashAsTag`). Only the simple comma-separated syntax is implemented.
-/

namespace Kue
namespace Registry

/-- The default Central Registry host `cue` falls back to when `CUE_REGISTRY` is empty/unset
    (`modconfig.DefaultRegistry`). All modules resolve here, securely, by default. -/
def defaultRegistryHost : String := "registry.cue.works"

/-! ## Module versions -/

/-- A module reference split into its bare base path (no major-version suffix) and version.
    `prodigy9.co/defs@v0` at `v0.3.19` is `{ basePath := "prodigy9.co/defs", version := "v0.3.19" }`.
    The base path is what prefix-matching and the OCI repository name are built from; the
    version is the OCI tag. -/
structure ModuleVersion where
  basePath : String
  version : String
deriving Repr, BEq, DecidableEq

/-- Strip a trailing `@<major>` suffix from a module path, mirroring `ast.SplitPackageVersion`
    (cut at the FIRST `@`). `prodigy9.co/defs@v0` → `prodigy9.co/defs`; a path with no `@` is
    returned verbatim. The text after `@` is the *major* version (`v0`), discarded for the OCI
    repo — the OCI tag carries the *full* version, supplied separately. -/
def stripMajor (modPath : String) : String :=
  match modPath.splitOn "@" with
  | base :: _ => base
  | [] => modPath

/-- Build a `ModuleVersion` from a (possibly `@major`-suffixed) module path and a full version.
    `mkModuleVersion "prodigy9.co/defs@v0" "v0.3.19"` strips the `@v0` major. -/
def mkModuleVersion (modPath version : String) : ModuleVersion :=
  { basePath := stripMajor modPath, version }

/-! ## On-disk cache-layout escaping (`mod/module/escape.go`)

    Used by the download/extract cache directory layout (`modcache/cache.go`), NOT the OCI
    repository name. Conforms to `escapeString`: a `!`-prefixed lowercasing of every ASCII
    upper-case rune, applied only when the string contains at least one such rune (otherwise
    returned unchanged). CUE's `CheckPath` already forbids upper-case in real module paths, so
    this is defensive — but it is the authoritative layout rule. -/

/-- Whether `c` is an ASCII upper-case letter `A`–`Z`. -/
def isAsciiUpper (c : Char) : Bool :=
  'A' ≤ c && c ≤ 'Z'

/-- Lower-case an ASCII upper-case letter (`'A' + (c - 'A')` shifted by `'a' - 'A' = 32`). -/
def asciiToLower (c : Char) : Char :=
  Char.ofNat (c.toNat + 32)

/-- `escape.go`'s `escapeString`: map every `A`–`Z` to `!` + its lower-case form; leave all
    other characters untouched; and as a fast path return the input verbatim when it has no
    upper-case letter. `Foo.com/Bar` → `!foo.com/!bar`; `foo.com/bar` → `foo.com/bar`. Total —
    cue's `!`/non-ASCII rejection is an input invariant, not a partiality here. -/
def escapeString (s : String) : String :=
  if s.any isAsciiUpper then
    String.ofList (s.toList.flatMap fun c =>
      if isAsciiUpper c then ['!', asciiToLower c] else [c])
  else
    s

/-- `module.EscapePath`: the escaped on-disk form of a module base path. (`CheckPath` validity
    is the caller's invariant; the escaping itself is `escapeString`.) -/
def escapePath (path : String) : String := escapeString path

/-- `module.EscapeVersion`: the escaped on-disk form of a module version. (Semver validity is
    the caller's invariant; the escaping itself is `escapeString`.) -/
def escapeVersion (version : String) : String := escapeString version

/-! ## Registry spec (one entry of `CUE_REGISTRY`)

    `parseRegistry` in `resolve.go`: a bare value is a host (`host`, `host:port`,
    `[::1]:5000`), optionally with a `/repository` path-prefix, optionally with a
    `+secure`/`+insecure` suffix; the literal `none` means "no registry". -/

/-- A parsed registry spec: either the sentinel `none` (resolution under it FAILS), or a real
    registry with a host, an insecure flag, and a (possibly empty) repository path-prefix that
    all modules routed here are stored under. Illegal-states-unrepresentable: a `none` registry
    carries no host/repository, so "no registry" can never be confused with an empty real one. -/
inductive RegistrySpec where
  | none
  | reg (host : String) (insecure : Bool) (repository : String)
deriving Repr, BEq, DecidableEq

/-- The host part of `hostPort`, dropping a `:port` suffix and unwrapping `[...]` IPv6
    brackets, mirroring `net.SplitHostPort` + the bracket strip in `isInsecureHost`.
    `localhost:5000` → `localhost`; `[::1]:5000` → `::1`; `[::1]` → `::1`; `foo.com` → `foo.com`.
    A bracketed host keeps any internal colons (an IPv6 literal); only a colon OUTSIDE brackets
    is a port separator. -/
def hostOf (hostPort : String) : String :=
  if hostPort.startsWith "[" then
    -- Bracketed IPv6: the host is between the brackets; a `:port` may trail the `]`.
    match (hostPort.drop 1).toString.splitOn "]" with
    | inner :: _ => inner
    | [] => hostPort
  else
    -- Unbracketed: a single trailing `:port` is a port; a bare `host` has none. (Real CUE
    -- rejects unbracketed multi-colon hosts as invalid; we take the text before the last
    -- colon as the host, matching `net.SplitHostPort`'s single-separator contract.)
    match hostPort.splitOn ":" with
    | [_] => hostPort         -- no colon ⇒ whole string is the host
    | parts =>
        match parts.dropLast with
        | [] => hostPort
        | hostParts => String.intercalate ":" hostParts

/-- `isInsecureHost`: whether a host defaults to an insecure (HTTP) connection — `localhost`,
    `127.0.0.1`, or the IPv6 loopback `::1` (in any zero-compressed spelling cue's
    `netip.ParseAddr` would canonicalise, e.g. `0:0::1`). Everything else defaults to secure. -/
def isInsecureHost (hostPort : String) : Bool :=
  let host := hostOf hostPort
  host == "localhost" || host == "127.0.0.1" || isLoopbackV6 host
where
  /-- An IPv6 string denotes the loopback `::1` iff every hextet is zero except a final `1`.
      Covers `::1`, `0:0::1`, `0:0:0:0:0:0:0:1`, etc. without a full IPv6 parser: split on `:`,
      drop empty segments (the `::` compression), require the last to be `1` and the rest `0`. -/
  isLoopbackV6 (host : String) : Bool :=
    let segs := (host.splitOn ":").filter (· ≠ "")
    match segs.reverse with
    | last :: rest => last == "1" && rest.all (fun s => s.all (· == '0'))
    | [] => false

/-- Parse one registry spec (`parseRegistry`). Recognises the `none` sentinel; otherwise peels
    an optional trailing `+secure`/`+insecure` suffix (the LAST `+`, and only when it is not at
    index 0), splits the remaining `host[/repository]` at the FIRST `/`, and resolves the
    insecure flag (explicit suffix wins; else the host's default). An unknown `+suffix` or an
    empty spec is an error.

    The `host` keeps any `host:port`/`[::1]:5000` form verbatim — only the `/repository` split
    and the `+suffix` are peeled. `repository` is the path-prefix all routed modules sit under. -/
def parseRegistry (spec : String) : Except String RegistrySpec :=
  if spec == "none" then
    .ok .none
  else if spec.isEmpty then
    .error "empty registry reference"
  else
    let (body, suffix) := splitSuffix spec
    let (host, repository) := splitRepo body
    if host.isEmpty then
      .error s!"invalid registry {spec}: empty host"
    else
      match suffix with
      | some "+insecure" => .ok (.reg host true repository)
      | some "+secure" => .ok (.reg host false repository)
      | some other =>
          .error s!"invalid registry {spec}: unknown suffix ({other}), need +insecure, +secure or no suffix"
      | none => .ok (.reg host (isInsecureHost host) repository)
where
  /-- Peel a trailing `+secure`/`+insecure`-style suffix at the LAST `+` (index > 0, matching
      `strings.LastIndex(env, "+") > 0`). Returns `(body, some "+suffix")` or `(spec, none)`. -/
  splitSuffix (s : String) : String × Option String :=
    match lastPlusIndex s with
    | some i => ((s.take i).toString, some (s.drop i).toString)
    | none => (s, none)
  /-- The index of the last `+` in `s` when it is > 0, else `none`. -/
  lastPlusIndex (s : String) : Option Nat :=
    let cs := s.toList
    let idxs := (List.range cs.length).filter (fun i => cs[i]? == some '+')
    match idxs.reverse with
    | i :: _ => if i > 0 then some i else none
    | [] => none
  /-- Split `host[/repository]` at the FIRST `/`. No `/` ⇒ empty repository. -/
  splitRepo (s : String) : String × String :=
    match s.splitOn "/" with
    | [host] => (host, "")
    | host :: rest => (host, String.intercalate "/" rest)
    | [] => (s, "")

/-! ## Registry config (`CUE_REGISTRY` as a whole) -/

/-- A routing entry: a registry spec constrained to a module-path `prefix`. The catch-all
    (an entry with no `prefix=`) is modelled as `prefix := ""` here; `ResolveToLocation`
    treats the empty prefix as the default that always matches with length 0. -/
structure RegistryEntry where
  pathPrefix : String
  registry : RegistrySpec
deriving Repr, BEq, DecidableEq

/-- The parsed `CUE_REGISTRY`: a list of prefix-routed entries plus the catch-all default for
    otherwise-unmatched modules. Mirrors `config{ ModuleRegistries, DefaultRegistry }`: the
    prefixed entries are order-independent and longest-prefix-wins; `default` is the wildcard. -/
structure RegistryConfig where
  entries : List RegistryEntry
  fallback : RegistrySpec
deriving Repr, BEq, DecidableEq

/-- Parse the full simple-syntax `CUE_REGISTRY` (`ParseCUERegistry`). Empty/unset ⇒ the Central
    Registry default. Otherwise a comma-separated list of `prefix=registryspec` (prefixed) or
    bare `registryspec` (catch-all) entries: prefixes route by longest complete-element match,
    the bare entry is the default. Errors: an empty part, an empty prefix or reference, a
    duplicate prefix, a duplicate catch-all, or a bad registry spec. When no catch-all is given,
    `registry.cue.works` is the default (cue's `catchAllDefault`).

    NOTE: a `file:`/`inline:`/`simple:` kind prefix on the *whole* string is handled upstream
    (`modconfig`): `simple:` strips and parses here; `file:`/`inline:` are DEFERRED. This parses
    the simple form only — callers pass the post-`simple:`-strip string. -/
def parseConfig (cueRegistry : String) : Except String RegistryConfig :=
  if cueRegistry.isEmpty then
    match parseRegistry defaultRegistryHost with
    | .ok fallback => .ok { entries := [], fallback }
    | .error e => .error e
  else do
    let parts := cueRegistry.splitOn ","
    let (entries, fallback?) ← foldParts parts [] Option.none
    let fallback ← match fallback? with
      | some d => .ok d
      | none =>
          match parseRegistry defaultRegistryHost with
          | .ok d => .ok d
          | .error e => .error e
    .ok { entries, fallback }
where
  /-- Fold the comma-separated parts into `(prefixedEntries, catchAllDefault?)`, rejecting
      duplicates and empty pieces as cue does. -/
  foldParts : List String -> List RegistryEntry -> Option RegistrySpec ->
      Except String (List RegistryEntry × Option RegistrySpec)
    | [], entries, default => .ok (entries.reverse, default)
    | part :: rest, entries, default =>
        match part.splitOn "=" with
        | [single] => do
            -- No `=`: a bare catch-all registry. Empty part is an error; a second catch-all
            -- is a duplicate.
            if single.isEmpty then
              .error "empty registry part"
            else if default.isSome then
              .error "duplicate catch-all registry"
            else
              let reg ← parseRegistry single
              foldParts rest entries (some reg)
        | key :: valParts => do
            -- A `prefix=registryspec` entry. (A registry spec never contains `=`, so re-join is
            -- unambiguous; we keep the full remainder for robustness.)
            let val := String.intercalate "=" valParts
            if key.isEmpty then
              .error "empty module prefix"
            else if val.isEmpty then
              .error "empty registry reference"
            else if entries.any (fun e => e.pathPrefix == key) then
              .error s!"duplicate module prefix {key}"
            else
              let reg ← parseRegistry val
              foldParts rest (⟨key, reg⟩ :: entries) default
        | [] => .error "empty registry part"

/-! ## Resolution (`ResolveToLocation`) -/

/-- The OCI location a module resolves to: host, secure-flag, repository, and tag. The result
    of resolution is `found`, `noRegistry` (a `none` registry — fetch must fail cleanly), or
    `error` (a malformed config). Illegal-states-unrepresentable: a successful location always
    carries all four fields; "no registry" is a distinct constructor, never a sentinel host. -/
structure OciRef where
  host : String
  insecure : Bool
  repository : String
  tag : String
deriving Repr, BEq, DecidableEq

inductive Resolution where
  | found (ref : OciRef)
  | noRegistry
  | error (msg : String)
deriving Repr, BEq, DecidableEq

/-- Whether `prefix` matches `mpath` on COMPLETE path elements (`ResolveToLocation`'s rule):
    an exact equality, or `mpath` starts with `prefix` AND the next character is `/`. So
    `foo.example/bar` matches `foo.example/bar/x` but NOT `foo.example/barry`. The empty prefix
    matches everything (it is the catch-all, handled separately). -/
def prefixMatches (pat mpath : String) : Bool :=
  if pat == mpath then
    true
  else if pat.isEmpty then
    true
  else if mpath.startsWith pat then
    -- Require a `/` immediately after the prefix: a complete-element boundary.
    (mpath.drop pat.length).startsWith "/"
  else
    false

/-- Pick the registry routing `mpath`: the longest-prefix complete-element match among
    `entries`, falling back to the catch-all `default`. Exact prefix==path wins outright.
    Order-independent (we scan all and keep the longest match), matching `ResolveToLocation`. -/
def selectRegistry (config : RegistryConfig) (mpath : String) : RegistrySpec :=
  let matched := config.entries.filter (fun e => prefixMatches e.pathPrefix mpath)
  match matched.foldl (fun best e =>
    match best with
    | some b =>
        if e.pathPrefix == mpath then some e                       -- exact match wins outright
        else if b.pathPrefix == mpath then best
        else if e.pathPrefix.length > b.pathPrefix.length then some e
        else best
    | none => some e) Option.none with
  | some e => e.registry
  | none => config.fallback

/-- Go `path.Join(prefix, mpath)` for the two-element case we need: join with a single `/`,
    then collapse the result the way `path.Clean` would for these inputs — an empty prefix
    yields the bare `mpath` (no leading slash), an empty `mpath` yields the bare prefix.
    Neither real input is empty-with-slashes, so a full `path.Clean` is unnecessary. -/
def joinRepo (pathPrefix mpath : String) : String :=
  if pathPrefix.isEmpty then mpath
  else if mpath.isEmpty then pathPrefix
  else pathPrefix ++ "/" ++ mpath

/-- Resolve a module to its OCI location (`ResolveToLocation` for the simple syntax): select
    the routing registry by longest-prefix match; a `none` registry ⇒ `noRegistry`; otherwise
    the repository is the registry path-prefix joined with the (UNESCAPED) base module path and
    the tag is the plain version. Total — the only failure mode is a `none` registry, surfaced
    as its own constructor, never an exception. -/
def resolve (config : RegistryConfig) (mv : ModuleVersion) : Resolution :=
  match selectRegistry config mv.basePath with
  | .none => .noRegistry
  | .reg host insecure repository =>
      .found {
        host,
        insecure,
        repository := joinRepo repository mv.basePath,
        tag := mv.version
      }

/-- Convenience end-to-end: parse `CUE_REGISTRY`, then resolve `modPath@version` (the `@major`
    suffix on `modPath` is stripped). A config parse error surfaces as `Resolution.error`. -/
def resolveFromConfig (cueRegistry modPath version : String) : Resolution :=
  match parseConfig cueRegistry with
  | .error e => .error e
  | .ok config => resolve config (mkModuleVersion modPath version)

/-! ## On-disk download/extract cache paths (`modcache/cache.go`)

    The Go-module-style cache layout the fetched bytes land in, computed purely so a later
    network slice (B3d-4/5) only has to write them. Both use the ESCAPED base path/version. -/

/-- The extract directory for a module under the cache root: `<root>/extract/<esc-path>@<esc-ver>`
    (`cache.go` `downloadDir`). Slash-separated, joined onto `root`. -/
def extractCachePath (root : String) (mv : ModuleVersion) : String :=
  s!"{root}/extract/{escapePath mv.basePath}@{escapeVersion mv.version}"

/-- A download-cache file for a module: `<root>/download/<esc-path>/@v/<esc-ver>.<suffix>`
    (`cache.go` `cachePath`); `suffix` is `zip`/`mod`/`lock`/`info`. -/
def downloadCachePath (root : String) (mv : ModuleVersion) (suffix : String) : String :=
  s!"{root}/download/{escapePath mv.basePath}/@v/{escapeVersion mv.version}.{suffix}"

end Registry
end Kue
