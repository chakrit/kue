/-!
# DEFLATE inflate (RFC 1951, PURE)

The decompressor the B3d registry-fetch track needs: a total, IO-free `ByteArray →
Except String ByteArray` implementing RFC 1951 DEFLATE. cue module zips store every entry
DEFLATE-compressed (`unzip -v` shows `Defl:N`), so the pure-Lean ZIP reader (`Kue/Zip.lean`)
cannot get away with STORED-only — it needs real inflate.

Decision: pure Lean, NOT an `unzip` subprocess
(`docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md` extends to extraction).
Deterministic, total, fully offline-testable, no runtime dependency, composes with the
`cue.sum` dirhash. The curl subprocess is the ONLY impurity in the fetch path; the transform
of the verified bytes is pure.

## Totality (no `partial`)

DEFLATE has no static structural recursion bound — a stream is a sequence of blocks, each a
sequence of symbols. We make every loop total with explicit fuel:

- **The symbol loop** within a Huffman block is bounded by `fuel := input.size * 8 + 1`: every
  iteration consumes at least one bit (a Huffman code is ≥ 1 bit, a literal advances the bit
  cursor, a back-reference reads length+distance codes), and the bit cursor never exceeds
  `input.size * 8`. So the loop cannot run more than `input.size * 8` productive iterations;
  the `+1` covers the terminating end-of-block symbol read. Running out of fuel ⇒ a malformed
  stream (truncated / no end-of-block) ⇒ `Except.error`, never a hang.
- **The block loop** is bounded by `input.size + 1`: every block reads at least its 3-bit
  header, so ≤ `input.size * 8 / 3 < input.size + 1` blocks (loosely, `input.size + 1` is a
  safe over-bound). The final block (BFINAL=1) ends it earlier in practice.
- **Huffman decode** walks at most `maxBits ≤ 15` bits — a literal `Nat`-recursion over a
  decreasing remaining-bit count, structurally total.

Out-of-fuel is unreachable on well-formed input (the end-of-block symbol always arrives first)
but yields a typed error rather than a `partial` non-termination hole.
-/

namespace Kue
namespace Inflate

/-! ## Bit reader (LSB-first, RFC 1951 §3.1.1)

    DEFLATE packs bits into bytes starting with the least-significant bit. Huffman codes are
    the exception: their bits are packed MSB-first WITHIN the code, so the decoder reverses
    them as it walks (handled in `decodeSymbol`). The reader tracks a byte array, a byte
    cursor, and a bit-within-byte cursor. -/

/-- The bit-reader state: the backing `data`, a current bit position `pos` (in bits from the
    start), measured against `data.size * 8`. Past-end reads are detected by the caller via
    `pos`; primitives that read past the end return 0 bits (a malformed/truncated stream is
    caught structurally by running out of fuel or a bad Huffman code). -/
structure BitReader where
  data : ByteArray
  /-- Absolute bit position from the start of `data` (byte = pos/8, bit-in-byte = pos%8). -/
  pos : Nat

namespace BitReader

/-- Total bit count of the backing data. -/
def bitLen (r : BitReader) : Nat := r.data.size * 8

/-- Read one bit at the current position (LSB-first within each byte), returning the bit and
    the advanced reader. A read past the end yields 0 (the stream is then malformed; fuel /
    Huffman validity catches it). -/
def readBit (r : BitReader) : Bool × BitReader :=
  let byteIdx := r.pos / 8
  let bitIdx := r.pos % 8
  let bit :=
    if h : byteIdx < r.data.size then
      ((r.data[byteIdx]'h).toNat >>> bitIdx) &&& 1 == 1
    else
      false
  (bit, { r with pos := r.pos + 1 })

/-- Read `n` bits LSB-first as a `Nat` (bit 0 is the first bit read = least significant).
    `n ≤ 32` in all DEFLATE uses; structural recursion on `n`. -/
def readBits (r : BitReader) (n : Nat) : Nat × BitReader :=
  go r n 0 0
where
  go (r : BitReader) (n acc shift : Nat) : Nat × BitReader :=
    match n with
    | 0 => (acc, r)
    | n + 1 =>
      let (bit, r) := r.readBit
      let acc := if bit then acc ||| (1 <<< shift) else acc
      go r n acc (shift + 1)

/-- Skip to the next byte boundary (used before a STORED block's LEN/NLEN, RFC 1951 §3.2.4). -/
def alignByte (r : BitReader) : BitReader :=
  let rem := r.pos % 8
  if rem == 0 then r else { r with pos := r.pos + (8 - rem) }

/-- Read one whole byte at the current (byte-aligned) position, advancing 8 bits. Used for a
    STORED block's raw bytes after `alignByte`. Past-end yields 0. -/
def readByte (r : BitReader) : UInt8 × BitReader :=
  let byteIdx := r.pos / 8
  let b := if h : byteIdx < r.data.size then r.data[byteIdx]'h else 0
  (b, { r with pos := r.pos + 8 })

end BitReader

/-! ## Huffman tables (RFC 1951 §3.2.2)

    A canonical Huffman code is fully determined by the per-symbol code lengths. We decode by
    walking bits MSB-first within the code, maintaining `(code, len)`, and using the
    first-code-per-length / count-per-length tables to map a completed code to its symbol. This
    is the standard "canonical decode" — no explicit tree, `O(maxBits)` per symbol. -/

/-- A canonical Huffman decoding table built from a list of code lengths (index = symbol, value
    = bit length, 0 = symbol absent). `maxBits` is the longest code length present.

    `firstCode[l]` is the numeric value of the first canonical code of length `l`; `firstSym[l]`
    is the index into `symbols` of the first symbol of length `l`; `count[l]` is how many
    symbols have length `l`. `symbols` lists the symbols of each length in ascending symbol
    order, grouped by ascending length — exactly the canonical assignment order. -/
structure Huffman where
  counts : Array Nat      -- counts[l] = number of codes of length l (l : 0..maxBits)
  firstCode : Array Nat   -- firstCode[l] = first canonical code value of length l
  firstSym : Array Nat    -- firstSym[l] = offset into `symbols` of the first length-l symbol
  symbols : Array Nat     -- symbols grouped by length, ascending symbol within each length
  maxBits : Nat
  deriving Repr

namespace Huffman

/-- Build a canonical Huffman table from per-symbol code lengths. RFC 1951 §3.2.2 algorithm:
    count codes per length, compute the first code per length (`firstCode[l] = (firstCode[l-1] +
    count[l-1]) << 1`), then list symbols grouped by length in ascending symbol order. Returns a
    table that decodes exactly the codes implied by `lengths`. -/
def build (lengths : Array Nat) : Huffman := Id.run do
  let maxBits := lengths.foldl Nat.max 0
  let mut counts : Array Nat := Array.replicate (maxBits + 1) 0
  for len in lengths do
    if len > 0 then
      counts := counts.set! len (counts[len]! + 1)
  -- first canonical code value per length
  let mut firstCode : Array Nat := Array.replicate (maxBits + 1) 0
  let mut code := 0
  for len in [1:maxBits + 1] do
    code := (code + counts[len - 1]!) <<< 1
    firstCode := firstCode.set! len code
  -- first symbol offset per length + the grouped symbol list
  let mut firstSym : Array Nat := Array.replicate (maxBits + 1) 0
  let mut off := 0
  for len in [1:maxBits + 1] do
    firstSym := firstSym.set! len off
    off := off + counts[len]!
  -- place symbols: for each symbol in ascending order, append into its length's slot
  let mut symbols : Array Nat := Array.replicate off 0
  let mut nextSlot : Array Nat := firstSym
  for sym in [0:lengths.size] do
    let len := lengths[sym]!
    if len > 0 then
      let slot := nextSlot[len]!
      symbols := symbols.set! slot sym
      nextSlot := nextSlot.set! len (slot + 1)
  return { counts, firstCode, firstSym, symbols, maxBits }

/-- Decode one symbol via the canonical algorithm: read bits MSB-first into a growing `code`,
    and at each length `len` test whether `code` falls in the `count[len]` codes starting at
    `firstCode[len]`; if so the symbol is `symbols[firstSym[len] + (code - firstCode[len])]`.
    `none` on an invalid code (no length matched within `maxBits` bits) — a malformed stream.
    `len` rises each step, bounded by `maxBits`, so it terminates. -/
def decodeGo (t : Huffman) (r : BitReader) (code : Nat) (len : Nat) :
    Option (Nat × BitReader) :=
  if len > t.maxBits then none
  else
    let (bit, r) := r.readBit
    let code := (code <<< 1) ||| (if bit then 1 else 0)
    let cnt := t.counts[len]!
    let first := t.firstCode[len]!
    if cnt > 0 && code >= first && code < first + cnt then
      let idx := t.firstSym[len]! + (code - first)
      some (t.symbols[idx]!, r)
    else
      decodeGo t r code (len + 1)
  termination_by t.maxBits + 1 - len

def decode (t : Huffman) (r : BitReader) : Option (Nat × BitReader) :=
  decodeGo t r 0 1

end Huffman

open BitReader Huffman

/-! ## Length / distance base tables (RFC 1951 §3.2.5)

    Length codes 257..285 and distance codes 0..29 each carry a base value plus a number of
    extra LSB-first bits added to the base. These tables are the spec's §3.2.5 Tables verbatim. -/

/-- Length base values for length symbols 257..285 (index = symbol - 257). -/
def lengthBase : Array Nat := #[
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
  131, 163, 195, 227, 258]

/-- Extra bits for length symbols 257..285 (index = symbol - 257). -/
def lengthExtra : Array Nat := #[
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]

/-- Distance base values for distance symbols 0..29. -/
def distBase : Array Nat := #[
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
  2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]

/-- Extra bits for distance symbols 0..29. -/
def distExtra : Array Nat := #[
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12,
  13, 13]

/-! ## Fixed Huffman tables (RFC 1951 §3.2.6) -/

/-- The fixed literal/length code lengths: 0..143 → 8, 144..255 → 9, 256..279 → 7, 280..287 → 8. -/
def fixedLitLengths : Array Nat := Id.run do
  let mut a : Array Nat := Array.replicate 288 0
  for i in [0:144] do a := a.set! i 8
  for i in [144:256] do a := a.set! i 9
  for i in [256:280] do a := a.set! i 7
  for i in [280:288] do a := a.set! i 8
  return a

/-- The fixed distance code lengths: all 30 (well, 32) distance codes are 5 bits. -/
def fixedDistLengths : Array Nat := Array.replicate 30 5

/-! ## Symbol decode loop within a Huffman block -/

/-- The code-length-code symbol order for a dynamic block's preamble (RFC 1951 §3.2.7). -/
def clcOrder : Array Nat := #[16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

/-- Copy `len` bytes from `dist` bytes back in `out` (an LZ77 back-reference, RFC 1951 §3.2.3).
    Overlapping copies are legal and common (e.g. `dist=1` run-length-fills): we copy
    byte-by-byte so each appended byte is visible to the next copy. Returns the extended `out`,
    or `none` if `dist` points before the start of `out` (a malformed stream). `len` bounds the
    recursion. -/
def copyBackref (out : ByteArray) (dist len : Nat) : Option ByteArray :=
  if dist == 0 || dist > out.size then none
  else go out len
where
  go (out : ByteArray) (len : Nat) : Option ByteArray :=
    match len with
    | 0 => some out
    | len + 1 =>
      -- read from `dist` bytes before the current end; `out.size ≥ dist` holds by induction
      -- (we only ever append, so size grows; the initial guard ensures dist ≤ size).
      let src := out.size - dist
      let b := out[src]!
      go (out.push b) len

/-- Decompress one Huffman block (fixed or dynamic) given the literal/length table `lit` and
    the distance table `dist`, appending to `out` and starting at reader `r`. Stops at the
    end-of-block symbol (256). `fuel` bounds the symbol loop (see module header): every
    iteration consumes ≥ 1 bit and the reader cannot advance past `bitLen`, so `bitLen + 1`
    iterations suffice; exhausting fuel ⇒ a truncated/no-EOB stream ⇒ error. -/
def decompressBlock (lit dist : Huffman) (r : BitReader) (out : ByteArray) :
    Except String (BitReader × ByteArray) :=
  go r out (r.bitLen + 1)
where
  go (r : BitReader) (out : ByteArray) (fuel : Nat) :
      Except String (BitReader × ByteArray) :=
    match fuel with
    | 0 => .error "inflate: block exhausted fuel (truncated or missing end-of-block)"
    | fuel + 1 =>
      match lit.decode r with
      | none => .error "inflate: invalid literal/length code"
      | some (sym, r) =>
        if sym < 256 then
          go r (out.push (UInt8.ofNat sym)) fuel
        else if sym == 256 then
          .ok (r, out)
        else if sym ≤ 285 then
          let li := sym - 257
          let (extra, r) := r.readBits lengthExtra[li]!
          let length := lengthBase[li]! + extra
          match dist.decode r with
          | none => .error "inflate: invalid distance code"
          | some (dsym, r) =>
            if dsym ≥ distBase.size then
              .error s!"inflate: distance symbol {dsym} out of range"
            else
              let (dextra, r) := r.readBits distExtra[dsym]!
              let distance := distBase[dsym]! + dextra
              match copyBackref out distance length with
              | none => .error s!"inflate: back-reference distance {distance} exceeds output"
              | some out => go r out fuel
        else
          .error s!"inflate: literal/length symbol {sym} out of range"

/-! ## Block dispatch + top level -/

/-- Read a dynamic block's Huffman tables from the §3.2.7 preamble: HLIT/HDIST/HCLEN counts,
    the code-length-code lengths (in `clcOrder`), then the run-length-encoded literal+distance
    code lengths decoded via the code-length-code Huffman table. Returns the two tables and the
    advanced reader, or an error on a malformed preamble. -/
def readDynamicTables (r : BitReader) : Except String (Huffman × Huffman × BitReader) :=
  let (hlit, r) := r.readBits 5
  let (hdist, r) := r.readBits 5
  let (hclen, r) := r.readBits 4
  let numLit := hlit + 257
  let numDist := hdist + 1
  let numClc := hclen + 4
  Id.run do
    -- read the code-length-code lengths into clcOrder positions
    let mut clcLens : Array Nat := Array.replicate 19 0
    let mut r := r
    for i in [0:numClc] do
      let (v, r') := r.readBits 3
      r := r'
      clcLens := clcLens.set! clcOrder[i]! v
    let clcTable := Huffman.build clcLens
    -- decode numLit + numDist code lengths via run-length symbols 0..18
    let total := numLit + numDist
    let mut lens : Array Nat := #[]
    let mut prev := 0
    let mut fuel := total + 1   -- each iteration appends ≥ 1 length; bounded by `total`
    let mut err : Option String := none
    while lens.size < total && fuel > 0 && err.isNone do
      fuel := fuel - 1
      match clcTable.decode r with
      | none => err := some "inflate: invalid code-length code in dynamic preamble"
      | some (sym, r') =>
        r := r'
        if sym < 16 then
          lens := lens.push sym
          prev := sym
        else if sym == 16 then
          let (rep, r') := r.readBits 2
          r := r'
          for _ in [0:rep + 3] do lens := lens.push prev
        else if sym == 17 then
          let (rep, r') := r.readBits 3
          r := r'
          for _ in [0:rep + 3] do lens := lens.push 0
          prev := 0
        else  -- sym == 18
          let (rep, r') := r.readBits 7
          r := r'
          for _ in [0:rep + 11] do lens := lens.push 0
          prev := 0
    if let some e := err then
      return .error e
    if lens.size < total then
      return .error "inflate: dynamic code lengths underflowed"
    let litLens := lens.extract 0 numLit
    let distLens := lens.extract numLit total
    return .ok (Huffman.build litLens, Huffman.build distLens, r)

/-- Read + emit a STORED (uncompressed) block: align to a byte, read LEN/NLEN, verify
    `NLEN = ~LEN`, then copy `LEN` raw bytes. RFC 1951 §3.2.4. -/
def storedBlock (r : BitReader) (out : ByteArray) :
    Except String (BitReader × ByteArray) :=
  let r := r.alignByte
  let (len, r) := r.readBits 16
  let (nlen, r) := r.readBits 16
  if (len ^^^ 0xFFFF) != nlen then
    .error "inflate: STORED block LEN/NLEN mismatch"
  else Id.run do
    let mut r := r
    let mut out := out
    for _ in [0:len] do
      let (b, r') := r.readByte
      r := r'
      out := out.push b
    return .ok (r, out)

/-- Inflate a raw DEFLATE stream (RFC 1951): loop over blocks until BFINAL. Each block reads a
    3-bit header (BFINAL + 2-bit BTYPE), then dispatches on BTYPE: 0 = STORED, 1 = fixed
    Huffman, 2 = dynamic Huffman, 3 = reserved (error). The block loop is bounded by
    `data.size + 1` (every block reads ≥ 3 bits; see module header). -/
def inflate (data : ByteArray) : Except String ByteArray :=
  let fixedLit := Huffman.build fixedLitLengths
  let fixedDist := Huffman.build fixedDistLengths
  go { data, pos := 0 } ByteArray.empty (data.size + 1) fixedLit fixedDist
where
  go (r : BitReader) (out : ByteArray) (fuel : Nat)
     (fixedLit fixedDist : Huffman) : Except String ByteArray :=
    match fuel with
    | 0 => .error "inflate: block count exhausted fuel (malformed stream)"
    | fuel + 1 =>
      let (bfinal, r) := r.readBit
      let (btype, r) := r.readBits 2
      let stepResult : Except String (BitReader × ByteArray) :=
        match btype with
        | 0 => storedBlock r out
        | 1 => decompressBlock fixedLit fixedDist r out
        | 2 =>
          match readDynamicTables r with
          | .error e => .error e
          | .ok (lit, dist, r) => decompressBlock lit dist r out
        | _ => .error "inflate: reserved block type (BTYPE=3)"
      match stepResult with
      | .error e => .error e
      | .ok (r, out) =>
        if bfinal then .ok out
        else go r out fuel fixedLit fixedDist

end Inflate
end Kue
