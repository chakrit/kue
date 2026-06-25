import Kue.Base64

/-!
# SHA-256 (FIPS 180-4) + `cue.sum` `h1:` dirhash (B3d-3, PURE)

The cryptographic primitive the B3d registry-fetch track needs (decision note
`docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`): a total, IO-free
SHA-256 over `ByteArray`, plus the Go `golang.org/x/mod/sumdb/dirhash` `Hash1` ("h1:")
algorithm that `cue.sum` entries are built from. No network, no IO, no `partial` — SHA-256
is fixed-round (64 rounds per 512-bit block), so every function here is structurally total.

Two consumers downstream:
- **B3d-4 (curl IO edge):** OCI blob descriptors carry a `sha256:<hex>` digest
  (`digest.FromBytes` in cue's `mod/modregistry/client.go`). `sha256` + `hex` here verify a
  downloaded manifest/blob against that digest.
- **B3d-5 (cue.sum verify):** `hash1` reproduces the `h1:<base64>` a `cue.sum` line records.

Authoritative protocol source (NOT the language spec — tooling, so the Go code IS the spec):
- FIPS 180-4 for the SHA-256 round structure, constants, padding, and big-endian packing.
- `golang.org/x/mod/sumdb/dirhash` `hash.go` `Hash1`: outer `sha256` over one
  `lowerhex(sha256(contents)) ++ "  " ++ name ++ "\n"` line per file (TWO spaces, U+000A
  newline), files sorted by name in byte order, result `"h1:" ++ base64.StdEncoding(...)`.
- `cuelang.org/go/mod/modzip` `zip.go` `Create`: a cue module zip stores entries under their
  BARE module-root-relative slash path (`cue.mod/module.cue`, `foo.cue`) — it does NOT prefix
  `<module>@<version>/` the way Go's own modzip does. So the dirhash `name` for a cue module
  zip is the zip-entry path verbatim. Zip reading itself is the IO edge (B3d-4); `hash1`
  operates on already-in-memory `(name, contents)` pairs, name-agnostic.

The std-base64 step reuses `Kue.base64Encode` (the `encoding/base64` builtin's encoder) — not
reimplemented here.
-/

namespace Kue
namespace Sha256

/-! ## Round constants and initial hash (FIPS 180-4 §4.2.2, §5.3.3) -/

/-- The 64 SHA-256 round constants `K₀..K₆₃` (first 32 bits of the fractional parts of the
    cube roots of the first 64 primes). -/
def K : Array UInt32 := #[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

/-- The eight initial hash words `H₀..H₇` (first 32 bits of the fractional parts of the square
    roots of the first 8 primes). -/
def initHash : Array UInt32 :=
  #[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

/-! ## 32-bit primitives (FIPS 180-4 §3.2, §4.1.2)

    `UInt32` operations are already mod-2³² wrapping in Lean, so `+`/`<<<`/`>>>`/`^^^` are the
    spec's `+`, `SHR`, `<<`, `⊕` directly. Only `rotr` needs spelling out. -/

/-- Rotate-right of a 32-bit word by `n` bits (`ROTR^n`): `(x >>> n) | (x <<< (32 - n))`. -/
def rotr (x : UInt32) (n : UInt32) : UInt32 :=
  (x >>> n) ||| (x <<< (32 - n))

/-- `Ch(x,y,z) = (x ∧ y) ⊕ (¬x ∧ z)`. -/
def ch (x y z : UInt32) : UInt32 := (x &&& y) ^^^ ((~~~x) &&& z)

/-- `Maj(x,y,z) = (x ∧ y) ⊕ (x ∧ z) ⊕ (y ∧ z)`. -/
def maj (x y z : UInt32) : UInt32 := (x &&& y) ^^^ (x &&& z) ^^^ (y &&& z)

/-- `Σ₀(x) = ROTR²(x) ⊕ ROTR¹³(x) ⊕ ROTR²²(x)`. -/
def bigSigma0 (x : UInt32) : UInt32 := rotr x 2 ^^^ rotr x 13 ^^^ rotr x 22

/-- `Σ₁(x) = ROTR⁶(x) ⊕ ROTR¹¹(x) ⊕ ROTR²⁵(x)`. -/
def bigSigma1 (x : UInt32) : UInt32 := rotr x 6 ^^^ rotr x 11 ^^^ rotr x 25

/-- `σ₀(x) = ROTR⁷(x) ⊕ ROTR¹⁸(x) ⊕ SHR³(x)`. -/
def smallSigma0 (x : UInt32) : UInt32 := rotr x 7 ^^^ rotr x 18 ^^^ (x >>> 3)

/-- `σ₁(x) = ROTR¹⁷(x) ⊕ ROTR¹⁹(x) ⊕ SHR¹⁰(x)`. -/
def smallSigma1 (x : UInt32) : UInt32 := rotr x 17 ^^^ rotr x 19 ^^^ (x >>> 10)

/-! ## Padding (FIPS 180-4 §5.1.1)

    Append `0x80`, then the minimum `0x00` bytes so the length ≡ 56 (mod 64), then the
    original message bit-length as a big-endian 64-bit integer. The padded length is always a
    multiple of 64 bytes. -/

/-- The big-endian 64-bit message bit-length suffix as 8 bytes. The bit length is `8 * n` for an
    `n`-byte message; we compute it on `Nat` then peel 8 bytes MSB-first. -/
def lengthSuffix (byteLen : Nat) : ByteArray := Id.run do
  let bitLen := byteLen * 8
  let mut out := ByteArray.empty
  for i in [0:8] do
    -- byte i (i=0 is the most significant): shift right by (7-i)*8, mask low 8 bits.
    let shift := (7 - i) * 8
    out := out.push (UInt8.ofNat ((bitLen >>> shift) &&& 0xff))
  return out

/-- FIPS padding: `msg ++ 0x80 ++ 0x00…0x00 ++ <64-bit BE bit length>`, padded so the result
    length is a multiple of 64. The count of zero pad bytes is `(56 - (len+1)) mod 64`. -/
def pad (msg : ByteArray) : ByteArray := Id.run do
  let len := msg.size
  -- After the mandatory 0x80 byte, pad with zeros until length ≡ 56 (mod 64).
  let zeros := (56 + 64 - ((len + 1) % 64)) % 64
  let mut out := msg.push 0x80
  for _ in [0:zeros] do
    out := out.push 0x00
  out := out ++ lengthSuffix len
  return out

/-! ## Compression (FIPS 180-4 §6.2)

    Process the padded message one 512-bit (64-byte) block at a time, updating the eight
    working words. The message schedule `W₀..W₆₃` is built in-place in a `64`-word array. -/

/-- Read a big-endian 32-bit word from `bytes` at byte offset `off` (`off..off+3`). Callers only
    pass in-range offsets on padded, block-aligned input; an out-of-range index reads 0. -/
def beWord (bytes : ByteArray) (off : Nat) : UInt32 :=
  let b0 := bytes[off]!
  let b1 := bytes[off + 1]!
  let b2 := bytes[off + 2]!
  let b3 := bytes[off + 3]!
  (b0.toUInt32 <<< 24) ||| (b1.toUInt32 <<< 16) ||| (b2.toUInt32 <<< 8) ||| b3.toUInt32

/-- Build the 64-word message schedule for the block starting at byte offset `base`.
    `W[0..15]` are the block's big-endian words; `W[t] = σ₁(W[t-2]) + W[t-7] + σ₀(W[t-15]) +
    W[t-16]` for `16 ≤ t < 64`. -/
def schedule (bytes : ByteArray) (base : Nat) : Array UInt32 := Id.run do
  let mut w : Array UInt32 := Array.replicate 64 0
  for i in [0:16] do
    w := w.set! i (beWord bytes (base + i * 4))
  for t in [16:64] do
    let s1 := smallSigma1 w[t - 2]!
    let s0 := smallSigma0 w[t - 15]!
    w := w.set! t (s1 + w[t - 7]! + s0 + w[t - 16]!)
  return w

/-- The 64-round compression of a single block's schedule `w` into the running hash `h`
    (an 8-word array). Returns the updated 8-word hash. -/
def compressBlock (h : Array UInt32) (w : Array UInt32) : Array UInt32 := Id.run do
  let mut a := h[0]!
  let mut b := h[1]!
  let mut c := h[2]!
  let mut d := h[3]!
  let mut e := h[4]!
  let mut f := h[5]!
  let mut g := h[6]!
  let mut hh := h[7]!
  for t in [0:64] do
    let t1 := hh + bigSigma1 e + ch e f g + K[t]! + w[t]!
    let t2 := bigSigma0 a + maj a b c
    hh := g
    g := f
    f := e
    e := d + t1
    d := c
    c := b
    b := a
    a := t1 + t2
  return #[h[0]! + a, h[1]! + b, h[2]! + c, h[3]! + d,
           h[4]! + e, h[5]! + f, h[6]! + g, h[7]! + hh]

/-- Fold the compression over every 64-byte block of the padded message. -/
def compressAll (padded : ByteArray) : Array UInt32 := Id.run do
  let blocks := padded.size / 64
  let mut h := initHash
  for blk in [0:blocks] do
    h := compressBlock h (schedule padded (blk * 64))
  return h

/-- Serialise the eight final hash words big-endian into the 32-byte digest. -/
def wordsToBytes (h : Array UInt32) : ByteArray := Id.run do
  let mut out := ByteArray.empty
  for i in [0:8] do
    let w := h[i]!
    out := out.push (UInt8.ofNat ((w >>> 24).toNat &&& 0xff))
    out := out.push (UInt8.ofNat ((w >>> 16).toNat &&& 0xff))
    out := out.push (UInt8.ofNat ((w >>> 8).toNat &&& 0xff))
    out := out.push (UInt8.ofNat (w.toNat &&& 0xff))
  return out

/-- SHA-256 of a byte array: pad, compress every block, serialise. Returns the 32-byte digest.
    Total — fixed 64 rounds per block over a finite, statically-padded message. -/
def sha256 (msg : ByteArray) : ByteArray :=
  wordsToBytes (compressAll (pad msg))

/-- SHA-256 of a string's UTF-8 bytes — the common case for hashing text content. -/
def sha256String (s : String) : ByteArray :=
  sha256 s.toUTF8

/-! ## Hex encoding (lowercase) -/

/-- The lowercase hex digit for a nibble `0..15` (values outside the range never occur — the
    caller masks to 4 bits). -/
def hexDigit (n : UInt8) : Char :=
  let v := n.toNat &&& 0xf
  if v < 10 then Char.ofNat (v + '0'.toNat)
  else Char.ofNat (v - 10 + 'a'.toNat)

/-- Lowercase hex of a byte array (`%x` over the bytes). `sha256 "" |> hex` gives the standard
    `e3b0c4…b855`. No existing bytes→hex helper in the codebase, so it lives here. -/
def hex (bytes : ByteArray) : String := Id.run do
  let mut out : Array Char := #[]
  for b in bytes.toList do
    out := out.push (hexDigit (b >>> 4))
    out := out.push (hexDigit (b &&& 0x0f))
  return String.ofList out.toList

/-- The `sha256:<hex>` digest form used by OCI descriptors (`digest.FromBytes`). -/
def digestString (bytes : ByteArray) : String :=
  "sha256:" ++ hex (sha256 bytes)

/-! ## dirhash `Hash1` (`golang.org/x/mod/sumdb/dirhash`)

    The `cue.sum` `h1:` algorithm. Files are `(name, contents)` pairs already in memory; the
    caller (B3d-4) supplies the zip-entry names. -/

/-- The inner per-file summary line for `Hash1`: `lowerhex(sha256(contents)) ++ "  " ++ name ++
    "\n"` — TWO U+0020 spaces, one U+000A newline (`fmt.Fprintf(h, "%x  %s\n", …)`). -/
def hash1Line (name : String) (contents : ByteArray) : String :=
  hex (sha256 contents) ++ "  " ++ name ++ "\n"

/-- `Hash1` over a list of `(name, contents)` files: sort by name (byte order), build the
    per-file summary lines, SHA-256 the concatenated summary, return `"h1:" ++ base64Std(...)`.
    Byte-order sort = compare on the UTF-8 byte sequences; for the ASCII module/zip paths cue
    produces, this coincides with Lean's `String` `<` on the same bytes, but we sort on
    `String.toUTF8.toList` explicitly to match `slices.Sort` over Go strings exactly. -/
def hash1 (files : List (String × ByteArray)) : String :=
  let sorted := files.toArray.qsort (fun a b =>
    byteLt a.1.toUTF8.toList b.1.toUTF8.toList) |>.toList
  let summary := String.join (sorted.map (fun (name, contents) => hash1Line name contents))
  "h1:" ++ base64Encode (sha256 summary.toUTF8).toList
where
  /-- Lexicographic `<` on two `UInt8` lists (byte-order string comparison): shorter-is-less on a
      common prefix, else the first differing byte decides. Total, structurally recursive. -/
  byteLt : List UInt8 → List UInt8 → Bool
    | [], [] => false
    | [], _ :: _ => true
    | _ :: _, [] => false
    | x :: xs, y :: ys => if x == y then byteLt xs ys else x < y

end Sha256
end Kue
