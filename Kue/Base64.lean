namespace Kue

/-- Standard-base64 alphabet (RFC 4648), index 0–63. -/
def base64Alphabet : Array Char :=
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".toList.toArray

/-- Standard padded base64 of `bytes` (RFC 4648), matching Go's `base64.StdEncoding`.
    Full 3-byte groups emit 4 symbols; a trailing 1- or 2-byte group emits 2 or 3
    symbols plus `=` padding to a 4-symbol quantum. -/
def base64Encode (bytes : List UInt8) : String := Id.run do
  let mut out : Array Char := #[]
  let arr := bytes.toArray
  let mut i := 0
  while i + 3 <= arr.size do
    let b0 := arr[i]!.toNat
    let b1 := arr[i + 1]!.toNat
    let b2 := arr[i + 2]!.toNat
    out := out.push base64Alphabet[b0 >>> 2]!
    out := out.push base64Alphabet[((b0 &&& 0x03) <<< 4) ||| (b1 >>> 4)]!
    out := out.push base64Alphabet[((b1 &&& 0x0f) <<< 2) ||| (b2 >>> 6)]!
    out := out.push base64Alphabet[b2 &&& 0x3f]!
    i := i + 3
  let remaining := arr.size - i
  if remaining == 1 then
    let b0 := arr[i]!.toNat
    out := out.push base64Alphabet[b0 >>> 2]!
    out := out.push base64Alphabet[(b0 &&& 0x03) <<< 4]!
    out := out.push '='
    out := out.push '='
  else if remaining == 2 then
    let b0 := arr[i]!.toNat
    let b1 := arr[i + 1]!.toNat
    out := out.push base64Alphabet[b0 >>> 2]!
    out := out.push base64Alphabet[((b0 &&& 0x03) <<< 4) ||| (b1 >>> 4)]!
    out := out.push base64Alphabet[(b1 &&& 0x0f) <<< 2]!
    out := out.push '='
  return String.ofList out.toList

/-- The standard-base64 decode value of a symbol (0–63), or `none` for a non-alphabet char.
    `=` padding is handled by the decoder, not here. -/
def base64DecodeChar (c : Char) : Option Nat :=
  if 'A' ≤ c && c ≤ 'Z' then some (c.toNat - 'A'.toNat)
  else if 'a' ≤ c && c ≤ 'z' then some (c.toNat - 'a'.toNat + 26)
  else if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat + 52)
  else if c == '+' then some 62
  else if c == '/' then some 63
  else none

/-- Decode standard padded base64 (RFC 4648, Go `base64.StdEncoding`) into raw bytes. Total:
    rejects (`none`) any input whose length is not a multiple of 4, that contains a non-alphabet
    character outside the trailing `=` padding, or with malformed/over-long padding. Round-trips
    `base64Encode`. ASCII whitespace is NOT tolerated — a docker `auth` field is canonical base64. -/
def base64Decode (s : String) : Option (List UInt8) := Id.run do
  let cs := s.toList
  if cs.length % 4 != 0 || cs.length == 0 then
    return none
  let mut out : Array UInt8 := #[]
  let arr := cs.toArray
  let mut i := 0
  while i < arr.size do
    let c0 := arr[i]!
    let c1 := arr[i + 1]!
    let c2 := arr[i + 2]!
    let c3 := arr[i + 3]!
    -- Padding (`=`) is only legal in the final quantum's last two positions.
    let isLast := i + 4 == arr.size
    match base64DecodeChar c0, base64DecodeChar c1 with
    | some v0, some v1 =>
        if c3 == '=' then
          if !isLast then return none
          if c2 == '=' then
            -- One output byte; `xxxxxx xx0000`.
            if v1 &&& 0x0f != 0 then return none   -- non-zero discarded bits
            out := out.push (UInt8.ofNat ((v0 <<< 2) ||| (v1 >>> 4)))
          else
            match base64DecodeChar c2 with
            | some v2 =>
                if v2 &&& 0x03 != 0 then return none
                out := out.push (UInt8.ofNat ((v0 <<< 2) ||| (v1 >>> 4)))
                out := out.push (UInt8.ofNat (((v1 &&& 0x0f) <<< 4) ||| (v2 >>> 2)))
            | none => return none
        else
          match base64DecodeChar c2, base64DecodeChar c3 with
          | some v2, some v3 =>
              out := out.push (UInt8.ofNat ((v0 <<< 2) ||| (v1 >>> 4)))
              out := out.push (UInt8.ofNat (((v1 &&& 0x0f) <<< 4) ||| (v2 >>> 2)))
              out := out.push (UInt8.ofNat (((v2 &&& 0x03) <<< 6) ||| v3))
          | _, _ => return none
    | _, _ => return none
    i := i + 4
  return some out.toList

/-- Decode base64 to a UTF-8 `String` (for the docker `auth` field, which is `user:pass`).
    `none` if the base64 is malformed or the decoded bytes are not valid UTF-8. -/
def base64DecodeString (s : String) : Option String :=
  match base64Decode s with
  | some bytes => String.fromUTF8? (ByteArray.mk bytes.toArray)
  | none => none

end Kue
