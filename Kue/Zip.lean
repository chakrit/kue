import Kue.Inflate

/-!
# Pure-Lean ZIP reader (PKWARE APPNOTE, PURE)

The container half of the B3d-5z extraction step: parse a ZIP archive's End-Of-Central-
Directory record + Central Directory, then decompress each entry (STORED or DEFLATE via
`Kue/Inflate.lean`) and VERIFY its CRC-32 against the central-directory value, yielding the
in-memory `(name, contents)` pairs that B3d-5 writes to the cache and `Sha256.hash1` hashes
into a `cue.sum` line.

Decision (`docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`, extended to
extraction): pure Lean, NOT an `unzip` subprocess — deterministic, total, offline-testable,
no runtime dep, composes with the dirhash. The curl GET is the sole impurity; the verified
bytes' transform is pure.

## Why the Central Directory, not local headers

The Central Directory is the archive's authoritative entry index (PKWARE APPNOTE §4.3.12);
local file headers can lie or omit sizes (streaming writers set bit 3 and defer sizes to a
data descriptor). We read the EOCD to find the Central Directory, walk its entries for the
name / method / sizes / CRC / local-header offset, then read each entry's compressed span via
the local header (only to skip its variable name+extra fields to the data start).

## cue module zips

cue's `mod/modzip` stores entries under their BARE module-root-relative slash path
(`cue.mod/module.cue`, `foo.cue`) — NO `<module>@<version>/` prefix (confirmed B3d-3). cue's
own `Unzip` skips entries whose name is empty or ends `/` (directory entries); we match that —
`readZip` returns files only, in central-directory order.

## Totality

The container parse loops are bounded by the entry count read from the EOCD (a finite 16-bit
field) and structural `Nat` recursion over the data; inflate is total (see `Kue/Inflate.lean`).
CRC-32 is a fixed 8-round-per-byte fold. No `partial`.
-/

namespace Kue
namespace Zip

/-! ## Little-endian readers (ZIP is little-endian) -/

/-- Read a little-endian `UInt16` (2 bytes) at `off`; out-of-range bytes read 0 (a truncated
    archive surfaces as a structural error upstream). -/
def u16 (b : ByteArray) (off : Nat) : Nat :=
  (b[off]?.getD 0).toNat ||| ((b[off + 1]?.getD 0).toNat <<< 8)

/-- Read a little-endian `UInt32` (4 bytes) at `off`. -/
def u32 (b : ByteArray) (off : Nat) : Nat :=
  (b[off]?.getD 0).toNat
    ||| ((b[off + 1]?.getD 0).toNat <<< 8)
    ||| ((b[off + 2]?.getD 0).toNat <<< 16)
    ||| ((b[off + 3]?.getD 0).toNat <<< 24)

/-! ## CRC-32 (ISO 3309 / zip, poly 0xEDB88320)

    The standard zip CRC-32: reflected, init `0xFFFFFFFF`, final XOR `0xFFFFFFFF`. We compute
    the per-byte step directly (8 conditional shifts) rather than precomputing a table — small,
    total, and table-free keeps it a pure fold. -/

/-- Fold one byte into the running CRC (8 rounds of the reflected polynomial). -/
def crcByte (crc : UInt32) (byte : UInt8) : UInt32 := Id.run do
  let mut c := crc ^^^ byte.toUInt32
  for _ in [0:8] do
    c := if c &&& 1 == 1 then (c >>> 1) ^^^ 0xEDB88320 else c >>> 1
  return c

/-- CRC-32 of a byte array: `0xFFFFFFFF`-seeded fold, final inversion. `crc32 "" = 0`;
    `crc32 "123456789" = 0xCBF43926`. -/
def crc32 (data : ByteArray) : UInt32 :=
  (data.foldl crcByte 0xFFFFFFFF) ^^^ 0xFFFFFFFF

/-! ## Entry model (illegal states unrepresentable for the compression method) -/

/-- A ZIP entry's compression method — a closed sum, not a loose `Nat`. STORED (0) and DEFLATE
    (8) are the only methods cue module zips use; any other method in the central directory is a
    typed error at parse time, never a silent skip. -/
inductive Method where
  | stored
  | deflate
  deriving Repr, DecidableEq

/-- Decode the 16-bit method field to a `Method`, or `none` for an unsupported method. -/
def Method.ofNat? : Nat → Option Method
  | 0 => some .stored
  | 8 => some .deflate
  | _ => none

/-- A parsed central-directory entry: everything needed to locate, decompress, and verify the
    entry's content. `localOffset` points at the local file header (whose name+extra lengths we
    re-read to find the compressed data start). -/
structure CDEntry where
  name : String
  method : Method
  crc32 : UInt32
  compSize : Nat
  uncompSize : Nat
  localOffset : Nat
  deriving Repr

/-! ## End-Of-Central-Directory + Central Directory parse -/

/-- EOCD signature `PK\x05\x06`, Central Directory header signature `PK\x01\x02`, local file
    header signature `PK\x03\x04`, as little-endian u32 values. -/
def eocdSig : Nat := 0x06054b50
def cdSig : Nat := 0x02014b50
def localSig : Nat := 0x04034b50

/-- Find the EOCD record by scanning backward for its signature (the comment field after it is
    ≤ 65535 bytes and variable-length, so the record isn't at a fixed offset). Returns the EOCD
    offset, or `none` if no archive end is found. Bounded by the scan window. -/
def findEocd (b : ByteArray) : Option Nat := Id.run do
  -- the EOCD is at least 22 bytes; scan from the last possible start backward.
  if b.size < 22 then return none
  let mut i := b.size - 22
  let mut found : Option Nat := none
  -- bound the scan to the max comment size + the record itself.
  let lowerBound := if b.size > 22 + 65535 then b.size - 22 - 65535 else 0
  while found.isNone do
    if u32 b i == eocdSig then
      found := some i
    if i ≤ lowerBound then
      break
    i := i - 1
  return found

/-- Parse the central directory into the entry list. From the EOCD read the entry count and the
    CD offset, then walk `count` central-directory headers, each variable-length (fixed 46-byte
    header + name + extra + comment). A bad method or a malformed header is a typed error. The
    walk is bounded by `count` (a finite EOCD field). -/
def parseCentralDirectory (b : ByteArray) : Except String (List CDEntry) := do
  let eocd ← match findEocd b with
    | some o => pure o
    | none => .error "zip: no End-Of-Central-Directory record (not a zip / truncated)"
  let count := u16 b (eocd + 10)   -- total entries in the central directory
  let cdStart := u32 b (eocd + 16) -- offset of the start of the central directory
  let entries ← go b cdStart count []
  pure entries.reverse
where
  /-- Read `remaining` CD headers starting at `off`, accumulating in reverse. -/
  go (b : ByteArray) (off remaining : Nat) (acc : List CDEntry) :
      Except String (List CDEntry) :=
    match remaining with
    | 0 => .ok acc
    | remaining + 1 =>
      if u32 b off != cdSig then
        .error s!"zip: bad central-directory header signature at offset {off}"
      else
        let methodRaw := u16 b (off + 10)
        match Method.ofNat? methodRaw with
        | none =>
          .error s!"zip: unsupported compression method {methodRaw} (only STORED/DEFLATE)"
        | some method =>
          let crc := UInt32.ofNat (u32 b (off + 16))
          let compSize := u32 b (off + 20)
          let uncompSize := u32 b (off + 24)
          let nameLen := u16 b (off + 28)
          let extraLen := u16 b (off + 30)
          let commentLen := u16 b (off + 32)
          let localOffset := u32 b (off + 42)
          let nameBytes := b.extract (off + 46) (off + 46 + nameLen)
          let name := String.fromUTF8! nameBytes
          let entry : CDEntry :=
            { name, method, crc32 := crc, compSize, uncompSize, localOffset }
          let next := off + 46 + nameLen + extraLen + commentLen
          go b next remaining (entry :: acc)

/-! ## Entry decompression + CRC verification -/

/-- Locate an entry's compressed data span from its local file header (the CD records the local
    header offset, but the data start depends on the LOCAL header's own name+extra lengths,
    which can differ from the CD's). Returns the compressed bytes. -/
def compressedBytes (b : ByteArray) (e : CDEntry) : Except String ByteArray := do
  if u32 b e.localOffset != localSig then
    .error s!"zip: bad local file header signature for {e.name}"
  let nameLen := u16 b (e.localOffset + 26)
  let extraLen := u16 b (e.localOffset + 28)
  let dataStart := e.localOffset + 30 + nameLen + extraLen
  pure (b.extract dataStart (dataStart + e.compSize))

/-- Decompress one entry's content and VERIFY it: STORED ⇒ the raw span; DEFLATE ⇒
    `Inflate.inflate`; then check the CRC-32 against the central-directory value (the integrity
    gate, like the blob digest gate in B3d-4) and the uncompressed size. A mismatch is a typed
    error — corrupt/tampered content is rejected, never returned. -/
def decompressEntry (b : ByteArray) (e : CDEntry) : Except String ByteArray := do
  let comp ← compressedBytes b e
  let content ← match e.method with
    | .stored => pure comp
    | .deflate => Inflate.inflate comp
  if content.size != e.uncompSize then
    .error s!"zip: {e.name} uncompressed size {content.size} ≠ declared {e.uncompSize}"
  let actual := crc32 content
  if actual != e.crc32 then
    .error s!"zip: {e.name} CRC-32 mismatch (got {actual.toNat}, expected {e.crc32.toNat})"
  pure content

/-! ## Top level -/

/-- Whether a central-directory entry is a directory entry (empty name or trailing `/`), which
    cue's `Unzip` skips. -/
def isDirEntry (e : CDEntry) : Bool :=
  e.name.isEmpty || e.name.endsWith "/"

/-- Read a ZIP archive into its `(name, uncompressed-contents)` files in central-directory
    order, decompressing + CRC-verifying each. Directory entries are skipped (matching cue's
    `Unzip`). A malformed archive, unsupported method, or CRC/size mismatch is a typed error. -/
def readZip (b : ByteArray) : Except String (List (String × ByteArray)) := do
  let entries ← parseCentralDirectory b
  let files := entries.filter (fun e => !isDirEntry e)
  files.mapM (fun e => do
    let content ← decompressEntry b e
    pure (e.name, content))

end Zip
end Kue
