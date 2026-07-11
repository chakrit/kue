import Kue.Manifest

namespace Kue

theorem manifest_primitive :
    (manifest (.prim (.int 1))
      == .ok (.prim (.int 1))) = true := by
  native_decide

theorem manifest_concrete_list :
    (manifest (.list [.prim (.int 1), .prim (.string "x")])
      == .ok (.list [.prim (.int 1), .prim (.string "x")])) = true := by
  native_decide

theorem manifest_open_list_drops_tail :
    (manifest (.listTail [.prim (.int 1)] .top)
      == .ok (.list [.prim (.int 1)])) = true := by
  native_decide

theorem manifest_empty_open_list :
    (manifest (.listTail [] .top)
      == .ok (.list [])) = true := by
  native_decide

theorem manifest_open_list_typed_tail_drops_tail :
    (manifest (.listTail [.prim (.int 1), .prim (.int 2)] (.kind .int))
      == .ok (.list [.prim (.int 1), .prim (.int 2)])) = true := by
  native_decide

theorem manifest_open_list_string_tail_keeps_prefix :
    (manifest (.listTail [.prim (.int 1)] (.kind .string))
      == .ok (.list [.prim (.int 1)])) = true := by
  native_decide

theorem manifest_open_list_non_concrete_prefix_incomplete :
    (manifest (.listTail [.kind .int] .top)
      == .error (.incomplete (.kind .int))) = true := by
  native_decide

theorem manifest_open_list_nested_in_struct :
    (manifest (mkStruct [⟨"xs", .regular, .listTail [.prim (.int 1)] .top, false⟩] .regularOpen none [])
      == .ok (.struct [("xs", .list [.prim (.int 1)])])) = true := by
  native_decide

theorem manifest_concrete_struct :
    (manifest (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.string "x"), false⟩] .regularOpen none [])
      == .ok (.struct [("a", .prim (.int 1)), ("b", .prim (.string "x"))])) = true := by
  native_decide

theorem manifest_string_pattern_struct_outputs_regular_fields :
    (manifest (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [((.kind .string), (.kind .int))])
      == .ok (.struct [("a", .prim (.int 1))])) = true := by
  native_decide

theorem manifest_filters_non_output_fields :
    (manifest
      (mkStruct [
          ⟨"a", .regular, .prim (.int 1), false⟩,
          ⟨"b", .optional, .prim (.int 2), false⟩,
          ⟨"_c", .hidden, .prim (.int 3), false⟩,
          ⟨"#D", .definition, .kind .int, false⟩
        ] .regularOpen none [])
      == .ok (.struct [("a", .prim (.int 1))])) = true := by
  native_decide

theorem manifest_incomplete_regular_field_fails :
    (manifest (mkStruct [⟨"a", .regular, .kind .int, false⟩] .regularOpen none [])
      == .error (.incomplete (.kind .int))) = true := by
  native_decide

theorem manifest_unsatisfied_required_field_fails :
    (manifest (mkStruct [⟨"a", .required, .prim (.int 1), false⟩] .regularOpen none [])
      == .error (.incomplete (.prim (.int 1)))) = true := by
  native_decide

theorem manifest_kind_incomplete :
    (manifest (.kind .int)
      == .error (.incomplete (.kind .int))) = true := by
  native_decide

theorem manifest_top_incomplete :
    (manifest .top
      == .error (.incomplete .top)) = true := by
  native_decide

theorem manifest_bottom_contradiction :
    (manifest .bottom
      == .error .contradiction) = true := by
  native_decide

theorem manifest_ambiguous_disjunction :
    (manifest (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))])
      == .error (.ambiguous [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))])) = true := by
  native_decide

theorem manifest_selects_single_default :
    (manifest (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
      == .ok (.prim (.string "prod"))) = true := by
  native_decide

theorem manifest_selects_struct_field_default :
    (manifest
      (mkStruct [⟨"mode", .regular, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))], false⟩] .regularOpen none [])
      == .ok (.struct [("mode", .prim (.string "prod"))])) = true := by
  native_decide

theorem manifest_selects_list_item_default :
    (manifest
      (.list [.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]])
      == .ok (.list [.prim (.string "prod")])) = true := by
  native_decide

theorem manifest_default_override_after_regular_unification :
    (manifest
      (meet
        (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))])
        (.prim (.string "dev")))
      == .ok (.prim (.string "dev"))) = true := by
  native_decide

theorem manifest_ignores_absent_optional_default :
    (manifest
      (mkStruct [⟨"mode", .optional, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))], false⟩] .regularOpen none [])
      == .ok (.struct [])) = true := by
  native_decide

theorem manifest_selects_optional_default_when_regular_field_exists :
    (manifest
      (meet
        (mkStruct [⟨"mode", .optional, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))], false⟩] .regularOpen none [])
        (mkStruct [⟨"mode", .regular, .top, false⟩] .regularOpen none []))
      == .ok (.struct [("mode", .prim (.string "prod"))])) = true := by
  native_decide

theorem manifest_unsatisfied_required_default_fails :
    (manifest
      (mkStruct [⟨"mode", .required, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))], false⟩] .regularOpen none [])
      == .error (.incomplete (.disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))]))) = true := by
  native_decide

theorem manifest_selects_required_default_when_regular_field_exists :
    (manifest
      (meet
        (mkStruct [⟨"mode", .required, .disj [(.default, .prim (.string "prod")), (.regular, .prim (.string "dev"))], false⟩] .regularOpen none [])
        (mkStruct [⟨"mode", .regular, .top, false⟩] .regularOpen none []))
      == .ok (.struct [("mode", .prim (.string "prod"))])) = true := by
  native_decide

-- RESID-MASK (manifest): a held `.structComp` residual whose RESOLVED fields carry an inline
-- `.bottomWith [.fieldConflict]` (the `{x:1,for…} & {x:2}` ⇒ `.structComp [x:_|_] …` convention)
-- is a CONTRADICTION on export, not an `incomplete value` — the conflict is terminal and a held
-- comprehension cannot un-conflict a static field (oracle v0.16.1: `conflicting values`, NOT
-- `incomplete`). Pre-fix the `.structComp` manifest arm reported `.incomplete` blind to the inner
-- bottom (the manifest sibling of the disjunction-prune masking RESID-MASK-1 closed). Fixed by
-- descending the resolved fields via `containsBottomFields` (the SAME predicate that prunes a dead
-- disjunction arm). A held comprehension stands in for the deferred residual.
theorem manifest_structcomp_inner_conflict_is_contradiction :
    (manifest (.structComp
        [⟨"x", .regular, .bottomWith [.fieldConflict "x"], false⟩]
        [.comprehension [] (mkStruct [⟨"y", .regular, .prim (.int 1), false⟩] .regularOpen none [])]
        .regularOpen)
      == .error .contradiction) = true := by
  native_decide

-- DEEP variant: the conflict is one level down (`p: {q: _|_}`) — `containsBottomFields` recurses the
-- inner `.struct` to the nested bottom (A#6 totality × the residual boundary). Still a contradiction.
theorem manifest_structcomp_nested_conflict_is_contradiction :
    (manifest (.structComp
        [⟨"p", .regular, mkStruct [⟨"q", .regular, .bottomWith [.fieldConflict "q"], false⟩] .regularOpen none [], false⟩]
        [.comprehension [] (mkStruct [⟨"y", .regular, .prim (.int 1), false⟩] .regularOpen none [])]
        .regularOpen)
      == .error .contradiction) = true := by
  native_decide

-- NO OVER-FIRE (control): a CONFLICT-FREE held residual stays `.incomplete` — only the held
-- comprehension blocks it, there is no terminal conflict to surface. Pins that the fix descends
-- ONLY to find a real bottom and does not reclassify every residual as a contradiction.
theorem manifest_structcomp_clean_residual_stays_incomplete :
    (manifest (.structComp
        [⟨"x", .regular, .prim (.int 1), false⟩]
        [.comprehension [] (mkStruct [⟨"y", .regular, .prim (.int 1), false⟩] .regularOpen none [])]
        .regularOpen)
      == .error (.incomplete (.structComp
          [⟨"x", .regular, .prim (.int 1), false⟩]
          [.comprehension [] (mkStruct [⟨"y", .regular, .prim (.int 1), false⟩] .regularOpen none [])]
          .regularOpen))) = true := by
  native_decide

-- OPTIONAL-bottom control: an UNSET optional field carrying `_|_` is NOT a contradiction (the
-- argocd `#u?:_|_` shape) — `containsBottomFields` skips optionals, so this stays `.incomplete`.
-- Guards against the fix over-firing on the legitimate optional-bottom case the manifest already
-- tolerates elsewhere.
theorem manifest_structcomp_optional_bottom_stays_incomplete :
    (manifest (.structComp
        [⟨"u", .optional, .bottomWith [.fieldConflict "u"], false⟩]
        [.comprehension [] (mkStruct [⟨"y", .regular, .prim (.int 1), false⟩] .regularOpen none [])]
        .regularOpen)
      == .error (.incomplete (.structComp
          [⟨"u", .optional, .bottomWith [.fieldConflict "u"], false⟩]
          [.comprehension [] (mkStruct [⟨"y", .regular, .prim (.int 1), false⟩] .regularOpen none [])]
          .regularOpen))) = true := by
  native_decide



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @manifest_structcomp_optional_bottom_stays_incomplete

end Kue
