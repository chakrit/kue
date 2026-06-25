import Kue.Sha256

/-!
# SHA-256 + dirhash `h1:` tests (B3d-3)

`native_decide`/`#guard` pins for the pure SHA-256 core and the `cue.sum` `h1:` dirhash.

Ground truth:
- SHA-256 vectors `""`, `"abc"`, the 56-byte NIST two-block vector: FIPS 180-4 / NIST CSRC.
- Padding-boundary vectors (lengths 0/55/56/63/64/65/119, `'a'` repeated) and the longer
  85-byte mixed vector: computed independently with `shasum -a 256` (an implementation Kue's
  code does not share), so they are a genuine cross-check, not a self-consistency test.
- dirhash `h1:` end-to-end values: reproduced independently from the Go
  `golang.org/x/mod/sumdb/dirhash` `Hash1` algorithm using `shasum -a 256` + `base64` + the
  documented `%x  %s\n` summary line (TWO spaces). Two cases (single- and two-file).

The cue module-zip entry-name convention (BARE module-root-relative path, NOT
`<module>@<version>/`-prefixed — `cuelang.org/go/mod/modzip` `zip.go` `Create`) is documented
in `Kue/Sha256.lean`; `hash1` is name-agnostic so the tests pin it on representative names.
-/

namespace Kue
namespace Sha256

/-- An `n`-byte array of the ASCII byte `'a'` (0x61) — the boundary-vector message generator. -/
def aBytes (n : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.empty
  for _ in [0:n] do
    out := out.push 0x61
  return out

/-! ## NIST / FIPS 180-4 standard vectors (MUST pass exactly) -/

-- Empty input → the canonical empty-string SHA-256.
theorem sha256_empty :
    (hex (sha256String "")
      == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") = true := by
  native_decide

-- "abc" → the FIPS 180-4 §B.1 one-block example.
theorem sha256_abc :
    (hex (sha256String "abc")
      == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") = true := by
  native_decide

-- The 56-byte FIPS 180-4 §B.2 two-block example (forces a second padding block).
theorem sha256_nist_two_block :
    (hex (sha256String "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
      == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1") = true := by
  native_decide

/-! ## Padding boundaries (the one-block↔two-block split — classic bug site)

    Lengths 55/56 straddle the point where the 0x80 + 64-bit length no longer fit in the same
    block; 63/64/65 straddle a full-block boundary. All `'a'`-repeated, pinned vs `shasum`. -/

-- len 0 (covered above by sha256_empty, repeated through aBytes for the generator path).
theorem sha256_len0 :
    (hex (sha256 (aBytes 0))
      == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") = true := by
  native_decide

-- len 55: the largest message that still fits with padding in ONE 64-byte block.
theorem sha256_len55 :
    (hex (sha256 (aBytes 55))
      == "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318") = true := by
  native_decide

-- len 56: the smallest message that forces a SECOND padding block.
theorem sha256_len56 :
    (hex (sha256 (aBytes 56))
      == "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a") = true := by
  native_decide

-- len 63: one byte short of a full block.
theorem sha256_len63 :
    (hex (sha256 (aBytes 63))
      == "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34") = true := by
  native_decide

-- len 64: exactly one full block of input (padding spills into a second block).
theorem sha256_len64 :
    (hex (sha256 (aBytes 64))
      == "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb") = true := by
  native_decide

-- len 65: one byte into the second block.
theorem sha256_len65 :
    (hex (sha256 (aBytes 65))
      == "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0") = true := by
  native_decide

-- len 119: largest single-padding-block fit at the two-input-block boundary (119 = 2*64 - 9).
theorem sha256_len119 :
    (hex (sha256 (aBytes 119))
      == "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb") = true := by
  native_decide

-- A longer 85-byte mixed-content vector (the "longer than the standard short vectors" case),
-- pinned vs `shasum -a 256`.
theorem sha256_longer_mixed :
    (hex (sha256String
        "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.")
      == "d51712a8d1852b5acf942c19caddf168f80120d2f3a72c2d917227fd37f22788") = true := by
  native_decide

/-! ## Digest form + hex helper -/

-- The OCI `sha256:<hex>` descriptor-digest form (digest.FromBytes of the empty blob).
theorem digest_empty :
    (digestString (aBytes 0)
      == "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") = true := by
  native_decide

-- hex is lowercase and fixed 2 chars/byte over a known pattern.
#guard hex (ByteArray.mk #[0x00, 0x0f, 0xff, 0xa5]) == "000fffa5"
#guard hexDigit 0 == '0'
#guard hexDigit 9 == '9'
#guard hexDigit 10 == 'a'
#guard hexDigit 15 == 'f'

/-! ## 32-bit primitives (spot pins for the FIPS functions) -/

#guard rotr 0x12345678 8 == 0x78123456
#guard rotr 0x00000001 1 == 0x80000000
#guard ch 0xffffffff 0xaaaaaaaa 0x55555555 == 0xaaaaaaaa   -- x all-ones ⇒ selects y
#guard ch 0x00000000 0xaaaaaaaa 0x55555555 == 0x55555555   -- x all-zero ⇒ selects z
#guard maj 0xffffffff 0xffffffff 0x00000000 == 0xffffffff   -- two-of-three ones
#guard maj 0x00000000 0x00000000 0xffffffff == 0x00000000

/-! ## dirhash `Hash1` structural pieces -/

-- The inner per-file line: lowerhex(sha256(contents)) ++ TWO spaces ++ name ++ "\n".
-- contents = "a: 1\n", name = "foo.cue" → inner sha256 pinned vs shasum.
theorem hash1Line_shape :
    (hash1Line "foo.cue" "a: 1\n".toUTF8
      == "37b128c59f1f5097f73f82691cb519f1f568667faab5ced1b4ab979d36837eae  foo.cue\n") = true := by
  native_decide

-- The base64-std step round-trips through the reused base64Encode encoder: the empty SHA-256
-- digest (32 bytes) base64-encodes to its known std form.
theorem hash1_base64_step :
    (base64Encode (sha256String "").toList
      == "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=") = true := by
  native_decide

/-! ## dirhash `h1:` end-to-end (independent Go-algorithm ground truth)

    Reproduced with `shasum -a 256` + `base64` over the documented `%x  %s\n` summary. -/

-- Single file: name "cue.mod/module.cue", contents 'module "x"\n'.
theorem hash1_single_file :
    (hash1 [("cue.mod/module.cue", "module \"x\"\n".toUTF8)]
      == "h1:ftG4xWQPV4pZ9dJyz1U9yMplIdnOoyX/hdskb0yd9w8=") = true := by
  native_decide

-- Two files, GIVEN unsorted (foo.cue before cue.mod/module.cue) to exercise the byte-order
-- sort: cue.mod/module.cue ('c'=0x63) sorts before foo.cue ('f'=0x66).
--   cue.mod/module.cue contents = 'module "foo.example@v0"\n'
--   foo.cue            contents = 'a: 1\n'
theorem hash1_two_files_sorted :
    (hash1 [("foo.cue", "a: 1\n".toUTF8),
            ("cue.mod/module.cue", "module \"foo.example@v0\"\n".toUTF8)]
      == "h1:P7/mTCFrvF77thKflcmV8eVMxjYU7kC0InTdJLeRHRI=") = true := by
  native_decide

-- Sort is by name, so passing the same two files already-sorted yields the identical h1.
theorem hash1_order_independent :
    (hash1 [("foo.cue", "a: 1\n".toUTF8),
            ("cue.mod/module.cue", "module \"foo.example@v0\"\n".toUTF8)]
      == hash1 [("cue.mod/module.cue", "module \"foo.example@v0\"\n".toUTF8),
                ("foo.cue", "a: 1\n".toUTF8)]) = true := by
  native_decide

end Sha256
end Kue
