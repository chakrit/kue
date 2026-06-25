import Kue.Registry

/-!
# Registry config + OCI-ref resolution tests (B3d-1)

`native_decide` pins for the pure `CUE_REGISTRY` parser and module→OCI-ref resolver. Expected
values are taken from cue v0.16.1's own source — the authoritative OCI protocol reference:
`internal/mod/modresolve/resolve.go` (`ParseCUERegistry`, `parseRegistry`, `ResolveToLocation`),
`mod/modconfig/modconfig.go` (`registry.cue.works` default), `mod/module/escape.go`
(`escapeString`), `mod/modcache/cache.go` (cache layout). Many literal expectations mirror
`internal/mod/modresolve/resolve_test.go`'s lookup table.
-/

namespace Kue
namespace Registry

/-! ## Default (empty CUE_REGISTRY) → Central Registry, secure -/

-- Empty config: every module resolves to `registry.cue.works`, secure, repo = bare module path.
theorem resolve_default_central :
    (resolveFromConfig "" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"registry.cue.works", false, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

#guard defaultRegistryHost == "registry.cue.works"
-- An empty config still parses (default catch-all installed) and never errors.
#guard (parseConfig "").toOption.isSome

/-! ## Bare host / host:port / host:port secure-default -/

-- A bare catch-all host (`CatchAllWithNoDefault` in resolve_test) — secure, no path prefix.
theorem resolve_bare_host :
    (resolveFromConfig "registry.somewhere" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"registry.somewhere", false, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

-- host:port for a non-local host stays secure and the port is kept verbatim in the host.
theorem resolve_host_port_secure :
    (resolveFromConfig "registry.somewhere:5000" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"registry.somewhere:5000", false, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

/-! ## host/path-prefix → repository = prefix-joined module path -/

-- A registry with a `/offset` path prefix: repository = `path.Join("offset", mpath)`
-- (`PrefixWithCatchAllDefault` in resolve_test → `offset/example.com/blah`).
theorem resolve_path_prefix_join :
    (resolveFromConfig "registry.example.com/offset" "example.com/blah@v0" "v0.0.1"
      == .found ⟨"registry.example.com", false, "offset/example.com/blah", "v0.0.1"⟩) = true := by
  native_decide

-- A multi-element path prefix is kept whole; only the FIRST `/` splits host from repository.
theorem resolve_multi_element_prefix :
    (resolveFromConfig "reg.example.com/a/b/c" "x.com/m@v0" "v1.0.0"
      == .found ⟨"reg.example.com", false, "a/b/c/x.com/m", "v1.0.0"⟩) = true := by
  native_decide

/-! ## +insecure / +secure overrides -/

-- `+insecure` flips a normally-secure host to insecure.
theorem resolve_explicit_insecure :
    (resolveFromConfig "registry.somewhere+insecure" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"registry.somewhere", true, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

-- `+secure` flips a normally-insecure (localhost) host to secure (`localhost:1234+secure`
-- in resolve_test → Insecure:false).
theorem resolve_localhost_explicit_secure :
    (resolveFromConfig "localhost:1234+secure" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"localhost:1234", false, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

-- `+secure` with a path prefix peels the suffix at the LAST `+`, then splits the repo.
theorem resolve_secure_suffix_with_prefix :
    (resolveFromConfig "reg.example.com/off+secure" "x.com/m@v0" "v1.0.0"
      == .found ⟨"reg.example.com", false, "off/x.com/m", "v1.0.0"⟩) = true := by
  native_decide

/-! ## localhost / 127.0.0.1 / [::1] default-insecure -/

-- `localhost:5000` defaults to insecure (`LocalhostIsInsecure` in resolve_test).
theorem resolve_localhost_default_insecure :
    (resolveFromConfig "localhost:5000" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"localhost:5000", true, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

-- `127.0.0.1` defaults to insecure.
theorem resolve_127_default_insecure :
    (resolveFromConfig "127.0.0.1" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"127.0.0.1", true, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

-- `[::1]` (IPv6 loopback) defaults to insecure (`[::1]IsInsecure` in resolve_test), host kept
-- bracketed.
theorem resolve_ipv6_loopback_default_insecure :
    (resolveFromConfig "[::1]" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"[::1]", true, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

-- `[::1]:5000` — bracketed IPv6 with a port; the port is kept, the host recognised as loopback.
theorem resolve_ipv6_loopback_with_port :
    (resolveFromConfig "[::1]:5000" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"[::1]:5000", true, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

-- A zero-compressed IPv6 loopback spelling (`[0:0::1]`) is still insecure
-- (`[0:0::1]IsInsecure` in resolve_test).
theorem resolve_ipv6_loopback_expanded :
    (resolveFromConfig "[0:0::1]" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"[0:0::1]", true, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

-- A non-loopback IPv6 host stays secure.
theorem resolve_ipv6_nonloopback_secure :
    (resolveFromConfig "[2001:db8::1]" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"[2001:db8::1]", false, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

/-! ## `none` (global) and `prefix=none` -/

-- The global `none` registry: a module fetch must FAIL — `noRegistry`, never a default host.
theorem resolve_global_none :
    (resolveFromConfig "none" "fruit.com/apple@v0" "v1.2.3" == .noRegistry) = true := by
  native_decide

-- `prefix=none`: the prefixed module resolves to no registry; others fall through to the
-- catch-all default (`PrefixWithExplicitNone` in resolve_test).
theorem resolve_prefix_none_matched :
    (resolveFromConfig "example.com=none,registry.somewhere" "example.com/blah@v0" "v0.0.1"
      == .noRegistry) = true := by
  native_decide

theorem resolve_prefix_none_unmatched_falls_through :
    (resolveFromConfig "example.com=none,registry.somewhere" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"registry.somewhere", false, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

-- A bare `none` catch-all with a prefixed real registry
-- (`PrefixWithCatchAllDefaultAndExplicitNoneFallback`): the prefixed module resolves, the
-- catch-all module fails.
theorem resolve_catchall_none_prefixed_resolves :
    (resolveFromConfig "example.com=registry.example.com/offset,none" "example.com/blah@v0" "v0.0.1"
      == .found ⟨"registry.example.com", false, "offset/example.com/blah", "v0.0.1"⟩) = true := by
  native_decide

theorem resolve_catchall_none_unmatched_fails :
    (resolveFromConfig "example.com=registry.example.com/offset,none" "fruit.com/apple@v0" "v1.2.3"
      == .noRegistry) = true := by
  native_decide

/-! ## Prefix matching: longest-wins, complete-element boundary, fallback, duplicates -/

-- Longest-prefix wins: `example.com/blah` matches `example.com` (catch-all) but the more
-- specific `example.com/blah` prefix should win when both are configured.
theorem resolve_longest_prefix_wins :
    (resolveFromConfig
        "example.com=reg.a.com,example.com/blah=reg.b.com" "example.com/blah/sub@v0" "v1.0.0"
      == .found ⟨"reg.b.com", false, "example.com/blah/sub", "v1.0.0"⟩) = true := by
  native_decide

-- Complete-element boundary: a prefix `foo.example/bar` matches `foo.example/bar/x` ...
theorem resolve_prefix_matches_complete_element :
    (resolveFromConfig
        "foo.example/bar=reg.match.com,reg.default.com" "foo.example/bar/x@v0" "v1.0.0"
      == .found ⟨"reg.match.com", false, "foo.example/bar/x", "v1.0.0"⟩) = true := by
  native_decide

-- ... but NOT `foo.example/barry` (partial element) — it falls through to the catch-all.
theorem resolve_prefix_rejects_partial_element :
    (resolveFromConfig
        "foo.example/bar=reg.match.com,reg.default.com" "foo.example/barry@v0" "v1.0.0"
      == .found ⟨"reg.default.com", false, "foo.example/barry", "v1.0.0"⟩) = true := by
  native_decide

-- An exact prefix==path match resolves to that registry (`example.com` itself, not under it).
theorem resolve_exact_prefix_match :
    (resolveFromConfig "example.com=reg.match.com,reg.default.com" "example.com@v0" "v1.0.0"
      == .found ⟨"reg.match.com", false, "example.com", "v1.0.0"⟩) = true := by
  native_decide

-- The catch-all (no `prefix=`) handles a module matching no configured prefix
-- (`PrefixWithCatchAllNoDefault` in resolve_test).
theorem resolve_fallback_entry :
    (resolveFromConfig
        "example.com=registry.example.com/offset,registry.somewhere" "fruit.com/apple@v0" "v1.2.3"
      == .found ⟨"registry.somewhere", false, "fruit.com/apple", "v1.2.3"⟩) = true := by
  native_decide

-- Order-independence: the same two entries in the other order give the same longest-match.
theorem resolve_order_independent :
    (resolveFromConfig
        "example.com/blah=reg.b.com,example.com=reg.a.com" "example.com/blah/sub@v0" "v1.0.0"
      == .found ⟨"reg.b.com", false, "example.com/blah/sub", "v1.0.0"⟩) = true := by
  native_decide

-- Duplicate identical prefix = a config error (`duplicate module prefix`).
theorem parse_duplicate_prefix_errors :
    (match parseConfig "example.com=reg.a.com,example.com=reg.b.com" with
      | .error _ => true | .ok _ => false) = true := by
  native_decide

-- Duplicate catch-all = error.
theorem parse_duplicate_catchall_errors :
    (match parseConfig "reg.a.com,reg.b.com" with
      | .error _ => true | .ok _ => false) = true := by
  native_decide

-- An empty registry part (trailing comma) = error (`empty registry part`).
theorem parse_empty_part_errors :
    (match parseConfig "reg.a.com," with
      | .error _ => true | .ok _ => false) = true := by
  native_decide

-- An empty prefix (`=reg`) = error.
theorem parse_empty_prefix_errors :
    (match parseConfig "=reg.a.com" with
      | .error _ => true | .ok _ => false) = true := by
  native_decide

-- An empty registry reference (`prefix=`) = error.
theorem parse_empty_reference_errors :
    (match parseConfig "example.com=" with
      | .error _ => true | .ok _ => false) = true := by
  native_decide

-- An unknown `+suffix` = error (`unknown suffix`).
theorem parse_unknown_suffix_errors :
    (match parseConfig "foo.com+bogus" with
      | .error _ => true | .ok _ => false) = true := by
  native_decide

/-! ## Major-version stripping and tag = plain version -/

-- The `@v0` major suffix is stripped from the OCI repo; the FULL version is the tag.
theorem resolve_strips_major_keeps_full_version :
    (resolveFromConfig "registry.somewhere" "prodigy9.co/defs@v0" "v0.3.19"
      == .found ⟨"registry.somewhere", false, "prodigy9.co/defs", "v0.3.19"⟩) = true := by
  native_decide

#guard stripMajor "prodigy9.co/defs@v0" == "prodigy9.co/defs"
#guard stripMajor "prodigy9.co/defs" == "prodigy9.co/defs"
#guard stripMajor "x.com/m@v2" == "x.com/m"
#guard (mkModuleVersion "prodigy9.co/defs@v0" "v0.3.19")
  == ⟨"prodigy9.co/defs", "v0.3.19"⟩

/-! ## On-disk cache-layout escaping (escape.go) -/

-- No upper-case ⇒ verbatim.
#guard escapePath "foo.com/bar" == "foo.com/bar"
-- Upper-case ⇒ `!`-prefixed lowercasing of each `A`–`Z` (escape.go `escapeString`).
theorem escape_uppercase_path :
    (escapePath "Foo.com/Bar" == "!foo.com/!bar") = true := by
  native_decide

theorem escape_version_uppercase :
    (escapeVersion "v1.2.3-RC1" == "v1.2.3-!r!c1") = true := by
  native_decide

#guard escapeVersion "v1.2.3" == "v1.2.3"

-- The download/extract cache paths use the ESCAPED base path + version (cache.go layout).
theorem extract_cache_path_layout :
    (extractCachePath "/cache/mod" ⟨"prodigy9.co/defs", "v0.3.19"⟩
      == "/cache/mod/extract/prodigy9.co/defs@v0.3.19") = true := by
  native_decide

theorem download_cache_path_layout :
    (downloadCachePath "/cache/mod" ⟨"prodigy9.co/defs", "v0.3.19"⟩ "zip"
      == "/cache/mod/download/prodigy9.co/defs/@v/v0.3.19.zip") = true := by
  native_decide

-- An upper-case-containing module path escapes in BOTH cache trees.
theorem extract_cache_path_escapes_upper :
    (extractCachePath "/c" ⟨"Foo.com/M", "v1.0.0"⟩
      == "/c/extract/!foo.com/!m@v1.0.0") = true := by
  native_decide

/-! ## joinRepo (Go path.Join two-arg) edge cases -/

#guard joinRepo "" "x.com/m" == "x.com/m"          -- empty prefix ⇒ bare module path
#guard joinRepo "offset" "x.com/m" == "offset/x.com/m"
#guard joinRepo "a/b" "x.com/m" == "a/b/x.com/m"

end Registry
end Kue
