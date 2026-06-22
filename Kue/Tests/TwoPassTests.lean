import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

-- DISJUNCTION SELECTION (argocd `#Secret` blocker, facet 1): selecting a field INTO a
    -- default disjunction (`d.a` where `d: *{a:1,c:9} | {a:2}`) collapses to the default arm
    -- first, then selects — CUE's default rule. Previously `selectEvaluatedField` had no `.disj`
    -- case and fell through to `.bottom`.
theorem select_into_default_disjunction :
    (selectEvaluatedField
      (.disj [(.default, mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"c", .regular, .prim (.int 9)⟩] .regularOpen none []),
              (.regular, mkStruct [⟨"a", .regular, .prim (.int 2)⟩] .regularOpen none [])])
      "a"
      == .prim (.int 1)) = true := by
  native_decide

-- CARRIER-DECL-SELECT routing: selecting off a defaulted disjunction whose default arm is an
    -- `.embeddedScalar` carrier resolves the default, then plucks the decl through the SHARED
    -- `selectFromDecls` helper — same path the plain-`.struct` arm above takes.
theorem select_into_default_disjunction_scalar_carrier :
    (selectEvaluatedField
      (.disj [(.default, .embeddedScalar (.prim (.int 5)) [⟨"#a", .definition, .prim (.int 1)⟩]),
              (.regular, mkStruct [⟨"#a", .definition, .prim (.int 2)⟩] .regularOpen none [])])
      "#a"
      == .prim (.int 1)) = true := by
  native_decide

-- Same routing for an `.embeddedList` default-arm carrier: `selectFromDecls` plucks the decl
    -- off the list carrier identically to the scalar and struct shapes.
theorem select_into_default_disjunction_list_carrier :
    (selectEvaluatedField
      (.disj [(.default, .embeddedList [.prim (.int 1), .prim (.int 2)] none [⟨"#a", .definition, .prim (.int 7)⟩]),
              (.regular, mkStruct [⟨"#a", .definition, .prim (.int 2)⟩] .regularOpen none [])])
      "#a"
      == .prim (.int 7)) = true := by
  native_decide

-- NO OVER-FIRE: a NON-default disjunction with multiple live arms does NOT collapse on
    -- selection — it stays a deferred `.selector` (manifest then reports the ambiguity), never a
    -- spurious `bottom` and never a silent pick of one arm.
theorem select_into_nondefault_disjunction_defers :
    (selectEvaluatedField
      (.disj [(.regular, mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []),
              (.regular, mkStruct [⟨"a", .regular, .prim (.int 2)⟩] .regularOpen none [])])
      "a"
      == .selector
           (.disj [(.regular, mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []),
                   (.regular, mkStruct [⟨"a", .regular, .prim (.int 2)⟩] .regularOpen none [])])
           "a") = true := by
  native_decide

-- EMBEDDED DEFAULT DISJUNCTION (argocd `#Secret` blocker, facet 2): an embedded default
    -- disjunction collapses to its default arm before merging into the host
    -- (`resolveEmbeddedDisjDefault`), so its fields land as regular host fields and a sibling
    -- `Self.a` resolves. A non-default disjunction passes through untouched.
theorem resolve_embedded_default_disjunction :
    (resolveEmbeddedDisjDefault
      (.disj [(.default, mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []),
              (.regular, mkStruct [⟨"a", .regular, .prim (.int 2)⟩] .regularOpen none [])])
      == mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_embedded_nondefault_disjunction_unchanged :
    (resolveEmbeddedDisjDefault
      (.disj [(.regular, mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []),
              (.regular, mkStruct [⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])])
      == .disj [(.regular, mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []),
                (.regular, mkStruct [⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])]) = true := by
  native_decide

-- TWO-PASS GATE (perf): the embedding-`Self` re-evaluation fires ONLY when a static field
    -- selects `Self.<embedded-label>`. This pins the no-over-fire boundary that keeps cert-manager
    -- (a `parts.#Metadata` embed never read via `Self.metadata`) on the single-pass path.
theorem embedded_self_pass_fires_on_self_select :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩, ⟨"b", .regular, .selector (.refId ⟨0, 0⟩) "a"⟩]
      ["a"] = true := by
  native_decide

theorem embedded_self_pass_skips_unselected_embed_label :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩, ⟨"b", .regular, .selector (.refId ⟨0, 0⟩) "a"⟩]
      ["metadata"] = false := by
  native_decide

theorem embedded_self_pass_skips_when_no_self_select :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩, ⟨"b", .regular, .prim (.int 1)⟩]
      ["metadata"] = false := by
  native_decide

-- ### argocd link 3/4 — DEEP and LIST-COMPREHENSION self-ref two-pass gate.
--
-- `refsSelfEmbeddedLabel` (the two-pass gate) previously matched only a DEPTH-0 `Self.<label>`
-- selector and had no `.listComprehension` arm. Two gaps:
  -- 1. A `Self.<embedded-label>` read from a NESTED struct (`spec: { hostnames: Self.#hosts }`)
     -- is `.selector (.refId ⟨1, selfIndex⟩) #hosts` — depth 1 — so it was invisible; Pass 2
     -- never fired and the nested ref resolved against the un-augmented frame → `.bottom`
     -- (argocd `#TLSRoute.spec.hostnames`, `#ListenerSet.spec.parentRef.name`).
  -- 2. A list-comprehension SOURCE (`listeners: [for h in Self.#hosts {…}]`) lives in a
     -- `.listComprehension`, which had no scan arm → the comprehension iterated the un-narrowed
     -- (empty) embedded field and dropped every element (argocd `#ListenerSet.spec.listeners`).
-- Both fixed by threading `depth` (incremented on struct descents, mirroring `hasSelfRefAtDepth`)
-- and adding a `.listComprehension` arm.

-- DEEP: `Self.a` read one frame deep (`b: { c: Self.a }`) fires the gate.
theorem embedded_self_pass_fires_on_nested_self_select :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩,
       ⟨"b", .regular, mkStruct [⟨"c", .regular, .selector (.refId ⟨1, 0⟩) "a"⟩] .regularOpen none []⟩]
      ["a"] = true := by
  native_decide

-- LIST-COMPREHENSION SOURCE: `b: [for x in Self.a {…}]` fires the gate (source at depth 0).
theorem embedded_self_pass_fires_on_listcomp_source :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩,
       ⟨"b", .regular, .list [.listComprehension [.forIn none "x" (.selector (.refId ⟨0, 0⟩) "a")]
                                (mkStruct [⟨"v", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none [])]⟩]
      ["a"] = true := by
  native_decide

-- LIST-COMPREHENSION SOURCE, NESTED: `spec: { listeners: [for x in Self.a {…}] }` (source at
-- depth 1) — the real argocd shape — fires the gate.
theorem embedded_self_pass_fires_on_nested_listcomp_source :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩,
       ⟨"spec", .regular, mkStruct [⟨"listeners", .regular, .list [.listComprehension
              [.forIn none "x" (.selector (.refId ⟨1, 0⟩) "a")]
              (mkStruct [⟨"v", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none [])]⟩] .regularOpen none []⟩]
      ["a"] = true := by
  native_decide

-- NO OVER-FIRE: a NESTED reference to an UNRELATED label (`Self.other`, not in the embedded set)
-- still does not fire — the depth-tracking widens detection only for genuinely-embedded labels.
theorem embedded_self_pass_skips_nested_unselected :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩,
       ⟨"b", .regular, mkStruct [⟨"c", .regular, .selector (.refId ⟨1, 0⟩) "other"⟩] .regularOpen none []⟩]
      ["a"] = false := by
  native_decide

-- ### A1 (soundness) — `Self.<embedded-label>` read WRAPPED IN A BUILTIN ARG.
--
-- Both two-pass scanners (`refsSelfEmbeddedLabel` gate / `selfReferencedLabels` selection) ended
-- in a catch-all that SILENTLY SWALLOWED `builtinCall`/`embeddedList`/`structPattern`/
-- `structPatterns`. So `count: len(Self.#x)` — a `.builtinCall` whose arg reads an embedded label —
-- was invisible: the gate stayed single-pass and (post-`2d87b8e` selective re-eval) the field was
-- skipped → stale Pass-1 value. Adding the missing arms (args at same depth; embeddedList items/tail
-- at depth, decls at depth+1; pattern fields/labelPattern/constraint at depth+1) makes the read
-- visible to BOTH.

-- GATE: `count: len(Self.x)` (an embedded-label read inside a builtin arg) fires the two-pass.
theorem embedded_self_pass_fires_on_builtin_wrapped_select :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩,
       ⟨"count", .regular, .builtinCall "len" [.selector (.refId ⟨0, 0⟩) "x"]⟩]
      ["x"] = true := by
  native_decide

-- NESTED builtin arg (`spec: { n: len(Self.x) }`, read at depth 1) also fires.
theorem embedded_self_pass_fires_on_nested_builtin_wrapped_select :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩,
       ⟨"spec", .regular, mkStruct [⟨"n", .regular, .builtinCall "len" [.selector (.refId ⟨1, 0⟩) "x"]⟩] .regularOpen none []⟩]
      ["x"] = true := by
  native_decide

-- SELECTION: `selfReferencedLabels` sees the embedded label THROUGH the builtin arg, so the
-- builtin-wrapped field is in the Pass-2 re-eval set (not skipped → not stale).
theorem selfreferenced_labels_descends_builtin_arg :
    (selfReferencedLabels evalFuel 0 0
        (.builtinCall "len" [.selector (.refId ⟨0, 0⟩) "x"]) == ["x"]) = true := by
  native_decide

-- The Pass-2 SELECTION set includes the builtin-wrapped field: `count: len(Self.et)` (canonical
-- index 1 after the `#self` binding) is selected when `et` is an embedded label.
theorem selpass_selects_builtin_wrapped_field :
    (embeddedSelfPassFieldIndices
        (canonicalizeFields
          [⟨"#self", .definition, .thisStruct⟩,
           ⟨"count", .regular, .builtinCall "len" [.selector (.refId ⟨0, 0⟩) "et"]⟩])
        ["et"]
      == [1]) = true := by
  native_decide

-- NO OVER-FIRE: a builtin arg reading an UNRELATED label does not fire the gate.
theorem embedded_self_pass_skips_builtin_unrelated :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩,
       ⟨"count", .regular, .builtinCall "len" [.selector (.refId ⟨0, 0⟩) "other"]⟩]
      ["x"] = false := by
  native_decide

-- ### B1 (soundness) — `remapConjRefs` SWALLOWED struct-comp / comprehension conjuncts.
--
-- The conj-frame-remap (`remapConjRefs`, rebasing a conjunct's frame-local `.refId`s onto a merged
-- conjunction frame) ended in `| _, value => value`, silently dropping `.structComp` (the dominant
-- `{embed;…;...}` `#Def` conjunct shape), `.comprehension`/`.listComprehension`, `.embeddedList`,
-- `.dynamicField`. A swallowed conjunct kept STALE merged-frame indices after a field-reindexing
-- merge → wrong resolution or spurious bottom. The fix adds explicit recursing arms (structComp
-- fields + comprehensions at frameDepth+1; comprehension clause-sources/guards + body at frameDepth;
-- embeddedList items/tail at frameDepth, decls at frameDepth+1; dynamicField label+value).

-- A `.structComp` conjunct whose inner field reads a frame sibling (`refId ⟨1, 1⟩` = old index 1
-- = "b", measured one frame deep inside the pushed struct-comp frame) is REINDEXED onto the merged
-- layout `[("b",0),("a",1)]` → `refId ⟨1, 0⟩`. Pre-fix: swallowed, stays the stale `⟨1, 1⟩`.
theorem remap_structcomp_conjunct_reindexes_inner_refid :
    (remapConjRefs remapFuel 0
        [Field.regular "a" .top, Field.regular "b" .top]
        [("b", 0), ("a", 1)]
        (.structComp [⟨"x", .regular, .refId ⟨1, 1⟩⟩] [] .regularOpen)
      == .structComp [⟨"x", .regular, .refId ⟨1, 0⟩⟩] [] .regularOpen) = true := by
  native_decide

-- A `.structComp` conjunct's COMPREHENSION list is also remapped (a comprehension body reading a
-- merged-frame sibling at `refId ⟨1, 1⟩` → `⟨1, 0⟩`). Pre-fix: the whole structComp was swallowed.
theorem remap_structcomp_conjunct_remaps_comprehension :
    (remapConjRefs remapFuel 0
        [Field.regular "a" .top, Field.regular "b" .top]
        [("b", 0), ("a", 1)]
        (.structComp [] [.comprehension [.guard (.refId ⟨1, 1⟩)] (.refId ⟨1, 1⟩)] .regularOpen)
      == .structComp [] [.comprehension [.guard (.refId ⟨1, 0⟩)] (.refId ⟨1, 0⟩)] .regularOpen) = true := by
  native_decide

-- ### A5 (regression from B1) — comprehension BODY remapped at the wrong frame depth.
--
-- A comprehension body lives `#forClauses` frames deeper than the comprehension node (`for`
-- pushes a frame, `guard` does not) — the rule encoded once in `resolveClausesWithFuel`. B1's
-- `.comprehension`/`.listComprehension` arms recursed the body at flat `frameDepth`, so a body
-- ref targeting the merged conjunction frame (at `frameDepth + #for`) was compared `== frameDepth`,
-- missed, and kept its stale conjunct-local slot → wrong value. The fix threads an incrementing
-- depth through the clause chain exactly as resolution does (now the shared `descendClauses`
-- fold via `clauseChainDepth`: +1 per `for`, +0 per `guard`); the body is remapped at
-- `clauseChainDepth frameDepth clauses`, and clause source N at `frameDepth + (#for before N)`.
--
-- These pins use REALISTICALLY-RESOLVED bodies (depth reflecting the loop frame), not the
-- hand-built depth-0 value the prior `remap_comprehension_conjunct_reindexes_source_and_body`
-- pin tested — that value is unreachable after real `for`-clause resolution, so it passed while
-- the behavior was broken.

-- A bare `.comprehension` with one `for`: the SOURCE sits at `frameDepth` (resolved before the
-- loop frame), but the BODY sits one frame deeper (`refId ⟨1, 1⟩`). The body ref targeting the
-- merged frame is reindexed `⟨1, 1⟩ → ⟨1, 0⟩`; the source ref at `⟨0, 1⟩ → ⟨0, 0⟩`. Pre-fix the
-- body was remapped at depth 0 (no match) and left stale.
theorem remap_comprehension_conjunct_reindexes_body_one_frame_deep :
    (remapConjRefs remapFuel 0
        [Field.regular "a" .top, Field.regular "b" .top]
        [("b", 0), ("a", 1)]
        (.comprehension [.forIn none "x" (.refId ⟨0, 1⟩)] (.refId ⟨1, 1⟩))
      == .comprehension [.forIn none "x" (.refId ⟨0, 0⟩)] (.refId ⟨1, 0⟩)) = true := by
  native_decide

-- Multi-`for`: clause 2's source is resolved under clause 1's frame, so it sits at `frameDepth+1`;
-- the body sits two frames deep (`frameDepth+2`). Pins that `remapConjClauses` threads the depth
-- per `for` (source at ⟨0,_⟩ then ⟨1,_⟩) and the body at ⟨2,_⟩, all reindexed to slot 0.
theorem remap_comprehension_conjunct_multi_for_threads_depth :
    (remapConjRefs remapFuel 0
        [Field.regular "a" .top, Field.regular "b" .top]
        [("b", 0), ("a", 1)]
        (.comprehension
          [.forIn none "x" (.refId ⟨0, 1⟩), .forIn none "y" (.refId ⟨1, 1⟩)]
          (.refId ⟨2, 1⟩))
      == .comprehension
          [.forIn none "x" (.refId ⟨0, 0⟩), .forIn none "y" (.refId ⟨1, 0⟩)]
          (.refId ⟨2, 0⟩)) = true := by
  native_decide

-- A `guard` does NOT push a frame: a `for` then `guard` leaves the body at `frameDepth+1`, and the
-- guard condition is read at `frameDepth+1` (under the `for`). Pins the clause-chain shift counts
-- only `for`, not `guard`.
theorem remap_comprehension_conjunct_guard_no_frame :
    (remapConjRefs remapFuel 0
        [Field.regular "a" .top, Field.regular "b" .top]
        [("b", 0), ("a", 1)]
        (.comprehension
          [.forIn none "x" (.refId ⟨0, 1⟩), .guard (.refId ⟨1, 1⟩)]
          (.refId ⟨1, 1⟩))
      == .comprehension
          [.forIn none "x" (.refId ⟨0, 0⟩), .guard (.refId ⟨1, 0⟩)]
          (.refId ⟨1, 0⟩)) = true := by
  native_decide

-- END-TO-END (source-level, cue-exact, oracle cue v0.16.1 → `s.a.out: 99`): the A5 repro. The
-- body's `zz` reads the merged-frame sibling (slot 3 after merge) from inside a `for`; pre-fix it
-- was not reindexed and resolved to merged slot 1 = `q` = 20.
theorem a5_comprehension_body_remap_picks_merged_sibling :
    evalSourceMatches
        "t: {s: {p: 10, q: 20}} & {s: {a: {for v in [1] {out: zz}}, zz: 99}}\n"
        "t: {s: {p: 10, q: 20, a: {out: 99}, zz: 99}}"
          = true := by
  native_decide

-- AGREEMENT with `remapConjClauses`: the rewriter rebuilds the clause LIST threading `frameDepth+1`
-- per `forIn`, while `remapConjRefs`'s `.comprehension` arm shifts the BODY by `clauseChainDepth`.
-- The two must reach the same post-chain depth — pin it: remap a comprehension whose body refId is
-- at `clauseChainDepth 0 clauses` and confirm it is treated as a merged-frame ref (reindexed),
-- which only happens when the body shift equals the depth the clause rebuild threaded to. Drift
-- between the list rebuild and the body fold becomes this test failing.
theorem descend_clauses_agrees_remapConjClauses :
    ([ [.forIn none "x" (.top : Value)]
     , [.forIn none "x" .top, .forIn none "y" .top]
     , [.forIn none "x" .top, .guard .top, .forIn none "y" .top]
     ].all (fun clauses =>
        let bodyDepth := clauseChainDepth 0 clauses
        match remapConjRefs remapFuel 0
            [Field.regular "a" .top, Field.regular "b" .top] [("b", 0), ("a", 1)]
            (.comprehension clauses (.refId ⟨⟨bodyDepth⟩, 1⟩)) with
        | .comprehension _ (.refId id) => id.depth.val == bodyDepth && id.index == 0
        | _ => false)) = true := by
  native_decide

-- ### A-EN3 — `foldValueWithDepth` combinator pins (the shared structural fold).
--
-- The three def-frame scanners (`refsSelfEmbeddedLabel`/`selfReferencedLabels`/`defFrameRefIndices`)
-- are thin `foldValueWithDepth` instantiations. These pins lock the combinator's contract and the
-- `.dynamicField` value-depth discipline (scanned at the PARENT depth, mirroring the resolver, which
-- pushes no frame for a dynamic field — A-EN3-DYN), so a future edit that drifts the shared skeleton
-- or re-introduces the over-deep `+1` scan is a `native_decide` failure, not a silent value change.

-- Empty-monoid degeneracy: a fold whose `combine` always returns `empty` and whose `leaf` never
-- fires collapses to `empty` regardless of the tree — the structural skeleton contributes nothing
-- on its own; ALL signal comes from the leaf hook.
theorem fold_value_with_depth_empty_monoid_is_empty :
    (foldValueWithDepth (β := List Nat) (fun _ _ => []) [] (fun _ _ => none) evalFuel 0
        (mkStruct [⟨"a", .regular, .refId ⟨0, 3⟩⟩] .regularOpen none
          [(.kind .string, .comprehension [.forIn none "x" (.list [])] (.refId ⟨1, 7⟩))])
      == []) = true := by
  native_decide

-- Leaf short-circuit: a `leaf` returning `some` makes the node a LEAF — descent stops, so children
-- are NOT visited. Here the leaf fires on every `.struct`, returning `[99]` and never recursing into
-- the inner `.refId ⟨0,0⟩` (which a structural descent would have collected as `[0]`).
theorem fold_value_with_depth_leaf_short_circuits :
    (foldValueWithDepth (β := List Nat) (· ++ ·) []
        (fun _ v => match v with | .struct .. => some [99] | _ => none) evalFuel 0
        (mkStruct [⟨"a", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none [])
      == [99]) = true := by
  native_decide

-- The `.dynamicField` value-depth discipline (A-EN3-DYN): `defFrameRefIndices` scans a dynamic
-- field's VALUE at the PARENT depth — no `+1` — because the resolver pushes no frame for a dynamic
-- field (key and value both resolve in the parent scope, `Resolve.lean`). Witnessed from `depth 0`:
-- a value-ref at `⟨0, 5⟩` (def-frame depth) IS collected, while `⟨1, 5⟩` (one frame deeper than the
-- def actually is) is NOT. This is the FIXED behavior; the pre-fix over-deep `+1` scan had the arms
-- swapped (`⟨1,5⟩ → [5]`), missing the real read and dropping the use-site narrowing.
theorem fold_value_dynfield_value_scanned_at_parent_depth :
    (defFrameRefIndices evalFuel 0 (.dynamicField (.prim (.string "k")) .regular (.refId ⟨0, 5⟩)) == [5]
      && defFrameRefIndices evalFuel 0 (.dynamicField (.prim (.string "k")) .regular (.refId ⟨1, 5⟩)) == []) = true := by
  native_decide

-- ### B7 — `descendClauses` agreement theorems (the new structural guarantee).
--
-- `descendClauses` (`Value.lean`) is the single authority for the comprehension clause-chain
-- frame-depth rule (`+1` per `forIn`, `+0` per `guard`, body at the accumulated depth). These pins
-- make a future drift between the fold and either `resolveClausesWithFuel` (the reference walker,
-- not migrated — it threads scopes, not `Nat`) or `remapConjClauses` a `native_decide` failure
-- rather than a silent wrong value.

-- `clauseChainDepth` self-consistency: the depth a clause chain accumulates is `start` plus one
-- per `forIn`, none per `guard` — the shape the former `clauseFrameShift` counted (and the depth
-- `resolveClausesWithFuel` reaches for the body, pinned below).
theorem descend_clauses_chain_depth_counts_only_for :
    (clauseChainDepth 0 ([] : List (Clause Value)) == 0
      && clauseChainDepth 0 [.forIn none "x" .top] == 1
      && clauseChainDepth 0 [.guard .top] == 0
      && clauseChainDepth 5 [.forIn none "x" .top, .guard .top, .forIn none "y" .top] == 7) = true := by
  native_decide

-- AGREEMENT with `resolveClausesWithFuel`: resolve threads `clauseLoopFrame :: scopes` (one frame
-- per `forIn`, none per `guard`). With the body `.ref "x"` and `x` bound in the OUTERMOST scope,
-- the resolved body is `.refId ⟨d, 0⟩` where `d` = the number of frames the chain pushed =
-- `findInScopes`' walk past every loop frame. Pinning `d == clauseChainDepth 0 clauses` ties the
-- fold to the reference walker WITHOUT coupling their code — drift becomes this test failing.
theorem descend_clauses_frame_count_matches_resolve :
    ([ ([] : List (Clause Value))
     , [.forIn none "x" .top]
     , [.guard .top]
     , [.forIn none "x" .top, .forIn none "y" .top]
     , [.forIn none "x" .top, .guard .top, .forIn none "y" .top]
     ].all (fun clauses =>
        match (resolveClausesWithFuel resolveFuel [[("outer", 0)]] clauses (.ref "outer")).snd with
        | .refId id => id.depth.val == clauseChainDepth 0 clauses
        | _ => false)) = true := by
  native_decide

-- ### A5 sibling — `selfReferencedLabels` MISSED a `Self.<embedded>` read inside a `for` body.
--
-- `selfReferencedLabels` (the Pass-2 selection seed: which static fields read an embedded label and
-- must be re-evaluated against the augmented frame) recursed a comprehension body at flat `depth`,
-- ignoring the loop frame each `for` pushes. A `Self.<embedded>` read inside a `for` body sits at
-- `depth + #forClauses` but was compared `== depth`, so the field was not collected → not selected
-- for Pass-2 → it reused its stale Pass-1 value. The fix threads the depth through the clause chain
-- via the shared `foldValueWithDepth`/`descendClauses` handler (A-EN3 unified the three scanners onto
-- it), identically to `resolveClausesWithFuel` (and to the `remapConj*` A5 fix above). These pins use
-- REALISTICALLY-RESOLVED body refIds (depth reflecting the loop frame).
--

-- A plain `.comprehension` with one `for` whose body struct reads `Self.#t` (`refId ⟨2,0⟩` — one
-- `for` frame + one struct-field frame above the `Self` slot at index 0): the label `#t` IS
-- collected. Flat recursion checks the ref at depth 1, misses it, returns `[]` → field skipped in
-- Pass-2 → stale value.
theorem self_referenced_labels_collects_through_for_body :
    (selfReferencedLabels evalFuel 0 0
        (.comprehension [.forIn none "x" (.list [])]
          (mkStruct [⟨"v", .regular, .selector (.refId ⟨2, 0⟩) "#t"⟩] .regularOpen none []))
      == ["#t"]) = true := by
  native_decide

-- A `guard` pushes no frame: a `Self.#t` read in a guard condition sits at the comprehension's own
-- `depth` (`refId ⟨0,0⟩`), and the body struct after the guard is still only the `for`-frame deep.
theorem self_referenced_labels_guard_no_frame :
    (selfReferencedLabels evalFuel 0 0
        (.comprehension [.guard (.selector (.refId ⟨0, 0⟩) "#g")]
          (mkStruct [⟨"v", .regular, .selector (.refId ⟨1, 0⟩) "#t"⟩] .regularOpen none []))
      == ["#g", "#t"]) = true := by
  native_decide

-- The gate twin `refsSelfEmbeddedLabel` (decides whether the two-pass fires at ALL) had the same
-- too-shallow comprehension-body scan, with a comment claiming it only over-fires (perf). That was
-- backwards: a too-shallow scan compares a deep `Self.<embedded>` read against `depth`, MISSES it,
-- returns `false`, and SKIPS the two-pass — a stale-value miss. Fixed via the shared
-- `foldValueWithDepth`/`descendClauses` clause handler (depth threaded like resolution). Pre-fix this
-- returns `false` (deep ref at ⟨2,0⟩ scanned at depth 1).
theorem refs_self_embedded_label_detects_through_for_body :
    refsSelfEmbeddedLabel evalFuel 0 0 ["#t"]
        (.comprehension [.forIn none "x" (.list [])]
          (mkStruct [⟨"v", .regular, .selector (.refId ⟨2, 0⟩) "#t"⟩] .regularOpen none [])) = true := by
  native_decide

-- NOTE on end-to-end coverage: the observable wrong-value form of this miss (a static field
-- reading `Self.<embedded>` inside a `for` body, narrowed at the use site) does NOT yet flip to the
-- correct value with these depth fixes alone — a SEPARATE Pass-2 re-eval defect for fields whose
-- VALUE contains a comprehension (the field is selected and the gate fires, but the comprehension
-- body is not refreshed against the augmented frame) gates it. That path is filed as its own
-- backlog item (A5-followup). These unit pins lock the `selfReferencedLabels` / `refsSelfEmbeddedLabel`
-- depth discipline, which is the piece A5 owns and a prerequisite for the followup fix.

-- A `.dynamicField` conjunct: both label and value refs are reindexed.
theorem remap_dynamicfield_conjunct_reindexes_label_and_value :
    (remapConjRefs remapFuel 0
        [Field.regular "a" .top, Field.regular "b" .top]
        [("b", 0), ("a", 1)]
        (.dynamicField (.refId ⟨0, 1⟩) .regular (.refId ⟨0, 1⟩))
      == .dynamicField (.refId ⟨0, 0⟩) .regular (.refId ⟨0, 0⟩)) = true := by
  native_decide

-- HEADLINE (source-level, cue-exact): a list comprehension over an embedded-def field narrowed
-- via a use-site `#host` yields the element. Pre-fix: empty list (gate missed the listComp source).
theorem listcomp_embed_selfref_narrows :
    evalSourceMatches
        "#H: {#host?: string, #hosts: [...string], if #host != _|_ {#hosts: [#host]}}\n#R: Self={#H, out: [for h in Self.#hosts {hostname: h}]}\nv: #R & {#host: \"x.com\"}\n"
        "#H: {#host?: string, #hosts: [...string]}\n#R: {out: [], #host?: string, #hosts: [...string]}\nv: {out: [{hostname: \"x.com\"}], #host: \"x.com\", #hosts: [\"x.com\"]}"
          = true := by
  native_decide

-- GUARD FALSE (no fabrication): `#host` absent ⇒ embedded `#hosts` stays empty ⇒ the comprehension
-- yields zero elements, matching cue. Pins the two-pass does not invent elements.
theorem listcomp_embed_selfref_empty_stays_empty :
    evalSourceMatches
        "#H: {#host?: string, #hosts: [...string], if #host != _|_ {#hosts: [#host]}}\n#R: Self={#H, out: [for h in Self.#hosts {hostname: h}]}\nv: #R & {}\n"
        "#H: {#host?: string, #hosts: [...string]}\n#R: {out: [], #host?: string, #hosts: [...string]}\nv: {out: [], #host?: string, #hosts: [...string]}"
          = true := by
  native_decide

-- ### argocd link 4 — open struct (`...`) with embeddings no longer splits into a `.conj`.
--
-- An open struct that ALSO carries comprehensions/embeddings (`{ embed; …; ... }`) was parsed as
-- `.conj [.structComp(embeds), .structTail(fields, tail)]` — two OVERLAPPING-field arms. A
-- `Self.<field>` self-ref landed in the `mkStruct ` .defOpenViaTail (some arm) [], which never saw the embedding-contributed
-- fields, so a use-site narrowing collapsed to `.bottom` (argocd `defs.#ListenerSet`: `parts.#Metadata`
-- embedded + a def-level `...`). The parser now keeps it ONE node: the comprehension form already
-- carries `open_ = true`, exactly what the bare `...` (`.top` tail) means; a definition-context one is
-- closed by `normalizeDefinitionValueWithFuel` like any `.structComp`. The cross-package end-to-end
-- shape is pinned by the committed module fixture `open_embed_selfref_guard`; these are the parser +
-- same-file source pins.

-- SAME-FILE source pin: an open struct (`...`) embedding a self-ref def, with a nested-scope
-- `Self.#g` read, narrowed at the use site, resolves (no `.bottom`). Pre-fix the def-level `...`
-- split the body into a `.conj` whose `Self.#g` arm bottomed.
theorem open_embed_selfref_narrows :
    evalSourceMatches
        "#B: {#g: string, gw: #g}\n#R: Self={#B, who: Self.#g, ...}\nout: #R & {#g: \"x\"}\n"
        "#B: {#g: string, gw: string}\n#R: {who: string, #g: string, gw: string}\nout: {who: \"x\", #g: \"x\", gw: \"x\"}"
          = true := by
  native_decide

-- ### argocd-secret-data sub-slice 1 — hidden-def embedding narrowing.
--
-- The argocd link-2 blocker: a hidden definition `_#OpaqueSecret` embedded into a host whose
-- use-site narrows a hidden field (`#data`). The embedded def's sibling self-ref (`data:
-- #data`, or a `for k,v in #data` comprehension) ran against the def's own ABSTRACT `#data`
-- before the use-site narrowing reached it → empty output instead of the populated map. Root
-- cause was a PARSER misclassification: `_#x` was tagged hidden-only (not a definition), so the
-- def-deferral path (`refDefClosureBody?`/`conjDefClosure?`) never fired for the embedding, and
-- the arm evaluated standalone (collapsing the self-ref) before the narrowing spliced in. Fixed
-- by classifying `_#x` as BOTH definition and hidden (see `parse_field_class_hidden_definition`).
-- Each pin is cue v0.16.1-exact.

-- HEADLINE: a `for k,v in #data` comprehension inside an embedded hidden-def populates AFTER
-- the use-site narrows `#data` (the secret-data shape). Pre-fix: `mapped: {}` (empty).
-- B2.2 dedup: the repeated `[string]: string` pattern (legacy `structPatterns` accumulated it
-- per meet, no dedup) now collapses to ONE via `mkStruct`/`dedupPatterns`, matching cue v0.16.1.
theorem hidden_def_embed_comprehension_narrows :
    evalSourceMatches
        "_#M: {#data: [string]: string, mapped: {for k, v in #data {\"\\(k)\": v}}}\n#S: {#data: [string]: string, _#M}\nout: #S & {#data: {a: \"x\"}}\n"
        "_#M: {#data: {[string]: string}, mapped: {}}\n#S: {#data: {[string]: string}, mapped: {}}\nout: {#data: {a: \"x\", [string]: string}, mapped: {a: \"x\"}}"
          = true := by
  native_decide

-- A plain SIBLING self-ref (`copy: #x`) in an embedded hidden-def sees the use-site narrowing
-- of `#x`. Pre-fix: `copy: string` (un-narrowed). The minimal scalar form of the headline.
theorem hidden_def_embed_sibling_narrows :
    evalSourceMatches
        "_#Hidden: {#x: string, copy: #x}\n#S: {#x: string, _#Hidden}\nout: #S & {#x: \"hi\"}\n"
        "_#Hidden: {#x: string, copy: string}\n#S: {#x: string, copy: string}\nout: {#x: \"hi\", copy: \"hi\"}"
          = true := by
  native_decide

-- EMPTY-NARROW (no over-population): narrowing the comprehension source to an empty struct
-- yields an empty `mapped`, matching cue — the comprehension iterates the NARROWED value, so
-- an empty narrowing is a real empty result, not a stale default.
theorem hidden_def_embed_comprehension_empty :
    evalSourceMatches
        "_#M: {#data: [string]: string, mapped: {for k, v in #data {\"\\(k)\": v}}}\n#S: {#data: [string]: string, _#M}\nout: #S & {#data: {}}\n"
        "_#M: {#data: {[string]: string}, mapped: {}}\n#S: {#data: {[string]: string}, mapped: {}}\nout: {#data: {[string]: string}, mapped: {}}"
          = true := by
  native_decide

-- A hidden definition is CLOSED (the parser fix's other half): `_#C & {a:1}` accepts the
-- declared `a`, `_#C & {a:1, b:2}` REJECTS the undeclared `b` (`b: _|_`). Pre-fix `_#C` was
-- open (hidden-only), so it wrongly admitted `b`. cue: "field not allowed".
theorem hidden_def_is_closed :
    evalSourceMatches
        "_#C: {a: int}\naccept: _#C & {a: 1}\nreject: _#C & {a: 1, b: 2}\n"
        "_#C: {a: int}\naccept: {a: 1}\nreject: {a: 1, b: _|_}" = true := by
  native_decide

-- NO-OVER-DEFER (regression): a plain `#Base` (non-hidden definition) embedding still narrows
-- correctly. The fix widened `_#x` classification without touching `#x`, so this stays green.
theorem plain_def_embed_sibling_narrows :
    evalSourceMatches
        "#Hidden: {#x: string, copy: #x}\n#S: {#x: string, #Hidden}\nout: #S & {#x: \"hi\"}\n"
        "#Hidden: {#x: string, copy: string}\n#S: {#x: string, copy: string}\nout: {#x: \"hi\", copy: \"hi\"}"
          = true := by
  native_decide

-- A comprehension over a CONCRETE source still expands EAGERLY (no over-defer): no use-site
-- narrowing involved, source is literal, so the map populates directly.
theorem hidden_def_embed_concrete_source :
    evalSourceMatches
        "_#M: {data: {x: \"1\", y: \"2\"}, mapped: {for k, v in data {\"\\(k)\": v}}}\nout: {_#M}\n"
        "_#M: {data: {x: \"1\", y: \"2\"}, mapped: {x: \"1\", y: \"2\"}}\nout: {data: {x: \"1\", y: \"2\"}, mapped: {x: \"1\", y: \"2\"}}"
          = true := by
  native_decide

-- ### argocd-secret-data sub-slice 2 — embedded DEFAULT DISJUNCTION arm narrowing.
--
-- The exact argocd `#Secret` shape: a hidden-def `_#OpaqueSecret` in an embedded DEFAULT
-- DISJUNCTION arm `(*_#A | _#B)` whose body's `for k,v in #data` comprehension (or sibling
-- self-ref) is narrowed by the use-site. Pre-fix the disjunction evaluated standalone — its
-- default arm forced with NO use-operands collapsed the comprehension/self-ref BEFORE the
-- narrowing reached it (`resolveEmbeddedDisjDefault` picked the already-collapsed value).
--
-- Fix: DISTRIBUTE the narrowing into the disjunction arms at the UNEVALUATED level — both in
-- the `.conj` fold (`splitDisjConjunct`/`conjDisjArms?` → `*(_#A & narrow) | (_#B & narrow)`) and
-- in the embedded-disjunction merge (`meetEmbeddingsWithFuel` collapses to the default arm via
-- `conjDisjArms?` BEFORE deferral, so the arm force-splices the host's narrowing). `bodyNeedsDefer`
-- now recurses into a `.disj` embedding's default arm (`resolveEmbedDefBody?`), so the host defers.
-- Gated on a deferral-needing arm — a plain scalar/struct disjunction is untouched (no over-defer).
-- Each pin cue v0.16.1-exact.

-- HEADLINE: a `for k,v in #data` comprehension inside an embedded DEFAULT DISJUNCTION arm
-- populates AFTER the use-site narrows `#data` (the argocd `#Secret` shape). Pre-fix `mapped: {}`.
-- Post-V2 (`embed-disj-arm-fallthrough`): the disjunction is DISTRIBUTED, not collapsed to the
-- default arm — both arms survive (`*{default} | {other}`), default carries the populated
-- `mapped` and manifests cue-exact (`{mapped: {a: "x"}}`). The surviving second arm
-- (`_#B & narrow`) is the cross-product, no longer discarded.
theorem disj_default_embed_comprehension_narrows :
    evalSourceMatches
        "_#A: {#data: [string]: string, mapped: {for k, v in #data {\"\\(k)\": v}}}\n_#B: {other: \"b\"}\n#S: {#data: [string]: string, (*_#A | _#B)}\nout: #S & {#data: {a: \"x\"}}\n"
        "_#A: {#data: {[string]: string}, mapped: {}}\n_#B: {other: \"b\"}\n#S: *{#data: {[string]: string}, mapped: {}} | {#data: {[string]: string}, other: \"b\"}\nout: *{#data: {a: \"x\", [string]: string}, mapped: {a: \"x\"}} | {#data: {a: \"x\", [string]: string}, other: \"b\"}"
          = true := by
  native_decide

-- A plain SIBLING self-ref in an embedded DEFAULT DISJUNCTION arm sees the use-site narrowing.
-- Pre-fix `copy: string`. The minimal scalar form (matches `ds1`). Post-V2: distributed; default
-- arm carries `copy: "hi"` and wins at manifest, the second arm (`_#B & {#x:"hi"}`) survives.
theorem disj_default_embed_sibling_narrows :
    evalSourceMatches
        "_#A: {#x: string, copy: #x}\n_#B: {#x: string, other: \"b\"}\n#S: {#x: string, (*_#A | _#B)}\nout: #S & {#x: \"hi\"}\n"
        "_#A: {#x: string, copy: string}\n_#B: {#x: string, other: \"b\"}\n#S: *{#x: string, copy: string} | {#x: string, other: \"b\"}\nout: *{#x: \"hi\", copy: \"hi\"} | {#x: \"hi\", other: \"b\"}"
          = true := by
  native_decide

-- EMPTY-NARROW through the disjunction (no over-population): empty `#data` → empty `mapped`.
-- Post-V2: distributed; the default arm (empty `mapped`) wins, second arm survives.
theorem disj_default_embed_comprehension_empty :
    evalSourceMatches
        "_#A: {#data: [string]: string, mapped: {for k, v in #data {\"\\(k)\": v}}}\n_#B: {other: \"b\"}\n#S: {#data: [string]: string, (*_#A | _#B)}\nout: #S & {#data: {}}\n"
        "_#A: {#data: {[string]: string}, mapped: {}}\n_#B: {other: \"b\"}\n#S: *{#data: {[string]: string}, mapped: {}} | {#data: {[string]: string}, other: \"b\"}\nout: *{#data: {[string]: string}, mapped: {}} | {#data: {[string]: string}, other: \"b\"}"
          = true := by
  native_decide

-- NO-OVER-DEFER (scalar disjunction): a plain `*"prod" | "dev"` met with `string` keeps BOTH
-- arms (default preserved) — `conjDisjArms?` yields `none` (no deferral-needing arm), so the
-- standard distribute-at-meet path runs unchanged. A regression that over-deferred would alter it.
theorem disj_scalar_no_over_defer :
    evalSourceMatches "out: (*\"prod\" | \"dev\") & string\n" "out: *\"prod\" | \"dev\"" = true := by
  native_decide

-- NO-OVER-DEFER (struct disjunction, no sibling self-ref): `*{a:1,b:int} | {a:2}` met with
-- `{b:5}` distributes into BOTH arms at the meet, NOT via deferral (arms have no self-ref to
-- narrow). Confirms the deferral gate is tight on the embedded-disjunction-as-value path too.
theorem disj_struct_no_over_defer :
    evalSourceMatches
        "out: (*{a: 1, b: int} | {a: 2}) & {b: 5}\n"
        "out: *{a: 1, b: 5} | {a: 2, b: 5}" = true := by
  native_decide

-- SATURATION GUARD (audit #6): `conjDisjArms?`'s `fuel = 0` arm returns `none` (declines to
    -- distribute) rather than dropping fields — it is NOT a truncation source, so it need not bump
    -- `truncCount`. Pin that the fuel-exhausted scan is a clean non-defer: at `fuel = 0` a
    -- `.refId`-bodied disjunction conjunct yields `none` (falls to the standard fold, which keeps
    -- its own bracketed truncation discipline). A regression that made it drop to a partial value
    -- without bumping would reopen the audit-#6 hole.
theorem conj_disj_arms_fuel_zero_declines :
    conjDisjArms? [(0, [])] 0 (.refId ⟨0, 0⟩) = none := by
  native_decide

-- ### embed-disj-arm-fallthrough (audit #10 V2): a dead default arm FALLS THROUGH.
--
-- An embedded default disjunction (`(*_#A | _#B)`) used to collapse to its default arm BEFORE the
-- host narrowing spliced in, with no fall-through when the narrowing KILLED the default arm — kue
-- bottomed where cue picks the surviving arm. Fix: distribute the host narrowing into EVERY arm and
-- prune bottoms (`normalizeDisj` via `liveAlternatives`), then resolve. cue v0.16.1-exact.

-- HEADLINE: narrowing `v:"s"` kills the default arm `_#A` (`v:int`); kue must fall through to the
-- surviving `_#B` (`v:string`) — not bottom. Was kue BOTTOM pre-fix; cue `{kind:"b",v:"s"}`.
theorem embed_disj_dead_default_falls_through :
    evalSourceMatches
        "_#A: {kind: \"a\", v: int}\n_#B: {kind: \"b\", v: string}\n#S: {kind: string, (*_#A | _#B)}\nout: #S & {v: \"s\"}\n"
        "_#A: {kind: \"a\", v: int}\n_#B: {kind: \"b\", v: string}\n#S: *{kind: \"a\", v: int} | {kind: \"b\", v: string}\nout: {kind: \"b\", v: \"s\"}"
          = true := by
  native_decide

-- narrowing COMPATIBLE with the default arm (`v:1`): the default still wins (no spurious switch).
-- `_#B` dies (`v:1 & string = _|_`), leaving a LONE default `*{kind:"a",v:1}` — vacuous, so it
-- collapses to the bare struct (matching cue, which shows `out: {kind:"a", v:1}`).
theorem embed_disj_live_default_kept :
    evalSourceMatches
        "_#A: {kind: \"a\", v: int}\n_#B: {kind: \"b\", v: string}\n#S: {kind: string, (*_#A | _#B)}\nout: #S & {v: 1}\n"
        "_#A: {kind: \"a\", v: int}\n_#B: {kind: \"b\", v: string}\n#S: *{kind: \"a\", v: int} | {kind: \"b\", v: string}\nout: {kind: \"a\", v: 1}"
          = true := by
  native_decide

-- narrowing kills ALL arms (`v:true` is neither int nor string): conflict, matching cue.
theorem embed_disj_all_arms_die_conflict :
    evalSourceMatches
        "_#A: {kind: \"a\", v: int}\n_#B: {kind: \"b\", v: string}\n#S: {kind: string, (*_#A | _#B)}\nout: #S & {v: true}\n"
        "_#A: {kind: \"a\", v: int}\n_#B: {kind: \"b\", v: string}\n#S: *{kind: \"a\", v: int} | {kind: \"b\", v: string}\nout: _|_"
          = true := by
  native_decide

-- a single-arm embedded "disjunction" (`(_#A)`) still narrows correctly (no arms to fall to).
theorem embed_disj_single_arm_narrows :
    evalSourceMatches
        "_#A: {kind: \"a\", v: int}\n#S: {kind: string, (_#A)}\nout: #S & {v: 1}\n"
        "_#A: {kind: \"a\", v: int}\n#S: {kind: \"a\", v: int}\nout: {kind: \"a\", v: 1}"
          = true := by
  native_decide

-- ### argocd `parts.#Mixin` — comprehension guard over a use-site-narrowed REGULAR sibling.
--
-- `#Inner` carries `for _, add in Self.#additions { if kind == add.#kind { add.#patch } }`: the guard
-- reads the REGULAR sibling `kind`, which `#Outer` (embedding `#Inner`) and the use site narrow.
-- `hiddenFieldsOnly` splices only hidden/def fields into a forced embed, so the guard fired against the
-- un-narrowed `kind: string`, stayed incomplete, and the guarded body dropped — the outer `meet` cannot
-- re-fire a collapsed comprehension. `embedComprehensionReadLabels` collects the def-frame indices a
-- comprehension reads, and `spliceOperandForEmbed` carries exactly those REGULAR siblings so the guard
-- sees the narrowed value at expansion time (matching cue's lazy comprehension). This was the first of
-- two cross-module argocd bottoms (`defaults.#ListenerSet`); the `let`-buried multi-embed shape is the
-- second, tracked separately.

-- The mechanism pin: a comprehension guard reading the regular sibling `kind` (slot 2) over the
-- `Self=` for-source (slot 0) reports BOTH def-frame labels read. `Self` is harmless (an alias,
-- not a regular operand field); `kind` is the regular sibling the splice must carry.
theorem embed_comprehension_reads_guarded_regular_sibling :
    embedComprehensionReadLabels
      (.structComp
        [⟨"Self", .letBinding, .thisStruct⟩, ⟨"#additions", .hidden, .top⟩, ⟨"kind", .regular, .kind .string⟩]
        [.comprehension
          [.forIn (some "_") "add" (.selector (.refId ⟨0, 0⟩) "#additions")]
          (.structComp []
            [.comprehension
              [.guard (.binary .eq (.refId ⟨2, 2⟩) (.selector (.refId ⟨1, 1⟩) "#kind"))]
              (.structComp [] [.selector (.refId ⟨2, 1⟩) "#patch"] .regularOpen)]
            .regularOpen)]
        .regularOpen)
      = ["Self", "kind"] := by
  native_decide

-- End-to-end: the matched patch surfaces (the embedded guard fires AFTER the use-site `kind`).
theorem embed_comprehension_guard_emits_matched_patch :
    exportJsonMatches
        "#Inner: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tkind: string\n\tfor _, add in Self.#additions {\n\t\tif kind == add.#kind {\n\t\t\tadd.#patch\n\t\t}\n\t}\n\t...\n}\n#Outer: {\n\t#Inner\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"yes\"}}\n}\nout: #Outer & {kind: \"ListenerSet\"}\n"
        "{\n    \"out\": {\n        \"kind\": \"ListenerSet\",\n        \"meta\": \"yes\"\n    }\n}\n"
          = true := by
  native_decide

-- Guard FALSE (use-site `kind` mismatches `add.#kind`): the body must NOT fire — no over-fire.
theorem embed_comprehension_guard_false_drops_body :
    exportJsonMatches
        "#Inner: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tkind: string\n\tfor _, add in Self.#additions {\n\t\tif kind == add.#kind {\n\t\t\tadd.#patch\n\t\t}\n\t}\n\t...\n}\n#Outer: {\n\t#Inner\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"yes\"}}\n}\nout: #Outer & {kind: \"Other\"}\n"
        "{\n    \"out\": {\n        \"kind\": \"Other\"\n    }\n}\n"
          = true := by
  native_decide

-- SOUNDNESS: a guarded patch that REALLY conflicts with a sibling still bottoms (no over-lazy).
-- `exportJsonBottoms` positively witnesses the bottom (the inner `.error` manifest arm), so a
-- regression to a spurious concrete output fails — unlike `exportJsonMatches … "" = false`, which
-- any non-empty output also satisfies.
theorem embed_comprehension_guard_real_conflict_bottoms :
    exportJsonBottoms
        "#Inner: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tkind: string\n\tmeta: \"fixed\"\n\tfor _, add in Self.#additions {\n\t\tif kind == add.#kind {\n\t\t\tadd.#patch\n\t\t}\n\t}\n\t...\n}\n#Outer: {\n\t#Inner\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"clash\"}}\n}\nout: #Outer & {kind: \"ListenerSet\"}\n"
          = true := by
  native_decide

-- ### Bug2-1 (Gap-1) + A-EN1 — let-buried comprehension read-label detection.
--
-- Bug #1 (above) detected only a comprehension at the embed body's TOP-LEVEL `cs`. When the
-- comprehension is buried inside the VALUE of a `let _patch = { … if kind == … }`, the top-level `cs`
-- holds only the `_patch` embed-ref — a `.refId` LEAF that `defFrameRefIndices` did not follow into
-- the let's value. So the regular sibling `kind` the guard reads THROUGH the let was never detected,
-- never spliced, and the guard fired against the un-narrowed `kind: string` → the body dropped.
-- `closeDefFrameReadIndices` closes the detected index set over `letBinding` slots (transitively, with
-- a visited-set cycle bound), so a read through one or more `let`s is found and spliced. Covers BOTH
-- the `if`-guard read (Gap-1) and the `for`-SOURCE read (A-EN1).

-- Mechanism (Gap-1, ONE let): the guard `if kind == add.#kind` lives inside `_patch`'s value (a
-- `let`, slot 3); the top-level `cs` holds only the `_patch` embed-ref (`.refId ⟨0,3⟩`). Following
-- the let into its value finds the regular `kind` (slot 2). Reports `kind` (the regular sibling the
-- splice must carry); `Self`/`_patch` are aliases, harmless. Pre-fix this returned `["_patch"]` only.
theorem let_buried_guard_reads_regular_sibling :
    embedComprehensionReadLabels
      (.structComp
        [⟨"Self", .letBinding, .thisStruct⟩, ⟨"#additions", .hidden, .top⟩,
         ⟨"kind", .regular, .kind .string⟩,
         ⟨"_patch", .letBinding,
            (.structComp []
              [.comprehension
                [.forIn (some "_") "add" (.selector (.refId ⟨1, 0⟩) "#additions")]
                (.structComp []
                  [.comprehension
                    [.guard (.binary .eq (.refId ⟨3, 2⟩) (.selector (.refId ⟨1, 1⟩) "#kind"))]
                    (.structComp [] [.selector (.refId ⟨3, 1⟩) "#patch"] .regularOpen)]
                  .regularOpen)]
              .regularOpen)⟩]
        [.refId ⟨0, 3⟩]
        .regularOpen)
      = ["_patch", "Self", "kind"] := by
  native_decide

-- Mechanism (Gap-1, TWO nested lets): `structShape` (slot 4) embeds `_patch` (slot 3), whose value
-- holds the guard reading `kind` (slot 2). Following the let chain `structShape -> _patch -> kind`
-- (the `closeDefFrameReadIndices` fixpoint) discovers `kind`.
theorem two_lets_buried_guard_reads_regular_sibling :
    ("kind" ∈ embedComprehensionReadLabels
      (.structComp
        [⟨"Self", .letBinding, .thisStruct⟩, ⟨"#additions", .hidden, .top⟩,
         ⟨"kind", .regular, .kind .string⟩,
         ⟨"_patch", .letBinding,
            (.structComp []
              [.comprehension
                [.forIn (some "_") "add" (.selector (.refId ⟨1, 0⟩) "#additions")]
                (.structComp []
                  [.comprehension
                    [.guard (.binary .eq (.refId ⟨3, 2⟩) (.selector (.refId ⟨1, 1⟩) "#kind"))]
                    (.structComp [] [.selector (.refId ⟨3, 1⟩) "#patch"] .regularOpen)]
                  .regularOpen)]
              .regularOpen)⟩,
         ⟨"structShape", .letBinding, (.structComp [] [.refId ⟨1, 3⟩] .regularOpen)⟩]
        [.refId ⟨0, 4⟩]
        .regularOpen)) = true := by
  native_decide

-- No-over-splice: a let whose comprehension reads NO regular sibling (it iterates the hidden
-- `#additions` and yields a static body) must NOT pull any regular label into the splice. The
-- detected set contains only aliases (`_patch`/`Self`), never a regular output field.
theorem let_buried_no_regular_read_no_over_splice :
    (embedComprehensionReadLabels
      (.structComp
        [⟨"Self", .letBinding, .thisStruct⟩, ⟨"#additions", .hidden, .top⟩,
         ⟨"_patch", .letBinding,
            (.structComp []
              [.comprehension
                [.forIn (some "_") "add" (.selector (.refId ⟨1, 0⟩) "#additions")]
                (.structComp [] [.selector (.refId ⟨2, 1⟩) "#patch"] .regularOpen)]
              .regularOpen)⟩]
        [.refId ⟨0, 2⟩]
        .regularOpen)).filter (fun l => l == "name" || l == "kind") = [] := by
  native_decide

-- Totality / cycle bound: a self-referential `let a = a` (its value reads its OWN slot 0) must
-- terminate — `closeDefFrameReadIndices`'s visited-set follows each let slot at most once. The
-- analysis returns rather than looping; the result is finite.
theorem let_self_ref_cycle_terminates :
    (embedComprehensionReadLabels
      (.structComp
        [⟨"a", .letBinding, (.refId ⟨0, 0⟩)⟩]
        [.refId ⟨0, 0⟩]
        .regularOpen)).length ≤ 1 := by
  native_decide

-- End-to-end (Gap-1, ONE let): the matched patch surfaces THROUGH the `let _patch`.
theorem let_buried_guard_emits_matched_patch :
    exportJsonMatches
        "#Mixin: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tkind: string\n\tlet _patch = {\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t}\n\t_patch\n\t...\n}\n#Use: {\n\t#Mixin\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"yes\"}}\n}\nout: #Use & {kind: \"ListenerSet\"}\n"
        "{\n    \"out\": {\n        \"kind\": \"ListenerSet\",\n        \"meta\": \"yes\"\n    }\n}\n"
          = true := by
  native_decide

-- End-to-end (Gap-1, ONE let): guard FALSE through the let drops the body — no over-fire.
theorem let_buried_guard_false_drops_body :
    exportJsonMatches
        "#Mixin: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tkind: string\n\tlet _patch = {\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t}\n\t_patch\n\t...\n}\n#Use: {\n\t#Mixin\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"yes\"}}\n}\nout: #Use & {kind: \"Other\"}\n"
        "{\n    \"out\": {\n        \"kind\": \"Other\"\n    }\n}\n"
          = true := by
  native_decide

-- SOUNDNESS (Gap-1): a let-buried matched patch that REALLY conflicts with the use-site narrowing
-- still bottoms (the splice lets the guard fire, then the merge conflicts — not a silent drop).
theorem let_buried_guard_real_conflict_bottoms :
    exportJsonBottoms
        "#Mixin: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tkind: string\n\tlet _patch = {\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t}\n\t_patch\n\t...\n}\n#Use: {\n\t#Mixin\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {tag: \"x\"}}\n}\nout: #Use & {kind: \"ListenerSet\", tag: \"y\"}\n"
          = true := by
  native_decide

-- End-to-end (A-EN1, let-buried `for`-SOURCE): the comprehension iterates the REGULAR sibling
-- `items` (narrowed at the use site) through the `let _expanded` — the keys must surface.
theorem let_buried_for_source_expands :
    exportJsonMatches
        "#Mixin: {\n\titems: [...string]\n\tlet _expanded = {\n\t\tfor _, it in items {\n\t\t\t\"\\(it)\": {present: true}\n\t\t}\n\t}\n\t_expanded\n\t...\n}\n#Use: {\n\t#Mixin\n}\nout: #Use & {items: [\"a\", \"b\"]}\n"
        "{\n    \"out\": {\n        \"items\": [\n            \"a\",\n            \"b\"\n        ],\n        \"a\": {\n            \"present\": true\n        },\n        \"b\": {\n            \"present\": true\n        }\n    }\n}\n"
          = true := by
  native_decide

-- ### Bug2-4 — let-LOCAL declare-and-read narrowing (the argocd `#Mixin` blocker).
--
-- Bug2-1 (above) handled a comprehension reading a regular sibling declared at the EMBED's def frame,
-- through one or more lets. Bug2-4 is the harder shape `defs/parts.#Mixin` uses: the read sibling is
-- DECLARED INSIDE the same let that buries the comprehension (`let _patch = { kind: string; for … {
-- if kind == add.#kind {…} } }`). The guard's `kind` resolves to `_patch`'s OWN frame and `kind` is
-- declared there too, so NO def-frame index names it — the splice would land at the def frame as a
-- sibling, a distinct binding the guard never reads. `letPromotedReadLabels` SURFACES the label (so the
-- host splices its narrowing toward the def), and `injectLetLocalNarrowings` MEETS that narrowing into
-- the let-local `kind` before the comprehension expands — matching cue's lazy promote-then-narrow.
-- Total via a `seen`/`fuel` bound (cycle-safe); sound because it only meets the host narrowing into a
-- field the host narrows anyway (never invents a value, never over-splices).

-- Mechanism: `_patch` declares-and-reads `kind` (slot 0 of its OWN frame) via a guard inside a
-- `for` body (which pushes one frame: the guard's `kind` ref is `⟨1,0⟩`, resolving back to the let
-- frame). `letPromotedReadLabels` surfaces `kind` even though it is NOT a def-frame label. Pre-fix
-- this was the gap: the read resolved to the let's own frame, the declaration was there too, so no
-- def-frame index named it and the narrowing never reached the guard.
theorem let_local_declare_and_read_surfaces_label :
    ("kind" ∈ letPromotedReadLabels evalFuel []
      (.structComp
        [⟨"kind", .regular, .kind .string⟩]
        [.comprehension
          [.forIn (some "_") "add" (.selector (.refId ⟨1, 0⟩) "#additions")]
          (.structComp []
            [.comprehension
              [.guard (.binary .eq (.refId ⟨2, 0⟩) (.selector (.refId ⟨1, 0⟩) "#kind"))]
              (.structComp [] [.selector (.refId ⟨1, 0⟩) "#patch"] .regularOpen)]
            .regularOpen)]
        .regularOpen)) = true := by
  native_decide

-- No-over-splice: a let-local that the comprehension does NOT read (here the let has no
-- comprehension at all, just a static field `x`) is never surfaced — so its narrowing is never
-- injected and an unrelated declaration stays byte-identical.
theorem let_local_unread_not_surfaced :
    ("x" ∈ letPromotedReadLabels evalFuel []
      (.structComp [⟨"x", .regular, .kind .string⟩] [] .regularOpen)) = false := by
  native_decide

-- Totality / cycle bound: `injectLetLocalNarrowings` over a self-referential let value terminates
-- (the `seen`-set stops re-following the same value) and returns a finite value (here unchanged —
-- the cycle is broken without narrowing an unread slot).
theorem inject_let_local_self_ref_terminates :
    (injectLetLocalNarrowings evalFuel [("kind", .prim (.string "X"))] []
      (.structComp [⟨"a", .letBinding, (.refId ⟨0, 0⟩)⟩] [.refId ⟨0, 0⟩] .regularOpen)
      == (.structComp [⟨"a", .letBinding, (.refId ⟨0, 0⟩)⟩] [.refId ⟨0, 0⟩] .regularOpen)) = true := by
  native_decide

-- End-to-end (the argocd `#Mixin` minimal shape, WITH the structural disjunction): the matched
-- patch surfaces THROUGH the let-buried declare-and-read `kind`, content-identical to cue.
theorem mixin_let_local_disj_emits_matched_patch :
    exportJsonMatches
        "#Mixin: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tlet _patch = {\n\t\tkind: string\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t\t...\n\t}\n\tlet listShape = {\n\t\t#components: [string]: _patch\n\t\t[...]\n\t}\n\tlet structShape = {\n\t\t_patch\n\t\t...\n\t}\n\tlistShape | structShape | error(\"nope\")\n\t...\n}\n#Use: {\n\t#Mixin\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"yes\"}}\n}\nout: #Use & {kind: \"ListenerSet\"}\n"
        "{\n    \"out\": {\n        \"kind\": \"ListenerSet\",\n        \"meta\": \"yes\"\n    }\n}\n"
          = true := by
  native_decide

-- SOUNDNESS: the let-local injection meets a REAL conflict to bottom (the let declares `meta:
-- \"fixed\"`, the matched patch yields `meta: \"clash\"`) — not a silent drop, not a spurious keep.
theorem mixin_let_local_real_conflict_bottoms :
    exportJsonBottoms
        "#Mixin: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tlet _patch = {\n\t\tkind: string\n\t\tmeta: \"fixed\"\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t\t...\n\t}\n\t_patch\n\t...\n}\n#Use: {\n\t#Mixin\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"clash\"}}\n}\nout: #Use & {kind: \"ListenerSet\"}\n"
          = true := by
  native_decide

-- Guard FALSE through the let-local: the matched-kind mismatches, so the body must NOT fire.
theorem mixin_let_local_guard_false_drops_body :
    exportJsonMatches
        "#Mixin: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tlet _patch = {\n\t\tkind: string\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t\t...\n\t}\n\t_patch\n\t...\n}\n#Use: {\n\t#Mixin\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"yes\"}}\n}\nout: #Use & {kind: \"Other\"}\n"
        "{\n    \"out\": {\n        \"kind\": \"Other\"\n    }\n}\n"
          = true := by
  native_decide

-- ### Bug2-5 — disjunction-arm let-local narrowing across a TRANSITIVE embed.
--
-- Bug2-4 (above) narrowed a let-local (`_patch.kind`) when the disjunction-bodied mixin is embedded
-- DIRECTLY by the host that declares the narrowing sibling (`#Use: {#Mixin; #additions; ...}` with
-- `out: #Use & {kind: …}`). The argocd `#ListenerSet` shape is one level deeper: a SIBLING def's static
-- field narrows the mixin, and the mixin is embedded TRANSITIVELY (`#ListenerSet` co-embeds
-- `#UseCertManager`, which embeds `#Mixin`). The host's `kind` narrowing must cross TWO embed levels to
-- reach `_patch.kind` on the disjunction-arm path. Pre-fix, `spliceOperandForEmbed` into the MIDDLE def
-- (`#UseCertManager`) dropped `kind` — that def neither reads `kind` nor DIRECTLY embeds a disjunction
-- (the disjunction is one more level down, inside `#Mixin`), so `embedBodyEmbedsDisj` (a one-level
-- check) returned false and the Gap-2b "splice ALL regular fields" gate never fired. `kind` never
-- reached the disjunction, the `if kind == add.#kind` guard fired against the un-narrowed `kind: string`,
-- and the patch dropped (argocd bottomed).
--
-- Fix: `embedBodyEmbedsDisjDeep` follows the embed chain (resolving each embedding via
-- `resolveEmbedDefBody?`, mirroring `bodyNeedsDefer`) so a TRANSITIVELY-embedded disjunction still
-- triggers the regular-field splice. The splice it gates is the SAME sound Gap-2b mechanism (meet is
-- idempotent on a field an arm already carries; a real conflict still bottoms), so widening the GATE
-- through the chain never over-narrows.

-- Mechanism: a MIDDLE def body (`#UseCertManager`) embeds `#Mixin` (slot 0 of its env frame), whose
-- body embeds a disjunction. `embedBodyEmbedsDisj` (one-level) is FALSE for the middle body (no `.disj`
-- in its own `cs`); `embedBodyEmbedsDisjDeep` follows the `#Mixin` embed-ref into the disjunction-bodied
-- def and returns TRUE — so the host's regular `kind` is spliced through the middle def.
theorem embed_body_embeds_disj_deep_transitive :
    -- env frame holds `#Mixin` at slot 0 (a struct-comp body whose `cs` is the structural disjunction).
    (embedBodyEmbedsDisjDeep
      [(0, [⟨"#Mixin", .definition,
              (.structComp [] [.disj [(.regular, mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []),
                                      (.regular, .builtinCall "error" [.prim (.string "no")])]] .regularOpen)⟩])]
      evalFuel
      -- the middle body re-embeds `#Mixin` (a depth-0 ref to slot 0) — no `.disj` of its OWN.
      (.structComp [] [.refId ⟨0, 0⟩] .regularOpen)) = true := by
  native_decide

-- GATE control (byte-identity guard): a middle body that re-embeds a NON-disjunction def is FALSE —
-- so the deep gate adds no splice, byte-identical to pre-fix for every non-mixin embed chain.
theorem embed_body_embeds_disj_deep_no_disj :
    (embedBodyEmbedsDisjDeep
      [(0, [⟨"#Plain", .definition, (.structComp [⟨"a", .regular, .prim (.int 1)⟩] [] .regularOpen)⟩])]
      evalFuel
      (.structComp [] [.refId ⟨0, 0⟩] .regularOpen)) = false := by
  native_decide

-- Direct (one-level) disjunction embedding is still detected by the deep check (it subsumes the
-- one-level `embedBodyEmbedsDisj` via the leading disjunct of the `||`).
theorem embed_body_embeds_disj_deep_direct :
    (embedBodyEmbedsDisjDeep []
      evalFuel
      (.structComp [] [.disj [(.regular, mkStruct [] .regularOpen none []),
                              (.regular, .builtinCall "error" [.prim (.string "no")])]] .regularOpen)) = true := by
  native_decide

-- End-to-end (the argocd `#ListenerSet` minimal shape): a co-embedding SIBLING def's static `kind`
-- narrows `_patch.kind` buried inside a TRANSITIVELY-embedded `#Mixin` disjunction. The matched patch
-- (`meta: "yes"`) surfaces across BOTH embed levels — content-identical to cue (cue emits it; pre-fix
-- kue DROPPED it).
theorem bug25_transitive_embed_disj_emits_matched_patch :
    exportJsonMatches
        "#Mixin: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tlet _patch = {\n\t\tkind: string\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t\t...\n\t}\n\tlet listShape = {\n\t\t#components: [string]: _patch\n\t\t[...]\n\t}\n\tlet structShape = {\n\t\t_patch\n\t\t...\n\t}\n\tlistShape | structShape | error(\"nope\")\n\t...\n}\n#Mid: {\n\t#Mixin\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"yes\"}}\n}\n#Outer: {\n\t#Mid\n\tkind: \"ListenerSet\"\n}\nout: #Outer\n"
        "{\n    \"out\": {\n        \"kind\": \"ListenerSet\",\n        \"meta\": \"yes\"\n    }\n}\n"
          = true := by
  native_decide

-- SOUNDNESS (transitive): the deep-spliced narrowing meets a REAL conflict to bottom — the buried
-- `_patch` declares `meta: \"fixed\"` and the matched patch yields `meta: \"clash\"` two levels down.
-- The widened gate must NOT silently drop or spuriously keep — it must conflict.
theorem bug25_transitive_real_conflict_bottoms :
    exportJsonBottoms
        "#Mixin: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tlet _patch = {\n\t\tkind: string\n\t\tmeta: \"fixed\"\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t\t...\n\t}\n\tlet structShape = {\n\t\t_patch\n\t\t...\n\t}\n\tstructShape | error(\"nope\")\n\t...\n}\n#Mid: {\n\t#Mixin\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"clash\"}}\n}\n#Outer: {\n\t#Mid\n\tkind: \"ListenerSet\"\n}\nout: #Outer\n"
          = true := by
  native_decide

-- Guard FALSE across the transitive embed: the sibling `kind` mismatches the addition's `#kind`, so
-- the buried body must NOT fire — the patch drops, NOT a spurious emit.
theorem bug25_transitive_guard_false_drops_body :
    exportJsonMatches
        "#Mixin: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tlet _patch = {\n\t\tkind: string\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t\t...\n\t}\n\tlet structShape = {\n\t\t_patch\n\t\t...\n\t}\n\tstructShape | error(\"nope\")\n\t...\n}\n#Mid: {\n\t#Mixin\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"yes\"}}\n}\n#Outer: {\n\t#Mid\n\tkind: \"Other\"\n}\nout: #Outer\n"
        "{\n    \"out\": {\n        \"kind\": \"Other\"\n    }\n}\n"
          = true := by
  native_decide

-- No-regression: the DIRECT one-level embed (the Bug2-4 shape, `kind` a sibling of `#Mixin`) still
-- emits the patch — the deep gate subsumes the one-level case without changing it.
theorem bug25_direct_embed_still_emits :
    exportJsonMatches
        "#Mixin: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tlet _patch = {\n\t\tkind: string\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t\t...\n\t}\n\tlet structShape = {\n\t\t_patch\n\t\t...\n\t}\n\tstructShape | error(\"nope\")\n\t...\n}\n#Host: {\n\t#Mixin\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"yes\"}}\n\tkind: \"ListenerSet\"\n}\nout: #Host\n"
        "{\n    \"out\": {\n        \"kind\": \"ListenerSet\",\n        \"meta\": \"yes\"\n    }\n}\n"
          = true := by
  native_decide

-- DEPTH (3-level chain): `#Outer` → `#Mid` → `#Mid2` → `#Mixin`. The narrowing `kind` crosses
-- THREE embed levels to reach `_patch.kind`. Confirms the deep walk is not accidentally
-- depth-bounded at 2 — `embedBodyEmbedsDisjDeep` follows `resolveEmbedDefBody?` through every
-- intermediary def. Oracle-confirmed identical to cue v0.16.1 (`{kind, meta:"deep3"}`).
theorem bug25_three_level_chain_emits :
    exportJsonMatches
        "#Mixin: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tlet _patch = {\n\t\tkind: string\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t\t...\n\t}\n\tlet structShape = {\n\t\t_patch\n\t\t...\n\t}\n\tstructShape | error(\"nope\")\n\t...\n}\n#Mid2: {#Mixin}\n#Mid: {#Mid2}\n#Outer: {\n\t#Mid\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"deep3\"}}\n\tkind: \"ListenerSet\"\n}\nout: #Outer\n"
        "{\n    \"out\": {\n        \"kind\": \"ListenerSet\",\n        \"meta\": \"deep3\"\n    }\n}\n"
          = true := by
  native_decide

-- TERMINATION (cyclic embed on the disj-gate path): `#A` embeds `#B`, `#B` embeds `#A`, and `#A`
-- carries a disjunction — so `embedBodyEmbedsDisjDeep` would loop forever if it weren't
-- fuel-bounded. The `native_decide` reducing AT ALL is the witness that evaluation TERMINATES (a
-- non-terminating walk would never produce a kernel value / the proof would never compile). The
-- deep walk's `termination_by fuel` bottoms the recursion at fuel exhaustion rather than diverging
-- on the cycle; the surrounding eval bottoms the self-embedding `#A`/`#B` cycle (Kue's standing
-- structural-cycle policy — `#L:{n,next:#L}` bottoms, plan item D#2). The contract here is purely
-- "returns, does not hang"; a regression to non-termination fails to BUILD, not just the pin.
theorem bug25_cyclic_embed_terminates :
    exportJsonBottoms
        "#A: {\n\t#B\n\tlet s = {tag: \"x\"}\n\ts | error(\"nope\")\n\t...\n}\n#B: {#A}\n#Outer: {\n\t#A\n\ttag: \"x\"\n}\nout: #Outer\n"
          = true := by
  native_decide

-- OVER-GATE CONTROL (narrowing must NOT spuriously resolve): two STRUCT-compatible arms behind a
-- transitive embed, host narrows fields BOTH arms admit (open `...`). The deep gate fires (regular
-- fields spliced in) but NEITHER arm structurally conflicts, so the disjunction must stay ambiguous
-- — the splice is a type-conflict PRUNE, not a shape heuristic, so it cannot pick a winner here.
-- cue v0.16.1 keeps it incomplete (`{…}|{…}`); kue keeps it ambiguous → both refuse to resolve.
-- Witnesses that the widened gate does NOT over-prune (a regression that picked an arm would make
-- this export succeed). See `disj_embed_struct_disc_struct_struct_stays_ambiguous` (one-level).
theorem bug25_transitive_no_over_prune_two_struct_arms :
    exportJsonBottoms
        "#Mixin: {\n\tlet listShape = {items: [...int]}\n\tlet structShape = {name: string}\n\tlistShape | structShape | error(\"nope\")\n\t...\n}\n#Mid: {#Mixin}\n#Outer: {\n\t#Mid\n\textra: \"hello\"\n\tname: \"x\"\n}\nout: #Outer\n"
          = true := by
  native_decide

-- ### Bug2-2 (Gap-2) — force-tier disjunction-arm narrowing.
--
-- An embedded def `#M` carrying a discriminated disjunction (`{shape:"struct",…} |
-- {shape:"list",…} | error`) selects the right arm when narrowed DIRECTLY (`#M &
-- {shape:"struct"}`, the `meetEmbeddingsWithFuel` `conjDisjArms?` distribution one tier up). But
-- when `#M` is itself embedded one layer down (`#U:{#M}`, then `#U & {shape:"struct"}`), the outer
-- narrowing of the discriminator `shape` reaches the host frame but was NOT spliced INTO `#M` behind
-- the force tier — the arms MATCH `shape`, they do not READ it, so `embedComprehensionReadLabels`
-- missed it. Every arm survived and the meet bottomed. `embedDisjArmDeclLabels` surfaces the regular
-- labels an embedded disjunction's arms DECLARE (following a `.refId` arm into its `let` slot for the
-- shapeD `structShape | listShape` form), so the host's narrowed discriminator splices into `#M` and
-- its force-time arm distribution prunes the dead arms exactly as the DIRECT case does. GATED: returns
-- `[]` unless the body's `cs` holds a `.disj` embedding — no disjunction embedding → no extra splice →
-- byte-identical (cert-manager fires this 0 times).

-- Mechanism (inline arms): the discriminator `shape` (body slot 1, a regular sibling) is declared by
-- the disjunction's struct arms (`shape:"struct"`, `shape:"list"`). It is surfaced so the host's
-- narrowed `shape` splices into the embedded `#M`. `#k` (hidden, slot 0) is NOT a discriminator (the
-- arms read it via `val:#k`, not declare-discriminate) — `embedComprehensionReadLabels` carries it.
theorem embed_disj_arm_decl_labels_inline :
    embedDisjArmDeclLabels
      (.structComp
        [⟨"#k", .hidden, .kind .string⟩, ⟨"shape", .regular, .kind .string⟩]
        [.disj
          [(.regular, mkStruct [⟨"shape", .regular, .prim (.string "struct")⟩,
                               ⟨"val", .regular, .refId ⟨1, 0⟩⟩] .regularOpen none []),
           (.regular, mkStruct [⟨"shape", .regular, .prim (.string "list")⟩,
                               ⟨"items", .regular, .list [.refId ⟨1, 0⟩]⟩] .regularOpen none []),
           (.regular, .builtinCall "error" [.prim (.string "no shape")])]]
        .regularOpen)
      = ["shape"] := by
  native_decide

-- Mechanism (let-ref arms, the shapeD form): the arms are `.refId`s to `let` slots
-- (`structShape`/`listShape`, slots 4/3) holding `{shape:"struct",…}`/`{shape:"list",…}`. Following
-- the `.refId ⟨0,i⟩` arm into the body's own let value at index `i` discovers the declared `shape`.
theorem embed_disj_arm_decl_labels_let_refs :
    embedDisjArmDeclLabels
      (.structComp
        [⟨"#additions", .hidden, .top⟩, ⟨"kind", .regular, .kind .string⟩,
         ⟨"shape", .regular, .kind .string⟩,
         ⟨"listShape", .letBinding,
            (mkStruct [⟨"shape", .regular, .prim (.string "list")⟩] .regularOpen none [])⟩,
         ⟨"structShape", .letBinding,
            (.structComp [⟨"shape", .regular, .prim (.string "struct")⟩] [] .regularOpen)⟩]
        [.disj
          [(.regular, .refId ⟨0, 4⟩), (.regular, .refId ⟨0, 3⟩),
           (.regular, .builtinCall "error" [.prim (.string "no shape")])]]
        .regularOpen)
      = ["shape"] := by
  native_decide

-- GATE (cert-manager byte-identity guard): a body with NO `.disj` embedding in `cs` yields `[]`, so
-- the splice path adds nothing — byte-identical. Here the embedding is a plain ref, not a `.disj`.
theorem embed_disj_arm_decl_labels_no_disj_gate :
    embedDisjArmDeclLabels
      (.structComp
        [⟨"shape", .regular, .kind .string⟩]
        [.refId ⟨1, 0⟩]
        .regularOpen)
      = [] := by
  native_decide

-- End-to-end (POSITIVE, inline): the struct arm is selected behind the force tier.
theorem disj_embed_one_layer_selects_struct_arm :
    exportJsonMatches
        "#M: {\n\t#k: string\n\tshape: string\n\t{shape: \"struct\", val: #k} | {shape: \"list\", items: [#k]} | error(\"no shape\")\n\t...\n}\n#U: {#M}\nout: #U & {#k: \"x\", shape: \"struct\"}\n"
        "{\n    \"out\": {\n        \"shape\": \"struct\",\n        \"val\": \"x\"\n    }\n}\n"
          = true := by
  native_decide

-- End-to-end (the OTHER arm, no over-prune): narrowing `shape:"list"` selects the list arm.
theorem disj_embed_one_layer_selects_list_arm :
    exportJsonMatches
        "#M: {\n\t#k: string\n\tshape: string\n\t{shape: \"struct\", val: #k} | {shape: \"list\", items: [#k]} | error(\"no shape\")\n\t...\n}\n#U: {#M}\nout: #U & {#k: \"y\", shape: \"list\"}\n"
        "{\n    \"out\": {\n        \"shape\": \"list\",\n        \"items\": [\n            \"y\"\n        ]\n    }\n}\n"
          = true := by
  native_decide

-- UNCHANGED: the DIRECT-narrowing case (`#M & {narrow}`, one tier up) still selects the struct arm —
-- the fix only adds the embedded-one-layer-down path, never perturbs the direct distribution.
theorem disj_direct_narrow_unchanged :
    exportJsonMatches
        "#M: {\n\t#k: string\n\tshape: string\n\t{shape: \"struct\", val: #k} | {shape: \"list\", items: [#k]} | error(\"no shape\")\n\t...\n}\nout: #M & {#k: \"z\", shape: \"struct\"}\n"
        "{\n    \"out\": {\n        \"shape\": \"struct\",\n        \"val\": \"z\"\n    }\n}\n"
          = true := by
  native_decide

-- SOUNDNESS (a real conflict kills ALL structural arms → still bottoms; no arm over-survives):
-- `shape:"other"` matches neither struct nor list arm; the error arm bottoms → the disjunction is
-- bottom. `exportJsonBottoms` positively witnesses it.
theorem disj_embed_one_layer_real_conflict_bottoms :
    exportJsonBottoms
        "#M: {\n\t#k: string\n\tshape: string\n\t{shape: \"struct\", val: #k} | {shape: \"list\", items: [#k]} | error(\"no shape\")\n\t...\n}\n#U: {#M}\nout: #U & {#k: \"w\", shape: \"other\"}\n"
          = true := by
  native_decide

-- shapeD end-to-end (Gap-2 + the buried let + comprehension): the struct arm is selected AND the
-- matched `#patch` (`meta:"yes"`) surfaces through the let chain behind the force tier.
theorem disj_embed_force_narrow_emits_patch :
    exportJsonMatches
        "#MixinD: Self={\n\t#additions: [string]: {#kind: string, #patch: _}\n\tkind: string\n\tshape: string\n\tlet _patch = {\n\t\tfor _, add in Self.#additions {\n\t\t\tif kind == add.#kind {add.#patch}\n\t\t}\n\t}\n\tlet listShape = {shape: \"list\", items: [_patch]}\n\tlet structShape = {shape: \"struct\", _patch}\n\tstructShape | listShape | error(\"no shape\")\n\t...\n}\n#UseD: {\n\t#MixinD\n\t#additions: cert_ls: {#kind: \"ListenerSet\", #patch: {meta: \"yes\"}}\n}\nout: #UseD & {kind: \"ListenerSet\", shape: \"struct\"}\n"
        "{\n    \"out\": {\n        \"kind\": \"ListenerSet\",\n        \"shape\": \"struct\",\n        \"meta\": \"yes\"\n    }\n}\n"
          = true := by
  native_decide

-- Gap-2b (Bug2-3): a STRUCTURAL disjunction (`listShape | structShape`, discriminated by
-- list-vs-struct SHAPE not a regular label) embedded one layer down (`#U: {#M}`) and narrowed by
-- a sibling regular OUTPUT field only the struct arm can carry (`meta`). The list arm CANNOT carry
-- `meta` (a list & a struct-with-a-regular-field = ⊥), so the sound meet prunes it; the struct arm
-- survives. The list arm is list-shaped (`#components` keyed map + `[...]` embedded list).
theorem disj_embed_struct_disc_prunes_list_arm :
    exportJsonMatches
        "#M: {\n\tlet listShape = {#components: [string]: {x: int}, [...]}\n\tlet structShape = {meta: string, ...}\n\tlistShape | structShape\n\t...\n}\n#U: {#M}\nout: #U & {meta: \"yes\", extra: \"ok\"}\n"
        "{\n    \"out\": {\n        \"meta\": \"yes\",\n        \"extra\": \"ok\"\n    }\n}\n"
          = true := by
  native_decide

-- Gap-2b UNCHANGED: DIRECT narrowing of the same structural disjunction (no embedding layer) also
-- selects the struct arm — the prune is the meet primitive, identical with or without the layer.
theorem disj_embed_struct_disc_direct_prunes :
    exportJsonMatches
        "#M: {\n\tlet listShape = {#components: [string]: {x: int}, [...]}\n\tlet structShape = {meta: string, ...}\n\tlistShape | structShape\n\t...\n}\nout: (#M) & {meta: \"direct\"}\n"
        "{\n    \"out\": {\n        \"meta\": \"direct\"\n    }\n}\n"
          = true := by
  native_decide

-- Gap-2b SOUNDNESS (real conflict bottoms): a host that matches NEITHER structural arm (a list
-- item type conflict AND a struct field conflict) kills both arms → bottom. `exportJsonBottoms`
-- positively witnesses it (a fallback regular disjunct keeps the parse valid).
theorem disj_embed_struct_disc_real_conflict_bottoms :
    exportJsonBottoms
        "#M: {\n\tlet listShape = {#components: [string]: {x: int}, [...]}\n\tlet structShape = {meta: string, ...}\n\tlistShape | structShape\n\t...\n}\n#U: {#M}\nout: #U & {#components: notallowed: {x: \"nope\"}, meta: 5}\n"
          = true := by
  native_decide

-- Gap-2b SOUNDNESS (no over-prune of two STRUCT-compatible arms): a `struct | struct` disjunction
-- narrowed by a field both arms admit stays AMBIGUOUS (neither arm is list-shaped, so no
-- `list & struct = ⊥` prune fires) — the meet primitive, not a shape heuristic, decides. cue keeps
-- it `incomplete`; Kue keeps it ambiguous (the SC-3/A display divergence). It does NOT collapse to
-- one arm, witnessed by the export failing rather than producing a single concrete value.
theorem disj_embed_struct_disc_struct_struct_stays_ambiguous :
    exportJsonBottoms
        "#M: {\n\tlet a = {x: int, ...}\n\tlet b = {y: int, ...}\n\ta | b\n}\n#U: {#M}\nout: #U & {z: 1}\n"
          = true := by
  native_decide

-- Gap-2b GATE: `embedBodyEmbedsDisj` is the cert-manager byte-identity guard — it returns `false`
-- for a body with NO disjunction embedding in `cs` (a plain embedding ref), so the all-regular
-- splice never fires there and the narrow comprehension-read splice is preserved (byte-identical).
theorem embed_body_embeds_disj_gate_no_disj :
    embedBodyEmbedsDisj
      (.structComp [⟨"shape", .regular, .kind .string⟩] [.refId ⟨1, 0⟩] .regularOpen)
      = false := by
  native_decide

-- Gap-2b GATE (positive): a direct `.disj` embedding in `cs` trips the gate, so the host's regular
-- output fields are routed into the arms for the sound meet-prune.
theorem embed_body_embeds_disj_gate_direct_disj :
    embedBodyEmbedsDisj
      (.structComp []
        [.disj [(.regular, .refId ⟨0, 0⟩), (.regular, .refId ⟨0, 1⟩)]]
        .regularOpen)
      = true := by
  native_decide

-- MEET-RESID-1 + D#1d-RESIDUAL: a HELD `.structComp` residual (a comprehension whose dynamic
    -- key/`if`/`for` is non-concrete) is HELD by the comprehension-body lift (D#1d-RESIDUAL) and
    -- SURVIVES a `meet`/`&` against a struct (MEET-RESID-1), instead of being dropped to `{}` or
    -- bottomed. The soundness tripwires (conflict-MUST-still-bottom) are pinned ADVERSARIALLY — the
    -- gate's whole purpose is that over-holding (deferring a real conflict) never happens. All
    -- source-level (full parse→eval→meet→format), oracle-cross-checked vs cue v0.16.1.

-- D#1d-RESIDUAL: a comprehension BODY that is itself a held residual (abstract dynamic key) is
-- HELD, not dropped to `{}`. cue holds the block under eval (the `@d.i` label is the D#1b display
-- limit). HEAD dropped this to `a: {}`.
theorem residual_comprehension_body_held :
    evalSourceMatches
      "a: {for k in [string] {(k): 1}}\n"
      "a: {for k in [string] {(@1.0): 1}}" = true := by
  native_decide

-- MEET-RESID-1 WITNESS: the held residual SURVIVES `a & {x:2}` (re-resolved by the two-pass
-- `.conj` fold), carrying the merged `x:2` plus the still-deferred `for`. HEAD bottomed `b`.
theorem residual_survives_meet_with_struct :
    evalSourceMatches
      "a: {for k in [string] {(k): 1}}\nb: a & {x: 2}\n"
      "a: {for k in [string] {(@1.0): 1}}\nb: {x: 2, for k in [string] {(@1.0): 1}}" = true := by
  native_decide

-- ★ SOUNDNESS TRIPWIRE 1 — a real FIELD CONFLICT inside the residual STILL bottoms (`x:1 & x:2`).
-- The merged field surfaces `x: _|_` (the kue rendering convention, identical to a plain
-- `{x:1} & {x:2}` control); the defer NEVER masks it. cue: `b.x: conflicting values 1 and 2`.
theorem residual_meet_field_conflict_bottoms :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\nb: a & {x: 2}\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nb: {x: _|_, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- ★ SOUNDNESS TRIPWIRE 2 — a residual met with a SCALAR is a struct-vs-nonstruct type error and
-- MUST bottom wholesale (NOT hold). cue: `mismatched types int and struct`.
theorem residual_meet_scalar_bottoms :
    evalSourceMatches
      "a: {for k in [string] {(k): 1}}\nb: a & 5\n"
      "a: {for k in [string] {(@1.0): 1}}\nb: _|_" = true := by
  native_decide

-- ★ SOUNDNESS TRIPWIRE 3 — the field-conflict residual export ERRORS (no concrete value escapes);
-- pins that the inline `x: _|_` is a genuine bottom, not a spurious survivable value.
theorem residual_meet_field_conflict_export_bottoms :
    exportJsonBottoms "a: {x: 1, for k in [string] {(k): 1}}\nb: a & {x: 2}\n" = true := by
  native_decide

-- A COMPATIBLE field merges and the comp is still held (no spurious conflict on equal values).
theorem residual_meet_compatible_field_held :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\nb: a & {x: 1, y: 2}\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nb: {x: 1, y: 2, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- A concrete-key comprehension still RESOLVES (no over-hold): the residual lift fires ONLY on a
-- genuinely-undecidable body, never freezing a resolvable one.
theorem concrete_key_comprehension_still_resolves :
    evalSourceMatches
      "a: {for k in [\"k\"] {(k): 1}}\nb: a & {x: 2}\n"
      "a: {k: 1}\nb: {k: 1, x: 2}" = true := by
  native_decide

-- ### MEET-RESID-1 audit — MASKED-BOTTOM regression guard (Phase-A `RESID-MASK-1`).
--
-- The MEET-RESID-1 soundness argument claimed "a `.structComp` never holds a conflict
-- (unrepresentable)". That is FALSE: `mergeFieldValueWith` stores a field conflict as a PRESENT
-- `.bottomWith` field VALUE (not a top-level `.bottom`), and MEET-RESID-1 / the eager
-- `withDeferredComprehensions` re-wrap such a struct as `.structComp [x:_|_] …` (see Tripwire 1
-- above, which pins exactly that inline `x: _|_`). The real invariant is weaker: a held conflict is
-- fine PROVIDED every bottom-consumer surfaces it. `containsBottom` (the `liveAlternatives`
-- disjunction-prune predicate) did NOT descend `.structComp` — so a residual-with-inner-conflict
-- surviving as a disjunction ARM was not pruned, and a DEAD arm survived → a wrong value (a spurious
-- unresolved `.disj`, or a stuck selector, where cue resolves to the live arm). Fixed by descending
-- `.structComp`'s RESOLVED fields in `containsBottom`. These pins are the destroy-test witnesses;
-- each is oracle-cross-checked vs cue v0.16.1 (cue prunes the dead arm).

-- ★ HEADLINE (the masked bottom): a residual-meet conflict as the NON-default arm of a default
-- disjunction. cue prunes the dead arm → `pick: {y:9}`. Pre-fix kue HELD the dead arm
-- (`*{y:9} | {x:_|_, for…}`) — `containsBottom` was blind to the `.structComp`-wrapped `x:_|_`.
theorem resid_mask_disj_default_prunes_dead_residual_arm :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\npick: *{y: 9} | (a & {x: 2})\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\npick: {y: 9}" = true := by
  native_decide

-- (NOTE — RESID-MASK-2, the eager-prune-vs-hold POLICY that this masking fix exposed, was
-- RESOLVED 2026-06-21 as a cue-spec-gap, not a divergence: see the "RESID-MASK-2" section at
-- the end of this file. The earlier framing here — "a NON-default residual-conflict arm survives
-- as a spurious arm" — was FALSIFIED on current HEAD: kue EAGERLY prunes the definitely-bottom
-- arm and commits to the (possibly still-incomplete) survivor, which is the MORE precise lattice
-- move and spec-consonant with "eliminate bottom alternatives". The soundness of that eager prune
-- — it fires only on a *materialized/terminal* bottom, never on a merely-incomplete arm — is
-- pinned adversarially in that section. The plain-arm control below shows the prune primitive
-- itself is correct.)

-- CONTROL (no residual): the SAME disjunction shape with a plain `{x:1}&{x:2}` dead arm was ALWAYS
-- pruned correctly (a plain `.struct` arm — `containsBottom` saw its `x:_|_`). Pins that the bug
-- was SOLELY the `.structComp` wrapper hiding the inner bottom, and the fix matches this baseline.
theorem resid_mask_control_plain_conflict_arm_pruned :
    evalSourceMatches
      "pick: *{y: 9} | ({x: 1} & {x: 2})\n"
      "pick: {y: 9}" = true := by
  native_decide

-- EVAL CONSTRUCT-SITE (not via meet): `withDeferredComprehensions` itself builds a residual with an
-- inner conflict (`x:1, x:2` static + a held `for`). As a disj arm it must ALSO be pruned — the
-- hole was never meet-specific. cue prunes → `pick: {y:9}`.
theorem resid_mask_eval_site_residual_arm_pruned :
    evalSourceMatches
      "a: {x: 1, x: 2, for k in [string] {(k): 1}}\npick: *{y: 9} | a\n"
      "a: {x: _|_, for k in [string] {(@1.0): 1}}\npick: {y: 9}" = true := by
  native_decide

-- RESIDUAL & RESIDUAL: two held comprehensions whose static fields conflict, as a disj arm — the
-- union-of-comps residual `{x:_|_, for…, for…}` is still pruned. cue → `pick: {y:9}`.
theorem resid_mask_residual_meet_residual_arm_pruned :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\nb: {x: 2, for j in [string] {(j): 2}}\npick: *{y: 9} | (a & b)\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nb: {x: 2, for j in [string] {(@1.0): 2}}\npick: {y: 9}"
        = true := by
  native_decide

-- DEEP/NESTED conflict inside the residual (A#6 depth × residual boundary): the conflict is one
-- level down (`p: {q: _|_}`). `containsBottom` descends the residual fields, then recurses the inner
-- `.struct` to the nested bottom. cue prunes → `pick: {y:9}`.
theorem resid_mask_nested_conflict_in_residual_arm_pruned :
    evalSourceMatches
      "a: {p: {q: 1}, for k in [string] {(k): 1}}\npick: *{y: 9} | (a & {p: {q: 2}})\n"
      "a: {p: {q: 1}, for k in [string] {(@1.0): 1}}\npick: {y: 9}" = true := by
  native_decide

-- NO OVER-PRUNE (the converse guard): a CONFLICT-FREE residual as the non-default arm must SURVIVE
-- (it is a genuinely-held value, not a dead arm). The fix descends only into the resolved fields, so
-- a residual whose fields carry no bottom stays live and the disjunction remains a real 2-arm value.
-- cue keeps both arms ambiguous here; `exportJsonBottoms` witnesses kue does NOT collapse to one.
theorem resid_mask_no_over_prune_clean_residual_survives :
    exportJsonBottoms
      "a: {for k in [string] {(k): 1}}\npick: {y: 9} | a\n" = true := by
  native_decide


-- ### RESID-MASK-2 — eager-prune-of-definitely-bottom-arm POLICY (resolved as a cue-spec-gap).
--
-- The RESID-MASK-1 fix (`containsBottom` descends `.structComp` resolved fields) made
-- `liveAlternatives` prune a disjunction arm whose held residual carries a TERMINAL inline conflict
-- — EVEN WHEN the surviving arm is itself still incomplete. cue is conservative here: it HOLDS the
-- whole disjunction unresolved until a survivor concretizes (`export` → `N errors in empty
-- disjunction`). kue is strictly MORE precise.
--
-- SOUNDNESS (verified adversarially, 2026-06-21): the prune fires ONLY on a *definitely/terminal*
-- bottom — a `.bottom`/`.bottomWith` node that has already MATERIALIZED from a concrete conflict
-- (`x:1 & x:2`, concrete-vs-bound `x:1 & x:>5`, disjoint-bound `x:>5 & x:<3`) and can never
-- un-bottom under later refinement. It NEVER fires on a merely-incomplete arm (one bottom NOW only
-- because an abstract operand has not resolved): such an arm carries no bottom node, so
-- `containsBottom` is false and the arm survives. The two are not the same, and the don't-prune
-- cases below pin the distinction — an unsoundness would be pruning an arm that a later resolution
-- could make viable, and the adversarial pins demonstrate kue does NOT.
--
-- SPEC BASIS: the CUE spec's disjunction rule mandates *"eliminate bottom alternatives"* and treats
-- `_|_` as the identity for `|`; eager elimination of a definitely-bottom arm is therefore spec-
-- consonant and the precise/total lattice move. The spec does NOT pin the *timing* (it also says
-- "evaluation can retain unresolved disjunctions"), so cue's hold is not a violation — only less
-- precise. Recorded in `docs/reference/cue-spec-gaps.md` (kue MORE precise; not a divergence).
-- These pins LOCK kue's eager-prune so it cannot regress to cue's hold.

-- ★ WITNESS (the spec-gap behavior PINNED): BOTH arms residual; arm 1 is a TERMINAL `x:1 & x:2`
-- conflict (the held `for` dyn-field can only add string-keyed fields, never touch static `x`, so
-- the conflict is terminal). kue prunes arm 1 and commits to the still-incomplete survivor arm 2.
-- cue HOLDS both (`export` → `2 errors in empty disjunction`). kue MORE precise; locked here.
theorem resid_mask2_witness_eager_prune_commits_to_incomplete_survivor :
    evalSourceMatches
      "a: {for k in [string] {(k): 1}, x: 1}\nout: (a & {x: 2}) | (a & {x: 1, ok: true})\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nout: {x: 1, ok: true, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- ★ SOUNDNESS — DON'T-PRUNE-INCOMPLETE (the adversarial core). arm 1's `a.x` is abstract `int`, so
-- `a & {x:2}` is `{x:2,for…}` — NOT a bottom (no materialized conflict). kue must NOT prune it: it
-- could become viable. Both arms SURVIVE as a real 2-arm disjunction. A regression that pruned on
-- "currently-incomplete-and-not-yet-concrete" rather than "definitely-bottom" would drop arm 1.
theorem resid_mask2_sound_abstract_operand_arm_not_pruned :
    evalSourceMatches
      "a: {x: int, for k in [string] {(k): 1}}\nout: (a & {x: 2}) | (a & {x: 3, ok: true})\n"
      "a: {x: int, for k in [string] {(@1.0): 1}}\nout: {x: 2, for k in [string] {(@1.0): 1}} | {x: 3, ok: true, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- SOUNDNESS — the could-become-viable arm WINS after narrowing. The same disjunction, then met
-- with `{x:2}`: arm 1 (`x:2`, viable) survives, arm 2 (`x:3 & x:2` = `_|_`) dies. kue commits to
-- arm 1 — the genuinely-correct survivor. Proves the abstract arm 1 was NOT prematurely pruned and
-- that the eager evaluation reaches the right lattice point (the value a later meet selects).
theorem resid_mask2_sound_incomplete_arm_resolves_correctly_after_narrowing :
    evalSourceMatches
      "a: {x: int, for k in [string] {(k): 1}}\nout: ((a & {x: 2}) | (a & {x: 3, ok: true})) & {x: 2}\n"
      "a: {x: int, for k in [string] {(@1.0): 1}}\nout: {x: 2, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- SOUNDNESS — both arms incomplete, NO conflict (differ only in non-conflicting `y`/`z`). Neither
-- arm is bottom, so the held `for` comprehension is NOT frozen into a bottom and pruned: both
-- survive. Pins that incompleteness alone never triggers a prune (no over-prune on residuals).
theorem resid_mask2_sound_both_incomplete_no_conflict_both_survive :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\nout: (a & {y: 2}) | (a & {z: 3})\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nout: {x: 1, y: 2, for k in [string] {(@1.0): 1}} | {x: 1, z: 3, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- SOUNDNESS — bound-narrowing convergence (no residual): `({x:>5} | {x:<0,ok}) & {x:7}`. arm 1
-- (`>5 & 7` = 7, viable) wins; arm 2 (`<0 & 7` = `_|_`) is pruned. cue AGREES exactly (`{x:7}`).
-- The `>5` arm was NOT prematurely pruned while abstract — pinned that the prune waits for a
-- materialized bottom and that kue and cue converge on this concrete-narrowing shape.
theorem resid_mask2_sound_bound_arm_survives_until_concrete_conflict :
    evalSourceMatches
      "out: ({x: >5} | {x: <0, ok: true}) & {x: 7}\n"
      "out: {x: 7}" = true := by
  native_decide

-- PRECISION — terminal-conflict residual arm | concrete-COMPLETE arm. kue prunes the dead residual
-- and yields the clean concrete survivor `{plain:5}`; cue ERRORS entirely (`key value of dynamic
-- field must be concrete`) — it never prunes the dead arm. The starkest spec-gap witness: kue
-- exports a value where cue fails. Locks the eager prune against regression to cue's hold.
theorem resid_mask2_precision_terminal_residual_arm_pruned_for_concrete_survivor :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\nout: (a & {x: 2}) | {plain: 5}\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nout: {plain: 5}" = true := by
  native_decide

-- REGRESSION — `_|_`-identity for `|`: `_|_ | X` collapses to X for concrete X (the spec rule the
-- eager prune rests on). A bare bottom arm and a terminal-conflict arm both shed cleanly.
theorem resid_mask2_bottom_identity_collapses_to_concrete_arm :
    exportJsonMatches
      "out: (_|_) | {a: 1, b: 2}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

theorem resid_mask2_terminal_conflict_arm_sheds_for_concrete_survivor :
    exportJsonMatches
      "out: ({x: 1} & {x: 2}) | {ok: true}\n"
      "{\n    \"out\": {\n        \"ok\": true\n    }\n}\n" = true := by
  native_decide

-- ### Bug2-6 — definition multi-declaration close-once (RESOLVED).
--
-- Two SEPARATE declarations of one definition path (`#Foo: {a:1}` + `#Foo: {c:3}`) UNIFY their field
-- SETS and close ONCE over the union (the same union-not-intersect rule as embedding closedness) →
-- cue v0.16.1 gives `{a:1, c:3}`. Kue formerly closed each decl's body SEPARATELY (`defClosed` at
-- load) and conjoined them (`canonicalizeFields` → `.conj [defClosed{a}, defClosed{c}]`), so the meet
-- MUTUALLY REJECTED → `{a:_|_, c:_|_}` (export bottomed). FIXED by `mergeDefinitionDecls`: when
-- `canonicalizeFields`/`mergeConjFields` merge two same-label DEFINITION-class decls, the bodies are
-- UNIONED into ONE def body (close-once via the existing single-`closedClauses`-clause path), NOT a
-- `.conj`. The `#A & #B` use-site-meet path is structurally untouched (a `meet` of two already-closed
-- structs CONCATENATES clauses → conjunction → reject), so distinct closed defs STILL reject — the
-- soundness guards below pin that.

-- TARGET (was the WITNESS of the wrong bottom; FLIPPED): same-def multi-decl close-once → {a:1,c:3}.
theorem bug26_same_def_multi_decl_close_once :
    exportJsonMatches "#Foo: {a: 1}\n#Foo: {c: 3}\nout: #Foo\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- 3-decl argocd shape: three same-def hidden/def decls unify their label-sets, close once.
theorem bug26_three_decl_close_once :
    exportJsonMatches "#Foo: {a: 1}\n#Foo: {b: 2}\n#Foo: {c: 3}\nout: #Foo\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- Nested same-def multi-decl close-once (def inside a regular field).
theorem bug26_nested_same_def_close_once :
    exportJsonMatches "out: {#m: {a: 1}, #m: {c: 3}, x: #m}\n"
      "{\n    \"out\": {\n        \"x\": {\n            \"a\": 1,\n            \"c\": 3\n        }\n    }\n}\n" = true := by
  native_decide

-- The merged def is CLOSED ONCE over the union: a use-site extra (in NEITHER decl) is rejected.
theorem bug26_merged_def_closes_once_rejects_extra :
    exportJsonBottoms "#Foo: {a: 1}\n#Foo: {c: 3}\nout: #Foo & {extra: 9}\n" = true := by
  native_decide

-- The merged def admits a use-site field that IS in the union (close-once, not over-closed).
theorem bug26_merged_def_admits_union_field :
    exportJsonMatches "#Foo: {a: 1}\n#Foo: {c: 3}\nout: #Foo & {a: 1}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- CONFLICT EDGE: same-def decls with conflicting VALUES on a SHARED label still bottom — close-once
-- unions LABELS, the values still `meet` (cue: `conflicting values 2 and 1`). Must NOT be papered over.
theorem bug26_same_def_conflict_still_bottoms :
    exportJsonBottoms "#Foo: {a: 1}\n#Foo: {a: 2}\nout: #Foo\n" = true := by
  native_decide

-- OPEN-VIA-`...` EDGE: if ANY decl is open via `...`, the union is OPEN (admits a use-site extra) —
-- openness UNIONS for same-def decls (open dominates), opposite to use-site meet (closed dominates).
theorem bug26_same_def_one_open_via_tail_admits_extra :
    exportJsonMatches "#Foo: {a: 1, ...}\n#Foo: {c: 3}\nout: #Foo & {extra: 9}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3,\n        \"extra\": 9\n    }\n}\n" = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): two DISTINCT closed defs reject. A "union closed sets on meet"
-- fix that admitted this would be UNSOUND. cue: `field not allowed`. The fix keeps this REJECTING
-- because the use-site `meet` CONCATENATES clauses (conjunction) — never routes through the decl union.
theorem bug26_distinct_closed_defs_still_reject :
    exportJsonBottoms "#A: {a: 1}\n#B: {c: 3}\nout: #A & #B\n" = true := by
  native_decide

-- SOUNDNESS GUARD variant: distinct defs where A declares an EXTRA field B does not — the meet must
-- reject the extra (cue: `field not allowed`), NOT union it in.
theorem bug26_distinct_closed_defs_reject_extra :
    exportJsonBottoms "#A: {a: 1, b: 2}\n#B: {a: 1}\nout: #A & #B\n" = true := by
  native_decide

-- SOUNDNESS GUARD variant: distinct defs with a CONFLICTING shared field still bottom on the conflict
-- (cue: `conflicting values 2 and 1`) — the meet is a genuine conjunction, not a close-once union.
theorem bug26_distinct_closed_defs_conflict_bottoms :
    exportJsonBottoms "#A: {a: 1}\n#B: {a: 2}\nout: #A & #B\n" = true := by
  native_decide

-- SOUNDNESS GUARD positive: distinct defs with the SAME single field admit (both closed sets agree).
theorem bug26_distinct_closed_defs_same_field_admits :
    exportJsonMatches "#A: {a: 1}\n#B: {a: 1}\nout: #A & #B\n"
      "{\n    \"out\": {\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- CLOSED-PATTERN multi-decl (the cert-manager `#data: [string]: string` class — the canary the fix
-- must not re-open): a `[string]: string` pattern decl unioned with a concrete decl keeps the PATTERN
-- as a value-constraint, NOT a re-opened tail. A string-typed use-site field is admitted by the
-- pattern (cue: `{extra:"ok", known:"x"}`); the union closes-once, the pattern stays a typecheck.
theorem bug26_closed_pattern_multi_decl_admits_string :
    exportJsonMatches "#data: {[string]: string}\n#data: {known: \"x\"}\nout: #data & {extra: \"ok\"}\n"
      "{\n    \"out\": {\n        \"known\": \"x\",\n        \"extra\": \"ok\"\n    }\n}\n" = true := by
  native_decide

-- CLOSED-PATTERN multi-decl BOUNDARY: the unioned pattern still TYPECHECKS — an INT use-site field
-- bottoms against `[string]: string` (cue: `conflicting values 5 and string`). The close-once union
-- does not weaken the pattern to a bare-`...` open tail (a naive union re-open would admit `n: 5`).
theorem bug26_closed_pattern_multi_decl_rejects_int :
    exportJsonBottoms "#data: {[string]: string}\n#data: {a: \"x\"}\nout: #data & {n: 5}\n" = true := by
  native_decide

-- 4-DECL close-once: four same-def decls union `{a,b,c,d}` and close ONCE — a use-site `extra` (in no
-- decl) is rejected (cue: `field not allowed`). Pins that the fold over decls scales past the 3-decl
-- argocd shape without leaking openness.
theorem bug26_four_decl_close_once_rejects_extra :
    exportJsonBottoms "#Foo: {a: 1}\n#Foo: {b: 2}\n#Foo: {c: 3}\n#Foo: {d: 4}\nout: #Foo & {extra: 9}\n" = true := by
  native_decide

-- 4-DECL with a CONFLICT in one decl: the union still `meet`s shared labels, so a conflicting `a`
-- (1 vs 99) bottoms while `b`/`d` survive (cue: `conflicting values 99 and 1`). Close-once over more
-- decls does not paper over a real conflict.
theorem bug26_four_decl_conflict_bottoms :
    exportJsonBottoms "#Foo: {a: 1}\n#Foo: {b: 2}\n#Foo: {a: 99}\n#Foo: {d: 4}\nout: #Foo\n" = true := by
  native_decide

-- ### Bug2-7 — same-def multi-decl close-once on the def-REFERENCE / force-fold path (RESOLVED).
--
-- Bug2-6's close-once is correct on DIRECT selection (`out: #Foo`) — the direct-eval `.struct` arm
-- `canonicalizeFields`-es the body and unions the same-label def decls into ONE close-once body. But it
-- was LOST when the merged def lives inside a DEFINITION wrapper that is selected/referenced through a
-- sibling (`#Use: {#additions:…; #additions:…; vis: #additions}` then `#Use.vis`): the def wrapper
-- defers to a `.closure` and the force-fold reconstruction (`forceClosureWithConjunctCore`) rebuilds
-- the body via `mergeConjOperands`, which ran `mergeConjFields` (plain `joinUnevaluated`/`.conj`) over
-- each operand's fields BEFORE the downstream `canonicalizeFields` could union them — so the two
-- `#additions` decls were `.conj`-collapsed and re-closed SEPARATELY, each clause rejecting the other's
-- fields → `{cert_gw:_|_, cert_ing:_|_}`.
--
-- FIXED by canonicalizing each operand's OWN fields up-front in `mergeConjOperands` (Bug2-7): a repeated
-- DEFINITION-class decl declared WITHIN one struct body (one operand) UNIONS via `mergeDefinitionDecls`
-- (Bug2-6 close-once), while the CROSS-operand merge stays plain `.conj`. That within-operand vs
-- cross-operand split IS the soundness boundary: a host's `#data` meeting an EMBED's `#data` (distinct
-- operands) still `.conj`-MEETs — never unions — so the cert-manager closed pattern def is not re-opened
-- and `#A & #B` (distinct closed defs, distinct operands) still rejects.

-- TARGET (was the WITNESS of the wrong bottom; FLIPPED): same-def multi-decl close-once survives a
-- def-REFERENCE through a sibling. cue v0.16.1: `{cert_gw:{}, cert_ing:{}}` (the `#kind` hidden field
-- does not export). Pre-fix kue bottomed (`{cert_gw:_|_, cert_ing:_|_}`).
theorem bug27_multi_decl_def_ref_close_once :
    exportJsonMatches
      "#Use: {\n\t#additions: cert_gw: {#kind: \"Gateway\"}\n\t#additions: cert_ing: {#kind: \"Ingress\"}\n\tvis: #additions\n}\nout: #Use.vis\n"
      "{\n    \"out\": {\n        \"cert_gw\": {},\n        \"cert_ing\": {}\n    }\n}\n" = true := by
  native_decide

-- 3-decl referenced through a sibling (the argocd `#additions` triple-decl shape).
theorem bug27_three_decl_def_ref_close_once :
    exportJsonMatches
      "#Use: {\n\t#additions: a: {x: 1}\n\t#additions: b: {y: 2}\n\t#additions: c: {z: 3}\n\tvis: #additions\n}\nout: #Use.vis\n"
      "{\n    \"out\": {\n        \"a\": {\n            \"x\": 1\n        },\n        \"b\": {\n            \"y\": 2\n        },\n        \"c\": {\n            \"z\": 3\n        }\n    }\n}\n" = true := by
  native_decide

-- REFERENCE and DIRECT-select are BOTH correct off the same def wrapper.
theorem bug27_def_ref_and_direct_select_both_close_once :
    exportJsonMatches
      "#Use: {\n\t#additions: a: {x: 1}\n\t#additions: b: {y: 2}\n\tvis: #additions\n}\nviaRef: #Use.vis\nviaDirect: #Use.#additions\n"
      "{\n    \"viaRef\": {\n        \"a\": {\n            \"x\": 1\n        },\n        \"b\": {\n            \"y\": 2\n        }\n    },\n    \"viaDirect\": {\n        \"a\": {\n            \"x\": 1\n        },\n        \"b\": {\n            \"y\": 2\n        }\n    }\n}\n" = true := by
  native_decide

-- NESTED reference: a multi-decl def referenced through a sibling INSIDE a def, the whole then
-- selected one level further out. The force-fold path is exercised at two nesting levels.
theorem bug27_nested_def_ref_close_once :
    exportJsonMatches
      "#Outer: {\n\t#Inner: {\n\t\t#m: {a: 1}\n\t\t#m: {c: 3}\n\t\tvis: #m\n\t}\n\tout: #Inner.vis\n}\nresult: #Outer.out\n"
      "{\n    \"result\": {\n        \"a\": 1,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- DEF-REF AFTER MEET: the close-once union still ADMITS a use-site field that IS in the union when
-- the referenced def is further `meet`-ed (cue: `{a:1, c:3}`).
theorem bug27_def_ref_after_meet_admits_union_field :
    exportJsonMatches
      "#Use: {\n\t#m: {a: 1}\n\t#m: {c: 3}\n\tvis: #m\n}\nout: #Use.vis & {a: 1}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): two DISTINCT closed defs `#A & #B` referenced through a sibling
-- STILL reject — distinct operands, so the cross-operand `.conj` (NOT the within-operand union) fires.
-- A fix that unioned indiscriminately would WRONGLY admit this. cue: `field not allowed`.
theorem bug27_distinct_closed_defs_via_ref_still_reject :
    exportJsonBottoms
      "#A: {a: 1}\n#B: {c: 3}\n#Use: {\n\tval: #A & #B\n}\nout: #Use.val\n" = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): same-def CONFLICT on a shared label referenced through a sibling
-- STILL bottoms — close-once unions LABELS, the shared label's VALUES still `meet`
-- (cue: `conflicting values 2 and 1`). Close-once does not paper over a real conflict.
theorem bug27_same_def_conflict_via_ref_still_bottoms :
    exportJsonBottoms
      "#Use: {\n\t#m: {a: 1}\n\t#m: {a: 2}\n\tvis: #m\n}\nout: #Use.vis\n" = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): the merged def is CLOSED ONCE over the union — a use-site extra
-- (in NEITHER decl), introduced via the reference, is rejected (cue: `field not allowed`).
theorem bug27_def_ref_close_once_rejects_use_site_extra :
    exportJsonBottoms
      "#Use: {\n\t#m: {a: 1}\n\t#m: {c: 3}\n\tvis: #m & {extra: 9}\n}\nout: #Use.vis\n" = true := by
  native_decide

-- OPEN-DOMINATES on the REFERENCE / force-fold path: if ANY within-operand decl is open via `...`, the
-- close-once union is OPEN even when reached through a sibling reference — a use-site `extra` is
-- admitted (cue: `{a:1, c:3, extra:9}`). The Bug2-6 `unionDefOpenness` (open dominates) carries
-- through the per-operand `canonicalizeFields`, not just the direct-eval arm.
theorem bug27_open_via_tail_admits_extra_via_ref :
    exportJsonMatches
      "#Use: {\n\t#m: {a: 1, ...}\n\t#m: {c: 3}\n\tvis: #m & {extra: 9}\n}\nout: #Use.vis\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3,\n        \"extra\": 9\n    }\n}\n" = true := by
  native_decide

-- CLOSED-PATTERN multi-decl on the REFERENCE path (cert-manager class through a sibling): the unioned
-- `[string]: string` pattern still TYPECHECKS via the force-fold reconstruction — an INT use-site field
-- bottoms (cue: `conflicting values 5 and string`). The per-operand canonicalize does not weaken the
-- closed pattern to an open tail when reached through a reference.
theorem bug27_closed_pattern_multi_decl_rejects_int_via_ref :
    exportJsonBottoms
      "#Use: {\n\t#data: {[string]: string}\n\t#data: {known: \"x\"}\n\tvis: #data & {n: 5}\n}\nout: #Use.vis\n" = true := by
  native_decide

-- ### Bug2-8 — same-def multi-decl close-once ACROSS AN EMBED boundary (RESOLVED).
--
-- Bug2-7 unions same-def decls declared WITHIN one struct body (one operand). Bug2-8 is when a def
-- declares `#m` once and EMBEDS another def that also declares `#m` (`#A: {#m:{a}}` then `#Use: {#A;
-- #m:{c}; vis:#m}`): the two `#m` decls are repeated declarations of the ONE def path `#m` spanning the
-- embed boundary, which cue close-once-UNIONS (`{a:1, c:3}`). kue formerly `.conj`-meet them across the
-- embed → each clause re-closes separately → mutual reject → bottom.
--
-- The fix carries def-path PROVENANCE through the embed merge (a SUM `DeclProvenance` =
-- `ownDecl`/`embeddedDecl`, on a named `ConjOperand`). A PLAIN embedding's same-def-path decls
-- (`embedSameDefPathDecls`, gated to labels the host ALSO declares as definitions) are folded into the
-- static frame as an `embeddedDecl` operand, so `mergeConjOperands` close-once-UNIONS the host `ownDecl
-- #m` × embed `embeddedDecl #m` pair (the Bug2-6 lever) AND a sibling `vis: #m` resolves against the
-- union; the embed meet-fold then unions the same `#m` idempotently (`meetEmbedUnioningDefDecls`). The
-- union fires ONLY for same-def-PATH DEFINITION-class decls of a PLAIN embed — a regular field, a
-- deferral/disjunction-bearing embed, and a cross-conjunct value-meet (the cert-manager `data: [string]:
-- string` REGULAR closed pattern) all stay MEET.

-- TARGET (was the WITNESS of the wrong bottom; FLIPPED): host declares `#m` once and EMBEDS `#A` which
-- also declares `#m` — the two decls of the ONE def path `#m` close-once-UNION across the embed. cue
-- v0.16.1: `{a:1, c:3}`. Pre-fix kue bottomed. BOTH whole-file (the hidden `#m`) and the `-e out`
-- projection (`#Use.vis`) must be the union.
theorem bug28_embed_cross_decl_close_once_unions :
    exportJsonMatches
      "#A: {#m: {a: 1}}\n#Use: {\n\t#A\n\t#m: {c: 3}\n\tvis: #m\n}\nout: #Use.vis\n"
      "{\n    \"out\": {\n        \"c\": 3,\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- 3-decl across the embed (the argocd `#additions` shape): host declares `#additions` once and EMBEDS
-- TWO defs each declaring `#additions` — all THREE decls of the ONE path union, close once. cue:
-- `{cert_gw, cert_ing, cert_ls}`.
theorem bug28_three_decl_host_plus_two_embeds_union :
    exportJsonMatches
      "#A1: {#additions: {cert_gw: {x: 1}}}\n#A2: {#additions: {cert_ls: {z: 3}}}\n#Use: {\n\t#A1\n\t#A2\n\t#additions: {cert_ing: {y: 2}}\n\tvis: #additions\n}\nout: #Use.vis\n"
      "{\n    \"out\": {\n        \"cert_ing\": {\n            \"y\": 2\n        },\n        \"cert_gw\": {\n            \"x\": 1\n        },\n        \"cert_ls\": {\n            \"z\": 3\n        }\n    }\n}\n" = true := by
  native_decide

-- TWO mixins each declaring the SAME `#m` path, plus the host's own `#m` — all three union into one
-- `#m`. cue: `{a:1, b:2, c:3}`.
theorem bug28_two_mixins_same_path_union :
    exportJsonMatches
      "#A: {#m: {a: 1}}\n#B: {#m: {b: 2}}\n#Use: {\n\t#A\n\t#B\n\t#m: {c: 3}\n\tvis: #m\n}\nout: #Use.vis\n"
      "{\n    \"out\": {\n        \"c\": 3,\n        \"a\": 1,\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

-- A DEFINITION pattern field `#data: [string]: string` across the embed: the union preserves the
-- PATTERN (unioned alongside the field), so a host string field is admitted. cue: `{known:"x"}`.
theorem bug28_def_pattern_across_embed_admits_string :
    exportJsonMatches
      "#M: {#data: {[string]: string}}\n#Use: {\n\t#M\n\t#data: {known: \"x\"}\n\tvis: #data\n}\nout: #Use.vis\n"
      "{\n    \"out\": {\n        \"known\": \"x\"\n    }\n}\n" = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): the unioned DEFINITION pattern still TYPECHECKS — a host INT field
-- on a `[string]: string` def pattern across the embed bottoms (cue: `conflicting values 5 and string`).
-- The union must not weaken the pattern to an open tail.
theorem bug28_def_pattern_across_embed_rejects_int :
    exportJsonBottoms
      "#M: {#data: {[string]: string}}\n#Use: {\n\t#M\n\t#data: {n: 5}\n\tvis: #data\n}\nout: #Use.vis\n" = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): a SHARED-label CONFLICT across the embed still bottoms — close-once
-- unions LABELS, the shared label's VALUES still `meet` (cue: `conflicting values 2 and 1`). The union
-- does not paper over a real conflict.
theorem bug28_same_def_conflict_across_embed_bottoms :
    exportJsonBottoms
      "#A: {#m: {a: 1}}\n#Use: {\n\t#A\n\t#m: {a: 2}\n\tvis: #m\n}\nout: #Use.vis\n" = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): two DISTINCT closed defs `#A & #B` (each declaring `#m`, NOT one
-- path embedded) selected and MET still reject the other's labels — they are independent closed
-- constraints, not repeated decls of one path, so the union must NOT fire. cue: `field not allowed`.
theorem bug28_distinct_closed_defs_meet_still_reject :
    exportJsonBottoms
      "#A: {#m: {a: 1}}\n#B: {#m: {b: 2}}\nv: #A.#m & #B.#m\nout: v\n" = true := by
  native_decide

-- Bug2-8 SOUNDNESS BOUNDARY (must STAY green): a host's REGULAR closed PATTERN field meeting an embed's
-- same pattern field stays closed-MEET (NOT union) — the cert-manager `data: [string]: string` shape (a
-- REGULAR field, so it never enters the DEFINITION decl-union). The pattern admits `extra`; cue and kue
-- AGREE (`{extra:"x"}`). Pins the boundary the fix respects.
theorem bug28_embed_closed_pattern_field_stays_meet :
    exportJsonMatches
      "#Data: {data: [string]: string}\n#Use: {\n\t#Data\n\tdata: {extra: \"x\"}\n\tvis: data\n}\nout: #Use.vis\n"
      "{\n    \"out\": {\n        \"extra\": \"x\"\n    }\n}\n" = true := by
  native_decide


-- ### Bug2-9 — use-site narrowing of a REFERENCED NAMED multi-conjunct def (RESOLVED).
--
-- `#LS: #Base & {…}` is a named def whose BODY is itself a `.conj`. Referencing it and narrowing at
-- the use site (`#LS & {#name}`) must flow `#name` into a field declared inside `#Base` (`vis: #name`).
-- Pre-fix kue forced `#LS`'s `.conj` body STANDALONE via the `.refId` eval arm — with NO use-operands —
-- so the sibling self-ref collapsed to its abstract value (`vis: string`) BEFORE the narrowing arrived,
-- then `& {#name}` met too late (`incomplete value: string`). The INLINED `#Base & {…} & {#name}`
-- already worked (all conjuncts in one fold). Fixed by `flattenConjDefRef`: a depth-0 ref to a
-- `.conj`-bodied def splices its constituents into the use-site `.conj` BEFORE the fold, making the
-- named ref byte-identical to the inlined meet. Distinct from Bug2-8 (decl-union across an embed);
-- this is narrowing-through-a-referenced-multi-conjunct-def.

-- TARGET (was the WITNESS of the wrong `incomplete value`; FLIPPED): a 2-conjunct named def narrowed
-- at the use site. `#name: "argocd-ls"` flows through `#LS` into `#Base`'s `vis: #name`. cue: `vis:
-- "argocd-ls"`. Pre-fix kue: `incomplete value: string`.
theorem bug29_named_multiconjunct_def_narrowed :
    evalSourceMatches
      "#Base: {#name: string, vis: #name}\n#LS: #Base & {#extra: \"x\"}\nout: #LS & {#name: \"argocd-ls\"}\n"
      "#Base: {#name: string, vis: string}\n#LS: {#name: string, vis: string, #extra: \"x\"}\nout: {#name: \"argocd-ls\", vis: \"argocd-ls\", #extra: \"x\"}"
        = true := by
  native_decide

-- The real-def shape: a conjunct carries a bare `...` tail (every prod9 def is `...`-open). The
-- flatten admits a bare-`...` conjunct losslessly (open via `open_`); the narrowing still reaches `vis`.
theorem bug29_named_multiconjunct_tail_narrowed :
    evalSourceMatches
      "#Base: {#name: string, vis: #name, ...}\n#LS: #Base & {#extra: \"x\"}\nout: #LS & {#name: \"argocd-ls\"}\n"
      "#Base: {#name: string, vis: string, ...}\n#LS: {#name: string, vis: string, #extra: \"x\", ...}\nout: {#name: \"argocd-ls\", vis: \"argocd-ls\", #extra: \"x\", ...}"
        = true := by
  native_decide

-- A CHAIN of named multi-conjunct defs (`#C: #B & …`, `#B: #A & …`) flattens fully — `flattenConjDefRef`
-- recurses through each `.conj` body, so the outermost narrowing reaches the deepest conjunct's self-ref.
theorem bug29_nested_named_multiconjunct_narrowed :
    evalSourceMatches
      "#A: {#name: string, vis: #name}\n#B: #A & {#p: \"b\"}\n#C: #B & {#q: \"c\"}\nout: #C & {#name: \"deep\"}\n"
      "#A: {#name: string, vis: string}\n#B: {#name: string, vis: string, #p: \"b\"}\n#C: {#name: string, vis: string, #p: \"b\", #q: \"c\"}\nout: {#name: \"deep\", vis: \"deep\", #p: \"b\", #q: \"c\"}"
        = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): flattening does NOT mask a real conflict. `val: 1` (in `#Base`,
-- via the named def) meets `val: 2` (use site) and BOTTOMS, exactly as cue.
theorem bug29_named_multiconjunct_conflict_bottoms :
    exportJsonBottoms
      "#Base: {#name: string, val: 1}\n#LS: #Base & {#extra: \"x\"}\nout: #LS & {#name: \"n\", val: 2}\n"
        = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): closedness is preserved through the flatten. The named def is
-- closed (no `...`), so a use-site field declared by NO conjunct (`notallowed`) is rejected. cue:
-- `field not allowed`.
theorem bug29_named_multiconjunct_closed_rejects_extra :
    exportJsonBottoms
      "#Base: {#name: string, vis: #name}\n#LS: #Base & {#extra: \"x\"}\nout: #LS & {#name: \"n\", notallowed: 9}\n"
        = true := by
  native_decide

-- OVER-FIRE WITNESS (2026-06-23 Phase-A audit): a DEPTH>0 ref (nested-scope `#Inner` inside `#Outer`)
-- is NOT a depth-0 `.refId`, so `flattenConjDefRef` leaves it unchanged — yet the narrowing still
-- reaches the conjunct self-ref through the ordinary nested-frame path. cue and kue agree (`vis: "z"`).
-- Pins that the depth-0 bound does not break deeper-scoped narrowing.
theorem bug29_depth_gt0_nested_scope_narrows :
    exportJsonMatches
      "#Outer: {\n\t#Inner: {#n: string, vis: #n}\n\tuse: #Inner & {#n: \"z\"}\n}\nout: #Outer.use\n"
      "{\n    \"out\": {\n        \"vis\": \"z\"\n    }\n}\n" = true := by
  native_decide

-- TERMINATION WITNESS (2026-06-23 Phase-A audit): an ALIAS cycle `#A: #A & #B` narrowed at the use
-- site must TERMINATE (the flatten fuel strictly decreases), not loop. cue and kue agree (`{n: 5}`).
-- Pins the fuel guard the depth-0 flatten relies on for cyclic defs.
theorem bug29_alias_cycle_narrow_terminates :
    exportJsonMatches
      "#B: {n: int}\n#A: #A & #B\nout: #A & {n: 5}\n"
      "{\n    \"out\": {\n        \"n\": 5\n    }\n}\n" = true := by
  native_decide

-- Bug2-8 BOUNDARY WITNESS (2026-06-23 Phase-A audit): a SCALAR def value (`#x: string`) across the
-- embed stays a MEET, never the decl-UNION — `isUnionableDefValue` is false for a scalar, so the host
-- `#x: "hi"` × embed `#x: string` pair `.conj`-meets to `"hi"` (a union would double the display). cue
-- and kue agree (`"hi"`). Pins the field/pattern-bearing-vs-scalar union boundary.
theorem bug28_scalar_def_across_embed_stays_meet :
    exportJsonMatches
      "#A: {#x: string}\n#Use: {\n\t#A\n\t#x: \"hi\"\n\tvis: #x\n}\nout: #Use.vis\n"
      "{\n    \"out\": \"hi\"\n}\n" = true := by
  native_decide

-- ### Bug2-10 — use-site narrowing into a structComp HOST's embedded self-ref (RESOLVED).
--
-- `{#Meta} & {#name:"x"}` — the host `{#Meta}` is a `.structComp` (the `#Meta` embed lives in its
-- `comprehensions` bucket), NOT a bare `.refId`. `conjDefClosure?` defers a `.refId` only, so the
-- structComp host evaluated STANDALONE through the `.structComp` arm with NO use-operands, freezing
-- the embed's `Self.#name` at abstract `string` BEFORE the sibling `{#name:"x"}` arrived → `incomplete
-- value: string`. The DIRECT `#Meta & {#name:"x"}` worked (bare ref IS deferred). Fixed by
-- `conjStructCompDefer?`: a structComp host whose embed body has a sibling self-ref (`bodyNeedsDefer`)
-- is deferred to its `.closure` and joins the SAME shared-`useOperands` fold the bare-ref path runs, so
-- the narrowing reaches the self-ref before it collapses. Gated on a narrowing sibling existing
-- (`conjNarrowingSibling?`) — a no-narrowing `{#Meta}` stays standalone. Distinct from Bug2-9
-- (referenced multi-conjunct def flatten): this is the structComp-WRAPPER deferral.

-- TARGET (was the WITNESS of the wrong `incomplete value`; FLIPPED): the structComp host's embedded
-- `Self.#name` now narrows to the use-site `"x"`. cue: `{metadata: {name: "x"}}`.
theorem bug210_embed_self_ref_narrowed :
    evalSourceMatches
      "#Meta: Self={#name: string, metadata: {name: Self.#name}}\nout: {#Meta} & {#name: \"x\"}\n"
      "#Meta: {#name: string, metadata: {name: string}}\nout: {#name: \"x\", metadata: {name: \"x\"}}"
        = true := by
  native_decide

-- TRANSITIVE (composes with Bug2-5): the host embeds `#Mid` which embeds `#Meta`. `bodyNeedsDefer`
-- walks the embed chain (`embedChainAny`), so a transitively-embedded self-ref still triggers the
-- deferral and the narrowing reaches the deepest self-ref. cue: `{metadata: {name: "x"}}`.
theorem bug210_transitive_embed_narrowed :
    evalSourceMatches
      "#Meta: Self={#name: string, metadata: {name: Self.#name}}\n#Mid: {#Meta}\nout: {#Mid} & {#name: \"x\"}\n"
      "#Meta: {#name: string, metadata: {name: string}}\n#Mid: {#name: string, metadata: {name: string}}\nout: {#name: \"x\", metadata: {name: \"x\"}}"
        = true := by
  native_decide

-- DEEP nested self-ref read (`spec: acme: val: Self.#name`, 2 frames deep — the real-app shape).
-- `hasSelfRefAtDepth` descends nested frames, so the deferral fires and the deep read narrows. cue:
-- `{spec: {acme: {val: "deep"}}}`.
theorem bug210_deep_nested_self_ref_narrowed :
    evalSourceMatches
      "#Meta: Self={#name: string, spec: {acme: {val: Self.#name}}}\nout: {#Meta} & {#name: \"deep\"}\n"
      "#Meta: {#name: string, spec: {acme: {val: string}}}\nout: {#name: \"deep\", spec: {acme: {val: \"deep\"}}}"
        = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): closedness preserved. `#Meta` is closed (no `...`), so a use-site
-- field it does not declare (`notallowed`) is REJECTED — the structComp-host force re-closes over the
-- embed's labels (`embeddingClosesHost`). cue: `field not allowed`.
theorem bug210_embed_closed_rejects_extra :
    exportJsonBottoms
      "#Meta: Self={#name: string, copy: Self.#name}\nout: {#Meta} & {#name: \"n\", notallowed: 9}\n"
        = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): a real conflict still bottoms. `val: 1` (in `#Meta`) meets `val:
-- 2` (use site) → `_|_`, exactly as cue. Delivery never masks a genuine conflict.
theorem bug210_embed_conflict_bottoms :
    exportJsonBottoms
      "#Meta: Self={#name: string, val: 1, copy: Self.#name}\nout: {#Meta} & {#name: \"n\", val: 2}\n"
        = true := by
  native_decide

-- CLOSEDNESS LEAK FIX (pre-existing, no self-ref needed): embedding a CLOSED def closes the host, so a
-- later MEET against it rejects an undeclared extra. `{#Meta} & {b}` REJECTS `b`; pre-fix kue admitted
-- it (the open-host embed-meet leak). cue: `field not allowed`.
theorem bug210_embed_meet_extra_rejected :
    exportJsonBottoms
      "#Meta: {a: 1}\nout: {#Meta} & {b: 2}\n"
        = true := by
  native_decide

-- CLOSEDNESS BOUNDARY (must STAY green): the EMBED-FORM `{#Meta, b}` (sibling `b` declared in the SAME
-- struct literal as the embed) ADMITS `b` — a sibling is part of the embedding struct's own declaration,
-- NOT a later meet. Distinguishes embed-form (admit) from meet-form (reject); pins `embeddingClosesHost`
-- does not over-close. cue: `{a: 1, b: 2}`.
theorem bug210_embed_form_sibling_admitted :
    exportJsonMatches
      "#Meta: {a: 1}\nout: {#Meta, b: 2}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- OVER-FIRE NEGATIVE (must STAY green): a structComp host with a self-ref embed but NO narrowing sibling
-- (`{#Meta}` alone) stays STANDALONE and incomplete — `conjStructCompDefer?` never fires (a single value
-- is not a `.conj`, and the call-site gate requires a narrowing sibling). cue: `incomplete value`.
theorem bug210_no_narrowing_stays_incomplete :
    exportJsonBottoms
      "#Meta: Self={#name: string, metadata: {name: Self.#name}}\nout: {#Meta}\n"
        = true := by
  native_decide

-- OVER-FIRE NEGATIVE (must STAY green): a structComp host with a narrowing sibling but NO self-ref embed
-- (`#Meta` has a fixed `metadata.name`) does NOT defer (`bodyNeedsDefer` false) — byte-identical to the
-- pre-fix standalone path. cue and kue agree (`{metadata: {name: "fixed"}}`).
theorem bug210_no_self_ref_unchanged :
    exportJsonMatches
      "#Meta: {#name: string, metadata: {name: \"fixed\"}}\nout: {#Meta} & {#name: \"x\"}\n"
      "{\n    \"out\": {\n        \"metadata\": {\n            \"name\": \"fixed\"\n        }\n    }\n}\n" = true := by
  native_decide

-- COVERAGE TRIPWIRE (test-health hardening, Phase-B 2026-06-23). Anchors the LAST theorem of
-- every section. If a stray block comment (`/-` … runaway) or an editing slip ever swallows a
-- section, the anchor name becomes unknown and `#check` fails to ELABORATE — a hard build
-- error, not a silently-dead green build. This is the structural guard the dead-theorem
-- incident (~140 silently dead, build green) lacked. Headers in THIS file are `--` line
-- comments (cannot run away); the tripwire backstops any future regression. Keep one anchor
-- per section; add a line when a section is added.
#check @embedded_self_pass_skips_nested_unselected            -- argocd link 3/4
#check @embedded_self_pass_skips_builtin_unrelated            -- A1 builtin-arg
#check @remap_structcomp_conjunct_remaps_comprehension        -- B1 conj-remap
#check @descend_clauses_agrees_remapConjClauses               -- A5 body-depth
#check @fold_value_dynfield_value_scanned_at_parent_depth     -- A-EN3 fold
#check @descend_clauses_frame_count_matches_resolve           -- B7 descendClauses
#check @remap_dynamicfield_conjunct_reindexes_label_and_value -- A5-sibling
#check @listcomp_embed_selfref_empty_stays_empty              -- argocd link 4
#check @hidden_def_embed_concrete_source                      -- secret-data sub-1
#check @disj_struct_no_over_defer                             -- secret-data sub-2
#check @conj_disj_arms_fuel_zero_declines                     -- saturation guard
#check @embed_disj_single_arm_narrows                         -- embed-disj-arm-fallthrough
#check @embed_comprehension_guard_real_conflict_bottoms       -- parts.#Mixin
#check @let_buried_for_source_expands                         -- Bug2-1 / A-EN1
#check @mixin_let_local_guard_false_drops_body                -- Bug2-4
#check @embed_body_embeds_disj_gate_direct_disj               -- Bug2-5 / Bug2-2
#check @concrete_key_comprehension_still_resolves             -- MEET-RESID-1
#check @resid_mask_no_over_prune_clean_residual_survives      -- RESID-MASK-1
#check @resid_mask2_terminal_conflict_arm_sheds_for_concrete_survivor -- RESID-MASK-2
#check @bug26_four_decl_conflict_bottoms                      -- Bug2-6
#check @bug27_closed_pattern_multi_decl_rejects_int_via_ref   -- Bug2-7
#check @bug29_alias_cycle_narrow_terminates                   -- Bug2-9
#check @bug28_scalar_def_across_embed_stays_meet              -- Bug2-8 (file tail)
#check @bug210_no_self_ref_unchanged                          -- Bug2-10 (file tail)

end Kue
