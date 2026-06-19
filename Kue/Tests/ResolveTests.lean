import Kue.Eval
import Kue.Resolve

namespace Kue

theorem resolve_same_struct_reference_to_binding_id :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_reference_uses_first_matching_binding :
    (resolveStructRefs
      (mkStruct [⟨"same", .definition, .kind .int⟩, ⟨"same", .regular, .kind .string⟩, ⟨"x", .regular, .ref "same"⟩] .regularOpen none [])
      == mkStruct [⟨"same", .definition, .kind .int⟩, ⟨"same", .regular, .kind .string⟩, ⟨"x", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_missing_reference_keeps_label_reference :
    (resolveStructRefs
      (mkStruct [⟨"x", .regular, .ref "#Missing"⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .ref "#Missing"⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_after_resolve_reference_to_definition :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] .regularOpen none []))
      == mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_reference_inside_list :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .list [.ref "#A"]⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .list [.refId ⟨0, 0⟩]⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_resolved_reference_inside_list :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .list [.ref "#A"]⟩] .regularOpen none []))
      == mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .list [.kind .int]⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_reference_inside_conjunction :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .conj [.ref "#A", .boundConstraint (intDecimal 0) .ge .number]⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .conj [.refId ⟨0, 0⟩, .boundConstraint (intDecimal 0) .ge .number]⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_reference_inside_disjunction :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .disj [(.regular, .ref "#A"), (.regular, .kind .string)]⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .disj [(.regular, .refId ⟨0, 0⟩), (.regular, .kind .string)]⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_reference_inside_struct_tail :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int⟩] .defOpenViaTail (some (.ref "#A")) [])
      == mkStruct [⟨"#A", .definition, .kind .int⟩] .defOpenViaTail (some (.refId ⟨0, 0⟩)) []) = true := by
  native_decide

theorem resolve_reference_inside_struct_pattern :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int⟩] .regularOpen none [((.kind .string), (.ref "#A"))])
      == mkStruct [⟨"#A", .definition, .kind .int⟩] .regularOpen none [((.kind .string), (.refId ⟨0, 0⟩))]) = true := by
  native_decide

theorem resolve_inner_reference_to_outer_field :
    (resolveStructRefs
      (mkStruct [⟨"a", .regular, .kind .int⟩,
                ⟨"b", .regular, mkStruct [⟨"c", .regular, .ref "a"⟩] .regularOpen none []⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .kind .int⟩,
                  ⟨"b", .regular, mkStruct [⟨"c", .regular, .refId ⟨1, 0⟩⟩] .regularOpen none []⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_inner_reference_prefers_nearest_scope :
    (resolveStructRefs
      (mkStruct [⟨"a", .regular, .kind .int⟩,
                ⟨"b", .regular, mkStruct [⟨"a", .regular, .kind .string⟩, ⟨"c", .regular, .ref "a"⟩] .regularOpen none []⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .kind .int⟩,
                  ⟨"b", .regular, mkStruct [⟨"a", .regular, .kind .string⟩, ⟨"c", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_inner_reference_to_outer_field :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"b", .regular, mkStruct [⟨"c", .regular, .ref "a"⟩] .regularOpen none []⟩] .regularOpen none []))
      == mkStruct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"b", .regular, mkStruct [⟨"c", .regular, .prim (.int 1)⟩] .regularOpen none []⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_comprehension_loop_vars_to_binding_ids :
    (resolveStructRefs
      (.structComp
        []
        [
          .comprehension
            [.forIn (some "k") "v" (mkStruct [⟨"x", .regular, .prim (.int 1)⟩] .regularOpen none [])]
            (mkStruct [⟨"key", .regular, .ref "k"⟩, ⟨"val", .regular, .ref "v"⟩] .regularOpen none [])
        ]
        .regularOpen)
      == .structComp
          []
          [
            .comprehension
              [.forIn (some "k") "v" (mkStruct [⟨"x", .regular, .prim (.int 1)⟩] .regularOpen none [])]
              (mkStruct [⟨"key", .regular, .refId ⟨1, 0⟩⟩, ⟨"val", .regular, .refId ⟨1, 1⟩⟩] .regularOpen none [])
          ]
          .regularOpen) = true := by
  native_decide

theorem resolve_comprehension_body_outer_field_depth :
    (resolveStructRefs
      (.structComp
        [⟨"base", .regular, .prim (.int 7)⟩]
        [.comprehension [.guard (.prim (.bool true))] (mkStruct [⟨"copy", .regular, .ref "base"⟩] .regularOpen none [])]
        .regularOpen)
      == .structComp
          [⟨"base", .regular, .prim (.int 7)⟩]
          [.comprehension [.guard (.prim (.bool true))] (mkStruct [⟨"copy", .regular, .refId ⟨1, 0⟩⟩] .regularOpen none [])]
          .regularOpen) = true := by
  native_decide

end Kue
