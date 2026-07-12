import Kue.Builtin
import Kue.Tests.EvalTestHelpers

namespace Kue

-- STDLIB-NET: the `net` package's IP string-validator surface. Each theorem pins one behavior
-- against cue v0.16.1 (whose validators call `net/netip` verbatim, so the classification is
-- cue-compat by construction). DEFERRED to `unsupportedBuiltin`: `FQDN` (full idna engine) and
-- every function returning a struct/list/tuple (`SplitHostPort`/`ToIP4`/`ParseCIDR`/`InCIDR`/…);
-- a nonexistent leaf (`net.Host`, `net.CIDR`) bottoms bare.

private def call (name : String) (args : List Value) : Value := evalBuiltinCall name args
private def str (s : String) : Value := .prim (.string s)

-- ### Validator VALUES (bare-call form → `.stringFormat` node)

theorem ip_validator_value : (call "net.IP" [] == .stringFormat .netIP) = true := by native_decide
theorem ipv4_validator_value : (call "net.IPv4" [] == .stringFormat .netIPv4) = true := by native_decide
theorem ipv6_validator_value : (call "net.IPv6" [] == .stringFormat .netIPv6) = true := by native_decide
theorem ipcidr_validator_value : (call "net.IPCIDR" [] == .stringFormat .netIPCIDR) = true := by native_decide
theorem loopback_validator_value :
    (call "net.LoopbackIP" [] == .stringFormat .netLoopbackIP) = true := by native_decide

-- ### `net.IPv4` / `net.IPv6` / `net.IP` — family membership (meet-participating)

theorem ipv4_valid : (meet (str "127.0.0.1") (.stringFormat .netIPv4) == str "127.0.0.1") = true := by
  native_decide
theorem ipv4_octet_over : isBottom (meet (str "256.0.0.1") (.stringFormat .netIPv4)) = true := by
  native_decide
theorem ipv4_leading_zero : isBottom (meet (str "01.2.3.4") (.stringFormat .netIPv4)) = true := by
  native_decide
theorem ipv4_too_few : isBottom (meet (str "1.2.3") (.stringFormat .netIPv4)) = true := by native_decide
theorem ipv4_too_many : isBottom (meet (str "1.2.3.4.5") (.stringFormat .netIPv4)) = true := by
  native_decide
-- An IPv6 (even 4-in-6) is NOT IPv4: `netip` keeps the v4/v6 distinction (`Is4` ≠ `Is6`).
theorem ipv4_rejects_v6 : isBottom (meet (str "::1") (.stringFormat .netIPv4)) = true := by native_decide
theorem ipv4_rejects_4in6 : isBottom (meet (str "::ffff:1.2.3.4") (.stringFormat .netIPv4)) = true := by
  native_decide

theorem ipv6_valid : (meet (str "::1") (.stringFormat .netIPv6) == str "::1") = true := by native_decide
theorem ipv6_compression : (meet (str "2001:db8::1") (.stringFormat .netIPv6) == str "2001:db8::1") = true := by
  native_decide
theorem ipv6_unspecified : (meet (str "::") (.stringFormat .netIPv6) == str "::") = true := by native_decide
theorem ipv6_embedded_v4 :
    (meet (str "::ffff:1.2.3.4") (.stringFormat .netIPv6) == str "::ffff:1.2.3.4") = true := by
  native_decide
theorem ipv6_rejects_v4 : isBottom (meet (str "1.2.3.4") (.stringFormat .netIPv6)) = true := by
  native_decide
theorem ipv6_multiple_ellipsis : isBottom (meet (str "1::2::3") (.stringFormat .netIPv6)) = true := by
  native_decide
theorem ipv6_too_many_groups :
    isBottom (meet (str "1:2:3:4:5:6:7:8:9") (.stringFormat .netIPv6)) = true := by native_decide
theorem ipv6_group_over_4_digits :
    isBottom (meet (str "12345::1") (.stringFormat .netIPv6)) = true := by native_decide
theorem ipv6_zone_accepted :
    (meet (str "fe80::1%eth0") (.stringFormat .netIPv6) == str "fe80::1%eth0") = true := by native_decide
theorem ipv6_empty_zone : isBottom (meet (str "fe80::1%") (.stringFormat .netIPv6)) = true := by
  native_decide

-- `net.IP` accepts either family.
theorem ip_accepts_v4 : (meet (str "127.0.0.1") (.stringFormat .netIP) == str "127.0.0.1") = true := by
  native_decide
theorem ip_accepts_v6 : (meet (str "::ffff:1.2.3.4") (.stringFormat .netIP) == str "::ffff:1.2.3.4") = true := by
  native_decide
theorem ip_rejects_garbage : isBottom (meet (str "bad") (.stringFormat .netIP)) = true := by native_decide

-- ### Abstract retention (the STDLIB-VALIDATORS-SOUND discipline) — one per axis

theorem ip_abstract_retains :
    (meet (.kind .string) (.stringFormat .netIP) == .stringFormat .netIP) = true := by native_decide
theorem ipv4_abstract_retains :
    (meet (.kind .string) (.stringFormat .netIPv4) == .stringFormat .netIPv4) = true := by native_decide
theorem loopback_abstract_retains :
    (meet (.kind .string) (.stringFormat .netLoopbackIP) == .stringFormat .netLoopbackIP) = true := by
  native_decide
theorem cidr_abstract_retains :
    (meet (.kind .string) (.stringFormat .netIPCIDR) == .stringFormat .netIPCIDR) = true := by native_decide
theorem ipv4_abstract_not_bottom :
    isBottom (meet (.kind .string) (.stringFormat .netIPv4)) = false := by native_decide
-- A non-string is a kind conflict, not a retention.
theorem ipv4_int_conflict : isBottom (meet (.prim (.int 5)) (.stringFormat .netIPv4)) = true := by
  native_decide

-- ### DISJUNCTION-ARM SURVIVAL — the exact path the earlier validator HIGHs lived in.
-- An abstract `string & net.IPv4()` arm must SURVIVE finalization (two live arms ⇒ ambiguous,
-- ok = false); fabrication-pruning the retained validator arm would collapse to "10.0.0.1".
theorem ipv4_abstract_disj_arm_survives :
    manifestValueOk (disjOfValues (meet (.kind .string) (.stringFormat .netIPv4))
      (str "10.0.0.1")) = false := by native_decide

-- ### Address-class predicates (`net/netip.Addr.Is*`), pinned against cue v0.16.1.

theorem loopback_v4 : (meet (str "127.0.0.1") (.stringFormat .netLoopbackIP) == str "127.0.0.1") = true := by
  native_decide
theorem loopback_v6 : (meet (str "::1") (.stringFormat .netLoopbackIP) == str "::1") = true := by native_decide
theorem loopback_rejects : isBottom (meet (str "8.8.8.8") (.stringFormat .netLoopbackIP)) = true := by
  native_decide
-- 4-in-6 loopback unmaps to 127.x → loopback.
theorem loopback_4in6 :
    (meet (str "::ffff:127.0.0.1") (.stringFormat .netLoopbackIP) == str "::ffff:127.0.0.1") = true := by
  native_decide

theorem multicast_v4 : (meet (str "224.0.0.1") (.stringFormat .netMulticastIP) == str "224.0.0.1") = true := by
  native_decide
theorem multicast_v4_high : (meet (str "239.1.2.3") (.stringFormat .netMulticastIP) == str "239.1.2.3") = true := by
  native_decide
theorem multicast_v6 : (meet (str "ff02::1") (.stringFormat .netMulticastIP) == str "ff02::1") = true := by
  native_decide
theorem multicast_rejects : isBottom (meet (str "8.8.8.8") (.stringFormat .netMulticastIP)) = true := by
  native_decide

-- Link-local multicast: v4 224.0.0.0/24 (so 224.0.0.1 yes, 224.0.1.1 no), v6 ff02::/16.
theorem ll_multicast_v4 :
    (meet (str "224.0.0.1") (.stringFormat .netLinkLocalMulticastIP) == str "224.0.0.1") = true := by
  native_decide
theorem ll_multicast_v4_not : isBottom (meet (str "224.0.1.1") (.stringFormat .netLinkLocalMulticastIP)) = true := by
  native_decide
theorem ll_multicast_v6 :
    (meet (str "ff02::1") (.stringFormat .netLinkLocalMulticastIP) == str "ff02::1") = true := by native_decide

-- Interface-local multicast: v6-ONLY ff01::/16 (v4 never qualifies; 4-in-6 excluded).
theorem il_multicast_v6 :
    (meet (str "ff01::1") (.stringFormat .netInterfaceLocalMulticastIP) == str "ff01::1") = true := by
  native_decide
theorem il_multicast_ff02_not :
    isBottom (meet (str "ff02::1") (.stringFormat .netInterfaceLocalMulticastIP)) = true := by native_decide
theorem il_multicast_v4_never :
    isBottom (meet (str "224.0.0.1") (.stringFormat .netInterfaceLocalMulticastIP)) = true := by native_decide

-- Link-local unicast: v4 169.254.0.0/16, v6 fe80::/10.
theorem ll_unicast_v4 :
    (meet (str "169.254.1.1") (.stringFormat .netLinkLocalUnicastIP) == str "169.254.1.1") = true := by
  native_decide
theorem ll_unicast_v6 : (meet (str "fe80::1") (.stringFormat .netLinkLocalUnicastIP) == str "fe80::1") = true := by
  native_decide
theorem ll_unicast_rejects : isBottom (meet (str "8.8.8.8") (.stringFormat .netLinkLocalUnicastIP)) = true := by
  native_decide

-- Unspecified: 0.0.0.0 or ::.
theorem unspecified_v4 : (meet (str "0.0.0.0") (.stringFormat .netUnspecifiedIP) == str "0.0.0.0") = true := by
  native_decide
theorem unspecified_v6 : (meet (str "::") (.stringFormat .netUnspecifiedIP) == str "::") = true := by native_decide
theorem unspecified_rejects : isBottom (meet (str "127.0.0.1") (.stringFormat .netUnspecifiedIP)) = true := by
  native_decide

-- Global unicast: public + private + ULA; NOT unspecified/loopback/multicast/link-local, and
-- NOT the IPv4 broadcast 255.255.255.255.
theorem global_public : (meet (str "8.8.8.8") (.stringFormat .netGlobalUnicastIP) == str "8.8.8.8") = true := by
  native_decide
theorem global_private : (meet (str "10.0.0.1") (.stringFormat .netGlobalUnicastIP) == str "10.0.0.1") = true := by
  native_decide
theorem global_ula : (meet (str "fc00::1") (.stringFormat .netGlobalUnicastIP) == str "fc00::1") = true := by
  native_decide
theorem global_rejects_broadcast :
    isBottom (meet (str "255.255.255.255") (.stringFormat .netGlobalUnicastIP)) = true := by native_decide
theorem global_rejects_loopback : isBottom (meet (str "127.0.0.1") (.stringFormat .netGlobalUnicastIP)) = true := by
  native_decide
theorem global_rejects_unspecified : isBottom (meet (str "::") (.stringFormat .netGlobalUnicastIP)) = true := by
  native_decide

-- ### `net.IPCIDR` — CIDR string validation
theorem cidr_valid_v4 : (meet (str "192.168.0.0/24") (.stringFormat .netIPCIDR) == str "192.168.0.0/24") = true := by
  native_decide
theorem cidr_valid_v6 : (meet (str "2001:db8::/32") (.stringFormat .netIPCIDR) == str "2001:db8::/32") = true := by
  native_decide
theorem cidr_prefix_zero : (meet (str "1.2.3.0/0") (.stringFormat .netIPCIDR) == str "1.2.3.0/0") = true := by
  native_decide
theorem cidr_no_slash : isBottom (meet (str "1.2.3.4") (.stringFormat .netIPCIDR)) = true := by native_decide
theorem cidr_v4_prefix_over_32 : isBottom (meet (str "1.2.3.0/33") (.stringFormat .netIPCIDR)) = true := by
  native_decide
theorem cidr_v6_prefix_over_128 : isBottom (meet (str "2001:db8::/129") (.stringFormat .netIPCIDR)) = true := by
  native_decide
theorem cidr_prefix_leading_zero : isBottom (meet (str "1.2.3.0/01") (.stringFormat .netIPCIDR)) = true := by
  native_decide
theorem cidr_zone_barred : isBottom (meet (str "fe80::1%eth0/64") (.stringFormat .netIPCIDR)) = true := by
  native_decide

-- ### Function forms — `net.X(s)` returns a BOOL (invalid ⇒ false, NOT bottom); IPCIDR bottoms.

theorem ipv4_fn_true : (call "net.IPv4" [str "1.2.3.4"] == .prim (.bool true)) = true := by native_decide
theorem ipv4_fn_false : (call "net.IPv4" [str "bad"] == .prim (.bool false)) = true := by native_decide
theorem ip_fn_false : (call "net.IP" [str "bad"] == .prim (.bool false)) = true := by native_decide
theorem loopback_fn_true : (call "net.LoopbackIP" [str "127.0.0.1"] == .prim (.bool true)) = true := by
  native_decide
theorem loopback_fn_false : (call "net.LoopbackIP" [str "8.8.8.8"] == .prim (.bool false)) = true := by
  native_decide
theorem ipcidr_fn_true : (call "net.IPCIDR" [str "10.0.0.0/8"] == .prim (.bool true)) = true := by native_decide
-- IPCIDR is `(bool, error)` in cue → an unparseable CIDR BOTTOMS, not false.
theorem ipcidr_fn_bottom : isBottom (call "net.IPCIDR" [str "bad"]) = true := by native_decide

-- ### Deferred functions → `unsupportedBuiltin`; nonexistent leaf → bare bottom.

theorem fqdn_deferred_validator :
    (call "net.FQDN" [] == .bottomWith [.unsupportedBuiltin "net.FQDN"]) = true := by native_decide
theorem fqdn_deferred_fn :
    (call "net.FQDN" [str "foo.com"] == .bottomWith [.unsupportedBuiltin "net.FQDN"]) = true := by native_decide
theorem splithostport_deferred :
    (call "net.SplitHostPort" [str "1.2.3.4:80"] == .bottomWith [.unsupportedBuiltin "net.SplitHostPort"]) = true := by
  native_decide
theorem toip4_deferred :
    (call "net.ToIP4" [str "1.2.3.4"] == .bottomWith [.unsupportedBuiltin "net.ToIP4"]) = true := by native_decide
theorem incidr_deferred :
    (call "net.InCIDR" [str "1.2.3.4", str "1.2.3.0/24"] == .bottomWith [.unsupportedBuiltin "net.InCIDR"]) = true := by
  native_decide
theorem parsecidr_deferred :
    (call "net.ParseCIDR" [str "1.2.3.0/24"] == .bottomWith [.unsupportedBuiltin "net.ParseCIDR"]) = true := by
  native_decide
-- A nonexistent leaf has no arm → bare bottom (B-1 ruling), NOT an unsupported marker.
theorem nonexistent_leaf_bottom : (call "net.Host" [str "x:80"] == .bottom) = true := by native_decide
theorem cidr_leaf_nonexistent : (call "net.CIDR" [str "x"] == .bottom) = true := by native_decide

-- ### Family classification (`BuiltinFamily.ofName?`)
theorem net_family : (BuiltinFamily.ofName? "net.IPv4" == some .net) = true := by native_decide

-- ### End-to-end: bare validators, constants, and a CIDR through parse → eval → JSON export.
theorem net_export_end_to_end :
    exportJsonMatches
      "import \"net\"\nip: net.IPv4 & \"10.0.0.1\"\ncidr: net.IPCIDR & \"10.0.0.0/8\"\nv4l: net.IPv4len\nv6l: net.IPv6len\n"
      "{\n    \"ip\": \"10.0.0.1\",\n    \"cidr\": \"10.0.0.0/8\",\n    \"v4l\": 4,\n    \"v6l\": 16\n}\n" = true := by
  native_decide

-- ### Fixed-width v6 invariant (PA-NET-1): `NetAddr.v6` carries `Vector UInt8 16`, so a
-- parsed v6 address is exactly 16 bytes by construction and a wrong-width address is
-- unrepresentable — the classifiers index with no can't-happen fallback. `mkNetAddrV6?` is
-- the sole trust boundary refining the parser's list into the fixed-width vector.
theorem v6_width_by_construction :
    (parseNetAddr? "::1").map (fun a => match a with | .v6 v => v.toList.length | .v4 .. => 4)
      = some 16 := by native_decide
theorem v6_embedded_width :
    (parseNetAddr? "::ffff:1.2.3.4").map (fun a => match a with | .v6 v => v.toList.length | .v4 .. => 4)
      = some 16 := by native_decide
theorem mkV6_accepts_16 : (mkNetAddrV6? (List.replicate 16 0)).isSome = true := by native_decide
theorem mkV6_rejects_short : mkNetAddrV6? [0, 0, 0] = none := by native_decide
theorem mkV6_rejects_long : mkNetAddrV6? (List.replicate 17 0) = none := by native_decide

-- Coverage tripwire: one anchor per section — a section swallowed by an editing slip makes
-- its `#check` an unknown identifier (a hard build error), not a silently dropped test.
#check @loopback_validator_value          -- validator VALUES
#check @ip_rejects_garbage                -- IPv4/IPv6/IP family membership + parser edges
#check @ipv4_int_conflict                 -- abstract retention
#check @ipv4_abstract_disj_arm_survives   -- disjunction-arm survival
#check @global_rejects_unspecified        -- address-class predicates
#check @cidr_zone_barred                  -- IPCIDR validation + boundaries
#check @ipcidr_fn_bottom                  -- function forms (bool / IPCIDR bottom)
#check @cidr_leaf_nonexistent             -- deferred functions + nonexistent leaf
#check @net_family                        -- family classification
#check @net_export_end_to_end             -- end-to-end export
#check @v6_width_by_construction          -- fixed-width v6 invariant

end Kue
