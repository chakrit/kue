import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

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

end Kue
