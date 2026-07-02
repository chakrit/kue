import Kue.Eval
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

-- # Comprehension evaluation pins
--
-- End-to-end + AST-level pins for the comprehension subsystem (`for` / `let` / `if`-guard
-- clauses, list and struct comprehensions). Carved out of `EvalTests.lean` (test-org pass).
-- The guard *classifier* unit pins (`classifyGuard`, D#1b/D#1c) live in `PresenceTests.lean`;
-- this module holds the comprehension-evaluation pins, including the comprehension-guard
-- end-to-end shapes. Each `.expected` string is cue v0.16.1-cross-checked.

namespace Kue

-- ### list-comprehension parse+eval pins (slice `list-comprehension-parse-eval`).
--
-- End-to-end behavioral pins over the full list-comprehension surface, each cue v0.16.1-exact (the
-- `.expected` strings are the oracle-checked outputs). Parsed-resolved-evaluated-formatted, so a
-- regression anywhere in the parser/resolver/eval chain trips them. Paired with the
-- fuel-truncation/saturation guards above (`sat_list_comprehension_*`).

-- for over a literal list, body uses the loop var.
theorem listcomp_for_basic :
    evalSourceMatches "out: [for x in [1, 2, 3] {x * 2}]\n" "out: [2, 4, 6]" = true := by
  native_decide

-- for-index form: `for i, x in list` binds the 0-based index.
theorem listcomp_for_index :
    evalSourceMatches "out: [for i, x in [10, 20, 30] {i*100 + x}]\n" "out: [10, 120, 230]"
      = true := by
  native_decide

-- for-k,v over a struct: iterates regular fields, binding key + value.
theorem listcomp_for_kv_struct :
    evalSourceMatches "out: [for k, v in {a: 1, b: 2} {v}]\n" "out: [1, 2]" = true := by
  native_decide

-- B3: a `for` over an `.embeddedList` (a struct embedding a list with decls) iterates the
-- EMBEDDED LIST, not zero times. cue v0.16.1: `for x in {#a:1,[1,2]}` → `[1, 2]`. The decls
-- (`#a`) are non-iterable members that the list iteration skips.
theorem listcomp_for_embedded_list :
    evalSourceMatches "out: [for x in {#a: 1, [1, 2]} {x}]\n" "out: [1, 2]" = true := by
  native_decide

-- A CONCRETE non-iterable `for` source is a TYPE ERROR (fix-slice (d), E#4 principle): the spec
-- mandates `for` range over a list or struct, so a concrete scalar is outside the domain — the
-- comprehension bottoms rather than silently zero-iterating. In a LIST comprehension the bottom is
-- the single element (`[_|_]`, same shape as a D#1a bottom guard); cue AGREES the source is a type
-- error (`cannot range over 5 …`) — Kue now conforms (see cue-divergences.md).
theorem listcomp_for_scalar_int_is_type_error :
    evalSourceMatches "out: [for x in 5 {x}]\n" "out: [_|_]" = true := by
  native_decide

theorem listcomp_for_scalar_string_is_type_error :
    evalSourceMatches "out: [for x in \"s\" {x}]\n" "out: [_|_]" = true := by
  native_decide

theorem listcomp_for_scalar_bool_is_type_error :
    evalSourceMatches "out: [for x in true {x}]\n" "out: [_|_]" = true := by
  native_decide

-- A scalar carrier (`{#a:1, 5}`) manifests as its inner scalar (int 5), so it inherits the SAME
-- concrete-non-iterable type error — consistent with a bare scalar, not a special case.
theorem listcomp_for_scalar_carrier_is_type_error :
    evalSourceMatches "out: [for x in {#a: 1, 5} {x}]\n" "out: [_|_]" = true := by
  native_decide

-- STRUCT comprehension over a concrete non-iterable: the whole struct bottoms (`out: _|_`), same
-- shape as a struct-comprehension non-bool guard.
theorem structcomp_for_scalar_int_is_type_error :
    evalSourceMatches "out: {for x in 5 {a: x}}\n" "out: _|_" = true := by
  native_decide

-- An abstract scalar TYPE (`int`) is DECIDABLY non-iterable (it can never unify to a list/struct),
-- so it is a type error just like a concrete scalar — cue agrees (`cannot range over y (found int,
-- want list or struct)`). This distinguishes "decidably-wrong" from a genuinely-unresolved source.
theorem listcomp_for_abstract_scalar_is_type_error :
    evalSourceMatches "y: int\nout: [for x in y {x}]\n" "y: int\nout: [_|_]" = true := by
  native_decide

-- A GENUINELY-UNRESOLVED `for` source (`_`, which may still resolve to a list/struct) DEFERS — the
-- comprehension stays a residual, NOT a type error. cue agrees: it HOLDS `out: [for x in y {x}]`
-- with `y: _`. This is the decidably-wrong→bottom / could-still-iterate→defer discipline; the
-- residual must not regress to either a spurious zero-iter or a spurious bottom.
theorem listcomp_for_top_source_defers :
    evalSourceMatches "y: _\nout: [for x in y {x}]\n" "y: _\nout: [for x in @0.0 {@1.0}]"
      = true := by
  native_decide

-- if guard mixed with a plain element: order preserved, false guard yields zero.
theorem listcomp_if_mixed :
    evalSourceMatches "out: [if true {1}, 2]\n" "out: [1, 2]" = true := by
  native_decide

theorem listcomp_if_false_zero :
    evalSourceMatches "out: [if false {42}]\n" "out: []" = true := by
  native_decide

-- for + if clause chain: the guard filters the iteration.
theorem listcomp_for_if_chain :
    evalSourceMatches "l: [1, 2, 3]\nout: [for x in l if x > 1 {x}]\n"
        "l: [1, 2, 3]\nout: [2, 3]" = true := by
  native_decide

-- nested for: the outer var is in scope for the inner; flattened in iteration order.
theorem listcomp_nested_for :
    evalSourceMatches "xs: [1, 2]\nys: [10, 20]\nout: [for x in xs for y in ys {x + y}]\n"
        "xs: [1, 2]\nys: [10, 20]\nout: [11, 21, 12, 22]" = true := by
  native_decide

-- mixed plain elements + comprehension: source order is preserved through the flatten.
theorem listcomp_mixed_order :
    evalSourceMatches "xs: [5, 6]\nout: [1, for x in xs {x}, 2]\n"
        "xs: [5, 6]\nout: [1, 5, 6, 2]" = true := by
  native_decide

-- empty source yields the empty list (not bottom).
theorem listcomp_empty_source :
    evalSourceMatches "out: [for x in [] {x}]\n" "out: []" = true := by
  native_decide

-- multiple elements yielded per outer iteration (inner for produces >1 each).
theorem listcomp_multi_yield :
    evalSourceMatches "out: [for x in [1, 2] for y in [x, x*10] {y}]\n" "out: [1, 10, 2, 20]"
      = true := by
  native_decide

-- struct-valued body element (body has a field, so the element IS that struct).
theorem listcomp_struct_body :
    evalSourceMatches "out: [for x in [1, 2] {a: x}]\n" "out: [{a: 1}, {a: 2}]" = true := by
  native_decide

-- ### `let`-clause comprehension pins (D#3).
--
-- `let <ident> = <expr>` as a comprehension clause: parses (was UNPARSEABLE), binds one name in a
-- NEW scope frame (`+1`, like `for`; `if` is `+0`) visible to subsequent clauses and the body. Spec:
-- *"The `for` and `let` clauses each define a new scope in which new values are bound to be available
-- for the next clause."* Each `.expected` is cue v0.16.1-cross-checked. The subtle pins are
-- `letcomp_for_after_let` (frame accounting: a `for` after a `let` must still resolve earlier
-- bindings across the let frame) and `letcomp_in_guard` (a later `if` reads the let-bound name).

-- basic: `let y = x*2` binds `y`, read by the body.
theorem letcomp_basic :
    evalSourceMatches "out: [for x in [1, 2, 3] let y = x * 2 {a: y}]\n"
        "out: [{a: 2}, {a: 4}, {a: 6}]" = true := by
  native_decide

-- a later `if` guard reads the let-bound name (`half`); frame depth across the let is correct.
theorem letcomp_in_guard :
    evalSourceMatches
        "out: [for x in [1, 2, 3, 4] let half = div(x, 2) if half*2 == x {even: x}]\n"
        "out: [{even: 2}, {even: 4}]" = true := by
  native_decide

-- chained lets: the second reads the first, then an `if` on the second.
theorem letcomp_multiple :
    evalSourceMatches "out: [for x in [1, 2, 3] let y = x * 2 let z = y + 1 if z > 3 {a: z}]\n"
        "out: [{a: 5}, {a: 7}]" = true := by
  native_decide

-- frame accounting: a `for` AFTER a `let`. The inner `for`'s source + body still resolve `y`
-- (and the outer `x`) correctly across the intervening let frame.
theorem letcomp_for_after_let :
    evalSourceMatches "out: [for x in [1, 2] let y = x + 10 for w in [y, y + 1] {v: w}]\n"
        "out: [{v: 11}, {v: 12}, {v: 12}, {v: 13}]" = true := by
  native_decide

-- the let SHADOWS an outer field `y`: the body sees the let `y`, the outer `y` is untouched.
theorem letcomp_shadows_outer :
    evalSourceMatches "y: \"outer\"\nout: [for x in [1, 2] let y = x * 10 {v: y}]\n"
        "y: \"outer\"\nout: [{v: 10}, {v: 20}]" = true := by
  native_decide

-- struct comprehension (not list): the let value feeds a dynamic field.
theorem letcomp_struct_form :
    evalSourceMatches "out: {\n\tfor x in [1, 2] let y = x + 100 {\n\t\t\"k\\(x)\": y\n\t}\n}\n"
        "out: {k1: 101, k2: 102}" = true := by
  native_decide

-- a REFERENCED let bound to a bottom propagates the bottom (cue: division by zero error).
theorem letcomp_referenced_bottom_propagates :
    evalSourceMatches "out: [for x in [1, 2] let bad = div(1, 0) {v: bad}]\n"
        "out: [{v: _|_}, {v: _|_}]" = true := by
  native_decide

-- an UNREFERENCED let bound to a bottom does NOT propagate — the binding sits unread in the
-- frame (cue agrees: `let bad = div(1,0)` unused yields the clean list). Lattice-correct: a dead
-- binding contributes nothing.
theorem letcomp_unreferenced_bottom_drops :
    evalSourceMatches "out: [for x in [1, 2] let bad = div(1, 0) {v: x}]\n"
        "out: [{v: 1}, {v: 2}]" = true := by
  native_decide

-- a `let` does NOT start a comprehension (spec `StartClause = ForClause | GuardClause`): a
-- struct-field-head `let` stays a struct-body let binding, NOT a comprehension clause.
theorem letcomp_let_not_start_clause :
    evalSourceMatches "out: {\n\tlet y = 5\n\tv: y\n}\n" "out: {v: 5}" = true := by
  native_decide

-- ### AST-level comprehension evaluation pins.
--
-- Direct `.structComp` shapes (constructed, not parsed) exercising `evalStructRefs` over the
-- comprehension clauses: `for` over a struct/list, `if` admit/drop, and the body/source seeing a
-- sibling field.

theorem eval_comprehension_for_keyed_over_struct :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [
            .comprehension
              [.forIn (some "k") "v" (mkStruct [⟨"x", .regular, .prim (.int 1)⟩] .regularOpen none [])]
              (mkStruct [⟨"key", .regular, .ref "k"⟩, ⟨"val", .regular, .ref "v"⟩] .regularOpen none [])
          ]
          .regularOpen))
      == mkStruct [⟨"key", .regular, .prim (.string "x")⟩, ⟨"val", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem eval_comprehension_for_over_list :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [
            .comprehension
              [.forIn none "v" (.list [.prim (.int 42)])]
              (mkStruct [⟨"only", .regular, .ref "v"⟩] .regularOpen none [])
          ]
          .regularOpen))
      == mkStruct [⟨"only", .regular, .prim (.int 42)⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_comprehension_if_true_admits :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [.comprehension [.guard (.prim (.bool true))] (mkStruct [⟨"flag", .regular, .prim (.bool true)⟩] .regularOpen none [])]
          .regularOpen))
      == mkStruct [⟨"flag", .regular, .prim (.bool true)⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_comprehension_if_false_drops :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [.comprehension [.guard (.prim (.bool false))] (mkStruct [⟨"hidden", .regular, .prim (.int 1)⟩] .regularOpen none [])]
          .regularOpen))
      == mkStruct [] .regularOpen none []) = true := by
  native_decide

theorem eval_comprehension_body_sees_sibling_field :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          [⟨"base", .regular, .prim (.int 7)⟩]
          [.comprehension [.guard (.prim (.bool true))] (mkStruct [⟨"copy", .regular, .ref "base"⟩] .regularOpen none [])]
          .regularOpen))
      == mkStruct [⟨"base", .regular, .prim (.int 7)⟩, ⟨"copy", .regular, .prim (.int 7)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem eval_comprehension_for_source_sees_sibling_field :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          [⟨"k", .regular, .prim (.int 3)⟩]
          [.comprehension [.forIn none "v" (.list [.ref "k"])] (mkStruct [⟨"g", .regular, .ref "v"⟩] .regularOpen none [])]
          .regularOpen))
      == mkStruct [⟨"k", .regular, .prim (.int 3)⟩, ⟨"g", .regular, .prim (.int 3)⟩] .regularOpen none [])
      = true := by
  native_decide

-- Slice C. The negated real-app guard shape: `x: bool | *false; if !x { y: 1 }`. The `!`
-- distributes over the default disjunction and the guard collapses the default to `true`,
-- so the body admits. cue-exact (`{x: false, out: {y: 1}}`).
theorem eval_comprehension_guard_negated_default_disj_admits :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"x", .regular, .disj [(.default, .prim (.bool false)), (.regular, .kind .bool)]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.unary .boolNot (.ref "x"))]
                 (mkStruct [⟨"y", .regular, .prim (.int 1)⟩] .regularOpen none [])]
               .regularOpen⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .disj [(.default, .prim (.bool false)), (.regular, .kind .bool)]⟩,
         ⟨"out", .regular, mkStruct [⟨"y", .regular, .prim (.int 1)⟩] .regularOpen none []⟩] .regularOpen none []) = true := by
  native_decide

-- Slice C. The direct guard shape `if x` with `x: bool | *true` admits (default `true`).
theorem eval_comprehension_guard_direct_default_disj_admits :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"x", .regular, .disj [(.default, .prim (.bool true)), (.regular, .kind .bool)]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.ref "x")]
                 (mkStruct [⟨"y", .regular, .prim (.int 1)⟩] .regularOpen none [])]
               .regularOpen⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .disj [(.default, .prim (.bool true)), (.regular, .kind .bool)]⟩,
         ⟨"out", .regular, mkStruct [⟨"y", .regular, .prim (.int 1)⟩] .regularOpen none []⟩] .regularOpen none []) = true := by
  native_decide

-- Slice C + D#1b. A NON-default disjunction guard is INCOMPLETE — only marked defaults
-- collapse to a concrete bool. `if x` with `x: true | false` (no default) cannot be decided,
-- so the comprehension DEFERS: it stays a residual `.structComp` carrying the unresolved
-- `.comprehension`, NOT a silent drop to `{}`. Matches cue eval (holds `if x {…}`; `cue export`
-- then errors `unresolved disjunction … (type bool)`). Pre-D#1b this WRONGLY dropped to `{}`.
theorem eval_comprehension_guard_non_default_disj_defers :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"x", .regular,
             .disj [(.regular, .prim (.bool true)), (.regular, .prim (.bool false))]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.ref "x")]
                 (mkStruct [⟨"y", .regular, .prim (.int 1)⟩] .regularOpen none [])]
               .regularOpen⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular,
           .disj [(.regular, .prim (.bool true)), (.regular, .prim (.bool false))]⟩,
         ⟨"out", .regular,
           .structComp []
             [.comprehension [.guard (.refId ⟨1, 0⟩)]
               (mkStruct [⟨"y", .regular, .prim (.int 1)⟩] .regularOpen none [])]
             .regularOpen⟩] .regularOpen none []) = true := by
  native_decide

-- ### `[]`-arm body-bottom asymmetry (AD4-1 — the `expandClauseChain` `onExhausted` parameter).
--
-- When a comprehension's clause chain is EXHAUSTED and the brace-block body itself evaluates to a
-- bare bottom, the struct and list comprehension drivers diverge — and this divergence is the entire
-- reason `expandClauseChain` takes the whole `[]`-arm body handler as a parameter rather than a naive
-- `body → β` wrap (a wrap would wrongly make the list twin bottom-propagate). It is VERIFIED-CORRECT
-- CUE semantics, not an accident, so it is pinned here so the AD4-1 dedup can never silently collapse
-- the two handlers into one.
--
-- - STRUCT (`out: {for x in ["s"] {x, a: 1}}`): embedding the string scalar `"s"` into the body
-- struct bottoms the WHOLE body; the struct `[]` handler SHORT-CIRCUITS that bare bottom (D#1a), so
-- `out` becomes `_|_`. cue agrees (`cannot combine regular field "a" with "s"`).
-- - LIST (`out: [for x in [1] {x & "s"}]`): the element `1 & "s"` bottoms, but the list `[]` handler
-- wraps ANY body — including a bottom — as a ONE-element list, so `out` becomes `[_|_]` (a list with
-- a bottom ELEMENT), NOT `_|_`. A bottom element is not the list being bottom; `cue eval` renders
-- the same value (`out.0: conflicting values "s" and 1`).
-- Both forms then ERROR identically under concrete `export` (the bottom surfaces either way).

-- STRUCT body-bottom SHORT-CIRCUITS: the comprehension collapses to the bare bottom.
theorem comprehension_struct_body_bottom_short_circuits :
    evalSourceMatches "out: {for x in [\"s\"] {x, a: 1}}\n" "out: _|_" = true := by
  native_decide

-- LIST body-bottom does NOT short-circuit: the bottom is an ELEMENT (`[_|_]`), not the list.
theorem comprehension_list_body_bottom_wraps_element :
    evalSourceMatches "out: [for x in [1] {x & \"s\"}]\n" "out: [_|_]" = true := by
  native_decide

-- Both forms error under concrete `export` — the asymmetry is in the SHAPE under eval (`_|_` vs
-- `[_|_]`), but concretization rejects either (a bottom value OR a list with a bottom element).
theorem comprehension_struct_body_bottom_export_errors :
    exportJsonBottoms "out: {for x in [\"s\"] {x, a: 1}}\n" = true := by
  native_decide

theorem comprehension_list_body_bottom_export_errors :
    exportJsonBottoms "out: [for x in [1] {x & \"s\"}]\n" = true := by
  native_decide

-- ### D#1d — comprehension body tail / pattern are body-local (emit fields, don't drop).
--
-- The struct-comprehension `[]`-arm handler (`expandClausesWithFuel`) emits the body struct's
-- named fields. A body's `...` tail and `[pat]:` constraints are BODY-LOCAL: they bound the body
-- block but do NOT propagate out of the `for`/`if` into the enclosing struct — only the named
-- fields merge (cue: `for _ in [1] {a: 1, ...}` ⇒ `{a: 1}`, the tail discarded). The handler match
-- formerly required `.struct _ _ none [] _` (no tail, no patterns), so a tail/pattern-bearing body
-- fell through to the catch-all and was DROPPED WHOLESALE — `a: 1` vanished with it. Now it matches
-- ANY `.struct`, taking the fields and leaving tail/patterns behind.

-- A body with an open `...` tail: emit the field, drop the tail (body-local).
theorem comprehension_body_tail_is_body_local :
    evalSourceMatches "out: {for x in [\"s\"] {a: 1, ...}}\n" "out: {a: 1}" = true := by
  native_decide

-- A body with a `[pattern]:` constraint: emit the field, drop the pattern (body-local).
theorem comprehension_body_pattern_is_body_local :
    evalSourceMatches "out: {for x in [\"s\"] {a: 1, [string]: int}}\n" "out: {a: 1}" = true := by
  native_decide

-- Export-faithful: the field survives concretely (a regression to the old drop would export `{}`).
theorem comprehension_body_tail_exports_field :
    exportJsonMatches "out: {for x in [\"s\"] {a: 1, ...}}\n"
      "{\n    \"out\": {\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- ### DYN-DEF-1 — dynamic-field label deferral (a dropped field becomes a held residual).
--
-- A dynamic field `(expr): v` whose `expr` is NOT yet a concrete string must be HELD as a residual
-- `.dynamicField`, not dropped — so a use-site narrowing that concretes `expr` can re-key it, and an
-- abstract export errors instead of silently vanishing (cue v0.16.1: holds under `eval`, errors
-- `key value of dynamic field must be concrete` under `export`). Pins are export-level (JSON,
-- display-independent) so the held-form's pre-existing `@d.i` reference rendering doesn't make them
-- brittle. The held-vs-dropped distinction is witnessed by `exportJsonBottoms`: a HELD residual
-- fails export (incomplete); a DROPPED field would export `{}` successfully.

-- The witness: a def's dynamic field, keyed on a field narrowed at the use site, is RE-KEYED
-- (not dropped). cue → `{out: {kind: "specific", specific: "m"}}`.
theorem dyndef_witness_rekeys_on_narrowing :
    exportJsonMatches
      "#Add: {kind: string, (kind): \"m\"}\nout: #Add & {kind: \"specific\"}\n"
      "{\n    \"out\": {\n        \"kind\": \"specific\",\n        \"specific\": \"m\"\n    }\n}\n" = true := by
  native_decide

-- Multiple dynamic fields in one def, all re-keyed once the shared key field narrows.
theorem dyndef_multi_dynamic_fields_rekey :
    exportJsonMatches
      "#M: {kind: string, (kind): \"a\", (\"x_\" + kind): \"b\"}\nout: #M & {kind: \"k\"}\n"
      "{\n    \"out\": {\n        \"kind\": \"k\",\n        \"k\": \"a\",\n        \"x_k\": \"b\"\n    }\n}\n" = true := by
  native_decide

-- Transitive: the dynamic key reads a sibling (`key`) that itself reads the narrowed field, so
-- the narrowing reaches the dynamic key through a chain. cue keys it `specific`.
theorem dyndef_transitive_narrowing_rekeys :
    exportJsonMatches
      "#Add: {kind: string, key: kind, (key): \"m\"}\nout: #Add & {kind: \"specific\"}\n"
      "{\n    \"out\": {\n        \"kind\": \"specific\",\n        \"key\": \"specific\",\n        \"specific\": \"m\"\n    }\n}\n"
      = true := by native_decide

-- Regression: a dynamic field whose key is ALREADY concrete in the def keys eagerly (the path
-- the fix must not disturb). cue → `{out: {kind: "fixed", fixed: "m"}}`.
theorem dyndef_concrete_key_in_def_rekeys :
    exportJsonMatches
      "#K: {kind: \"fixed\", (kind): \"m\"}\nout: #K\n"
      "{\n    \"out\": {\n        \"kind\": \"fixed\",\n        \"fixed\": \"m\"\n    }\n}\n" = true := by
  native_decide

-- A def's dynamic field with a NEVER-concrete key is HELD, not dropped: export errors (incomplete)
-- because the field survives. Pre-fix it dropped and `x` exported as `{}`. This is the core
-- regression witness for DYN-DEF-1.
theorem dyndef_abstract_key_held_export_errors :
    exportJsonBottoms "#Add: {kind: string, (kind): \"m\"}\nx: #Add\n" = true := by
  native_decide

-- Same for a PLAIN struct (no definition): the bug and fix are not def-specific.
theorem dyndef_abstract_key_plain_struct_held_export_errors :
    exportJsonBottoms "s: string\nout: {(s): \"m\"}\n" = true := by
  native_decide

-- A CONCRETE non-string key is a type error (cue: `invalid index … (invalid type bool)`), not a
-- silent drop — export bottoms.
theorem dyndef_concrete_nonstring_key_errors :
    exportJsonBottoms "out: {(true): \"m\"}\n" = true := by
  native_decide

-- A BOTTOM key propagates the bottom (the underlying conflict), not a silent drop.
theorem dyndef_bottom_key_propagates :
    exportJsonBottoms "out: {((1 & 2)): \"m\"}\n" = true := by
  native_decide

-- ### Dynamic-field label DEFAULT-disjunction collapse (DYN-DEF-1 follow-up).
--
-- A dynamic-field label that evaluates to a DEFAULT disjunction collapses to its default before
-- classification (`resolveDynLabelDefault` at both `.dynamicField` sites), exactly as a default
-- disjunction collapses as an `if` guard or under manifestation — so `(*"a" | "b"): v` keys on
-- `"a"`. Pre-fix `classifyDynLabel`'s `.disj` arm sent EVERY disjunction (default or not) to DEFER,
-- so a default-keyed field was wrongly held and exported `incomplete` instead of cue's concrete
-- re-key. The AMBIGUOUS (non-default) disjunction still defers — `resolveDisjDefault?` returns none
-- and the field stays a residual (its own pin below, `dyndef_nondefault_disj_key_still_defers`).

-- A default disjunction label keys on its default. cue v0.16.1 → `{out: {a: 1}}`.
theorem dyndef_default_disj_key_collapses :
    exportJsonMatches "out: {(*\"a\" | \"b\"): 1}\n"
      "{\n    \"out\": {\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- The default arrives through a field reference. cue → `{k: "a", out: {a: 1}}`.
theorem dyndef_default_disj_key_via_ref :
    exportJsonMatches "k: *\"a\" | \"b\"\nout: {(k): 1}\n"
      "{\n    \"k\": \"a\",\n    \"out\": {\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- A default whose chosen value is a CONCRETE non-string is a type error (the collapse exposes
-- the int default `3`, which cannot label): export bottoms (cue: `integer fields not supported`).
theorem dyndef_default_disj_key_nonstring_errors :
    exportJsonBottoms "out: {(*3 | \"b\"): 1}\n" = true := by
  native_decide

-- The boundary: an AMBIGUOUS disjunction (no default, two live arms) does NOT collapse — it stays
-- incomplete and the field DEFERS (held), so export errors. Pre- and post-fix identical; pins the
-- guard so the collapse never over-fires on a non-default disjunction.
theorem dyndef_nondefault_disj_key_still_defers :
    exportJsonBottoms "out: {(\"a\" | \"b\"): 1}\n" = true := by
  native_decide



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @listcomp_struct_body                               -- list-comprehension parse+eval pins (slice `list-c...
#check @letcomp_let_not_start_clause                       -- `let`-clause comprehension pins (D#3)
#check @eval_comprehension_guard_non_default_disj_defers   -- AST-level comprehension evaluation pins
#check @comprehension_list_body_bottom_export_errors       -- `[]`-arm body-bottom asymmetry (AD4-1 — the `expa...
#check @comprehension_body_tail_exports_field              -- D#1d — comprehension body tail / pattern are body...
#check @dyndef_bottom_key_propagates                       -- DYN-DEF-1 — dynamic-field label deferral (a dropp...
#check @dyndef_nondefault_disj_key_still_defers            -- Dynamic-field label DEFAULT-disjunction collapse...

end Kue
