import Kue.Builtin
import Kue.Lattice

namespace Kue

/-! `strings` case-mapping builtins: `ToUpper`/`ToLower` (Unicode simple case mapping over
    the oracle-derived BMP table — see `Kue/CaseTable.lean`) and `ToTitle` (ASCII-bounded —
    its title-case mapping + Unicode word boundary are a separate deferred slice). Mappings
    are cross-checked against the `cue` v0.16.1 oracle. -/

/-! ## ToUpper / ToLower — ASCII (regression: the table covers ASCII, no behavior change) -/

theorem strings_to_upper_lowercases :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "hello world")]
      == .prim (.string "HELLO WORLD")) = true := by
  native_decide

theorem strings_to_upper_already_upper :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "ABC")]
      == .prim (.string "ABC")) = true := by
  native_decide

theorem strings_to_upper_empty :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "")]
      == .prim (.string "")) = true := by
  native_decide

theorem strings_to_upper_digits_punct_unchanged :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "abc123!@#")]
      == .prim (.string "ABC123!@#")) = true := by
  native_decide

theorem strings_to_lower_uppercases :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "Hello WORLD")]
      == .prim (.string "hello world")) = true := by
  native_decide

theorem strings_to_lower_already_lower :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "abc")]
      == .prim (.string "abc")) = true := by
  native_decide

theorem strings_to_lower_empty :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "")]
      == .prim (.string "")) = true := by
  native_decide

theorem strings_to_lower_digits_punct_unchanged :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "ABC123!@#")]
      == .prim (.string "abc123!@#")) = true := by
  native_decide

/-! ## ToUpper / ToLower — Unicode (the BI-1 table). Each mapping cross-checked vs `cue`. -/

/-- Latin-1 supplement round-trip: `é`↔`É` (offset −32, regular range). -/
theorem strings_to_upper_latin1 :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "café")]
      == .prim (.string "CAFÉ")) = true := by
  native_decide

theorem strings_to_lower_latin1 :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "CAFÉ")]
      == .prim (.string "café")) = true := by
  native_decide

/-- Greek round-trip: `αβγ`↔`ΑΒΓ`. -/
theorem strings_to_upper_greek :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "αβγ")]
      == .prim (.string "ΑΒΓ")) = true := by
  native_decide

theorem strings_to_lower_greek :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "ΑΒΓ")]
      == .prim (.string "αβγ")) = true := by
  native_decide

/-- Cyrillic round-trip: `я`↔`Я`. -/
theorem strings_to_upper_cyrillic :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "я")]
      == .prim (.string "Я")) = true := by
  native_decide

theorem strings_to_lower_cyrillic :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "Я")]
      == .prim (.string "я")) = true := by
  native_decide

/-- Irregular singletons the table covers but a fixed-offset rule would miss:
    `µ` (U+00B5 MICRO SIGN) → `Μ` (U+039C, offset +743) and `ÿ` (U+00FF) → `Ÿ`
    (U+0178, offset +121). These justify the full table over algorithmic ranges. -/
theorem strings_to_upper_micro_sign :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "µ")]
      == .prim (.string "Μ")) = true := by
  native_decide

theorem strings_to_upper_y_diaeresis :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "ÿ")]
      == .prim (.string "Ÿ")) = true := by
  native_decide

/-- Coverage boundary (CONFORMS to cue): German `ß` (U+00DF) has NO simple upper mapping —
    cue's `strings.ToUpper` leaves it unchanged (full-folding `ß`→`SS` is length-changing and
    is NOT done by the simple rune map). Pins that Kue does NOT mis-map it. -/
theorem strings_to_upper_sharp_s_unchanged :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "ß")]
      == .prim (.string "ß")) = true := by
  native_decide

/-- Coverage boundary (deliberate identity): runes with no case — CJK ideograph and an
    arrow symbol — pass through unchanged, documenting the table's no-mapping default. -/
theorem strings_to_upper_uncased_unchanged :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "中→")]
      == .prim (.string "中→")) = true := by
  native_decide

/-- Mixed ASCII + multiple non-ASCII scripts in one string: ASCII upper-cases, Latin/Greek/
    Cyrillic map via the table, digits + uncased runes pass through, in one pass. -/
theorem strings_to_upper_mixed_scripts :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "café 123 αβγ я 中")]
      == .prim (.string "CAFÉ 123 ΑΒΓ Я 中")) = true := by
  native_decide

theorem strings_to_lower_mixed_scripts :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "CAFÉ 123 ΑΒΓ Я 中")]
      == .prim (.string "café 123 αβγ я 中")) = true := by
  native_decide

/-! ## ToTitle — ASCII-bounded (unchanged this slice; Unicode title-casing is deferred) -/

/-- `ToTitle` is per-word capitalization — the first letter of each whitespace-delimited
    word — NOT "upper-case every letter". A multi-word lowercase input proves it. -/
theorem strings_to_title_capitalizes_each_word :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "hello world foo")]
      == .prim (.string "Hello World Foo")) = true := by
  native_decide

/-- Already-upper input is left as-is (ToTitle only upper-cases word-initial letters;
    it never lower-cases the rest, distinguishing it from a "capitalize" that downcases). -/
theorem strings_to_title_leaves_upper_word_as_is :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "HELLO WORLD")]
      == .prim (.string "HELLO WORLD")) = true := by
  native_decide

theorem strings_to_title_empty :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "")]
      == .prim (.string "")) = true := by
  native_decide

/-- Word boundary is whitespace ONLY: `-`, `.`, `_`, `/` do NOT start a new word,
    so the letter after them is not capitalized. -/
theorem strings_to_title_non_whitespace_separators_dont_split :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "a-b a.b a_b a/b")]
      == .prim (.string "A-b A.b A_b A/b")) = true := by
  native_decide

/-- A digit is not a word separator: the letter following a digit mid-token is not
    capitalized; the letter after whitespace is. -/
theorem strings_to_title_digit_is_not_separator :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "3 abc a3bc")]
      == .prim (.string "3 Abc A3bc")) = true := by
  native_decide

theorem strings_to_title_leading_whitespace :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "  leading")]
      == .prim (.string "  Leading")) = true := by
  native_decide

/-- ToTitle deferral boundary (still ASCII this slice): a non-ASCII word-initial letter is
    NOT title-cased — `über` stays lowercase. Kue: "über Alles"; cue: "Über Alles".
    Documented divergence (Unicode title-casing is a separate deferred slice — title-case
    mapping ≠ upper, e.g. `ǆ`→`ǅ`, plus `unicode.IsSpace` word boundaries). -/
theorem strings_to_title_non_ascii_passthrough :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "über alles")]
      == .prim (.string "über Alles")) = true := by
  native_decide

/-! ## Argument guards (shared by the case builtins) -/

theorem strings_to_upper_abstract_arg_stays_unresolved :
    (evalBuiltinCall "strings.ToUpper" [.kind .string]
      == .builtinCall "strings.ToUpper" [.kind .string]) = true := by
  native_decide

theorem strings_to_title_non_string_is_bottom :
    (evalBuiltinCall "strings.ToTitle" [.prim (.int 1)]
      == .bottom) = true := by
  native_decide

/-! ## Lookup unit pins (the total binary search directly) -/

/-- A hit returns the mapped code point; a miss returns `none` (identity at the call site).
    Pins both the found and not-found arms of `caseTableLookup` over the real table. -/
theorem case_table_lookup_hit :
    caseTableLookup CaseTable.upperEntries (Char.val 'é') = some (Char.val 'É') := by
  native_decide

theorem case_table_lookup_miss :
    caseTableLookup CaseTable.upperEntries (Char.val '中') = none := by
  native_decide

end Kue
