import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

-- Struct closedness / pattern-constraint / definition-closing family (B2.2 pattern path,
-- B6 depth, SC-2/SC-4 hidden-and-let closing). Carved out of `EvalTests.lean` (test-org
-- split, PB-2).

-- ### B2.2 must-fix item 3 — `applyEvaluatedStructN` pattern path (end-to-end, live).
--
-- With production emitting the unified `.struct`, an evaluated pattern-struct now flows through
-- `applyEvaluatedStructN`'s pattern arm (`meet (mkStruct [] op none patterns) (mkStruct fields
-- …)`), which applies each `[pattern]: constraint` to the matching evaluated fields. These pin
-- that arm against cue v0.16.1: a matching field is constrained (`xy` matches `=~"x"`, so
-- `string & "hi" = "hi"`; a conflicting constraint bottoms it), a non-matching field is left
-- untouched (`z`). cue elides the residual `[=~"x"]: c` pattern in `eval` output but APPLIES it;
-- Kue keeps the pattern visible (a formatting divergence, recorded) — the field VALUES agree
-- exactly with cue (`xy: "hi"`/`xy: _|_`, `z: 1`).
theorem eval_pattern_struct_applies_to_matching_field :
    evalSourceMatches
        "out: {[=~\"x\"]: string, xy: \"hi\", z: 1}\n"
        "out: {xy: \"hi\", z: 1, [=~\"x\"]: string}"
      = true := by
  native_decide

theorem eval_pattern_struct_constraint_conflict_bottoms_field :
    evalSourceMatches
        "out: {[=~\"x\"]: int, xy: \"str\"}\n"
        "out: {xy: _|_, [=~\"x\"]: int}"
      = true := by
  native_decide

-- ### B6 — definition-body closedness enforced through a regular field (gap 1).
--
-- A closed `#Def` nested under a REGULAR field reaches the use-site meet still closed, so an
-- undeclared field is rejected. Pre-B6 `normalizeFieldWithFuel` left a regular field's value
-- unwalked, so the nested def stayed open and admitted the extra. Oracle: cue v0.16.1 reports
-- `out.extra: field not allowed` for the closed form and admits `extra` when the def is opened via
-- `...`. The eager-selector form (`x.#Inner`, gap 2) is the SAME root cause — once normalize closes
-- the def, the eager selector returns the closed body and the existing meet enforces it.
theorem eval_closed_def_under_regular_field_rejects_extra :
    evalSourceMatches
        "a: {\n\t#Inner: {x: int}\n}\nout: a.#Inner & {x: 1, extra: 2}\n"
        "a: {#Inner: {x: int}}\nout: {x: 1, extra: _|_}"
      = true := by
  native_decide

theorem eval_eager_selector_closed_def_rejects_extra :
    evalSourceMatches
        "x: {#Inner: {y: int}}\nout: x.#Inner & {y: 1, extra: 3}\n"
        "x: {#Inner: {y: int}}\nout: {y: 1, extra: _|_}"
      = true := by
  native_decide

theorem eval_open_def_under_regular_field_admits_extra :
    evalSourceMatches
        "a: {\n\t#Inner: {x: int, ...}\n}\nout: a.#Inner & {x: 1, extra: 2}\n"
        "a: {#Inner: {x: int, ...}}\nout: {x: 1, extra: 2, ...}"
      = true := by
  native_decide

-- ### B6-A2 — definition-body closedness enforced through a `let`-bound value.
--
-- A closed `#Def` nested under a `let` binding closes exactly as under a regular field: `letBinding`
-- is its OWN `FieldClass` kind, NOT the import-binding A2 trap (the hidden-field skip), so the spine
-- walker can recurse it safely. Oracle cue v0.16.1: `let x = {#I: {y:int}}; x.#I & {extra}` →
-- `out.extra: field not allowed`; an open def (`...`) under the same `let` admits `extra` (no
-- over-close). This is the `letBinding` arm of the future A2-followup 4-way `FieldClass` split.
theorem eval_let_nested_def_closes :
    evalSourceMatches
        "let x = {#I: {y: int}}\nout: x.#I & {y: 1, extra: 2}\n"
        "out: {y: 1, extra: _|_}"
      = true := by
  native_decide

theorem eval_let_nested_def_open_admits_extra :
    evalSourceMatches
        "let x = {#I: {y: int, ...}}\nout: x.#I & {y: 1, extra: 2}\n"
        "out: {y: 1, extra: 2, ...}"
      = true := by
  native_decide

theorem eval_let_plain_struct_stays_open :
    evalSourceMatches
        "let x = {p: {y: int}}\nout: x.p & {y: 1, extra: 2}\n"
        "out: {y: 1, extra: 2}"
      = true := by
  native_decide

-- ### B6-T1 — closedness regression pins.
--
-- B6 is the most regression-prone class (prior closedness changes bottomed `#ListenerSet`/
-- cert-manager). These pin the shapes the Phase-A over-close hunt exercised so future closedness
-- work cannot silently regress them. Each oracle-checked vs cue v0.16.1. (SC-2 closed the former
-- direct-def-path gap — `#D.r & {extra}` now correctly rejects; pinned in the SC-2 cluster below.)
theorem eval_b6_depth2_nested_def_closes :
    evalSourceMatches
        "a: {b: {#Inner: {x: int}}}\nout: a.b.#Inner & {x: 1, extra: 2}\n"
        "a: {b: {#Inner: {x: int}}}\nout: {x: 1, extra: _|_}"
      = true := by
  native_decide

theorem eval_b6_plain_struct_under_regular_stays_open :
    evalSourceMatches
        "a: {b: {x: int}}\nout: a.b & {x: 1, extra: 2}\n"
        "a: {b: {x: int}}\nout: {x: 1, extra: 2}"
      = true := by
  native_decide

theorem eval_b6_def_meet_rejects_unallowed :
    evalSourceMatches
        "#D: {a: int, b: string}\nout: #D & {a: 1, c: 2}\n"
        "#D: {a: int, b: string}\nout: {a: 1, b: string, c: _|_}"
      = true := by
  native_decide

theorem eval_b6_comprehension_field_admits_sibling :
    evalSourceMatches
        "a: {x: int, if true {y: 1}}\nout: a & {x: 1, y: 1}\n"
        "a: {x: int, y: 1}\nout: {x: 1, y: 1}"
      = true := by
  native_decide

theorem eval_b6_embedding_field_admits_sibling :
    evalSourceMatches
        "base: {m: int}\na: {base, n: int}\nout: a & {m: 1, n: 2}\n"
        "base: {m: int}\na: {n: int, m: int}\nout: {n: 2, m: 1}"
      = true := by
  native_decide

-- SC-2b — DIVERGES from cue (recorded in cue-divergences.md). cue RE-OPENS nested closedness on
-- a `& {}` instantiation (`(#D & {}).r & {extra}` admits `extra`); the spec says closedness is
-- monotone through meet, so the closed `r` STAYS closed and `extra` is REJECTED. Kue follows the
-- spec. cue is internally inconsistent: the direct path `#D.r & {extra}` rejects (cue+Kue agree),
-- only the no-op `& {}` re-opens — an eval-strategy artifact, not lattice-derivable.
theorem eval_sc2b_instantiated_def_field_stays_closed :
    evalSourceMatches
        "#D: {r: {x: int}}\nout: (#D & {}).r & {x: 1, extra: 2}\n"
        "#D: {r: {x: int}}\nout: {x: 1, extra: _|_}"
      = true := by
  native_decide

-- ### SC-2 — nested def-body closedness (the closing field-walker twin).
--
-- The four soundness obligations from the SC-2 design, pinned. The closing walker closes a
-- referenced def's nested PLAIN-struct field VALUES (obligation 1), recursively, AND a def's
-- HIDDEN-field nested PLAIN-struct value too (obligation 4 — SC-4 fix), BUT a plain non-def
-- struct (obligation 2) and a nested `...` (obligation 3) stay open. Each oracle-checked vs
-- cue v0.16.1; obligations 1/3/4 agree with cue, 2 agrees with cue (control).

-- Obligation 1: a referenced closed def's nested field rejects an extra (the SC-2a fix).
theorem eval_sc2_nested_def_field_closes :
    evalSourceMatches
        "#A: {a: {b: int}}\nout: #A & {a: {b: 1, extra: 5}}\n"
        "#A: {a: {b: int}}\nout: {a: {b: 1, extra: _|_}}"
      = true := by
  native_decide

-- Obligation 2: a PLAIN (non-def) nested struct stays OPEN — the closing twin never runs here.
theorem eval_sc2_plain_nested_struct_stays_open :
    evalSourceMatches
        "A: {a: {b: int}}\nout: A & {a: {b: 1, extra: 5}}\n"
        "A: {a: {b: int}}\nout: {a: {b: 1, extra: 5}}"
      = true := by
  native_decide

-- Obligation 3: a nested `...` keeps the nested struct OPEN (`defOpenViaTail` left unchanged).
theorem eval_sc2_nested_tail_stays_open :
    evalSourceMatches
        "#A: {a: {b: int, ...}}\nout: #A & {a: {b: 1, extra: 5}}\n"
        "#A: {a: {b: int, ...}}\nout: {a: {b: 1, extra: 5, ...}}"
      = true := by
  native_decide

-- ### SC-4 — a def's HIDDEN-field nested PLAIN-struct value CLOSES (the closing twin's
-- hidden arm now recurses the CLOSING walker, like the regular arm).
--
-- Closedness is a property of the definition and is MONOTONE; the visibility of the field
-- carrying a nested value (`_h` hidden vs `h` regular) does NOT change whether that nested
-- value is closed — a `_h: {x: int}` declared in a closed `#A` with no `...` is itself a
-- closed struct. So `#A & {_h: {x: 1, extra: 2}}` REJECTS `extra`, exactly as the regular
-- analog (obligation 1). cue v0.16.1 AGREES on the direct-meet AND the direct-select
-- (`#A._h & {extra}`) paths; only the bound-then-select path (`y: #A; y._h & {extra}`)
-- re-opens in cue — the same SC-2b-family eval artifact (closedness lost through a regular
-- binding), where Kue follows the spec and diverges. The let-read analog (`v: _h` where `_h`
-- is a let-bound struct in the def, read into a regular field) closes for free: `v` is a
-- regular field whose resolved value is the closing-walked struct.

-- SC-4 obligation 4 (FLIPPED from the stale "stays open"): direct-meet hidden nested CLOSES.
theorem eval_sc4_hidden_field_nested_closes :
    evalSourceMatches
        "#A: {_h: {x: int}}\nout: #A & {_h: {x: 1, extra: 2}}\n"
        "#A: {_h: {x: int}}\nout: {_h: {x: 1, extra: _|_}}"
      = true := by
  native_decide

-- SC-4: a nested `...` under a HIDDEN field still STAYS OPEN (the tail dominates closedness).
theorem eval_sc4_hidden_field_nested_tail_stays_open :
    evalSourceMatches
        "#A: {_h: {x: int, ...}}\nout: #A & {_h: {x: 1, extra: 2}}\n"
        "#A: {_h: {x: int, ...}}\nout: {_h: {x: 1, extra: 2, ...}}"
      = true := by
  native_decide

-- SC-4: a NEW hidden field added at the use-site is still ADMITTED (top-level hidden ignores
-- closedness — `ignoresClosedness = isDefinition || isHidden`; this is orthogonal to the
-- nested-value close and must not regress).
theorem eval_sc4_new_hidden_field_admitted :
    evalSourceMatches
        "#A: {a: int}\nout: #A & {_new: 9}\n"
        "#A: {a: int}\nout: {a: int, _new: 9}"
      = true := by
  native_decide

-- SC-4: a depth-2 hidden→regular nested struct also closes (recursion through the hidden value).
theorem eval_sc4_hidden_field_nested_depth2 :
    evalSourceMatches
        "#A: {_h: {r: {b: int}}}\nout: #A & {_h: {r: {b: 1, extra: 2}}}\n"
        "#A: {_h: {r: {b: int}}}\nout: {_h: {r: {b: 1, extra: _|_}}}"
      = true := by
  native_decide

-- SC-4 LET analog: a LET-bound struct read into a regular field of a closed def CLOSES — the let
-- arm of the closing twin now recurses the closing walker, so `_t`'s value closes and `v: _t`
-- resolves to the closed struct. cue v0.16.1 AGREES (`out.v.extra: field not allowed`).
theorem eval_sc4_let_read_nested_closes :
    evalSourceMatches
        "#A: {let _t = {x: 5}, v: _t}\nout: #A & {v: {extra: 2}}\n"
        "#A: {v: {x: 5}}\nout: {v: {x: 5, extra: _|_}}"
      = true := by
  native_decide

-- SC-4 LET control: a let-read nested struct in a PLAIN (non-def) struct STAYS OPEN — the closing
-- twin never runs (the spine does), so `extra` is admitted (cue agrees).
theorem eval_sc4_let_read_plain_stays_open :
    evalSourceMatches
        "A: {let _t = {x: 5}, v: _t}\nout: A & {v: {extra: 2}}\n"
        "A: {v: {x: 5}}\nout: {v: {x: 5, extra: 2}}"
      = true := by
  native_decide

-- SC-4 NON-STRUCT control: a hidden field carrying a SCALAR is unaffected by the closing walker —
-- the closing value walker's catch-all returns a scalar unchanged, so a use-site meet that adds
-- nothing illegal resolves cleanly (the hidden scalar drops from output, `k` survives). cue agrees.
theorem eval_sc4_hidden_scalar_unaffected :
    exportJsonMatches
        "#A: {_h: 5, k: int}\nout: #A & {k: 7}\n"
        "{\n    \"out\": {\n        \"k\": 7\n    }\n}\n"
      = true := by
  native_decide

-- SC-4 NON-STRUCT + extra: the def is still CLOSED, so an extra REGULAR field at the use site
-- bottoms even though the hidden carrier is a scalar (closedness is the def's, not the field's). cue agrees.
theorem eval_sc4_hidden_scalar_extra_bottoms :
    exportJsonBottoms "#A: {_h: 5, k: int}\nout: #A & {k: 7, extra: 9}\n" = true := by
  native_decide

-- SC-4 LIST element: a struct nested in a LIST under a hidden field CLOSES — the closing value
-- walker recurses `.list` elements with itself, so a use-site extra in the element bottoms. cue agrees
-- (`out._h.0.extra: field not allowed`).
theorem eval_sc4_hidden_list_elem_closes :
    exportJsonBottoms "#A: {_h: [{x: int}]}\nout: #A & {_h: [{x: 1, extra: 2}]}\n" = true := by
  native_decide

-- SC-4 LET DISJUNCTION: a let bound to a DISJUNCTION read into a regular field — the closing walker
-- recurses `.disj` alternatives, so each arm closes; meeting the use-site struct picks the matching
-- arm and resolves cleanly. cue agrees (`{out:{v:{x:1}}}`).
theorem eval_sc4_let_disjunction_arm_resolves :
    exportJsonMatches
        "#A: {let _t = {x: int} | {y: int}, v: _t}\nout: #A & {v: {x: 1}}\n"
        "{\n    \"out\": {\n        \"v\": {\n            \"x\": 1\n        }\n    }\n}\n"
      = true := by
  native_decide

-- SC-4 LET DISJUNCTION + extra: an extra field added to the picked arm bottoms BOTH arms (each is a
-- closed struct under the def), so the disjunction is empty → bottom. cue agrees (2 errors in empty disjunction).
theorem eval_sc4_let_disjunction_arm_extra_bottoms :
    exportJsonBottoms "#A: {let _t = {x: int} | {y: int}, v: _t}\nout: #A & {v: {x: 1, extra: 2}}\n" = true := by
  native_decide

-- COVERAGE TRIPWIRE (test-health). Anchors the LAST theorem of every section.
#check @eval_sc4_hidden_scalar_unaffected                     -- SC-4 hidden non-struct unaffected
#check @eval_sc4_hidden_list_elem_closes                      -- SC-4 closing recurses list elements
#check @eval_sc4_let_disjunction_arm_extra_bottoms            -- SC-4 closing recurses disjunction arms

end Kue
