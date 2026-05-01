import Kue.Order

namespace Kue

theorem top_subsumes_primitive :
    subsumes .top (.prim (.int 1)) = true := by
  native_decide

theorem kind_subsumes_matching_primitive :
    subsumes (.kind .int) (.prim (.int 1)) = true := by
  native_decide

theorem kind_does_not_subsume_other_primitive :
    subsumes (.kind .int) (.prim (.string "x")) = false := by
  native_decide

theorem primitive_subsumes_identical_primitive :
    subsumes (.prim (.int 1)) (.prim (.int 1)) = true := by
  native_decide

theorem primitive_does_not_subsume_distinct_primitive :
    subsumes (.prim (.int 1)) (.prim (.int 2)) = false := by
  native_decide

theorem value_subsumes_bottom :
    subsumes (.kind .int) .bottom = true := by
  native_decide

theorem disjunction_subsumes_matching_alternative :
    subsumes
      (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))])
      (.prim (.string "b"))
      = true := by
  native_decide

theorem closed_struct_subsumes_matching_struct :
    subsumes
      (.struct [("a", .regular, .kind .int)] false)
      (.struct [("a", .regular, .prim (.int 1))] false)
      = true := by
  native_decide

theorem closed_struct_rejects_extra_field :
    subsumes
      (.struct [("a", .regular, .kind .int)] false)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      = false := by
  native_decide

theorem open_struct_accepts_extra_field :
    subsumes
      (.struct [("a", .regular, .kind .int)] true)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      = true := by
  native_decide

theorem typed_tail_subsumes_matching_extra_field :
    subsumes
      (.structTail [("a", .regular, .kind .int)] (.kind .string))
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      = true := by
  native_decide

theorem typed_tail_rejects_conflicting_extra_field :
    subsumes
      (.structTail [("a", .regular, .kind .int)] (.kind .string))
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true)
      = false := by
  native_decide

theorem string_pattern_subsumes_matching_regular_fields :
    subsumes
      (.structPattern [] (.kind .string) (.kind .int) true)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true)
      = true := by
  native_decide

theorem string_pattern_rejects_conflicting_regular_field :
    subsumes
      (.structPattern [] (.kind .string) (.kind .int) true)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      = false := by
  native_decide

theorem exact_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (.structPattern [] (.prim (.string "a")) (.kind .int) true)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      = true := by
  native_decide

theorem exact_label_pattern_rejects_matching_conflict :
    subsumes
      (.structPattern [] (.prim (.string "a")) (.kind .int) true)
      (.struct [("a", .regular, .prim (.string "x")), ("b", .regular, .prim (.string "x"))] true)
      = false := by
  native_decide

theorem regex_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (.structPattern [] (.stringRegex "^a$") (.kind .int) true)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      = true := by
  native_decide

theorem regex_label_pattern_rejects_matching_conflict :
    subsumes
      (.structPattern [] (.stringRegex "^a$") (.kind .int) true)
      (.struct [("a", .regular, .prim (.string "x")), ("b", .regular, .prim (.string "x"))] true)
      = false := by
  native_decide

theorem regex_wildcard_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (.structPattern [] (.stringRegex "^a.*z$") (.kind .int) true)
      (.struct [("abcz", .regular, .prim (.int 1)), ("abcy", .regular, .prim (.string "skip"))] true)
      = true := by
  native_decide

theorem regex_wildcard_label_pattern_rejects_matching_conflict :
    subsumes
      (.structPattern [] (.stringRegex "^a.*z$") (.kind .int) true)
      (.struct [("abcz", .regular, .prim (.string "bad")), ("abcy", .regular, .prim (.string "skip"))] true)
      = false := by
  native_decide

theorem regex_plus_label_pattern_requires_one_character :
    subsumes
      (.structPattern [] (.stringRegex "^a.+z$") (.kind .int) true)
      (.struct [("az", .regular, .prim (.string "skip")), ("abz", .regular, .prim (.int 2))] true)
      = true := by
  native_decide

theorem regex_question_label_pattern_rejects_matching_conflict :
    subsumes
      (.structPattern [] (.stringRegex "^colou?r$") (.kind .int) true)
      (.struct
        [
          ("color", .regular, .prim (.string "bad")),
          ("colour", .regular, .prim (.int 2)),
          ("colouur", .regular, .prim (.string "skip"))
        ]
        true)
      = false := by
  native_decide

theorem regex_class_label_pattern_subsumes_matching_regular_fields :
    subsumes
      (.structPattern [] (.stringRegex "^[ab]cz$") (.kind .int) true)
      (.struct
        [
          ("acz", .regular, .prim (.int 1)),
          ("bcz", .regular, .prim (.int 2)),
          ("ccz", .regular, .prim (.string "skip"))
        ]
        true)
      = true := by
  native_decide

theorem regex_range_label_pattern_rejects_matching_conflict :
    subsumes
      (.structPattern [] (.stringRegex "^a[0-9]z$") (.kind .int) true)
      (.struct [("a5z", .regular, .prim (.string "bad")), ("axz", .regular, .prim (.string "skip"))] true)
      = false := by
  native_decide

theorem escaped_regex_label_pattern_rejects_matching_conflict :
    subsumes
      (.structPattern [] (.stringRegex "^a\\.z$") (.kind .int) true)
      (.struct [("a.z", .regular, .prim (.string "bad")), ("abz", .regular, .prim (.string "skip"))] true)
      = false := by
  native_decide

theorem closed_regex_pattern_rejects_non_matching_regular_field :
    subsumes
      (.structPattern [] (.stringRegex "^a$") (.kind .int) false)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true)
      = false := by
  native_decide

theorem closed_struct_subsumes_hidden_and_definition_extra_fields :
    subsumes
      (.struct [("a", .regular, .kind .int)] false)
      (.struct
        [
          ("a", .regular, .prim (.int 1)),
          ("_h", .hidden, .prim (.string "secret")),
          ("#D", .definition, .kind .string)
        ]
        true)
      = true := by
  native_decide

theorem closed_regex_pattern_subsumes_hidden_and_definition_extra_fields :
    subsumes
      (.structPattern [] (.stringRegex "^a$") (.kind .int) false)
      (.struct
        [
          ("a", .regular, .prim (.int 1)),
          ("_h", .hidden, .prim (.string "secret")),
          ("#D", .definition, .kind .string)
        ]
        true)
      = true := by
  native_decide

end Kue
