import Kue.Format
import Kue.Lattice
import Kue.Manifest
import Kue.Order

namespace Kue

theorem format_closed_list :
    formatValue (.list [.prim (.int 1), .prim (.string "x")]) = "[1, \"x\"]" := by
  native_decide

theorem format_open_list_tail :
    formatValue (.listTail [.kind .int] (.kind .string)) = "[int, ...string]" := by
  native_decide

theorem meet_lists_elementwise :
    meet
      (.list [.kind .int, .kind .string])
      (.list [.prim (.int 1), .prim (.string "x")])
      = .list [.prim (.int 1), .prim (.string "x")] := by
  rfl

theorem meet_lists_preserves_element_bottom :
    meet
      (.list [.kind .int])
      (.list [.prim (.string "x")])
      = .list [.bottomWith [.kindConflict .int .string]] := by
  rfl

theorem meet_lists_different_lengths_bottom :
    meet
      (.list [.kind .int])
      (.list [.prim (.int 1), .prim (.int 2)])
      = .bottom := by
  rfl

theorem meet_open_list_tail_with_longer_closed_list :
    meet
      (.listTail [.kind .int] (.kind .string))
      (.list [.prim (.int 1), .prim (.string "x"), .prim (.string "y")])
      = .list [.prim (.int 1), .prim (.string "x"), .prim (.string "y")] := by
  rfl

theorem meet_open_list_tail_preserves_extra_bottom :
    meet
      (.listTail [.kind .int] (.kind .string))
      (.list [.prim (.int 1), .prim (.int 2)])
      = .list [.prim (.int 1), .bottomWith [.kindConflict .string .int]] := by
  rfl

theorem meet_struct_field_open_list_tail_with_longer_closed_list :
    meet
      (.struct [⟨"x", .regular, .listTail [.kind .int] (.kind .string)⟩] true)
      (.struct [⟨"x", .regular, .list [.prim (.int 1), .prim (.string "x")]⟩] true)
      = .struct [⟨"x", .regular, .list [.prim (.int 1), .prim (.string "x")]⟩] true := by
  rfl

theorem meet_struct_field_open_list_tail_preserves_extra_bottom :
    meet
      (.struct [⟨"x", .regular, .listTail [.kind .int] (.kind .string)⟩] true)
      (.struct [⟨"x", .regular, .list [.prim (.int 1), .prim (.int 2)]⟩] true)
      = .struct [⟨"x", .regular, .list [.prim (.int 1), .bottomWith [.kindConflict .string .int]]⟩] true := by
  rfl

theorem meet_struct_field_closed_list_uses_list_meet :
    meet
      (.struct [⟨"x", .regular, .list [.kind .int, .kind .string]⟩] true)
      (.struct [⟨"x", .regular, .list [.prim (.int 1), .prim (.string "x")]⟩] true)
      = .struct [⟨"x", .regular, .list [.prim (.int 1), .prim (.string "x")]⟩] true := by
  rfl

theorem meet_list_item_disjunction_distributes :
    meet
      (.list [.disj [(.regular, .kind .int), (.regular, .kind .string)]])
      (.list [.prim (.int 1)])
      = .list [.prim (.int 1)] := by
  rfl

theorem meet_open_list_tail_rejects_short_closed_list :
    meet
      (.listTail [.kind .int, .kind .string] (.kind .bool))
      (.list [.prim (.int 1)])
      = .bottom := by
  rfl

theorem list_subsumes_matching_items :
    subsumes
      (.list [.kind .int, .kind .string])
      (.list [.prim (.int 1), .prim (.string "x")])
      = true := by
  native_decide

theorem list_rejects_different_length :
    subsumes
      (.list [.kind .int])
      (.list [.prim (.int 1), .prim (.int 2)])
      = false := by
  native_decide

theorem open_list_tail_subsumes_matching_extra_items :
    subsumes
      (.listTail [.kind .int] (.kind .string))
      (.list [.prim (.int 1), .prim (.string "x"), .prim (.string "y")])
      = true := by
  native_decide

theorem open_list_tail_rejects_conflicting_extra_item :
    subsumes
      (.listTail [.kind .int] (.kind .string))
      (.list [.prim (.int 1), .prim (.int 2)])
      = false := by
  native_decide

/-! ### List-embedding-in-struct (`meet(struct, list)`) semantics — CUE v0.16.1

A struct whose members are all non-output (hidden/definition/optional/let) embedding a
list IS that list (an `embeddedList` carrying the surviving decls). A regular/required
field present makes it a genuine struct/list conflict (bottom). Oracle-matched. -/

/-- Only-non-output struct meet a list → the list, with the decl preserved. -/
theorem meet_hidden_struct_list_is_embedded_list :
    (meet (.struct [⟨"#a", .definition, .prim (.int 1)⟩] true)
          (.list [.prim (.int 1), .prim (.int 2)])
      == .embeddedList [.prim (.int 1), .prim (.int 2)] none [⟨"#a", .definition, .prim (.int 1)⟩])
      = true := by native_decide

/-- A regular (output) field present → genuine conflict. -/
theorem meet_regular_struct_list_is_bottom :
    isBottom (meet (.struct [⟨"a", .regular, .prim (.int 1)⟩] true)
                   (.list [.prim (.int 1), .prim (.int 2)]))
      = true := by native_decide

/-- A required field present → genuine conflict. -/
theorem meet_required_struct_list_is_bottom :
    isBottom (meet (.struct [⟨"a", .required, .kind .int⟩] true)
                   (.list [.prim (.int 1), .prim (.int 2)]))
      = true := by native_decide

/-- Optional fields are non-output → the list survives. -/
theorem meet_optional_struct_list_is_embedded_list :
    (meet (.struct [⟨"a", .optional, .kind .int⟩] true)
          (.list [.prim (.int 1), .prim (.int 2)])
      == .embeddedList [.prim (.int 1), .prim (.int 2)] none [⟨"a", .optional, .kind .int⟩])
      = true := by native_decide

/-- Empty struct (no members at all) embedding a list → the bare list (no decls). -/
theorem meet_empty_struct_list_is_embedded_list :
    (meet (.struct [] true) (.list [.prim (.int 7)])
      == .embeddedList [.prim (.int 7)] none [])
      = true := by native_decide

/-- Open list embed: `[...]` is `listTail [] top` → `embeddedList [] (some top)`. -/
theorem meet_hidden_struct_open_list :
    (meet (.struct [⟨"#a", .definition, .prim (.int 1)⟩] true)
          (.listTail [] .top)
      == .embeddedList [] (some .top) [⟨"#a", .definition, .prim (.int 1)⟩])
      = true := by native_decide

/-- Meet of two embeddedLists merges decls and meets the lists (`[...int] & [1,2]`). -/
theorem meet_two_embedded_lists :
    (meet (.embeddedList [] (some (.kind .int)) [⟨"#a", .definition, .prim (.int 1)⟩])
          (.embeddedList [.prim (.int 1), .prim (.int 2)] none [⟨"#b", .definition, .prim (.int 2)⟩])
      == .embeddedList [.prim (.int 1), .prim (.int 2)] none
           [⟨"#a", .definition, .prim (.int 1)⟩, ⟨"#b", .definition, .prim (.int 2)⟩])
      = true := by native_decide

/-- An embeddedList whose list conflicts a concrete element carries an element bottom
    (matching `cue`'s `x.0: conflicting values` and the export error). -/
theorem meet_embedded_list_conflicting_elements :
    containsBottom (meet (.embeddedList [.prim (.int 1)] none [])
                         (.embeddedList [.prim (.int 9)] none []))
      = true := by native_decide

/-- An embeddedList still manifests as its list (decls and open tail dropped). -/
theorem manifest_embedded_list_is_list :
    (manifest (.embeddedList [.prim (.int 1), .prim (.int 2)] (some .top)
                 [⟨"#a", .definition, .prim (.int 1)⟩])).toOption
      == some (.list [.prim (.int 1), .prim (.int 2)])
      := by native_decide

end Kue
