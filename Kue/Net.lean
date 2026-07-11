import Kue.Value

namespace Kue

/-! # `net` standard-library validators (STDLIB-NET)

Pure, total, exact ports of cue's `net` package IP-validation surface. Every function
mirrors Go's `net/netip` (`ParseAddr`/`ParsePrefix` and the `Addr.Is*` classification
methods), which cue calls verbatim — the classification predicates are cue-compat by
construction (spec-silent tooling surface; see `docs/spec/cue-spec-gaps.md`). A
non-conforming input yields `false`, never a wrong value.

**Scope boundary.** Only the string-validator surface lands here: `IP`/`IPv4`/`IPv6`,
`IPCIDR`, and the address-class predicates (`LoopbackIP`, `MulticastIP`, …). The
parsing/formatting functions that return structs, byte lists, or tuples (`SplitHostPort`,
`JoinHostPort`, `ToIP4`/`ToIP16`, `ParseCIDR`, `ParseIP`, `AddIP*`, `InCIDR`, `CompareIP`)
are DEFERRED at the dispatcher with an `unsupportedBuiltin` marker, never faked. `FQDN` is
DEFERRED too: cue implements it as `golang.org/x/net/idna`'s `ToASCII` (full IDNA2008 +
punycode/ACE-prefix validation — `ab--cd` and `xn--a` reject as invalid A-labels), which
needs the idna engine, not a label-rule predicate. -/

/-- A successfully parsed IP address, mirroring `net/netip.Addr`'s v4/v6 distinction: `v4`
    is a dotted-decimal address (netip's `z4` form), `v6` a 16-byte address (`z6`). The
    distinction — not merely the bytes — drives classification: `Is4`/`Is6` key off it, and
    every class predicate unmaps an IPv4-mapped IPv6 address (`::ffff:a.b.c.d`) to its v4
    form first (except `InterfaceLocalMulticast`, which excludes 4-in-6). A `v6`'s `bytes`
    is always length 16 by construction (the parser fills exactly 16). Zone identifiers are
    accepted by the parser but dropped — no classification predicate inspects them. -/
inductive NetAddr where
  | v4 (a b c d : UInt8)
  | v6 (bytes : List UInt8)
deriving Repr, BEq

/-- Whether `c` is an ASCII decimal digit. -/
def isDecDigit (c : Char) : Bool := c.toNat ≥ 48 ∧ c.toNat ≤ 57

/-- The value of an ASCII hex digit (`0-9a-fA-F`), or `none`. -/
def hexDigit? (c : Char) : Option Nat :=
  let n := c.toNat
  if n ≥ 48 ∧ n ≤ 57 then some (n - 48)
  else if n ≥ 97 ∧ n ≤ 102 then some (n - 97 + 10)
  else if n ≥ 65 ∧ n ≤ 70 then some (n - 65 + 10)
  else none

/-! ## IPv4 parsing (`net/netip.parseIPv4Fields`, strict) -/

/-- Parse the four dotted-decimal octets, faithfully to `netip`'s strict rules: exactly four
    fields, each 1–3 digits with value ≤ 255 and NO leading zero (`01` rejects, `0` accepts),
    no empty field, no leading/trailing dot, no non-digit/non-dot character. `val`/`digLen`
    accumulate the current octet, `acc` the completed octets (0–3). Structural on the char
    list, hence total. Returns the four octet bytes, or `none` on any violation. -/
def parseIPv4Fields : List Char → (val digLen : Nat) → (acc : List UInt8) → Option (List UInt8)
  | [], val, digLen, acc =>
      if digLen == 0 then none
      else if acc.length == 3 then some (acc ++ [UInt8.ofNat val])
      else none
  | c :: rest, val, digLen, acc =>
      if isDecDigit c then
        if digLen == 1 ∧ val == 0 then none
        else
          let val := val * 10 + (c.toNat - 48)
          if val > 255 then none else parseIPv4Fields rest val (digLen + 1) acc
      else if c == '.' then
        if digLen == 0 then none
        else if acc.length == 3 then none
        else parseIPv4Fields rest 0 0 (acc ++ [UInt8.ofNat val])
      else none

/-- Parse an IPv4 dotted-decimal address to its four bytes. -/
def parseIPv4Addr (s : List Char) : Option (List UInt8) := parseIPv4Fields s 0 0 []

/-! ## IPv6 parsing (`net/netip.parseIPv6`) -/

/-- Split off a leading run of hex digits: `(digits, rest)`. Structural, hence total. -/
def takeHexDigits : List Char → List Char × List Char
  | [] => ([], [])
  | c :: rest =>
      if (hexDigit? c).isSome then
        let (ds, tl) := takeHexDigits rest
        (c :: ds, tl)
      else ([], c :: rest)

/-- The numeric value of a hex-digit run. -/
def hexRunValue (ds : List Char) : Nat := ds.foldl (fun acc c => acc * 16 + (hexDigit? c).getD 0) 0

/-- Expand the accumulated bytes around an optional `::` ellipsis into exactly 16 bytes, or
    fail. Mirrors the tail of `parseIPv6`: a short address needs the ellipsis to zero-fill
    the gap; a full (16-byte) address must NOT carry an ellipsis (`::` must expand to ≥ 1
    zero group). -/
def finalizeIPv6 (acc : List UInt8) (ellipsis : Option Nat) : Option (List UInt8) :=
  let i := acc.length
  if i < 16 then
    match ellipsis with
    | none => none
    | some e => some (acc.take e ++ List.replicate (16 - i) 0 ++ acc.drop e)
  else if i == 16 then
    match ellipsis with
    | some _ => none
    | none => some acc
  else none

/-- The IPv6 group-parsing loop, a faithful port of `parseIPv6`'s inner loop. `acc` holds the
    bytes filled so far (length = `i`), `ellipsis` the byte index of a seen `::`, `s` the
    remaining address chars (zone already stripped). Each iteration reads one hex group
    (1–4 digits); a group followed by `.` is the embedded trailing IPv4 (`::ffff:1.2.3.4`),
    which must sit at the final two fields. `fuel` bounds the recursion by the input length
    (each iteration consumes ≥ 1 char), keeping it total. -/
def parseIPv6Loop (fuel : Nat) (acc : List UInt8) (ellipsis : Option Nat) : List Char → Option (List UInt8)
  | s =>
    match fuel with
    | 0 => none
    | fuel + 1 =>
        if acc.length ≥ 16 then
          if s.isEmpty then finalizeIPv6 acc ellipsis else none
        else
          let (hexDigits, afterHex) := takeHexDigits s
          let cnt := hexDigits.length
          if cnt == 0 ∨ cnt > 4 then none
          else
            let val := hexRunValue hexDigits
            match afterHex with
            | '.' :: _ =>
                -- Embedded trailing IPv4: `s` is the full `a.b.c.d`.
                if ellipsis.isNone ∧ acc.length ≠ 12 then none
                else if acc.length + 4 > 16 then none
                else
                  match parseIPv4Addr s with
                  | some v4 => finalizeIPv6 (acc ++ v4) ellipsis
                  | none => none
            | _ =>
                let acc := acc ++ [UInt8.ofNat (val / 256), UInt8.ofNat (val % 256)]
                match afterHex with
                | [] => finalizeIPv6 acc ellipsis
                | ':' :: rest =>
                    match rest with
                    | [] => none
                    | ':' :: rest2 =>
                        match ellipsis with
                        | some _ => none
                        | none =>
                            if rest2.isEmpty then finalizeIPv6 acc (some acc.length)
                            else parseIPv6Loop fuel acc (some acc.length) rest2
                    | _ => parseIPv6Loop fuel acc ellipsis rest
                | _ => none

/-- Parse the address portion of an IPv6 string (zone already stripped) to its 16 bytes,
    handling a leading `::` (and the bare `::` unspecified address). A single leading `:`
    (`":1:2"`) is rejected: the first group has no digits. -/
def parseIPv6Body (s : List Char) : Option (List UInt8) :=
  match s with
  | ':' :: ':' :: rest =>
      if rest.isEmpty then some (List.replicate 16 0)
      else parseIPv6Loop (rest.length + 1) [] (some 0) rest
  | ':' :: _ => none
  | _ => parseIPv6Loop (s.length + 1) [] none s

/-- Parse an IPv6 string, stripping an optional `%zone` suffix (a present zone must be
    non-empty). The zone is discarded — it affects no classification predicate. -/
def parseIPv6Addr (s : List Char) : Option (List UInt8) :=
  match s.span (· ≠ '%') with
  | (addr, []) => parseIPv6Body addr
  | (addr, _ :: zone) => if zone.isEmpty then none else parseIPv6Body addr

/-! ## `netip.ParseAddr` dispatch -/

/-- The first `.`, `:`, or `%` in the string, if any — `ParseAddr`'s dispatch discriminant:
    a leading `.` selects IPv4, `:` selects IPv6, `%` (before either) is an error. -/
def firstAddrMark : List Char → Option Char
  | [] => none
  | c :: rest => if c == '.' ∨ c == ':' ∨ c == '%' then some c else firstAddrMark rest

/-- Parse a string as an IP address (`netip.ParseAddr`): dispatch on whichever of `.`/`:`
    appears first (a leading `%`, or neither mark, fails). -/
def parseNetAddr? (s : String) : Option NetAddr :=
  let chars := s.toList
  match firstAddrMark chars with
  | some '.' => (parseIPv4Addr chars).map (fun bs => .v4 (bs.getD 0 0) (bs.getD 1 0) (bs.getD 2 0) (bs.getD 3 0))
  | some ':' => (parseIPv6Addr chars).map NetAddr.v6
  | _ => none

/-! ## Classification (`net/netip.Addr.Is*`) -/

/-- Whether the 16-byte address is IPv4-mapped IPv6 (`::ffff:0:0/96`): bytes 0–9 zero, bytes
    10–11 `0xff`. -/
def isMappedV4 (bs : List UInt8) : Bool :=
  (bs.take 10).all (· == 0) ∧ bs.getD 10 0 == 0xff ∧ bs.getD 11 0 == 0xff

/-- Unmap an IPv4-mapped IPv6 address to its v4 form (`Addr.Unmap`); a no-op otherwise. -/
def netUnmap : NetAddr → NetAddr
  | .v6 bs => if isMappedV4 bs then .v4 (bs.getD 12 0) (bs.getD 13 0) (bs.getD 14 0) (bs.getD 15 0) else .v6 bs
  | a => a

/-- `Addr.Is4`: a pure IPv4 address (not IPv4-mapped IPv6). -/
def netIs4 : NetAddr → Bool
  | .v4 .. => true
  | .v6 _ => false

/-- `Addr.Is6`: an IPv6 address, including IPv4-mapped forms. -/
def netIs6 : NetAddr → Bool
  | .v4 .. => false
  | .v6 _ => true

/-- `Addr.IsLoopback`: IPv4 `127.0.0.0/8`, IPv6 `::1`. -/
def netIsLoopback (a : NetAddr) : Bool :=
  match netUnmap a with
  | .v4 x _ _ _ => x == 127
  | .v6 bs => (bs.take 15).all (· == 0) ∧ bs.getD 15 0 == 1

/-- `Addr.IsMulticast`: IPv4 `224.0.0.0/4`, IPv6 `ff00::/8`. -/
def netIsMulticast (a : NetAddr) : Bool :=
  match netUnmap a with
  | .v4 x _ _ _ => (x &&& 0xf0) == 0xe0
  | .v6 bs => bs.getD 0 0 == 0xff

/-- `Addr.IsInterfaceLocalMulticast`: IPv6-only `ff01::/16`; explicitly excludes IPv4-mapped
    IPv6 (no unmap). -/
def netIsInterfaceLocalMulticast (a : NetAddr) : Bool :=
  match a with
  | .v6 bs => if isMappedV4 bs then false else (bs.getD 0 0 == 0xff ∧ (bs.getD 1 0 &&& 0x0f) == 0x01)
  | .v4 .. => false

/-- `Addr.IsLinkLocalMulticast`: IPv4 `224.0.0.0/24`, IPv6 `ff02::/16`. -/
def netIsLinkLocalMulticast (a : NetAddr) : Bool :=
  match netUnmap a with
  | .v4 x y z _ => x == 224 ∧ y == 0 ∧ z == 0
  | .v6 bs => bs.getD 0 0 == 0xff ∧ (bs.getD 1 0 &&& 0x0f) == 0x02

/-- `Addr.IsLinkLocalUnicast`: IPv4 `169.254.0.0/16`, IPv6 `fe80::/10`. -/
def netIsLinkLocalUnicast (a : NetAddr) : Bool :=
  match netUnmap a with
  | .v4 x y _ _ => x == 169 ∧ y == 254
  | .v6 bs => bs.getD 0 0 == 0xfe ∧ (bs.getD 1 0 &&& 0xc0) == 0x80

/-- `Addr.IsUnspecified`: IPv4 `0.0.0.0` or IPv6 `::` (no unmap). -/
def netIsUnspecified (a : NetAddr) : Bool :=
  match a with
  | .v4 x y z w => x == 0 ∧ y == 0 ∧ z == 0 ∧ w == 0
  | .v6 bs => bs.all (· == 0)

/-- `Addr.IsGlobalUnicast`: everything that is not unspecified, loopback, multicast, or
    link-local unicast — and, for IPv4, not the broadcast `255.255.255.255`. Private IPv4
    and ULA IPv6 addresses ARE global unicast, matching netip. -/
def netIsGlobalUnicast (a : NetAddr) : Bool :=
  let u := netUnmap a
  match u with
  | .v4 x y z w =>
      let bcast := x == 255 ∧ y == 255 ∧ z == 255 ∧ w == 255
      if netIsUnspecified u ∨ bcast then false
      else !netIsLoopback u ∧ !netIsMulticast u ∧ !netIsLinkLocalUnicast u
  | .v6 bs =>
      if bs.all (· == 0) then false
      else !netIsLoopback u ∧ !netIsMulticast u ∧ !netIsLinkLocalUnicast u

/-! ## CIDR (`netip.ParsePrefix`) -/

/-- Validate the prefix-length suffix of a CIDR: digits only, no leading zero unless a lone
    `0`, no sign, value in `0..maxBits`. Mirrors `ParsePrefix`'s bit-string rule. -/
def validPrefixLen (bitsStr : List Char) (maxBits : Nat) : Bool :=
  match bitsStr with
  | [] => false
  | first :: _ =>
      let allDigits := bitsStr.all isDecDigit
      let leadingOk := bitsStr.length == 1 ∨ (first.toNat ≥ 49 ∧ first.toNat ≤ 57)
      let value := bitsStr.foldl (fun n c => n * 10 + (c.toNat - 48)) 0
      allDigits ∧ leadingOk ∧ value ≤ maxBits

/-- Whether `s` is a valid CIDR address (`netip.ParsePrefix` succeeds): `addr/bits` split on
    the LAST `/`, `addr` a valid IP (with no IPv6 zone — zones are barred in a prefix), `bits`
    a valid prefix length for the address family (`≤ 32` v4, `≤ 128` v6). -/
def isNetIPCIDRString (s : String) : Bool :=
  let chars := s.toList
  match chars.reverse.span (· ≠ '/') with
  | (_, []) => false
  | (revBits, _ :: revAddr) =>
      let addrChars := revAddr.reverse
      let bitsChars := revBits.reverse
      if addrChars.any (· == '%') then false
      else
        match parseNetAddr? (String.ofList addrChars) with
        | none => false
        | some a => validPrefixLen bitsChars (if netIs6 a then 128 else 32)

/-! ## Public string validators (bool per validator) -/

def isNetIP (s : String) : Bool := (parseNetAddr? s).isSome
def isNetIPv4 (s : String) : Bool := match parseNetAddr? s with | some a => netIs4 a | none => false
def isNetIPv6 (s : String) : Bool := match parseNetAddr? s with | some a => netIs6 a | none => false
def isNetLoopbackIP (s : String) : Bool := match parseNetAddr? s with | some a => netIsLoopback a | none => false
def isNetMulticastIP (s : String) : Bool := match parseNetAddr? s with | some a => netIsMulticast a | none => false
def isNetInterfaceLocalMulticastIP (s : String) : Bool := match parseNetAddr? s with | some a => netIsInterfaceLocalMulticast a | none => false
def isNetLinkLocalMulticastIP (s : String) : Bool := match parseNetAddr? s with | some a => netIsLinkLocalMulticast a | none => false
def isNetLinkLocalUnicastIP (s : String) : Bool := match parseNetAddr? s with | some a => netIsLinkLocalUnicast a | none => false
def isNetGlobalUnicastIP (s : String) : Bool := match parseNetAddr? s with | some a => netIsGlobalUnicast a | none => false
def isNetUnspecifiedIP (s : String) : Bool := match parseNetAddr? s with | some a => netIsUnspecified a | none => false

end Kue
