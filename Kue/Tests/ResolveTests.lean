import Kue.Eval
import Kue.Resolve

namespace Kue

theorem resolve_same_struct_reference_to_binding_id :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .ref "#A", false⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .refId ⟨0, 0⟩, false⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_reference_uses_first_matching_binding :
    (resolveStructRefs
      (mkStruct [⟨"same", .definition, .kind .int, false⟩, ⟨"same", .regular, .kind .string, false⟩, ⟨"x", .regular, .ref "same", false⟩] .regularOpen none [])
      == mkStruct [⟨"same", .definition, .kind .int, false⟩, ⟨"same", .regular, .kind .string, false⟩, ⟨"x", .regular, .refId ⟨0, 0⟩, false⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_missing_reference_keeps_label_reference :
    (resolveStructRefs
      (mkStruct [⟨"x", .regular, .ref "#Missing", false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .ref "#Missing", false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_after_resolve_reference_to_definition :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .ref "#A", false⟩] .regularOpen none []))
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .kind .int, false⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_reference_inside_list :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .list [.ref "#A"], false⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .list [.refId ⟨0, 0⟩], false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_resolved_reference_inside_list :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .list [.ref "#A"], false⟩] .regularOpen none []))
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .list [.kind .int], false⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_reference_inside_conjunction :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .conj [.ref "#A", .boundConstraint (.int 0) .ge .number], false⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .conj [.refId ⟨0, 0⟩, .boundConstraint (.int 0) .ge .number], false⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_reference_inside_disjunction :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .disj [(.regular, .ref "#A"), (.regular, .kind .string)], false⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .disj [(.regular, .refId ⟨0, 0⟩), (.regular, .kind .string)], false⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_reference_inside_struct_tail :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int, false⟩] .defOpenViaTail (some (.ref "#A")) [])
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩] .defOpenViaTail (some (.refId ⟨0, 0⟩)) []) = true := by
  native_decide

theorem resolve_reference_inside_struct_pattern :
    (resolveStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int, false⟩] .regularOpen none [((.kind .string), (.ref "#A"))])
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩] .regularOpen none [((.kind .string), (.refId ⟨0, 0⟩))]) = true := by
  native_decide

theorem resolve_inner_reference_to_outer_field :
    (resolveStructRefs
      (mkStruct [⟨"a", .regular, .kind .int, false⟩,
                ⟨"b", .regular, mkStruct [⟨"c", .regular, .ref "a", false⟩] .regularOpen none [], false⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .kind .int, false⟩,
                  ⟨"b", .regular, mkStruct [⟨"c", .regular, .refId ⟨1, 0⟩, false⟩] .regularOpen none [], false⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_inner_reference_prefers_nearest_scope :
    (resolveStructRefs
      (mkStruct [⟨"a", .regular, .kind .int, false⟩,
                ⟨"b", .regular, mkStruct [⟨"a", .regular, .kind .string, false⟩, ⟨"c", .regular, .ref "a", false⟩] .regularOpen none [], false⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .kind .int, false⟩,
                  ⟨"b", .regular, mkStruct [⟨"a", .regular, .kind .string, false⟩, ⟨"c", .regular, .refId ⟨0, 0⟩, false⟩] .regularOpen none [], false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_inner_reference_to_outer_field :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩,
                  ⟨"b", .regular, mkStruct [⟨"c", .regular, .ref "a", false⟩] .regularOpen none [], false⟩] .regularOpen none []))
      == mkStruct [⟨"a", .regular, .prim (.int 1), false⟩,
                  ⟨"b", .regular, mkStruct [⟨"c", .regular, .prim (.int 1), false⟩] .regularOpen none [], false⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_comprehension_loop_vars_to_binding_ids :
    (resolveStructRefs
      (.structComp
        []
        [
          .comprehension
            [.forIn (some "k") "v" (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])]
            (mkStruct [⟨"key", .regular, .ref "k", false⟩, ⟨"val", .regular, .ref "v", false⟩] .regularOpen none [])
        ]
        .regularOpen)
      == .structComp
          []
          [
            .comprehension
              [.forIn (some "k") "v" (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])]
              (mkStruct [⟨"key", .regular, .refId ⟨1, 0⟩, false⟩, ⟨"val", .regular, .refId ⟨1, 1⟩, false⟩] .regularOpen none [])
          ]
          .regularOpen) = true := by
  native_decide

theorem resolve_comprehension_body_outer_field_depth :
    (resolveStructRefs
      (.structComp
        [⟨"base", .regular, .prim (.int 7), false⟩]
        [.comprehension [.guard (.prim (.bool true))] (mkStruct [⟨"copy", .regular, .ref "base", false⟩] .regularOpen none [])]
        .regularOpen)
      == .structComp
          [⟨"base", .regular, .prim (.int 7), false⟩]
          [.comprehension [.guard (.prim (.bool true))] (mkStruct [⟨"copy", .regular, .refId ⟨1, 0⟩, false⟩] .regularOpen none [])]
          .regularOpen) = true := by
  native_decide

-- ### TL-2 — `Depth`/`FieldIndex` newtype invariants.
--
-- The two `BindingId` coordinates are distinct nominal types so a coordinate swap is a type
-- error, not a silent bug. The transposition guard itself is enforced at COMPILE time (a
-- `Depth` cannot be passed where a `FieldIndex` is expected — see `Value.lean`), so it is not
-- expressible as a runtime `native_decide`. These pin the runtime contract that survives the
-- wrapping: the `⟨d, i⟩` literal elaborates through `OfNat`, `.val` round-trips, and swapping
-- the two coordinates yields a DISTINCT `BindingId` (the bug class the newtypes make
-- unrepresentable, witnessed at the value level).

theorem tl2_bindingId_literal_matches_explicit_mk :
    (BindingId.mk ⟨2⟩ ⟨5⟩ == (⟨2, 5⟩ : BindingId)) = true := by native_decide

theorem tl2_bindingId_val_roundtrips :
    (let id : BindingId := ⟨3, 7⟩; id.depth.val == 3 && id.index.val == 7) = true := by
  native_decide

theorem tl2_bindingId_swapped_coordinates_distinct :
    ((⟨2, 5⟩ : BindingId) == (⟨5, 2⟩ : BindingId)) = false := by native_decide

theorem tl2_depth_distinguishes_underlying_nat :
    ((⟨3⟩ : Depth) == (⟨4⟩ : Depth)) = false := by native_decide

theorem tl2_fieldIndex_distinguishes_underlying_nat :
    ((⟨3⟩ : FieldIndex) == (⟨4⟩ : FieldIndex)) = false := by native_decide

-- DEDUP-MIRROR-GUARD. Belt-and-suspenders over the structural single-source: the resolver's
-- lexical slot layout and the evaluator's frame must agree on WHICH slots exist for every
-- duplicate-bearing struct body, or a reference lands on a stale index and dangles. Both now
-- fold the SAME `mergeFieldLayoutInto` (Lattice), so they cannot diverge by construction; this
-- pins the label projection anyway across an adversarial dup battery (dup, dup-with-hidden-
-- between, dup-of-definition, triple-dup, dup-with-optional, class-mismatch let-vs-field).
theorem canonical_layout_label_mirrors_canonicalize_fields :
    let batteries : List (List Field) := [
      [⟨"a", .regular, .kind .int, false⟩, ⟨"a", .regular, .kind .string, false⟩],
      [⟨"a", .regular, .kind .int, false⟩, ⟨"h", .hidden, .kind .int, false⟩,
        ⟨"a", .regular, .kind .string, false⟩],
      [⟨"#D", .definition, .kind .int, false⟩, ⟨"#D", .definition, .kind .string, false⟩],
      [⟨"a", .regular, .kind .int, false⟩, ⟨"a", .regular, .kind .string, false⟩,
        ⟨"a", .regular, .kind .int, false⟩],
      [⟨"a", .optional, .kind .int, false⟩, ⟨"a", .regular, .kind .string, false⟩],
      [⟨"a", .letBinding, .kind .int, false⟩, ⟨"a", .regular, .kind .string, false⟩]
    ]
    batteries.all (fun fs =>
      (canonicalFieldLayout fs).map Field.label == (canonicalizeFields fs).map Field.label)
      = true := by native_decide



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @resolve_comprehension_body_outer_field_depth
#check @tl2_fieldIndex_distinguishes_underlying_nat    -- TL-2 — `Depth`/`FieldIndex` newtype invariants
#check @canonical_layout_label_mirrors_canonicalize_fields  -- DEDUP-MIRROR-GUARD equivalence

end Kue
