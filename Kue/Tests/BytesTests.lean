import Kue.Format
import Kue.Json
import Kue.Lattice
import Kue.Order
import Kue.Parse

namespace Kue

-- Byte-literal escape lexing (`parseQuotedBytes`). `\xNN`/`\NNN` name ONE raw byte
-- (including ≥ 0x80, held exactly by the `Array UInt8` carrier); `\u`/`\U` are unicode →
-- UTF-8 codepoints (one or more bytes).
private def lexBytes (source : String) : Option (Array UInt8) :=
  match parseQuotedBytes source.toList with
  | .ok (out, []) => some out
  | _ => none

theorem lex_bytes_hex_escape :
    lexBytes "'\\x41\\x42'" = some #[0x41, 0x42] := by native_decide

theorem lex_bytes_control_hex :
    lexBytes "'\\x01ab'" = some #[0x01, 0x61, 0x62] := by native_decide

theorem lex_bytes_octal :
    lexBytes "'\\101'" = some #[0x41] := by native_decide

theorem lex_bytes_unicode_escape :
    lexBytes "'\\u0041'" = some #[0x41] := by native_decide

theorem lex_bytes_named_controls :
    lexBytes "'\\n\\t\\r'" = some #[0x0a, 0x09, 0x0d] := by native_decide

theorem lex_bytes_escaped_quote :
    lexBytes "'\\''" = some #[0x27] := by native_decide

-- Regression: a plain byte literal is unchanged by the escape-decoding path.
theorem lex_bytes_plain_unchanged :
    lexBytes "'abc'" = some #[0x61, 0x62, 0x63] := by native_decide

-- HIGH-BYTE ROUND-TRIP (graduates the `byte-literal-high-byte` wild seed). A `\xff` is the
-- ONE octet 0xFF — distinct from the two-byte UTF-8 form of the codepoint U+00FF (0xC3 0xBF).
theorem lex_bytes_high_byte_hex :
    lexBytes "'\\xff'" = some #[0xff] := by native_decide

-- The octal sibling `'\377'` is the same single byte 0xFF.
theorem lex_bytes_high_byte_octal :
    lexBytes "'\\377'" = some #[0xff] := by native_decide

-- Mixed ASCII + high byte stays one octet per byte, in order.
theorem lex_bytes_mixed_ascii_high :
    lexBytes "'a\\xffb'" = some #[0x61, 0xff, 0x62] := by native_decide

-- A `\u` escape ≥ 0x80 is a CODEPOINT, so it UTF-8-encodes to multiple bytes (U+00FF ⇒
-- 0xC3 0xBF) — distinguishing it from the raw-byte `\xff`.
theorem lex_bytes_unicode_high_multibyte :
    lexBytes "'\\u00ff'" = some #[0xc3, 0xbf] := by native_decide

-- The empty byte literal carries no bytes.
theorem lex_bytes_empty :
    lexBytes "''" = some #[] := by native_decide

-- Byte-context interpolation is not yet implemented: `\(` falls through to a literal `(`,
-- pinning the `byte-literal-interpolation` seed's current (quarantined-red) behavior.
theorem lex_bytes_interp_unimplemented_keeps_literal :
    lexBytes "'\\(1)'" = some #[0x28, 0x31, 0x29] := by native_decide

theorem format_bytes_kind_and_primitive :
    formatValue (.kind .bytes) = "bytes"
      ∧ formatValue (.prim (.bytes (textBytes "abc"))) = "'abc'" := by
  native_decide

-- A high byte formats back to its `\xNN` escape, round-tripping through `parseQuotedBytes`.
theorem format_bytes_high_byte :
    formatValue (.prim (.bytes #[0xff])) = "'\\xff'" := by native_decide

theorem meet_bytes_kind_with_bytes_primitive :
    meet (.kind .bytes) (.prim (.bytes #[0x61, 0x62, 0x63]))
      = .prim (.bytes #[0x61, 0x62, 0x63]) := by
  rfl

theorem meet_string_kind_with_bytes_primitive_bottoms :
    meet (.kind .string) (.prim (.bytes (textBytes "abc")))
      = .bottomWith [.kindConflict .string .bytes] := by
  rfl

theorem bytes_kind_subsumes_bytes_primitive :
    subsumes (.kind .bytes) (.prim (.bytes (textBytes "abc"))) = true := by
  native_decide

theorem string_kind_rejects_bytes_primitive :
    subsumes (.kind .string) (.prim (.bytes (textBytes "abc"))) = false := by
  native_decide

-- Base64 export of a high-byte payload is base64 of the ONE octet 0xFF (`/w==`), the value
-- the `byte-literal-high-byte` seed pins — NOT `w78=` (base64 of the 2-byte UTF-8 form).
theorem export_high_byte_base64 :
    manifestToJson (.prim (.bytes #[0xff])) = "\"/w==\"" := by native_decide

-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @export_high_byte_base64
#check @lex_bytes_interp_unimplemented_keeps_literal

end Kue
