import Kue.Format
import Kue.Lattice
import Kue.Order
import Kue.Parse

namespace Kue

-- Byte-literal escape lexing (`parseQuotedBytes`). A value < 0x80 decodes to the one
-- intended byte; `\x`/`\NNN` are byte-only, `\u`/`\U` are unicode → UTF-8 codepoints.
private def lexBytes (source : String) : Option String :=
  match parseQuotedBytes source.toList with
  | .ok (out, []) => some out
  | _ => none

theorem lex_bytes_hex_escape :
    lexBytes "'\\x41\\x42'" = some "AB" := by native_decide

theorem lex_bytes_control_hex :
    lexBytes "'\\x01ab'" = some (String.mk [Char.ofNat 1, 'a', 'b']) := by native_decide

theorem lex_bytes_octal :
    lexBytes "'\\101'" = some "A" := by native_decide

theorem lex_bytes_unicode_escape :
    lexBytes "'\\u0041'" = some "A" := by native_decide

theorem lex_bytes_named_controls :
    lexBytes "'\\n\\t\\r'" = some (String.mk ['\n', '\t', '\r']) := by native_decide

theorem lex_bytes_escaped_quote :
    lexBytes "'\\''" = some "'" := by native_decide

-- Regression: a plain byte literal is unchanged by the escape-decoding path.
theorem lex_bytes_plain_unchanged :
    lexBytes "'abc'" = some "abc" := by native_decide

-- Byte-context interpolation is not yet implemented: `\(` falls through to a literal `(`,
-- pinning the `byte-literal-interpolation` seed's current (quarantined-red) behavior.
theorem lex_bytes_interp_unimplemented_keeps_literal :
    lexBytes "'\\(1)'" = some "(1)" := by native_decide

theorem format_bytes_kind_and_primitive :
    formatValue (.kind .bytes) = "bytes" ∧ formatValue (.prim (.bytes "abc")) = "'abc'" := by
  native_decide

theorem meet_bytes_kind_with_bytes_primitive :
    meet (.kind .bytes) (.prim (.bytes "abc")) = .prim (.bytes "abc") := by
  rfl

theorem meet_string_kind_with_bytes_primitive_bottoms :
    meet (.kind .string) (.prim (.bytes "abc")) = .bottomWith [.kindConflict .string .bytes] := by
  rfl

theorem bytes_kind_subsumes_bytes_primitive :
    subsumes (.kind .bytes) (.prim (.bytes "abc")) = true := by
  native_decide

theorem string_kind_rejects_bytes_primitive :
    subsumes (.kind .string) (.prim (.bytes "abc")) = false := by
  native_decide



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @string_kind_rejects_bytes_primitive
#check @lex_bytes_interp_unimplemented_keeps_literal

end Kue
