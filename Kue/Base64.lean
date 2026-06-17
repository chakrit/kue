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

end Kue
