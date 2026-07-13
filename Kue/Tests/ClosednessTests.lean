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

-- ### PATTERN-CONSTRAINT CONFORMANCE PROBE (CORE-CONFORMANCE-PROBE, 2026-07-12).
--
-- Measures pattern-constraint APPLICATION: a `[pattern]: constraint` pair constrains every
-- field whose label matches `pattern`. Probed differentially vs cue v0.16.1 (export
-- byte-identical); the one gap found — a NON-NUMERIC bound OPERAND in a label predicate
-- (`[>"m"]`) — is filed (PATTERN-BOUND-REF-OPERAND) and red-seeded
-- (`testdata/wild/pattern-bound-string-operand/`), not a divergence in the surface pinned here.

-- A regex label predicate constrains matching fields (`apple` ⇒ int) and leaves non-matching
-- fields (`box`) unconstrained by that pattern. cue agrees.
theorem eval_pattern_regex_filters_by_label :
    exportJsonMatches
        "out: {[=~\"^a\"]: int, apple: 1, box: 2}\n"
        "{\n    \"out\": {\n        \"apple\": 1,\n        \"box\": 2\n    }\n}\n"
      = true := by
  native_decide

-- OVERLAPPING patterns INTERSECT their value constraints: `ab` matches both `[=~"a"]` and
-- `[=~"b"]`, so its value must satisfy `<10 & >5`; 7 passes. cue agrees.
theorem eval_pattern_overlap_intersects_bound_constraints :
    exportJsonMatches
        "out: {[=~\"a\"]: <10, [=~\"b\"]: >5, ab: 7}\n"
        "{\n    \"out\": {\n        \"ab\": 7\n    }\n}\n"
      = true := by
  native_decide

-- Same overlap, value out of the intersected bound: `ab: 20` violates `<10` ⇒ bottom. cue
-- agrees (`invalid value 20 (out of bound <10)`).
theorem eval_pattern_overlap_intersects_bound_rejects :
    exportJsonBottoms "out: {[=~\"a\"]: <10, [=~\"b\"]: >5, ab: 20}\n" = true := by
  native_decide

-- A recursive pattern (constraint is itself a pattern struct) applies at each level. cue agrees.
theorem eval_pattern_recursive_applies :
    exportJsonMatches
        "out: {[string]: {y: int}, a: {y: 1}, b: {y: 2}}\n"
        "{\n    \"out\": {\n        \"a\": {\n            \"y\": 1\n        },\n        \"b\": {\n            \"y\": 2\n        }\n    }\n}\n"
      = true := by
  native_decide

-- A pattern introduced by UNIFICATION with a later struct constrains that struct's fields. cue agrees.
theorem eval_pattern_via_unification_constrains :
    exportJsonMatches
        "out: {[string]: int} & {n: 3}\n"
        "{\n    \"out\": {\n        \"n\": 3\n    }\n}\n"
      = true := by
  native_decide

-- A DISJUNCTION-valued pattern admits a field satisfying either arm and bottoms one satisfying
-- neither (`b: true` is neither int nor string). cue agrees (empty disjunction).
theorem eval_pattern_disjunction_valued_rejects :
    exportJsonBottoms "out: {[string]: int | string, a: 1, b: true}\n" = true := by
  native_decide

-- ### DEF-FLATTEN-CLOSEDNESS — a NON-recursive def unioning its OWN literals is CLOSED (RESOLVED).
--
-- `#X: {a:1} & {b:3}` is a CLOSED definition whose body unions its own struct literals — a FIXED
-- field set `{a,b}`, exactly like the single-decl `#X: {a:1, b:3}`. A use-site `#X & {c:4}` must
-- REJECT `c` (cue v0.16.1: `#X.c: field not allowed`). Pre-fix `flattenConjDefRef`'s close gate was
-- `isDefinition && (isSelfRef || inCycle)`: this shape is neither self-ref nor in-cycle, so the
-- literals flattened OPEN and `c` leaked (over-acceptance). FIXED by the `ownLiteralUnion` disjunct —
-- fires when every non-`.refId` conjunct is `isUnionableDefValue` and no `.refId` conjunct targets a
-- DIFFERENT slot — reusing the Bug2-12b union-then-close-once path. A def EXTENDING a reference
-- (`#LS: #Base & {extra}`) keeps a cross-def `.refId` conjunct, so it stays on the OPEN-extension path
-- (Bug2-6..9), proved by the open-extension guards below.

-- REJECT (the bug, FLIPPED): a use-site extra `c` ∉ {a,b} on an own-literal-union def is rejected.
theorem defflatten_ownunion_rejects_extra :
    exportJsonBottoms "#X: {a: 1} & {b: 3}\ny: #X & {c: 4}\n" = true := by
  native_decide

-- BASE (no use-site narrow): the closed own-union yields `{a:1,b:3}` — closedness does not reject the
-- def's own declared fields. cue `{a:1,b:3}`.
theorem defflatten_ownunion_base_admits :
    exportJsonMatches "#X: {a: 1} & {b: 3}\nout: #X\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 3\n    }\n}\n" = true := by
  native_decide

-- ADMIT (redeclare an existing field): `& {a:1}` is the def's OWN field, admitted + narrowed. cue agrees.
theorem defflatten_ownunion_redeclare_admits :
    exportJsonMatches "#X: {a: 1} & {b: 3}\nout: #X & {a: 1}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 3\n    }\n}\n" = true := by
  native_decide

-- CONFLICT (must bottom): a shared label re-declared with a conflicting value still `.conj`-meets and
-- conflicts — closedness does not mask a real value clash. cue `conflicting values 3 and 99`.
theorem defflatten_ownunion_conflict_bottoms :
    exportJsonBottoms "#X: {a: 1} & {b: 3}\ny: #X & {b: 99}\n" = true := by
  native_decide

-- OPEN-TAIL (do NOT over-close): a `...` in ONE literal opens the union, so a use-site extra is
-- ADMITTED — `unionDefOpenness` lets `defOpenViaTail` dominate across the own-literal union. cue admits.
theorem defflatten_ownunion_opentail_admits :
    exportJsonMatches "#X: {a: 1} & {b: 3, ...}\nout: #X & {c: 4}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 3,\n        \"c\": 4\n    }\n}\n" = true := by
  native_decide

-- NESTED (reject): closedness propagates into a nested struct literal across the own-union — an extra
-- in `sub` is rejected. cue `field not allowed`.
theorem defflatten_ownunion_nested_rejects :
    exportJsonBottoms "#X: {sub: {s: 1}} & {t: 2}\ny: #X & {sub: {extra: 9}}\n" = true := by
  native_decide

-- OPEN-EXTENSION GUARD (must STAY open — the over-close boundary): a def EXTENDING an OPEN ref
-- (`#Base: {a:1, ...}`, `#LS: #Base & {b:2}`) keeps a cross-def `.refId` conjunct, so `ownLiteralUnion`
-- does NOT fire; the open base's `...` flows through the close-once fold and a use-site extra `c` is
-- ADMITTED. Pins that the fix does not over-close the legitimate open-extension pattern. cue admits.
theorem defflatten_open_extension_still_admits :
    exportJsonMatches "#Base: {a: 1, ...}\n#LS: #Base & {b: 2}\nout: #LS & {c: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2,\n        \"c\": 9\n    }\n}\n" = true := by
  native_decide

-- CLOSED-BASE EXTENSION (reject): extending a CLOSED own-union def (`#A: {a:1} & {b:2}`) with a new
-- field (`#B: #A & {c:3}`) rejects — `#A` is closed to `{a,b}`, so `c` is not allowed. The ref-extension
-- path composes `#A`'s closedness correctly. cue `field not allowed`.
theorem defflatten_closed_base_extension_rejects :
    exportJsonBottoms "#A: {a: 1} & {b: 2}\n#B: #A & {c: 3}\nout: #B\n" = true := by
  native_decide

-- SINGLE-DECL anchor (already correct, must STAY green): the non-`.conj` body shape rejects the extra
-- via the bare `.refId` arm, unchanged by this fix. cue rejects.
theorem defflatten_singledecl_still_rejects :
    exportJsonBottoms "#X: {a: 1, b: 3}\ny: #X & {c: 4}\n" = true := by
  native_decide

-- MULTI-DISJUNCTION (DEF-FLATTEN-CLOSEDNESS-DISJ-REF, reject): the own-literal union distributes across
-- the CROSS-PRODUCT of TWO closable disjunctions, closing each of the four combinations
-- ({a,b,d}|{a,b,e}|{a,c,d}|{a,c,e}); an undeclared `f` bottoms every combination. Before the
-- cross-product distribution the def flattened OPEN and the defaults SILENTLY exported `{a,b,d,f}`.
-- cue v0.16.1 `field not allowed`.
theorem defflatten_multidisj_rejects :
    exportJsonBottoms "#X: {a: 1} & (*{b: 2} | {c: 3}) & (*{d: 4} | {e: 5})\ny: #X & {f: 6}\n" = true := by
  native_decide

-- MULTI-DISJUNCTION SELECT (both-direction guard, admit): unifying a NON-default combination's own
-- fields resolves to exactly that combination — `{c:3, e:5}` picks the `{a,c,e}` arm and admits `c`,`e`.
-- Guards against over-closing a legitimately-selected combination. cue v0.16.1 admits.
theorem defflatten_multidisj_select_admits :
    exportJsonMatches "#X: {a: 1} & (*{b: 2} | {c: 3}) & (*{d: 4} | {e: 5})\nout: #X & {c: 3, e: 5}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3,\n        \"e\": 5\n    }\n}\n" = true := by
  native_decide

-- MULTI-DISJUNCTION DEFAULT (default = product of defaults): with no use-site selection the default
-- combination is the one where EVERY component arm is a default (`*{b}` & `*{d}` → `{a,b,d}`), matching
-- cue's product-of-defaults collapse. cue v0.16.1 `{a,b,d}`.
theorem defflatten_multidisj_default_collapses :
    exportJsonMatches "#X: {a: 1} & (*{b: 2} | {c: 3}) & (*{d: 4} | {e: 5})\nout: #X\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2,\n        \"d\": 4\n    }\n}\n" = true := by
  native_decide

-- MULTI-DISJUNCTION OPEN-TAIL ARM (both-direction guard, admit): a `...`-tail arm in the cross-product
-- keeps its combination OPEN, so a use-site extra is ADMITTED — the over-close direction the
-- distribution must not trip. cue v0.16.1 admits `{a,b,d,f}`.
theorem defflatten_multidisj_opentail_admits :
    exportJsonMatches
      "#X: {a: 1} & (*{b: 2, ...} | {c: 3}) & (*{d: 4} | {e: 5})\nout: #X & {f: 6}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2,\n        \"d\": 4,\n        \"f\": 6\n    }\n}\n" = true := by
  native_decide

-- REF ARM (DEF-FLATTEN-CLOSEDNESS-DISJ-REF, reject): a disjunction arm that is a def-REF (`#Base`,
-- closed `{b:2}`) resolves as an OPEN-compose arm `{a:1} & #Base` — `a` is not in `#Base`'s closed
-- allowed-set, so that arm bottoms; the `{z:9}` arm closes to `{a,z}` and rejects `b`,`extra`. Both
-- arms bottom. Before per-arm distribution the ref arm failed `isClosableDisj`, so `#X` flattened
-- OPEN and SILENTLY exported `{a,z,b,extra}`. cue v0.16.1 bottom.
theorem defflatten_refarm_closed_rejects :
    exportJsonBottoms "#Base: {b: 2}\n#X: {a: 1} & ({z: 9} | #Base)\ny: #X & {b: 2, extra: 7}\n"
      = true := by
  native_decide

-- REF ARM SELECT (both-direction guard, admit the z-arm): selecting `{z:9}` picks the closed `{a,z}`
-- arm; the `#Base` arm bottoms (`a` not allowed). Guards that distribution does not over-reject a
-- legitimately-selected struct arm. cue v0.16.1 `{a,z}`.
theorem defflatten_refarm_select_admits :
    exportJsonMatches "#Base: {b: 2}\n#X: {a: 1} & ({z: 9} | #Base)\nout: #X & {z: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- REF ARM base-contains-literal (both-direction guard, admit): when `#Base` CONTAINS the def's own
-- field (`#Base: {a:1, q:9}`), the ref arm `{a:1} & #Base` composes to the closed `{a,q}` and admits
-- `q`. The open literal must NOT be independently closed to `{a}` (which would reject `q`). cue admits.
theorem defflatten_refarm_base_contains_admits :
    exportJsonMatches "#Base: {a: 1, q: 9}\n#X: {a: 1} & ({z: 9} | #Base)\nout: #X & {q: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"q\": 9\n    }\n}\n" = true := by
  native_decide

-- OPEN REF ARM (over-close guard, must STAY open): an OPEN `#Base: {b:2, ...}` arm keeps the arm
-- OPEN, so `#X & {b:2, extra:7}` ADMITS `extra` on the `#Base` arm — the distribution composes the
-- ref's OPENNESS, it does not force-close. (The `b, a` field order reflects ref-fields-first
-- open-composition, a PRE-EXISTING order quirk shared with plain `{a:1} & #Base`; values spec-correct,
-- logged in `cue-divergences.md`.) cue v0.16.1 admits `{a,b,extra}`.
theorem defflatten_refarm_open_admits :
    exportJsonMatches "#Base: {b: 2, ...}\n#X: {a: 1} & ({z: 9} | #Base)\nout: #X & {b: 2, extra: 7}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"a\": 1,\n        \"extra\": 7\n    }\n}\n" = true := by
  native_decide

-- NESTED DISJUNCTION ARM (reject): a nested `.disj` arm flattens (disjunction is associative) to
-- `{b:2}|{c:3}|{e:5}`, each closed to `{a}∪arm`; an undeclared `g` bottoms every arm. Before flattening
-- the nested arm failed `isClosableDisj`, so `#X` stayed OPEN and reported `ambiguous`. cue v0.16.1 bottom.
theorem defflatten_nesteddisj_rejects :
    exportJsonBottoms "#X: {a: 1} & ({b: 2} | ({c: 3} | {e: 5}))\ny: #X & {g: 9}\n" = true := by
  native_decide

-- NESTED DISJUNCTION SELECT (both-direction guard, admit): selecting a flattened inner arm resolves to
-- exactly that closed arm — `{c:3}` picks `{a,c}`. Guards against over-rejecting a nested arm. cue admits.
theorem defflatten_nesteddisj_select_admits :
    exportJsonMatches "#X: {a: 1} & ({b: 2} | ({c: 3} | {e: 5}))\nout: #X & {c: 3}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- SCALAR ARM (reject): a scalar disjunction arm (`3`) dies against the def's struct literal (`{a:1} & 3`
-- ⇒ struct-vs-int bottom), so only the `{b:2}` struct arm survives, closes to `{a,b}`, and rejects
-- `extra`. cue v0.16.1 bottom.
theorem defflatten_scalararm_rejects :
    exportJsonBottoms "#X: {a: 1} & ({b: 2} | 3)\ny: #X & {b: 2, extra: 7}\n" = true := by
  native_decide

-- BOUND ARM (DISJ-CLOSEDNESS-EXCLUDED-ARM-LEAK, reject): a comparator-bound disjunction arm (`>5`)
-- dies against the def's own struct literal (`{a:1} & >5` ⇒ struct-vs-number bottom) EXACTLY like a
-- scalar, so it is DISTRIBUTE-SAFE — its combination drops and the surviving `{z:9}` arm closes to
-- `{a,z}`, rejecting `w`. The all-or-nothing whitelist previously excluded the bound arm, so the
-- WHOLE disjunction stayed non-distributable, the def flattened OPEN, and `w` leaked. cue v0.16.1
-- bottom.
theorem defflatten_boundarm_rejects :
    exportJsonBottoms "#X: {a: 1} & ({z: 9} | >5)\ny: #X & {w: 7}\n" = true := by
  native_decide

-- BOUND ARM SELECT (both-direction guard, admit): selecting the struct arm resolves to `{a,z}`; the
-- bound arm has dropped. Guards that distributing the bound arm does not over-reject the struct sibling.
-- cue v0.16.1 `{a,z}`.
theorem defflatten_boundarm_select_admits :
    exportJsonMatches "#X: {a: 1} & ({z: 9} | >5)\nout: #X & {z: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- LIST ARM (DISJ-CLOSEDNESS-EXCLUDED-ARM-LEAK, reject): a list-carrier disjunction arm (`[1,2]`) dies
-- against the def's struct literal (`{a:1} & [1,2]` ⇒ struct-vs-list bottom), so it is distribute-safe
-- like the bound arm; the `{z:9}` arm closes and rejects `w`. cue v0.16.1 bottom.
theorem defflatten_listarm_rejects :
    exportJsonBottoms "#X: {a: 1} & ({z: 9} | [1, 2])\ny: #X & {w: 7}\n" = true := by
  native_decide

-- KIND ARM (reject): a scalar-kind disjunction arm (`string`) dies against the def's struct literal
-- (`{a:1} & string` ⇒ struct-vs-string bottom) — every `Kind` is scalar/list, never struct, so a kind
-- arm is always distribute-safe. cue v0.16.1 bottom.
theorem defflatten_kindarm_rejects :
    exportJsonBottoms "#X: {a: 1} & ({z: 9} | string)\ny: #X & {w: 7}\n" = true := by
  native_decide

-- BOUND ARM MULTIDISJ (reject): a bound arm mixed into a cross-product of two disjunctions
-- (`({z:9}|>5) & ({d:4}|{e:5})`) drops every combination it appears in; the surviving struct
-- combinations `{a,z,d}|{a,z,e}` close and reject `w`. Pins that the per-arm distribute-safe drop
-- composes correctly with the cross-product. cue v0.16.1 bottom.
theorem defflatten_boundarm_multidisj_rejects :
    exportJsonBottoms "#X: {a: 1} & ({z: 9} | >5) & ({d: 4} | {e: 5})\ny: #X & {w: 7}\n" = true := by
  native_decide

-- BOUND ARM MULTIDISJ SELECT (both-direction guard, admit): the surviving cross-product combination
-- `{a,z,d}` resolves when its own fields are selected. cue v0.16.1 `{a,z,d}`.
theorem defflatten_boundarm_multidisj_select_admits :
    exportJsonMatches "#X: {a: 1} & ({z: 9} | >5) & ({d: 4} | {e: 5})\nout: #X & {z: 9, d: 4}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"z\": 9,\n        \"d\": 4\n    }\n}\n" = true := by
  native_decide

-- BOUND ARM OPEN-TAIL SIBLING (over-close guard, must STAY open): the struct sibling carries a `...`
-- tail (`{p:1, ...}`), so its combination stays OPEN and admits a use-site extra `w`; the bound arm
-- still drops. Pins that distribute-safe bound handling does not force-close a legitimately-open struct
-- sibling. cue v0.16.1 admits `{a,p,w}`.
theorem defflatten_boundarm_opentail_sibling_admits :
    exportJsonMatches "#X: {a: 1} & ({p: 1, ...} | >5)\nout: #X & {w: 7}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"p\": 1,\n        \"w\": 7\n    }\n}\n" = true := by
  native_decide

-- REGEX ARM (DISJ-CLOSEDNESS-EXCLUDED-ARM-LEAK-2, reject): a string-regex arm (`=~"foo"`) is
-- string-kinded and dies against the def's struct literal, so it is distribute-safe; the `{z:9}` arm
-- closes and rejects `w`. cue v0.16.1 bottom.
theorem defflatten_regexarm_rejects :
    exportJsonBottoms "#X: {a: 1} & ({z: 9} | =~\"foo\")\ny: #X & {z: 9, w: 7}\n" = true := by
  native_decide

-- REGEX ARM SELECT (both-direction guard, admit): the surviving struct arm resolves to `{a,z}`; the
-- regex arm dropped, not over-rejecting the sibling. cue v0.16.1 `{a,z}`.
theorem defflatten_regexarm_select_admits :
    exportJsonMatches "#X: {a: 1} & ({z: 9} | =~\"foo\")\nout: #X & {z: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- NOTPRIM ARM (reject): a `!=` negation arm (`!=5`) is number-kinded and dies against the def's struct
-- literal, so it is distribute-safe; the `{z:9}` arm closes and rejects `w`. cue v0.16.1 bottom.
theorem defflatten_notprimarm_rejects :
    exportJsonBottoms "#X: {a: 1} & ({z: 9} | !=5)\ny: #X & {z: 9, w: 7}\n" = true := by
  native_decide

-- MINITEMS ARM (reject): a CALL-FORM list-length validator (`list.MinItems(2)`) reaches the
-- def-flatten level as an unlowered `.builtinCall`; `disjArmClass` lowers it to a `.lengthConstraint`
-- (`.items`) which dies against the struct literal, so it is distribute-safe; the `{z:9}` arm closes
-- and rejects `w`. cue v0.16.1 bottom.
theorem defflatten_minitemsarm_rejects :
    exportJsonBottoms "import \"list\"\n#X: {a: 1} & ({z: 9} | list.MinItems(2))\ny: #X & {z: 9, w: 7}\n"
      = true := by
  native_decide

-- MINFIELDS ARM (reject): a `struct.MinFields(2)` arm is the subtle length case — it COMPOSES-CLOSED
-- with the def's CLOSED literal (carrying no new allowed field), so the literal closes around it and a
-- use-site extra `w` is rejected. `disjArmClass` lowers the call-form builtin to a `.lengthConstraint`
-- (`.fields`); the emission closes the literal, so the arm rejects extras exactly as a closed struct.
-- cue v0.16.1 bottom (a closed definition rejects the extra regardless of the validator).
theorem defflatten_minfieldsarm_rejects :
    exportJsonBottoms
      "import \"struct\"\n#X: {a: 1, b: 2} & ({z: 9} | struct.MinFields(2))\ny: #X & {w: 7}\n"
      = true := by
  native_decide

-- MINFIELDS ARM SELECT (both-direction guard, admit): with a two-field literal satisfying the count,
-- selecting the declared `z` resolves to `{a,b,z}`; the MinFields arm composed-closed to `{a,b}` and
-- dropped against `z`. cue v0.16.1 `{a,b,z}`.
theorem defflatten_minfieldsarm_select_admits :
    exportJsonMatches
      "import \"struct\"\n#X: {a: 1, b: 2} & ({z: 9} | struct.MinFields(2))\nout: #X & {z: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- ERROR ARM (DISJ-CLOSEDNESS-ERROR-ARM-LEAK, reject): a DIRECT `error(...)` disjunction arm in a
-- CLOSED definition. The layer separation dissolves the bug214b tension — bug214b's disjunction lives
-- under a REGULAR field (`close=false`, never distributed), while a def-flatten `error` arm force-folds
-- to bottom against the closed literal (its `.conj` bottoms, message preserved through the meet), so it
-- carries no allowed field; the `{z:9}` arm closes and rejects `w`. cue v0.16.1 bottom (message `x`).
theorem defflatten_errorarm_rejects :
    exportJsonBottoms "#X: {a: 1} & ({z: 9} | error(\"x\"))\ny: #X & {w: 7}\n" = true := by
  native_decide

-- ERROR ARM SELECT (both-direction guard, admit): selecting the declared `z` resolves to `{a,z}`; the
-- error arm dropped as bottom, not force-folding the whole disjunction. cue v0.16.1 `{a,z}`.
theorem defflatten_errorarm_select_admits :
    exportJsonMatches "#X: {a: 1} & ({z: 9} | error(\"x\"))\nout: #X & {z: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- ### DEF-CLOSEDNESS-NESTED-CONJ-ARM — a PARENTHESIZED nested struct-literal `.conj` closes (RESOLVED).
--
-- `#X: {a:1} & ({b:2} & {d:4})` is a CLOSED def with a FIXED field set `{a,b,d}`, exactly like the
-- flat `#X: {a:1} & {b:2} & {d:4}` — `&`-grouping is associative and must not change closedness. Pre-fix
-- the parens kept `{b:2} & {d:4}` a NESTED `.conj` conjunct, which is neither `isUnionableDefValue` nor a
-- self-ref, so `ownLiteralUnion`'s `cs.all` failed → def flattened OPEN → a use-site `z` leaked. Same
-- root, disjunction face: a `.conj` disjunction arm (`({b:2}&{d:4}) | {c:3}`) was `disjArmClass`
-- `.blocking` → the disjunction non-distributable → OPEN. FIXED by `normalizeDefBodyConjunct` — a def
-- body's pure-struct-literal `.conj` conjunct is SPLICED into its members and a `.disj` conjunct's
-- pure-struct `.conj` arms are MERGED, BEFORE the closedness gate — so both faces close exactly as the
-- flat/plain-arm forms already do. cue v0.16.1 bottom on both.

-- FACE 1 (nested-conj conjunct, reject): a use-site extra `z` on `#X: {a:1} & ({b:2} & {d:4})` is rejected.
theorem defflatten_nestedconj_rejects :
    exportJsonBottoms "#X: {a: 1} & ({b: 2} & {d: 4})\ny: #X & {z: 9}\n" = true := by
  native_decide

-- FACE 1 BASE (admit the def's own fields): the closed nested-conj union yields `{a,b,d}`. cue agrees.
theorem defflatten_nestedconj_base_admits :
    exportJsonMatches "#X: {a: 1} & ({b: 2} & {d: 4})\nout: #X\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2,\n        \"d\": 4\n    }\n}\n" = true := by
  native_decide

-- FACE 1 DEEP (reject): a doubly-nested `.conj` (`{b:2} & ({d:4} & {e:5})`) splices recursively and
-- still closes to `{a,b,d,e}`, rejecting `z`. cue v0.16.1 bottom.
theorem defflatten_nestedconj_deep_rejects :
    exportJsonBottoms "#X: {a: 1} & ({b: 2} & ({d: 4} & {e: 5}))\ny: #X & {z: 9}\n" = true := by
  native_decide

-- FLAT CONTROL (already correct, must STAY green): the unparenthesized form closes identically.
theorem defflatten_nestedconj_flat_control_rejects :
    exportJsonBottoms "#X: {a: 1} & {b: 2} & {d: 4}\ny: #X & {z: 9}\n" = true := by
  native_decide

-- FACE 2 (disjunction arm is a nested `.conj`, reject): `({b:2}&{d:4}) | {c:3}` distributes to
-- `{a,b,d} | {a,c}`, both closed; a use-site `z` bottoms both. cue v0.16.1 bottom.
theorem defflatten_nestedconj_disjarm_rejects :
    exportJsonBottoms "#X: {a: 1} & (({b: 2} & {d: 4}) | {c: 3})\ny: #X & {z: 9}\n" = true := by
  native_decide

-- FACE 2 SELECT the conj arm (both-direction guard, admit): `{b:2,d:4}` picks the `{a,b,d}` arm. cue admits.
theorem defflatten_nestedconj_disjarm_select_conj_admits :
    exportJsonMatches "#X: {a: 1} & (({b: 2} & {d: 4}) | {c: 3})\nout: #X & {b: 2, d: 4}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2,\n        \"d\": 4\n    }\n}\n" = true := by
  native_decide

-- FACE 2 SELECT the plain arm (both-direction guard, admit): `{c:3}` picks the `{a,c}` arm; the closed
-- conj arm rejects `c`, so only `{a,c}` survives. cue v0.16.1 `{a,c}`.
theorem defflatten_nestedconj_disjarm_select_plain_admits :
    exportJsonMatches "#X: {a: 1} & (({b: 2} & {d: 4}) | {c: 3})\nout: #X & {c: 3}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- FACE 2 OPEN-TAIL conj arm (over-close guard, admit): a `...` inside the merged conj arm
-- (`{b:2} & {d:4, ...}`) keeps that arm OPEN, so a use-site extra `q` is ADMITTED — the merge
-- normalizes-to-closed only the plain members and preserves an explicit tail. cue v0.16.1 admits.
theorem defflatten_nestedconj_disjarm_opentail_admits :
    exportJsonMatches "#X: {a: 1} & (({b: 2} & {d: 4, ...}) | {c: 3})\nout: #X & {b: 2, d: 4, q: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2,\n        \"d\": 4,\n        \"q\": 9\n    }\n}\n" = true := by
  native_decide

-- MIXED-REF CONJUNCT (over-splice guard, admit): a nested `.conj` mixing a struct with a def-REF
-- (`#Base & {c:3}` where `#Base` is OPEN) is NOT a pure-struct conj, so it is NOT spliced — the ref
-- governs closedness and the body stays OPEN, admitting `q`. Pins that the normal form fires ONLY for
-- pure-struct-literal `.conj`s. cue admits.
theorem defflatten_nestedconj_mixed_ref_stays_open :
    exportJsonMatches "#Base: {a: 1, ...}\n#X: {b: 2} & (#Base & {c: 3})\nout: #X & {q: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3,\n        \"b\": 2,\n        \"q\": 9\n    }\n}\n" = true := by
  native_decide

-- ### DEF-CLOSEDNESS-NESTED-CONJ-RESIDUAL — the nested-`.conj` close reaches EVERY def-body entry path.
--
-- The `345f08b` normal form ran only inside `flattenConjDefRef`'s `.conj`-body arm. Two def-body shapes
-- reach the closedness fold by a DIFFERENT exit and leaked a use-site extra past a parenthesized nested
-- `.conj`: (a) a BARE `.disj` body (`#X: (…) | {c}`) took the catch-all, so its nested-`.conj` arm was
-- never merged; (b) a BURIED self-ref (`#X: {a} & (#X & {b})`) took the unexpanded-ref exit, dropping
-- closedness. FIXED by routing a `.disj` DEFINITION body through the same machinery, and by re-deriving
-- the buried-self-ref case's closedness from its own struct-literals (self-ref drops out). cue v0.16.1
-- bottoms both faces.

-- RESIDUAL (a) BARE-DISJ reject: the nested-`.conj` arm merges to a CLOSED struct, so `z` bottoms both arms.
theorem defflatten_baredisj_conjarm_rejects :
    exportJsonBottoms "#X: ({b: 2} & {d: 4}) | {c: 3}\ny: #X & {z: 9}\n" = true := by
  native_decide

-- RESIDUAL (a) BARE-DISJ select the conj arm (both-direction, admit): `{b:2,d:4}` picks the `{b,d}` arm.
theorem defflatten_baredisj_conjarm_select_conj_admits :
    exportJsonMatches "#X: ({b: 2} & {d: 4}) | {c: 3}\nout: #X & {b: 2, d: 4}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"d\": 4\n    }\n}\n" = true := by
  native_decide

-- RESIDUAL (a) BARE-DISJ select the plain arm (both-direction, admit): `{c:3}` picks the `{c}` arm.
theorem defflatten_baredisj_conjarm_select_plain_admits :
    exportJsonMatches "#X: ({b: 2} & {d: 4}) | {c: 3}\nout: #X & {c: 3}\n"
      "{\n    \"out\": {\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- RESIDUAL (a) BARE-DISJ conj in the SECOND arm (reject): arm order is irrelevant to the merge.
theorem defflatten_baredisj_conjarm_second_rejects :
    exportJsonBottoms "#X: {c: 3} | ({b: 2} & {d: 4})\ny: #X & {z: 9}\n" = true := by
  native_decide

-- RESIDUAL (a) BARE-DISJ PLAIN control (already correct, must STAY green): plain struct arms close.
theorem defflatten_baredisj_plain_control_rejects :
    exportJsonBottoms "#X: {b: 2} | {c: 3}\ny: #X & {z: 9}\n" = true := by
  native_decide

-- RESIDUAL (a) BARE-DISJ open-tail arm (over-close guard, admit): a `...` in the merged conj arm keeps
-- it OPEN, so `q` is admitted. cue v0.16.1 admits.
theorem defflatten_baredisj_conjarm_opentail_admits :
    exportJsonMatches "#X: ({b: 2, ...} & {d: 4}) | {c: 3}\nout: #X & {b: 2, d: 4, q: 9}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"d\": 4,\n        \"q\": 9\n    }\n}\n" = true := by
  native_decide

-- RESIDUAL (b) BURIED-SELFREF reject: `{a} & (#X & {b})` closes to `{a,b}` (self-ref drops out); `z` bottoms.
theorem defflatten_buried_selfref_rejects :
    exportJsonBottoms "#X: {a: 1} & (#X & {b: 2})\ny: #X & {z: 9}\n" = true := by
  native_decide

-- RESIDUAL (b) BURIED-SELFREF admit its own fields (both-direction): `#X` resolves to `{a,b}`.
theorem defflatten_buried_selfref_admits :
    exportJsonMatches "#X: {a: 1} & (#X & {b: 2})\nout: #X & {a: 1, b: 2}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

-- RESIDUAL (b) BURIED-SELFREF FLAT control (already correct, must STAY green): top-level self-ref closes.
theorem defflatten_buried_selfref_flat_control_rejects :
    exportJsonBottoms "#X: {a: 1} & #X & {b: 2}\ny: #X & {z: 9}\n" = true := by
  native_decide

-- RESIDUAL (b) BURIED-SELFREF deeper (reject): a triply-grouped self-ref conj still closes to `{a,b,e}`.
theorem defflatten_buried_selfref_deep_rejects :
    exportJsonBottoms "#X: {a: 1} & ((#X & {b: 2}) & {e: 5})\ny: #X & {z: 9}\n" = true := by
  native_decide

-- ### DEF-BODY-CLOSEDNESS-UNIFY — one flow point: EVERY def-body entry path carries closedness.
--
-- `flattenConjDefRef`'s `defBodyConjuncts` dispatched per top constructor and dropped closedness on
-- the `| _ => none` arm. Each of THREE audits found a new entry path leaking a use-site extra: a
-- bare-`.disj` body, a buried self-ref, and now a bare-`.refId` body (`#X: #Y` re-referencing a
-- FLATTEN-DERIVED-closed def). The fix routes every INDIRECT/COMPOSITIONAL def body through the ONE
-- normalization+flatten point (`.disj`/`.refId`/… default to `some [body]`); a struct-shaped body
-- self-closes standalone. A `.refId` now recurses into its referent's own flatten, carrying the
-- referent's derived closedness — so a new indirection constructor cannot bypass by construction.
-- cue v0.16.1 bottoms every reject face; closedness is a def-only property (a regular-field ref
-- stays open).

-- REREF nested-conj face (reject): `#Y: {b}&{d}` derives closedness at flatten; `#X: #Y` propagates
-- it, so a use-site `z` bottoms. THE leak this slice closed.
theorem defflatten_reref_nestedconj_rejects :
    exportJsonBottoms "#Y: ({b: 2} & {d: 4})\n#X: #Y\ny: #X & {z: 9}\n" = true := by
  native_decide

-- REREF split-literal face (reject): `#Y: {b} & {d}` (top-level `.conj` of two literals) re-referenced.
theorem defflatten_reref_splitliteral_rejects :
    exportJsonBottoms "#Y: {b: 2} & {d: 4}\n#X: #Y\ny: #X & {z: 9}\n" = true := by
  native_decide

-- REREF admit own fields (both-direction): `#X` inherits `#Y`'s closed `{b,d}`; declaring them is ok.
theorem defflatten_reref_admits_own :
    exportJsonMatches "#Y: {b: 2} & {d: 4}\n#X: #Y\nout: #X & {b: 2, d: 4}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"d\": 4\n    }\n}\n" = true := by
  native_decide

-- REREF MULTI-HOP (reject): closedness propagates transitively through a chain of bare-`.refId` defs.
theorem defflatten_reref_multihop_rejects :
    exportJsonBottoms "#Y: {b: 2} & {d: 4}\n#Z: #Y\n#X: #Z\ny: #X & {z: 9}\n" = true := by
  native_decide

-- REREF of a bare-`.disj` def body (reject): the referent's distributed-and-closed arms carry through.
theorem defflatten_reref_disjbody_rejects :
    exportJsonBottoms "#Y: ({b: 2} & {d: 4}) | {c: 3}\n#X: #Y\ny: #X & {z: 9}\n" = true := by
  native_decide

-- REREF CONTROL single-struct-literal (already closed; must STAY reject): closedness intrinsic to the
-- struct, so the re-ref rejects even without derived-closedness propagation.
theorem defflatten_reref_singlestruct_control_rejects :
    exportJsonBottoms "#Y: {b: 2, d: 4}\n#X: #Y\ny: #X & {z: 9}\n" = true := by
  native_decide

-- REREF open-tail (over-close guard, admit): a `...` in the referent keeps the def OPEN through the
-- re-ref, so a use-site extra `q` is ADMITTED. cue v0.16.1 admits.
theorem defflatten_reref_opentail_admits :
    exportJsonMatches "#Y: {b: 2, ...}\n#X: #Y\nout: #X & {q: 9}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"q\": 9\n    }\n}\n" = true := by
  native_decide

-- REREF NON-DEFINITION control (closedness is def-only, admit): re-referencing a REGULAR (hidden)
-- field (`_X: _Y`, `_Y: {b}&{d}`) carries no closedness, so a use-site extra is ADMITTED. cue v0.16.1
-- admits. Hidden so only `out` exports; hidden ≠ definition, so it stays open.
theorem defflatten_reref_regular_field_admits :
    exportJsonMatches "_Y: {b: 2} & {d: 4}\n_X: _Y\nout: _X & {z: 9}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"d\": 4,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- ### DEF-CLOSEDNESS-NONDEF-REFERENT — a definition indirecting to a NON-definition struct closes.
-- The value of a definition is closed HOWEVER reached; the referent's def-ness is irrelevant. A
-- bare-`.refId` chain closes its non-def struct terminal at the flatten (`underDef` struct arm); a
-- `.selector`/`.index` def body closes on resolution (the `.refId` eval arm). An explicit `...` on the
-- referent keeps it OPEN through the definition; a non-definition enclosing field stays open (def-only).
-- cue v0.16.1 adjudicates every face (rejects each extra; admits the open/own/non-def faces).

-- Non-def struct referent (reject): `#X: _foo`, `_foo: {a}` a plain struct — closes over `{a}`.
theorem defflatten_nondef_referent_rejects :
    exportJsonBottoms "_foo: {a: 1}\n#X: _foo\nout: #X & {z: 9}\n" = true := by
  native_decide

-- Selector referent (reject): `#X: _foo.bar` selects a non-def struct — resolves-and-closes.
theorem defflatten_nondef_selector_rejects :
    exportJsonBottoms "_foo: {bar: {a: 1}}\n#X: _foo.bar\nout: #X & {z: 9}\n" = true := by
  native_decide

-- Index referent (reject): `#X: _l[0]` indexes a non-def struct — resolves-and-closes.
theorem defflatten_nondef_index_rejects :
    exportJsonBottoms "_l: [{a: 1}]\n#X: _l[0]\nout: #X & {z: 9}\n" = true := by
  native_decide

-- Chain through non-def bindings (reject): `#X: _bar`, `_bar: _foo`, `_foo: {a}` — the chain reaches
-- and closes the terminal struct.
theorem defflatten_nondef_chain_rejects :
    exportJsonBottoms "_foo: {a: 1}\n_bar: _foo\n#X: _bar\nout: #X & {z: 9}\n" = true := by
  native_decide

-- Nested recursive close (reject): closedness propagates into the referent's nested struct.
theorem defflatten_nondef_nested_rejects :
    exportJsonBottoms "_foo: {a: {c: 1}}\n#X: _foo\nout: #X & {a: {d: 2}}\n" = true := by
  native_decide

-- Admit own field (both-direction): the referent's own declared field is admitted.
theorem defflatten_nondef_admits_own :
    exportJsonMatches "_foo: {a: 1}\n#X: _foo\nout: #X & {a: 1}\n"
      "{\n    \"out\": {\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- OPEN referent (over-close guard, admit): an explicit `...` on the referent keeps the def OPEN, so a
-- use-site extra `z` is ADMITTED.
theorem defflatten_nondef_opentail_admits :
    exportJsonMatches "_foo: {a: 1, ...}\n#X: _foo\nout: #X & {z: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- NON-DEFINITION enclosing (def-only guard, admit): a regular field indirecting to the same struct
-- carries NO closedness, so a use-site extra is ADMITTED — closedness is a definition property.
theorem defflatten_nondef_enclosing_admits :
    exportJsonMatches "_foo: {a: 1}\n_x: _foo\nout: _x & {z: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- Scalar referent (no-op): a definition aliasing a scalar carries no closedness.
theorem defflatten_nondef_scalar_noop :
    exportJsonMatches "#X: 5\nout: #X & 5\n"
      "{\n    \"out\": 5\n}\n" = true := by
  native_decide

-- ### DEF-COMPREHENSION-CONJUNCT-USESITE-BOTTOM — comprehension embedding conjoined with a struct
-- literal in a def body closes JOINTLY, not per-conjunct.
--
-- `#X: {for…} & {b:2}` flattened SPLIT the comprehension `.structComp` from its sibling literal, each
-- self-closed, and the two disjoint closed structs mutually rejected each other's fields
-- (`close{p} & close{b}` ⊥) — a spurious over-rejection that bottomed even a `& {}` use-site meet.
-- `ownLiteralUnion` covers a pure-literal body but a `.structComp` is not `isUnionableDefValue`, so
-- `mergeCompDefBody` merges the comprehension+literal conjuncts into ONE normalized `.structComp` that
-- closes over the joint field set. Both-direction guards: the resolution ADMITS (comp output + own
-- field), and closedness still REJECTS a genuine use-site extra. cue v0.16.1 truth table.

-- Core over-rejection (admit): `& {}` is the identity — resolves to `{b,p}`. THE seed graduated here.
theorem defcomp_conjunct_empty_meet_resolves :
    exportJsonMatches "#X: {for k, v in {p: 1} {\"\\(k)\": v}} & {b: 2}\nout: #X & {}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"p\": 1\n    }\n}\n" = true := by
  native_decide

-- Admit own field (`& {b:2}`) and comprehension-produced field (`& {p:1}`) — both in the closed set.
theorem defcomp_conjunct_own_field_admits :
    exportJsonMatches "#X: {for k, v in {p: 1} {\"\\(k)\": v}} & {b: 2}\nout: #X & {b: 2}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"p\": 1\n    }\n}\n" = true := by
  native_decide

theorem defcomp_conjunct_comp_output_admits :
    exportJsonMatches "#X: {for k, v in {p: 1} {\"\\(k)\": v}} & {b: 2}\nout: #X & {p: 1}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"p\": 1\n    }\n}\n" = true := by
  native_decide

-- CLOSEDNESS GUARD (reject): a genuine use-site extra `z` is NOT in the joint set `{b,p}` → ⊥.
theorem defcomp_conjunct_extra_rejects :
    exportJsonBottoms "#X: {for k, v in {p: 1} {\"\\(k)\": v}} & {b: 2}\ny: #X & {z: 9}\n" = true := by
  native_decide

-- Conflict on a comprehension-produced field (`p:1` vs `p:99`) → ⊥.
theorem defcomp_conjunct_conflict_rejects :
    exportJsonBottoms "#X: {for k, v in {p: 1} {\"\\(k)\": v}} & {b: 2}\ny: #X & {p: 99}\n" = true := by
  native_decide

-- Multi-field comprehension output composes: `{p,q}` from the comprehension ∪ `{b}` literal.
theorem defcomp_conjunct_multifield_resolves :
    exportJsonMatches "#X: {for k, v in {p: 1, q: 2} {\"\\(k)\": v}} & {b: 2}\nout: #X & {}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"p\": 1,\n        \"q\": 2\n    }\n}\n" = true := by
  native_decide

-- Empty-source comprehension yields no field; only the literal `{b}` survives.
theorem defcomp_conjunct_empty_source_resolves :
    exportJsonMatches "#X: {for k, v in {} {\"\\(k)\": v}} & {b: 2}\nout: #X & {}\n"
      "{\n    \"out\": {\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

-- Empty-source comprehension still CLOSES over `{b}` — a use-site extra `z` rejects.
theorem defcomp_conjunct_empty_source_extra_rejects :
    exportJsonBottoms "#X: {for k, v in {} {\"\\(k)\": v}} & {b: 2}\ny: #X & {z: 9}\n" = true := by
  native_decide

-- Order-independent: literal FIRST, comprehension second — same joint close.
theorem defcomp_conjunct_order_independent_resolves :
    exportJsonMatches "#X: {b: 2} & {for k, v in {p: 1} {\"\\(k)\": v}}\nout: #X & {}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"p\": 1\n    }\n}\n" = true := by
  native_decide

-- Comprehension output OVERLAPS the literal on a conflicting value (`b:1` vs `b:2`) → ⊥.
theorem defcomp_conjunct_overlap_conflict_rejects :
    exportJsonBottoms "#X: {for k, v in {b: 1} {\"\\(k)\": v}} & {b: 2}\nout: #X & {}\n" = true := by
  native_decide

-- OPEN-TAIL over-close guard (admit): a `...` in the comprehension struct keeps the def OPEN, so a
-- use-site extra `z` is ADMITTED. cue v0.16.1 admits.
theorem defcomp_conjunct_opentail_admits :
    exportJsonMatches "#X: {for k, v in {p: 1} {\"\\(k)\": v}, ...} & {b: 2}\nout: #X & {z: 9}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"p\": 1,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- CONTROL comprehension-ALONE def (must STAY clean): resolves to `{p}`; use-site field-add rejects.
theorem defcomp_alone_control_resolves :
    exportJsonMatches "#X: {for k, v in {p: 1} {\"\\(k)\": v}}\nout: #X & {}\n"
      "{\n    \"out\": {\n        \"p\": 1\n    }\n}\n" = true := by
  native_decide

theorem defcomp_alone_control_field_add_rejects :
    exportJsonBottoms "#X: {for k, v in {p: 1} {\"\\(k)\": v}}\ny: #X & {b: 2}\n" = true := by
  native_decide

-- CONTROL non-definition (closedness is def-only): `X: {for…} & {b:2}` stays OPEN, use-site add admits.
theorem defcomp_conjunct_nondef_control_admits :
    exportJsonMatches "X: {for k, v in {p: 1} {\"\\(k)\": v}} & {b: 2}\nout: X & {c: 3}\n"
      "{\n    \"X\": {\n        \"p\": 1,\n        \"b\": 2\n    },\n    \"out\": {\n        \"p\": 1,\n        \"b\": 2,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- ### DEF-CLOSEDNESS-INDIRECT-DISJ-CONJ — indirection-close FOLDED into the direct-def-body path.
--
-- A definition whose body INDIRECTS to a disjunction/conjunction of non-def referents closes with
-- the SAME machinery a direct body uses: `resolveDefBodyReferent` inlines a struct referent OPEN (it
-- unions ONCE with siblings, not each separately) and a disjunction referent CLOSED per arm (like a
-- direct `.disj` body), so both the per-arm distribute (Face A) and the union-close-once (Face B)
-- come by construction. A DEFINITION referent (`#Base`) still governs its own closedness (composes).
-- cue v0.16.1 adjudicates every face identically.

-- Face A (disjunction referent). Reject a use-site extra in every arm → empty disjunction (⊥).
theorem defflatten_indirect_disj_referent_rejects :
    exportJsonBottoms "_foo: {a: 1} | {b: 2}\n#X: _foo\nout: #X & {b: 2, z: 9}\n" = true := by
  native_decide

-- Face A select: a use-site meet matching ONE arm resolves to that arm (the `b`-arm survives).
theorem defflatten_indirect_disj_referent_selects_arm :
    exportJsonMatches "_foo: {a: 1} | {b: 2}\n#X: _foo\nout: #X & {b: 2}\n"
      "{\n    \"out\": {\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

-- Face A open-arm over-close guard: a `...` arm stays OPEN, so a use-site extra is ADMITTED there.
theorem defflatten_indirect_disj_referent_opentail_admits :
    exportJsonMatches "_foo: {a: 1, ...} | {b: 2}\n#X: _foo\nout: #X & {a: 1, z: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- Face B (conjunction of struct referents). Close ONCE over the UNION — both fields admitted.
theorem defflatten_indirect_conj_referent_admits_union :
    exportJsonMatches "_a0: {a: 1}\n_b0: {b: 2}\n#X: _a0 & _b0\nout: #X & {a: 1}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

-- Face B closedness guard: a genuine use-site extra `z` is NOT in the union `{a,b}` → ⊥ (no leak).
theorem defflatten_indirect_conj_referent_rejects_extra :
    exportJsonBottoms "_a0: {a: 1}\n_b0: {b: 2}\n#X: _a0 & _b0\ny: #X & {z: 9}\n" = true := by
  native_decide

-- Face B mixed ref + literal conjunct: same union-close-once — `{a}` referent ∪ `{b}` literal admit.
theorem defflatten_indirect_mixed_conj_admits_union :
    exportJsonMatches "_a0: {a: 1}\n#X: _a0 & {b: 2}\nout: #X & {a: 1}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

theorem defflatten_indirect_mixed_conj_rejects_extra :
    exportJsonBottoms "_a0: {a: 1}\n#X: _a0 & {b: 2}\ny: #X & {z: 9}\n" = true := by
  native_decide

-- Struct referent DISTRIBUTED across a disjunction referent: `{a} & ({b}|{c})` → `{a,c}` arm selected.
theorem defflatten_indirect_struct_distributes_over_disj :
    exportJsonMatches "_a0: {a: 1}\n_foo: {b: 2} | {c: 3}\n#X: _a0 & _foo\nout: #X & {c: 3}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- Same, closedness guard: an extra outside every distributed combination bottoms all arms → ⊥.
theorem defflatten_indirect_struct_disj_rejects_extra :
    exportJsonBottoms "_a0: {a: 1}\n_foo: {b: 2} | {c: 3}\n#X: _a0 & _foo\ny: #X & {a: 1, b: 2, z: 9}\n"
      = true := by
  native_decide

-- REGRESSION guard (def-ref composition unchanged): a def EXTENDING a def-ref (`#LS: #Base & {…}`)
-- still composes the ref's OWN closedness at the meet — a FOREIGN field rejects (not union-inlined).
theorem defflatten_indirect_defref_extend_rejects_foreign :
    exportJsonBottoms "#Base: {b: 1}\n#LS: #Base & {b: 1}\ny: #LS & {q: 9}\n" = true := by
  native_decide

-- REGRESSION guard (def-ref reaching a non-def referent): `#X: #Base`, `#Base: _foo`, `_foo: {a}`
-- closes through the def-ref chain — the resolution recurses at each def level.
theorem defflatten_indirect_defref_to_nondef_rejects :
    exportJsonBottoms "_foo: {a: 1}\n#Base: _foo\n#X: #Base\ny: #X & {z: 9}\n" = true := by
  native_decide

-- CONTROL (direct disj def body stays green): the DIRECT face already closed — must not regress.
theorem defflatten_indirect_direct_disj_control_rejects :
    exportJsonBottoms "#X: {a: 1} | {b: 2}\ny: #X & {b: 2, z: 9}\n" = true := by
  native_decide

-- CONTROL (non-def enclosing stays OPEN): closedness is a def property — a regular field indirecting
-- to a conjunction of structs admits a use-site extra.
theorem defflatten_indirect_nondef_enclosing_admits :
    exportJsonMatches "_a0: {a: 1}\n_b0: {b: 2}\n_x: _a0 & _b0\nout: _x & {z: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- COVERAGE TRIPWIRE (test-health). Anchors the LAST theorem of every section.
#check @eval_sc4_hidden_scalar_unaffected                     -- SC-4 hidden non-struct unaffected
#check @eval_sc4_hidden_list_elem_closes                      -- SC-4 closing recurses list elements
#check @eval_sc4_let_disjunction_arm_extra_bottoms            -- SC-4 closing recurses disjunction arms
#check @eval_pattern_disjunction_valued_rejects               -- pattern-constraint conformance probe
#check @defflatten_errorarm_select_admits                     -- DEF-FLATTEN-CLOSEDNESS
#check @defflatten_nestedconj_mixed_ref_stays_open            -- DEF-CLOSEDNESS-NESTED-CONJ-ARM
#check @defflatten_buried_selfref_deep_rejects                -- DEF-CLOSEDNESS-NESTED-CONJ-RESIDUAL
#check @defflatten_reref_regular_field_admits                 -- DEF-BODY-CLOSEDNESS-UNIFY
#check @defcomp_conjunct_nondef_control_admits                -- DEF-COMPREHENSION-CONJUNCT-USESITE-BOTTOM
#check @defflatten_indirect_nondef_enclosing_admits           -- DEF-CLOSEDNESS-INDIRECT-DISJ-CONJ

end Kue
