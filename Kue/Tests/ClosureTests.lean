import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

/-! ## `Value.closure` constructor — slice 1 (closure-ctor) round-trip pins

The constructor is inert (no producer yet); these theorems lock its identity so the later
producer/meet slices can't silently corrupt hashing or comparison. -/

/-- A closure `BEq`-compares equal to itself (derived `BEq` extends to the new arm). -/
theorem closure_beq_self :
    ((Value.closure [(0, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name"))
      == (Value.closure [(0, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name")))
      = true := by
  native_decide

/-- A different captured env makes two closures compare unequal — the captured ids carry
    the "independently-built frames never falsely share" invariant into `BEq`. -/
theorem closure_beq_distinct_env :
    ((Value.closure [(0, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name"))
      == (Value.closure [(1, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name")))
      = false := by
  native_decide

/-- A different body makes two closures compare unequal. -/
theorem closure_beq_distinct_body :
    ((Value.closure [(0, [])] (.ref "a")) == (Value.closure [(0, [])] (.ref "b")))
      = false := by
  native_decide

/-- The closure tag is its own bucket in the memo hash (no collision with other arms). -/
theorem closure_valueTag :
    valueTag (.closure [(0, [])] .top) = 29 := by
  native_decide

/-! ### slice 2 (closure-eval) — forcing the deferred body under its captured env

The eval arm forces `body` against `capturedEnv` (lexical scope), discarding the call-site
env/visited. No producer yet ⇒ these run on hand-built `.closure` literals, but they pin the
semantic anchor slices 3-4 target. -/

/-- Forcing a closure evaluates its body under the captured env: a depth-0 ref into the
    captured frame resolves to that frame's binding, proving the body sees `capturedEnv`. -/
theorem closure_eval_forces_captured_binding :
    (runEval (evalValueWithFuel evalFuel [] []
        (.closure [(7, [⟨"x", .regular, .prim (.int 42)⟩])] (.refId ⟨0, 0⟩)))
      == .prim (.int 42)) = true := by
  native_decide

/-- A closure with an empty captured env forces a body that needs no scope to a literal. -/
theorem closure_eval_empty_captured_env :
    (runEval (evalValueWithFuel evalFuel [] []
        (.closure [] (.prim (.int 1))))
      == .prim (.int 1)) = true := by
  native_decide

/-- A closure whose body is itself a closure forces through both layers (nested force):
    the inner closure carries its own captured frame, resolved when the outer body forces. -/
theorem closure_eval_nested_closure :
    (runEval (evalValueWithFuel evalFuel [] []
        (.closure []
          (.closure [(9, [⟨"y", .regular, .prim (.string "inner")⟩])] (.refId ⟨0, 0⟩))))
      == .prim (.string "inner")) = true := by
  native_decide

/-- Lexical, not dynamic, scope: the call-site env binds slot 0 to one value, the captured
    env binds it to another. The closure resolves against the captured env — its definition
    site — so the call-site binding (which would win under dynamic scope) is ignored. -/
theorem closure_eval_lexical_not_dynamic :
    (runEval (evalValueWithFuel evalFuel
        [(3, [⟨"x", .regular, .prim (.string "callsite")⟩])] []
        (.closure [(7, [⟨"x", .regular, .prim (.string "captured")⟩])] (.refId ⟨0, 0⟩)))
      == .prim (.string "captured")) = true := by
  native_decide

/-- Fuel exhaustion degrades like every other arm — at `fuel = 0` the closure passes
    through unevaluated rather than crashing or looping. -/
theorem closure_eval_fuel_exhaustion :
    (runEval (evalValueWithFuel 0 []
        [] (.closure [(7, [⟨"x", .regular, .prim (.int 42)⟩])] (.refId ⟨0, 0⟩)))
      == .closure [(7, [⟨"x", .regular, .prim (.int 42)⟩])] (.refId ⟨0, 0⟩)) = true := by
  native_decide

/-- Inert manifest: an unforced closure is non-concrete (incomplete). -/
theorem closure_manifest_incomplete :
    manifest (.closure [(0, [])] (.prim (.int 1)))
      = .error (.incomplete (.closure [(0, [])] (.prim (.int 1)))) := by
  rfl

/-- Inert meet: a closure does not unify with anything yet (slice 4 changes this). -/
theorem closure_meet_bottom :
    (meet (.closure [(0, [])] .top) (.struct [] .regularOpen none []) == .bottom) = true := by
  native_decide

/-! ### slice 3 (closure-producer) — the import-selector arm emits a closure

White-box pins: closures are not user-visible until slice 4, so these assert the producer
CONSTRUCTS the right `.closure` (full id-stack captured, unevaluated def body) at the
trigger site, and — critically — that the shapes which currently resolve correctly do NOT
become closures. `runEval` starts `nextFrameId := 0`, so the producer's first `pushFrame`
captures frame id `0`. -/

/-- The collapse shape: a package struct `parts` holding a definition `#M` whose body
    self-references a sibling (`out: #name`, `refId ⟨0,0⟩`). Selecting `parts.#M` OUTSIDE a
    conjunction defers to a closure, then FORCES it standalone (no use-operands) — the terminal
    value when there is no use-site to splice. With no narrowing, `out: #name` collapses against
    the def's own `#name: string`, so the forced result is `{#name: string, out: string}`,
    normalized-CLOSED (`open_ := false`). (A `pkg.#M & {narrow}` instead splices the narrowing via
    the `.conj` fold, which re-produces the closure from the raw selector — see
    `crosspkg_defmeet`.) -/
theorem closure_producer_emits_on_selfref_def :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"parts", .hidden,
          .struct [⟨"#M", .definition,
            .struct [⟨"#name", .definition, .kind .string⟩,
                     ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []⟩] .regularOpen none []⟩])] []
        (.selector (.refId ⟨0, 0⟩) "#M"))
      == .struct [⟨"#name", .definition, .kind .string⟩,
                  ⟨"out", .regular, .kind .string⟩] .defClosed none []) = true := by
  native_decide

/-- NON-REGRESSION: a definition WITHOUT a sibling self-reference (`#Widget` = flat
    `{name: string, size: int}`) stays on the eager path — selecting it yields the evaluated
    field, NOT a closure. This is every committed `pkg.#Def & {…}` fixture's shape; the gate
    must leave it untouched so slice 3 is byte-identical on all of them. -/
theorem closure_producer_skips_selfref_free_def :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"defs", .hidden,
          .struct [⟨"#Widget", .definition,
            .struct [⟨"name", .regular, .kind .string⟩,
                     ⟨"size", .regular, .kind .int⟩] .regularOpen none []⟩] .regularOpen none []⟩])] []
        (.selector (.refId ⟨0, 0⟩) "#Widget"))
      == .struct [⟨"name", .regular, .kind .string⟩,
                  ⟨"size", .regular, .kind .int⟩] .regularOpen none []) = true := by
  native_decide

/-- NON-REGRESSION: a NON-definition field (regular, not `#`) with a sibling self-ref is NOT
    a definition selection, so it stays eager — only `#`-definitions defer. -/
theorem closure_producer_skips_non_definition :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"pkg", .hidden,
          .struct [⟨"r", .regular,
            .struct [⟨"a", .regular, .prim (.int 1)⟩,
                     ⟨"b", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []⟩] .regularOpen none []⟩])] []
        (.selector (.refId ⟨0, 0⟩) "r"))
      == .struct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none []) = true := by
  native_decide

/-- FULL ID-STACK capture: the producer captures the ENTIRE env (not just the package frame)
    when building the closure, so a def body's depth>0 cross-package embeds still walk the import
    chain when forced. Selected standalone (no conjunction), the closure is forced with no
    use-operands; `out: refId ⟨0,1⟩` reads the def's own sibling slot 1 (`x`), so the forced
    result is `{out: 1, x: 1}`, normalized-CLOSED. The outer frame 7 is retained beneath the
    pushed package frame — the capture is the full id-stack, not just the package frame. -/
theorem closure_producer_captures_full_id_stack :
    (runEval (evalValueWithFuel evalFuel
        [(5, [⟨"parts", .hidden,
          .struct [⟨"#M", .definition,
            .struct [⟨"out", .regular, .refId ⟨0, 1⟩⟩,
                     ⟨"x", .regular, .prim (.int 1)⟩] .regularOpen none []⟩] .regularOpen none []⟩]),
         (7, [⟨"outer", .regular, .prim (.int 9)⟩])] []
        (.selector (.refId ⟨0, 0⟩) "#M"))
      == .struct [⟨"out", .regular, .prim (.int 1)⟩,
                  ⟨"x", .regular, .prim (.int 1)⟩] .defClosed none []) = true := by
  native_decide

/-- DEPTH-MATCHED self-ref detection (slice A): a `refId ⟨0,0⟩` nested inside a `.struct` field
    is depth-0 relative to that NESTED frame, NOT the def body — `hasSelfRefAtDepth` descends to
    depth 1 there, so `⟨0,0⟩` (`d == 0 ≠ 1`) is the nested frame's own sibling, not the def's. So
    a def whose only inner ref sits in a nested struct and points at THAT frame is not a def
    self-ref and stays eager. Pins the boundary that keeps the gate from over-firing. -/
theorem closure_producer_nested_struct_ref_not_sibling :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"nested", .regular,
                    .struct [⟨"inner", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []⟩] .regularOpen none [])) = false := by
  native_decide

/-- And the positive companion: a direct sibling ref IS detected. -/
theorem closure_producer_direct_sibling_ref_detected :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#name", .definition, .kind .string⟩,
                  ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none [])) = true := by
  native_decide

/-- DEEP self-ref (slice A — the real-app shape): a hidden field read from a NESTED struct
    (`spec: acme: email: #email`, where `#email` is a top-level def field referenced from 3
    frames deep → `refId ⟨3, _⟩`) IS a def self-ref. `hasSelfRefAtDepth` descends `spec`(1),
    `acme`(2), then matches `refId ⟨2, 0⟩` at depth 2 — `d == depth` lands on the def frame. This
    is exactly the shape `#ClusterIssuer`/`#Secret` use that slice 4's depth-0-only gate missed. -/
theorem closure_producer_deep_nested_self_ref_detected :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#email", .definition, .kind .string⟩,
                  ⟨"spec", .regular,
                    .struct [⟨"acme", .regular,
                      .struct [⟨"email", .regular, .refId ⟨2, 0⟩⟩] .regularOpen none []⟩] .regularOpen none []⟩] .regularOpen none [])) = true := by
  native_decide

/-- DEEP self-ref in a comprehension GUARD (slice A): `if Self.#staging` inside a nested struct
    references the def's `#staging` from the guard condition, which `hasSelfRefAtDepth` scans at
    the comprehension's own depth. A `refId ⟨1, 0⟩` in a guard one struct deep matches depth 1. -/
theorem closure_producer_comprehension_guard_self_ref_detected :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#staging", .definition, .kind .bool⟩,
                  ⟨"spec", .regular,
                    .structComp [] [.comprehension [.guard (.refId ⟨1, 0⟩)]
                      (.struct [⟨"server", .regular, .prim (.string "x")⟩] .regularOpen none [])] true false⟩] .regularOpen none [])) = true := by
  native_decide

/-! ### A5-followup — comprehension-BODY self-ref deferral gate (`hasSelfRefAtDepthClauses`)

`hasSelfRefAtDepth`'s comprehension arms previously scanned the BODY at the comprehension's own
`depth`, ignoring the loop frame each `for` clause pushes. So a `Self.#t` read inside a `for`
body — resolved at `depth + #forClauses` — was compared against `depth`, MISSED, and the def
`#R = {#H, out: [for x in [1] {v: Self.#t}]}` was judged to have NO sibling self-ref. The `.conj`
`#R & {#t: "y"}` then took the eager-then-meet path (which cannot re-evaluate the comprehension
against the narrowed frame) instead of the closure-force path → stale `out: [{v: string|*"def"}]`.
Threading the loop-frame depth (`hasSelfRefAtDepthClauses`, +1 per `for`, +0 per `guard`) detects
the deep body ref and restores deferral. These pin the gate at the realistically-resolved depths. -/

/-- A `.list [.listComprehension [for x …] {v: Self.#t}]` static-field value: the `Self` alias
    read in the body resolves to `refId ⟨2, _⟩` (loop frame +1, body struct +1). Scanned from the
    def frame (depth 0), the body sits at depth 2, so `⟨2,0⟩` IS the def self-ref — DETECTED only
    once the loop frame is threaded. Pre-fix the body was scanned at depth 1 → `2 ≠ 1` → missed. -/
theorem a5fu_listcomp_body_self_ref_detected :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#t", .definition, .kind .string⟩,
                  ⟨"out", .regular,
                    .list [.listComprehension [.forIn none "x" (.list [.prim (.int 1)])]
                      (.struct [⟨"v", .regular, .refId ⟨2, 0⟩⟩] .regularOpen none [])]⟩] .regularOpen none [])) = true := by
  native_decide

/-- BOUNDARY (no over-detection): the SAME shape but the body ref lands at depth 1 (`⟨1,0⟩`) —
    the loop frame's own variable, NOT the def. With the loop-frame shift, the body is scanned at
    depth 2, so `⟨1,0⟩` (`1 ≠ 2`) is correctly NOT a def self-ref and the def stays eager. -/
theorem a5fu_listcomp_body_loopvar_ref_not_self :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#t", .definition, .kind .string⟩,
                  ⟨"out", .regular,
                    .list [.listComprehension [.forIn none "x" (.list [.prim (.int 1)])]
                      (.struct [⟨"v", .regular, .refId ⟨1, 0⟩⟩] .regularOpen none [])]⟩] .regularOpen none [])) = false := by
  native_decide

/-- MULTI-`for`: two `for` clauses push two loop frames, so the body's def self-ref resolves to
    `refId ⟨3, _⟩` (loop +1, loop +1, body struct +1). `hasSelfRefAtDepthClauses` adds +1 per
    `for`, so the body is scanned at depth 3 and `⟨3,0⟩` is detected. -/
theorem a5fu_listcomp_body_multi_for_self_ref_detected :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#t", .definition, .kind .string⟩,
                  ⟨"out", .regular,
                    .list [.listComprehension
                      [.forIn none "x" (.list [.prim (.int 1)]),
                       .forIn none "y" (.list [.prim (.int 2)])]
                      (.struct [⟨"v", .regular, .refId ⟨3, 0⟩⟩] .regularOpen none [])]⟩] .regularOpen none [])) = true := by
  native_decide

/-- A `guard` pushes NO frame: with one `for` then an `if`, the body's def self-ref is still at
    `refId ⟨2, _⟩` (only the single `for` loop frame + body struct), and the guard condition reading
    the def (`if Self.#on`, `⟨1,0⟩` under the one loop frame) is detected at the clause level. Pins
    that `guard` contributes +0 to the body depth while still being scanned itself. -/
theorem a5fu_listcomp_body_guard_no_extra_frame :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#t", .definition, .kind .string⟩,
                  ⟨"out", .regular,
                    .list [.listComprehension
                      [.forIn none "x" (.list [.prim (.int 1)]), .guard (.refId ⟨1, 0⟩)]
                      (.struct [⟨"v", .regular, .refId ⟨2, 0⟩⟩] .regularOpen none [])]⟩] .regularOpen none [])) = true := by
  native_decide

/-- The clause helper threads depth directly: a STRUCT-context comprehension body whose self-ref
    lands at `⟨1,_⟩` under one `for` is detected by `hasSelfRefAtDepthClauses` at base depth 0
    (the loop frame puts the body at depth 1). Mirrors the `.comprehension` (struct) arm. -/
theorem a5fu_structcomp_body_self_ref_detected :
    (hasSelfRefAtDepthClauses evalFuel 0
        [.forIn none "x" (.list [.prim (.int 1)])]
        (.refId ⟨1, 0⟩)) = true := by
  native_decide

/-! ### slice 4 (closure-meet) — splice the use-site struct into the forced def body

THE unlock: `defs.#M & {#name: "keel"}` where `#M = {#name: string, out: #name}` is an
imported self-referential definition. The `.conj` fallback evaluates `defs.#M` to a closure
(slice 3) and `{#name: "keel"}` to a struct; instead of the inert `meet` (→ `.bottom`), the
closure is forced with the use-site spliced in as an extra conjunct, so `out`'s `#name` ref
sees the narrowed `"keel"` instead of collapsing to `string`. The env mirrors the producer
tests (package binding at frame 7); `runEval` allocates the closure's pushed frame ids. -/

private def pkgEnvWith (defBody : Value) : Env :=
  [(7, [⟨"parts", .hidden, .struct [⟨"#M", .definition, defBody⟩] .regularOpen none []⟩])]

private def selfRefM : Value :=
  .struct [⟨"#name", .definition, .kind .string⟩, ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []

/-- THE unlock pinned: forcing `parts.#M & {#name: "keel"}` yields `out: "keel"` (the hidden
    `#name` and the spliced narrowing resolve), NOT the slice-3 `.bottom`. Body is closed
    (`open_ := false`) because `#M` is a definition. -/
theorem closure_meet_splices_use_site :
    (runEval (evalValueWithFuel evalFuel (pkgEnvWith selfRefM) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] .regularOpen none []]))
      == .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                  ⟨"out", .regular, .prim (.string "keel")⟩] .defClosed none []) = true := by
  native_decide

/-- CONFLICT → bottom: the use-site narrows `#name` to a value the def's own `#name` rejects
    (def `#name: "fixed"`, use-site `#name: "keel"`). The splice unifies the two `#name`
    conjuncts → a primitive conflict, which propagates through `#name`'s spliced slot AND
    `out`'s ref to it as a field-local `.bottomWith`; export then rejects the struct. -/
theorem closure_meet_conflict_is_bottom :
    (runEval (evalValueWithFuel evalFuel
        (pkgEnvWith (.struct [⟨"#name", .definition, .prim (.string "fixed")⟩,
                              ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none [])) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] .regularOpen none []]))
      == .struct [⟨"#name", .definition,
            .bottomWith [.primitiveConflict (.string "fixed") (.string "keel")]⟩,
           ⟨"out", .regular,
            .bottomWith [.primitiveConflict (.string "fixed") (.string "keel")]⟩] .defClosed none []) = true := by
  native_decide

/-- EMPTY use-site: `parts.#M & {}` == `parts.#M` — splicing zero use fields leaves the def
    body unchanged (here `#name` stays `string`, so `out` is `string`). -/
theorem closure_meet_empty_use_site :
    (runEval (evalValueWithFuel evalFuel (pkgEnvWith selfRefM) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M", .struct [] .regularOpen none []]))
      == .struct [⟨"#name", .definition, .kind .string⟩,
                  ⟨"out", .regular, .kind .string⟩] .defClosed none []) = true := by
  native_decide

/-- SELF-REF captured frame TERMINATES (does not loop / exhaust fuel): a def field referencing
    itself directly (`loop: loop`, `refId ⟨0,1⟩` at its own slot) is caught by the ordinary
    `slotVisited` machinery on the pushed frame and resolves to `.top` rather than diverging.
    `out` still resolves to the spliced `#name`. -/
theorem closure_meet_self_ref_terminates :
    (runEval (evalValueWithFuel evalFuel
        (pkgEnvWith (.struct [⟨"#name", .definition, .kind .string⟩,
                              ⟨"loop", .regular, .refId ⟨0, 1⟩⟩,
                              ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none [])) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] .regularOpen none []]))
      == .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                  ⟨"loop", .regular, .top⟩,
                  ⟨"out", .regular, .prim (.string "keel")⟩] .defClosed none []) = true := by
  native_decide

/-- OPEN def body (`...` → `.structTail`): the use-site may add a field absent from the def,
    and it appears in the output; `out` still sees the narrowed `#name`. The forced body stays
    a `.structTail` (open). -/
theorem closure_meet_open_def_admits_extra :
    (runEval (evalValueWithFuel evalFuel
        (pkgEnvWith (.struct [⟨"#name", .definition, .kind .string⟩,
                                  ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .defOpenViaTail (some .top) [])) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                         ⟨"extra", .regular, .prim (.int 42)⟩] .regularOpen none []]))
      == .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                      ⟨"out", .regular, .prim (.string "keel")⟩,
                      ⟨"extra", .regular, .prim (.int 42)⟩] .defOpenViaTail (some .top) []) = true := by
  native_decide

/-- The producer NOW also fires on an OPEN (`.structTail`) self-ref def body (slice 4 extends
    `defBodyHasSiblingSelfRef` to `.structTail`), so open imported defs defer too. -/
theorem closure_producer_detects_structtail_sibling :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#name", .definition, .kind .string⟩,
                      ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .defOpenViaTail (some .top) [])) = true := by
  native_decide

/-! ### slice A (closure-realapp-selfalias) — multi-operand fold + `.structComp` embed defs

Real prod9 apps use value-alias defs that EMBED cross-package defs
(`#Def: { parts.#Metadata; #x: string; spec: #x }`). The embed makes the def body a
`.structComp` (the parser routes embeddings into `structComp.comprehensions`), which slice 4's
gate/force/embedding-meet paths all dropped. Slice A: (A.1) gate fires on `.structComp` siblings,
(A.2) the force path splices use-operands into a `.structComp` body and meet-folds its
embeddings, (A.3) the `.conj` fold splices the SHARED use set into EVERY closure operand, (A.4)
an embedding/operand that evaluated to a `.closure` is force-spliced not plain-`meet`-ed. -/

/-- A.1 GATE: a `.structComp` def body (an embedding-bearing def) with a sibling self-ref in its
    static fields IS detected — slice 4's gate only matched `.struct`/`.structTail`, so an
    embed-def returned `false` and never deferred. -/
theorem closure_producer_detects_structcomp_sibling :
    (defBodyHasSiblingSelfRef
        (.structComp [⟨"#x", .definition, .kind .string⟩,
                      ⟨"spec", .regular, .refId ⟨0, 1⟩⟩]
                     [.struct [⟨"kind", .regular, .prim (.string "Service")⟩] .regularOpen none []] true false)) = true := by
  native_decide

/-- A.1 GATE companion: a `.structComp` whose self-ref lives in the EMBEDDING (not the static
    fields) is also detected — the gate scans comprehensions too. -/
theorem closure_producer_detects_structcomp_embedding_sibling :
    (defBodyHasSiblingSelfRef
        (.structComp [⟨"#x", .definition, .kind .string⟩]
                     [.refId ⟨0, 0⟩] true false)) = true := by
  native_decide

/-- A.2 FORCE `.structComp`: `parts.#Def & {#x: "hello"}` where `#Def` embeds a literal struct
    `{kind: "Service"}` and has a self-ref `spec: #x`. The force splices `{#x:"hello"}` into the
    static fields BEFORE evaluating, so `spec` sees `"hello"`, AND meet-folds the embedding so
    `kind` appears. Was `incomplete value: string` (eager collapse) pre-slice-A. -/
private def embedDefBody : Value :=
  .structComp [⟨"#x", .definition, .kind .string⟩,
               ⟨"spec", .regular, .refId ⟨0, 0⟩⟩]
              [.struct [⟨"kind", .regular, .prim (.string "Service")⟩] .regularOpen none []] false false

theorem closure_meet_structcomp_embed_splices :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"defs", .hidden, .struct [⟨"#Def", .definition, embedDefBody⟩] .regularOpen none []⟩])] []
        (.conj [.selector (.refId ⟨0, 0⟩) "#Def",
                .struct [⟨"#x", .definition, .prim (.string "hello")⟩] .regularOpen none []]))
      == .struct [⟨"#x", .definition, .prim (.string "hello")⟩,
                  ⟨"spec", .regular, .prim (.string "hello")⟩,
                  ⟨"kind", .regular, .prim (.string "Service")⟩] .defClosed none []) = true := by
  native_decide

/-- A.3 MULTI-OPERAND FOLD: `#M & #N & {narrow}` — two self-ref imported defs met with one
    use-site struct narrowing BOTH. Slice 4 spliced only the first closure (`#M`); the second
    (`#N`) was forced UNSPLICED → `tag: #label` collapsed → `incomplete value: string`. The fold
    splices the shared use set into BOTH. `#M = {#name, out:#name}`, `#N = {#label, tag:#label}`,
    both open (`...`) so they admit each other's fields. -/
private def twoDefEnv : Env :=
  [(7, [⟨"defs", .hidden,
    .struct [⟨"#M", .definition,
        .struct [⟨"#name", .definition, .kind .string⟩,
                     ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .defOpenViaTail (some .top) []⟩,
       ⟨"#N", .definition,
        .struct [⟨"#label", .definition, .kind .string⟩,
                     ⟨"tag", .regular, .refId ⟨0, 0⟩⟩] .defOpenViaTail (some .top) []⟩] .regularOpen none []⟩])]

theorem closure_meet_multi_operand_fold :
    (runEval (evalValueWithFuel evalFuel twoDefEnv []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .selector (.refId ⟨0, 0⟩) "#N",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                         ⟨"#label", .definition, .prim (.string "x")⟩] .regularOpen none []]))
      == .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                      ⟨"out", .regular, .prim (.string "keel")⟩,
                      ⟨"#label", .definition, .prim (.string "x")⟩,
                      ⟨"tag", .regular, .prim (.string "x")⟩] .defOpenViaTail (some .top) []) = true := by
  native_decide

/-- GENUINE CAPTURED-FRAME CYCLE termination (replaces the weak depth-0-slot
    `closure_meet_self_ref_terminates`): the closure's CAPTURED package frame contains a binding
    `#Self` that refs BACK into the def at depth 1 (`refId ⟨1, 0⟩` — out of the def's own frame,
    into the package frame, at `#Self`'s own slot → a capture-level self-loop). Forcing must
    terminate (→ `.top` for the cyclic slot) rather than diverge / exhaust fuel. -/
private def capturedCycleEnv : Env :=
  [(7, [⟨"pkg", .hidden,
    .struct [⟨"#Self", .definition, .refId ⟨0, 0⟩⟩,
       ⟨"#M", .definition,
        .struct [⟨"#name", .definition, .kind .string⟩,
                 ⟨"back", .regular, .refId ⟨1, 0⟩⟩,
                 ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []⟩] .regularOpen none []⟩])]

theorem closure_meet_captured_frame_cycle_terminates :
    (runEval (evalValueWithFuel evalFuel capturedCycleEnv []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] .regularOpen none []]))
      == .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                  ⟨"back", .regular, .top⟩,
                  ⟨"out", .regular, .prim (.string "keel")⟩] .defClosed none []) = true := by
  native_decide

/-! ### slice E (closure-embed-chain) — multi-level embed chains + the closedness leak.

The 3-level real shape `#ClusterIssuer → parts.#Metadata → attr.#Metadata` collapsed to `bottom`.
TWO independent root causes (both fixed here): (E1) the eager `.structComp` eval arm and the
non-closure branch of `meetEmbeddingsWithFuel` let an embedded CLOSED struct impose its closedness
on the host's regular fields → `.bottom` (slice A's hidden-only embeds dodged it). (E2) a bare ref
to a self-ref def the lazy-merge path can't splice — an embed-bearing `.structComp` (any depth) or a
NESTED (`depth > 0`) `.struct`/`.structTail` (the inner def of an embed chain) — was evaluated
eagerly, collapsing its self-ref before the use-site narrowing arrived. Fix: producers
(`refDefClosureBody?`/`conjDefClosure?`) defer them to `.closure`s the force-fold splices. -/

/-- E1 CLOSEDNESS LEAK (the closedness rule, isolated): `closeEmbeddedOver` re-closes a meet-folded
    struct over `def ∪ embed` labels — a field declared by neither the def nor any embedding is
    rejected, one declared by EITHER survives. This is what lets an embedding widen the host's
    allowed set without imposing its own closedness. -/
theorem close_embedded_over_unions_allowed_labels :
    (closeEmbeddedOver [⟨"a", .regular, .top⟩] [⟨"b", .regular, .top⟩] false
        (.struct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"b", .regular, .prim (.int 2)⟩,
                  ⟨"c", .regular, .prim (.int 3)⟩] .regularOpen none [])
      == .struct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"b", .regular, .prim (.int 2)⟩,
                  ⟨"c", .regular, .bottomWith [.fieldNotAllowed "c"]⟩] .defClosed none []) = true := by
  native_decide

/-- E1 EAGER ARM: embedding a CLOSED struct `{pval}` (a `#`-def's value) into an OPEN host that
    carries a regular `x` keeps BOTH — the closed embed must NOT reject the host's `x`. Was
    `x: bottomWith [fieldNotAllowed "x"]` pre-E (the embed's closedness leaked onto the host). -/
theorem eager_structcomp_embed_closed_keeps_host_field :
    (runEval (evalValueWithFuel evalFuel [] []
        (.structComp [⟨"x", .regular, .prim (.string "z")⟩]
                     [.struct [⟨"pval", .regular, .prim (.string "p")⟩] .defClosed none []] true false))
      == .struct [⟨"x", .regular, .prim (.string "z")⟩,
                  ⟨"pval", .regular, .prim (.string "p")⟩] .regularOpen none []) = true := by
  native_decide

/-- E2 + the headline: the 2-LEVEL embed chain, cue-exact. `#Outer` (a `.structComp`) embeds
    `#Inner & {#name: Self.#oname}`; the use-site `#Outer & {#oname: "z"}` narrows `#oname`, which
    flows into the embed's `#name`, which the inner def's `iname: Self.#name` reads → all "z". Was
    `bottom` (closedness leak), then `iname: string` (inner closure not force-spliced) pre-fix. -/
private def chainInnerBody : Value :=
  .struct [⟨"#name", .definition, .kind .string⟩,
           ⟨"iname", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []

private def chainOuterBody : Value :=
  .structComp
    [⟨"#oname", .definition, .kind .string⟩,
     ⟨"oname", .regular, .refId ⟨0, 0⟩⟩]
    [.conj [.refId ⟨1, 0⟩,
            .struct [⟨"#name", .definition, .refId ⟨1, 0⟩⟩] .regularOpen none []]]
    false false

private def chainEnv : Env :=
  [(7, [⟨"#Inner", .definition, chainInnerBody⟩,
        ⟨"#Outer", .definition, chainOuterBody⟩])]

theorem embed_chain_two_level_narrows_through :
    (runEval (evalValueWithFuel evalFuel chainEnv []
        (.conj [.refId ⟨0, 1⟩,
                .struct [⟨"#oname", .definition, .prim (.string "z")⟩] .regularOpen none []]))
      == .struct [⟨"#oname", .definition, .prim (.string "z")⟩,
                  ⟨"oname", .regular, .prim (.string "z")⟩,
                  ⟨"#name", .definition, .prim (.string "z")⟩,
                  ⟨"iname", .regular, .prim (.string "z")⟩] .defClosed none []) = true := by
  native_decide

/-- E2 STANDALONE: the SAME `#Outer` selected WITHOUT a use-site narrowing forces to its own value
    (the bare-ref producer forces standalone, no splice) — `#oname`/`oname`/`iname` stay `string`,
    not `bottom` or a leaked `.closure`. Pins that the standalone force terminates and is concrete. -/
theorem embed_chain_two_level_standalone_forces :
    (runEval (evalValueWithFuel evalFuel chainEnv [] (.refId ⟨0, 1⟩))
      == .struct [⟨"#oname", .definition, .kind .string⟩,
                  ⟨"oname", .regular, .kind .string⟩,
                  ⟨"#name", .definition, .kind .string⟩,
                  ⟨"iname", .regular, .kind .string⟩] .defClosed none []) = true := by
  native_decide

/-- E2 CONFLICT → bottom: the outer fixes `iname: "fixed"` but the inner embed sets `iname` to the
    chain-narrowed `#name = #oname = "z"` → a genuine conflict, matching cue's `bottom`. The
    narrowing propagates correctly AND the conflict is honestly reported (the fix does not paper
    over a real conflict by dropping the chain). -/
private def chainConflictOuterBody : Value :=
  .structComp
    [⟨"#oname", .definition, .kind .string⟩,
     ⟨"iname", .regular, .prim (.string "fixed")⟩]
    [.conj [.refId ⟨1, 0⟩,
            .struct [⟨"#name", .definition, .refId ⟨1, 0⟩⟩] .regularOpen none []]]
    false false

private def chainConflictEnv : Env :=
  [(7, [⟨"#Inner", .definition, chainInnerBody⟩,
        ⟨"#Outer", .definition, chainConflictOuterBody⟩])]

theorem embed_chain_inner_conflict_is_bottom :
    (runEval (evalValueWithFuel evalFuel chainConflictEnv []
        (.conj [.refId ⟨0, 1⟩,
                .struct [⟨"#oname", .definition, .prim (.string "z")⟩] .regularOpen none []]))
      == .struct [⟨"#oname", .definition, .prim (.string "z")⟩,
                  ⟨"iname", .regular, .bottomWith [.fieldConflict "iname"]⟩,
                  ⟨"#name", .definition, .prim (.string "z")⟩] .defClosed none []) = true := by
  native_decide

/-- E2 NON-REGRESSION (the bare-ref producer does NOT over-fire): a DEPTH-0 `.struct` self-ref def
    ref keeps the lazy-merge path (`refDefClosureBody?` returns `none` for it), so `#M & {narrow}`
    still resolves exactly as before — the producer only fires for `.structComp` (any depth) or a
    NESTED `.struct`. -/
theorem ref_def_closure_skips_depth0_struct :
    (refDefClosureBody?
        [(7, [⟨"#M", .definition,
          .struct [⟨"#name", .definition, .kind .string⟩,
                   ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []⟩])] ⟨0, 0⟩
      == none) = true := by
  native_decide

/-- E2 producer FIRES for a NESTED (`depth > 0`) `.struct` self-ref def — the inner def of an embed
    chain, one frame deeper than the embedding's host, which `conjStructOperand?` (depth-0-only)
    cannot lazy-merge. `refDefClosureBody?` returns the normalized (closed) body. -/
theorem ref_def_closure_fires_for_nested_struct :
    (refDefClosureBody?
        [(5, []),
         (7, [⟨"#M", .definition,
          .struct [⟨"#name", .definition, .kind .string⟩,
                   ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []⟩])] ⟨1, 0⟩).isSome = true := by
  native_decide

/-! ### F2 (structcomp-force-comprehension-loss) — a forced `.structComp` def's `if`/`for`
    guard must FIRE post-narrowing, and a struct embedding a guard-bearing def must DEFER so the
    use-site narrowing reaches the embedded guard before it collapses. -/

/-- THE HEADLINE: a forced cross-package structComp def `#M: {#x: int, if #x > 0 {y: #x}}` met
    with `{#x: 5}` expands its `if`-guard AFTER the splice, so `y: 5` appears — the force arm now
    mirrors the eager arm's `staticFields ++ expanded`. The forced body is selected as a `.closure`
    standalone, then the `.conj` fold splices `{#x: 5}` and forces it. Result: `{#x: 5, y: 5}`
    (`#x` hidden → manifests to `{y: 5}`). Before F2 the force arm dropped the guard → `{#x: 5}`. -/
theorem f2_force_structcomp_guard_fires_post_meet :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"pkg", .hidden,
          .struct [⟨"#M", .definition,
            .structComp [⟨"#x", .definition, .kind .int⟩]
              [.comprehension [.guard (.binary .gt (.refId ⟨0, 0⟩) (.prim (.int 0)))]
                (.struct [⟨"y", .regular, .refId ⟨1, 0⟩⟩] .regularOpen none [])] false false⟩] .regularOpen none []⟩])] []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#x", .definition, .prim (.int 5)⟩] .regularOpen none []]))
      == .struct [⟨"#x", .definition, .prim (.int 5)⟩,
                  ⟨"y", .regular, .prim (.int 5)⟩] .defClosed none []) = true := by
  native_decide

/-- The guard does NOT fire when the narrowing fails it: `#M & {#x: -1}` → no `y`. Pins that the
    expansion is GATED on the guard condition, not unconditional. -/
theorem f2_force_structcomp_guard_does_not_fire :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"pkg", .hidden,
          .struct [⟨"#M", .definition,
            .structComp [⟨"#x", .definition, .kind .int⟩]
              [.comprehension [.guard (.binary .gt (.refId ⟨0, 0⟩) (.prim (.int 0)))]
                (.struct [⟨"y", .regular, .refId ⟨1, 0⟩⟩] .regularOpen none [])] false false⟩] .regularOpen none []⟩])] []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#x", .definition, .prim (.int (-1))⟩] .regularOpen none []]))
      == .struct [⟨"#x", .definition, .prim (.int (-1))⟩] .defClosed none []) = true := by
  native_decide

/-- `bodyNeedsDefer` fires for a struct whose body EMBEDS a guard-bearing def — the embed-chain
    case `Outer: {#Inner}` where `#Inner` carries an `if`-guard self-ref. The embed is NOT a
    self-ref of `Outer`, so the direct `defBodyHasSiblingSelfRef` misses it; the recursive clause
    resolves the embed `#Inner` against env and detects its guard → `Outer` must defer so the
    use-site narrowing reaches `#Inner`. The env places `#Inner` at depth-1 (the binding scope). -/
theorem f2_body_needs_defer_through_embed :
    (bodyNeedsDefer
        [(0, []),
         (9, [⟨"#Inner", .definition,
            .structComp [⟨"#port", .definition, .kind .int⟩]
              [.comprehension [.guard (.binary .gt (.refId ⟨0, 0⟩) (.prim (.int 0)))]
                (.struct [⟨"ports", .regular, .refId ⟨1, 0⟩⟩] .regularOpen none [])] true false⟩])]
        evalFuel
        (.structComp [] [.refId ⟨1, 0⟩] true false)) = true := by
  native_decide

/-- `bodyNeedsDefer` does NOT fire for a struct embedding a self-ref-FREE def — the recursion
    bottoms out (`#Plain` = `{a: 1}` has no sibling self-ref), so `Outer` stays on the eager path.
    Pins that the embed recursion does not over-fire (which would churn green fixtures). -/
theorem f2_body_needs_defer_skips_plain_embed :
    (bodyNeedsDefer
        [(0, []),
         (9, [⟨"#Plain", .definition,
            .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []⟩])]
        evalFuel
        (.structComp [] [.refId ⟨1, 0⟩] true false)) = false := by
  native_decide

/-! ### closure-import-selector-alias — a def aliased to (or embedding) an import-selector must
    DEFER through the package indirection. `#A: parts.#M`, then `defs.#A & {#name: "n"}` collapsed
    eagerly (kue `incomplete value: string`) because the producer only detected a DIRECT import
    selector, not one reached through ANOTHER def alias. `followAliasDefBody?` follows the
    selector/ref chain to the terminal `parts.#M` body AND its `parts` package frame, so the
    use-site conjunct splices at force time exactly as a direct `parts.#M & {…}` does. -/

/-- The `parts` package: `#M: {#name: string, name: #name}` (a self-ref def). -/
private def aliasPartsPkg : Value :=
  .struct [⟨"#M", .definition,
    .struct [⟨"#name", .definition, .kind .string⟩,
             ⟨"name", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []⟩] .regularOpen none []

/-- The `defs` package: imports `parts` (binding at index 0) and aliases `#A: parts.#M`
    (`parts` is `.refId ⟨0,0⟩` within the defs frame; index 1 is `#A`). -/
private def aliasDefsPkg : Value :=
  .struct [⟨"parts", .hidden, aliasPartsPkg⟩,
           ⟨"#A", .definition, .selector (.refId ⟨0, 0⟩) "#M"⟩] .regularOpen none []

/-- THE HEADLINE: `defs.#A & {#name: "n"}` where `#A: parts.#M` forces THROUGH the alias to the
    `parts.#M` body, splicing the use-site narrowing → `{name: "n"}`. Before this slice the
    eager path resolved `parts.#M` in the defs frame first → `name: string` (incomplete). The
    use-site env binds `defs` at frame index 0. -/
theorem alias_import_selector_splices_use_site :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"defs", .hidden, aliasDefsPkg⟩])] []
        (.conj [.selector (.refId ⟨0, 0⟩) "#A",
                .struct [⟨"#name", .definition, .prim (.string "n")⟩] .regularOpen none []]))
      == .struct [⟨"#name", .definition, .prim (.string "n")⟩,
                  ⟨"name", .regular, .prim (.string "n")⟩] .defClosed none []) = true := by
  native_decide

/-- `importDefClosureBody?` follows the alias to discover the deferring `parts.#M` body — it
    returns `some` even though `#A`'s OWN body (`parts.#M`) is a selector, not a struct. Pins
    that the alias-follow path is wired into the selector producer. -/
theorem alias_import_selector_producer_fires :
    (importDefClosureBody? [(7, [⟨"defs", .hidden, aliasDefsPkg⟩])] ⟨0, 0⟩ "#A").isSome = true := by
  native_decide

/-- `followAliasDefBody?` returns the terminal `parts.#M` body paired with the `parts` package
    frame (NOT the `defs` frame) — the captured frame must be where `name: #name` resolves. The
    frame env places the `defs` package fields (holding the `parts` binding at index 0) at depth 0. -/
private def aliasDefsFields : List Field :=
  [⟨"parts", .hidden, aliasPartsPkg⟩,
   ⟨"#A", .definition, .selector (.refId ⟨0, 0⟩) "#M"⟩]

theorem alias_follow_returns_terminal_parts_frame :
    (followAliasDefBody? evalFuel
        [(0, aliasDefsFields), (7, [])]
        aliasDefsFields
        (.selector (.refId ⟨0, 0⟩) "#M")).isSome = true := by
  native_decide

-- EMBED form (`#A: {parts.#M}`) is pinned cue-exact by the committed module fixture
-- `alias_import_selector_embed` — the hand-built in-memory env diverges from the loader's
-- `normalizeDefinitions` frame layout for the `.structComp` embed case, so it is covered
-- end-to-end through the CLI fixture rather than a fragile unit AST.

/-- TWO-LEVEL alias indirection: `#A: parts.#M`, `#B: #A` (a `.refId` to `#A`), then
    `defs.#B & {#name: "n"}` follows the chain `#B → #A → parts.#M`. Pins that the follow
    recurses through a same-package `.refId` alias, not just one selector hop. -/
private def aliasDefsPkgTwoLevel : Value :=
  .struct [⟨"parts", .hidden, aliasPartsPkg⟩,
           ⟨"#A", .definition, .selector (.refId ⟨0, 0⟩) "#M"⟩,
           ⟨"#B", .definition, .refId ⟨0, 1⟩⟩] .regularOpen none []

theorem alias_import_selector_two_level_splices :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"defs", .hidden, aliasDefsPkgTwoLevel⟩])] []
        (.conj [.selector (.refId ⟨0, 0⟩) "#B",
                .struct [⟨"#name", .definition, .prim (.string "n")⟩] .regularOpen none []]))
      == .struct [⟨"#name", .definition, .prim (.string "n")⟩,
                  ⟨"name", .regular, .prim (.string "n")⟩] .defClosed none []) = true := by
  native_decide

/-- NO OVER-DEFERRAL: a def aliased to a NON-import-selector struct (`#A: {x: int}`, no self-ref)
    does NOT defer — `followAliasDefBody?` returns `none` for it, so the eager/lazy-merge path
    handles `defs.#A & {x: 5}` → `{x: 5}` exactly as before. Pins the gate stays narrow. -/
theorem alias_non_selector_does_not_defer :
    (importDefClosureBody?
        [(7, [⟨"defs", .hidden,
          .struct [⟨"#A", .definition, .struct [⟨"x", .regular, .kind .int⟩] .regularOpen none []⟩] .regularOpen none []⟩])]
        ⟨0, 0⟩ "#A") == none := by
  native_decide

/-- CYCLE SAFETY: a self-referential alias chain (`#A: #B`, `#B: #A`) terminates — the
    fuel-bounded follow does not diverge. `followAliasDefBody?` returns (terminating) for the
    cyclic body rather than looping forever; the result is `none` (no struct terminal reached). -/
theorem alias_follow_cycle_terminates :
    (followAliasDefBody? evalFuel
        [(0, [⟨"#A", .definition, .refId ⟨0, 1⟩⟩, ⟨"#B", .definition, .refId ⟨0, 0⟩⟩])]
        [⟨"#A", .definition, .refId ⟨0, 1⟩⟩, ⟨"#B", .definition, .refId ⟨0, 0⟩⟩]
        (.refId ⟨0, 1⟩)) == none := by
  native_decide


end Kue
