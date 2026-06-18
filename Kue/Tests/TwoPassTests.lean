import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

/-- DISJUNCTION SELECTION (argocd `#Secret` blocker, facet 1): selecting a field INTO a
    default disjunction (`d.a` where `d: *{a:1,c:9} | {a:2}`) collapses to the default arm
    first, then selects — CUE's default rule. Previously `selectEvaluatedField` had no `.disj`
    case and fell through to `.bottom`. -/
theorem select_into_default_disjunction :
    (selectEvaluatedField
      (.disj [(.default, .struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"c", .regular, .prim (.int 9)⟩] .regularOpen none []),
              (.regular, .struct [⟨"a", .regular, .prim (.int 2)⟩] .regularOpen none [])])
      "a"
      == .prim (.int 1)) = true := by
  native_decide

/-- NO OVER-FIRE: a NON-default disjunction with multiple live arms does NOT collapse on
    selection — it stays a deferred `.selector` (manifest then reports the ambiguity), never a
    spurious `bottom` and never a silent pick of one arm. -/
theorem select_into_nondefault_disjunction_defers :
    (selectEvaluatedField
      (.disj [(.regular, .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []),
              (.regular, .struct [⟨"a", .regular, .prim (.int 2)⟩] .regularOpen none [])])
      "a"
      == .selector
           (.disj [(.regular, .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []),
                   (.regular, .struct [⟨"a", .regular, .prim (.int 2)⟩] .regularOpen none [])])
           "a") = true := by
  native_decide

/-- EMBEDDED DEFAULT DISJUNCTION (argocd `#Secret` blocker, facet 2): an embedded default
    disjunction collapses to its default arm before merging into the host
    (`resolveEmbeddedDisjDefault`), so its fields land as regular host fields and a sibling
    `Self.a` resolves. A non-default disjunction passes through untouched. -/
theorem resolve_embedded_default_disjunction :
    (resolveEmbeddedDisjDefault
      (.disj [(.default, .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []),
              (.regular, .struct [⟨"a", .regular, .prim (.int 2)⟩] .regularOpen none [])])
      == .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_embedded_nondefault_disjunction_unchanged :
    (resolveEmbeddedDisjDefault
      (.disj [(.regular, .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []),
              (.regular, .struct [⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])])
      == .disj [(.regular, .struct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []),
                (.regular, .struct [⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])]) = true := by
  native_decide

/-- TWO-PASS GATE (perf): the embedding-`Self` re-evaluation fires ONLY when a static field
    selects `Self.<embedded-label>`. This pins the no-over-fire boundary that keeps cert-manager
    (a `parts.#Metadata` embed never read via `Self.metadata`) on the single-pass path. -/
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

/-! ### argocd link 3/4 — DEEP and LIST-COMPREHENSION self-ref two-pass gate.

`refsSelfEmbeddedLabel` (the two-pass gate) previously matched only a DEPTH-0 `Self.<label>`
selector and had no `.listComprehension` arm. Two gaps:
  1. A `Self.<embedded-label>` read from a NESTED struct (`spec: { hostnames: Self.#hosts }`)
     is `.selector (.refId ⟨1, selfIndex⟩) #hosts` — depth 1 — so it was invisible; Pass 2
     never fired and the nested ref resolved against the un-augmented frame → `.bottom`
     (argocd `#TLSRoute.spec.hostnames`, `#ListenerSet.spec.parentRef.name`).
  2. A list-comprehension SOURCE (`listeners: [for h in Self.#hosts {…}]`) lives in a
     `.listComprehension`, which had no scan arm → the comprehension iterated the un-narrowed
     (empty) embedded field and dropped every element (argocd `#ListenerSet.spec.listeners`).
Both fixed by threading `depth` (incremented on struct descents, mirroring `hasSelfRefAtDepth`)
and adding a `.listComprehension` arm. -/

-- DEEP: `Self.a` read one frame deep (`b: { c: Self.a }`) fires the gate.
theorem embedded_self_pass_fires_on_nested_self_select :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩,
       ⟨"b", .regular, .struct [⟨"c", .regular, .selector (.refId ⟨1, 0⟩) "a"⟩] .regularOpen none []⟩]
      ["a"] = true := by
  native_decide

-- LIST-COMPREHENSION SOURCE: `b: [for x in Self.a {…}]` fires the gate (source at depth 0).
theorem embedded_self_pass_fires_on_listcomp_source :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩,
       ⟨"b", .regular, .list [.listComprehension [.forIn none "x" (.selector (.refId ⟨0, 0⟩) "a")]
                                (.struct [⟨"v", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none [])]⟩]
      ["a"] = true := by
  native_decide

-- LIST-COMPREHENSION SOURCE, NESTED: `spec: { listeners: [for x in Self.a {…}] }` (source at
-- depth 1) — the real argocd shape — fires the gate.
theorem embedded_self_pass_fires_on_nested_listcomp_source :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩,
       ⟨"spec", .regular, .struct [⟨"listeners", .regular, .list [.listComprehension
              [.forIn none "x" (.selector (.refId ⟨1, 0⟩) "a")]
              (.struct [⟨"v", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none [])]⟩] .regularOpen none []⟩]
      ["a"] = true := by
  native_decide

-- NO OVER-FIRE: a NESTED reference to an UNRELATED label (`Self.other`, not in the embedded set)
-- still does not fire — the depth-tracking widens detection only for genuinely-embedded labels.
theorem embedded_self_pass_skips_nested_unselected :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩,
       ⟨"b", .regular, .struct [⟨"c", .regular, .selector (.refId ⟨1, 0⟩) "other"⟩] .regularOpen none []⟩]
      ["a"] = false := by
  native_decide

/-! ### A1 (soundness) — `Self.<embedded-label>` read WRAPPED IN A BUILTIN ARG.

Both two-pass scanners (`refsSelfEmbeddedLabel` gate / `selfReferencedLabels` selection) ended
in a catch-all that SILENTLY SWALLOWED `builtinCall`/`embeddedList`/`structPattern`/
`structPatterns`. So `count: len(Self.#x)` — a `.builtinCall` whose arg reads an embedded label —
was invisible: the gate stayed single-pass and (post-`2d87b8e` selective re-eval) the field was
skipped → stale Pass-1 value. Adding the missing arms (args at same depth; embeddedList items/tail
at depth, decls at depth+1; pattern fields/labelPattern/constraint at depth+1) makes the read
visible to BOTH. -/

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
       ⟨"spec", .regular, .struct [⟨"n", .regular, .builtinCall "len" [.selector (.refId ⟨1, 0⟩) "x"]⟩] .regularOpen none []⟩]
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

/-! ### B1 (soundness) — `remapConjRefs` SWALLOWED struct-comp / comprehension conjuncts.

The conj-frame-remap (`remapConjRefs`, rebasing a conjunct's frame-local `.refId`s onto a merged
conjunction frame) ended in `| _, value => value`, silently dropping `.structComp` (the dominant
`{embed;…;...}` `#Def` conjunct shape), `.comprehension`/`.listComprehension`, `.embeddedList`,
`.dynamicField`. A swallowed conjunct kept STALE merged-frame indices after a field-reindexing
merge → wrong resolution or spurious bottom. The fix adds explicit recursing arms (structComp
fields + comprehensions at frameDepth+1; comprehension clause-sources/guards + body at frameDepth;
embeddedList items/tail at frameDepth, decls at frameDepth+1; dynamicField label+value). -/

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

/-! ### A5 (regression from B1) — comprehension BODY remapped at the wrong frame depth.

A comprehension body lives `#forClauses` frames deeper than the comprehension node (`for`
pushes a frame, `guard` does not) — the rule encoded once in `resolveClausesWithFuel`. B1's
`.comprehension`/`.listComprehension` arms recursed the body at flat `frameDepth`, so a body
ref targeting the merged conjunction frame (at `frameDepth + #for`) was compared `== frameDepth`,
missed, and kept its stale conjunct-local slot → wrong value. The fix threads an incrementing
depth through the clause chain exactly as resolution does (now the shared `descendClauses`
fold via `clauseChainDepth`: +1 per `for`, +0 per `guard`); the body is remapped at
`clauseChainDepth frameDepth clauses`, and clause source N at `frameDepth + (#for before N)`.

These pins use REALISTICALLY-RESOLVED bodies (depth reflecting the loop frame), not the
hand-built depth-0 value the prior `remap_comprehension_conjunct_reindexes_source_and_body`
pin tested — that value is unreachable after real `for`-clause resolution, so it passed while
the behavior was broken. -/

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
            (.comprehension clauses (.refId ⟨bodyDepth, 1⟩)) with
        | .comprehension _ (.refId id) => id.depth == bodyDepth && id.index == 0
        | _ => false)) = true := by
  native_decide

/-! ### B7 — `descendClauses` agreement theorems (the new structural guarantee).

`descendClauses` (`Value.lean`) is the single authority for the comprehension clause-chain
frame-depth rule (`+1` per `forIn`, `+0` per `guard`, body at the accumulated depth). These pins
make a future drift between the fold and either `resolveClausesWithFuel` (the reference walker,
not migrated — it threads scopes, not `Nat`) or `remapConjClauses` a `native_decide` failure
rather than a silent wrong value. -/

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
        | .refId id => id.depth == clauseChainDepth 0 clauses
        | _ => false)) = true := by
  native_decide

/-! ### A5 sibling — `selfReferencedLabels` MISSED a `Self.<embedded>` read inside a `for` body.

`selfReferencedLabels` (the Pass-2 selection seed: which static fields read an embedded label and
must be re-evaluated against the augmented frame) recursed a comprehension body at flat `depth`,
ignoring the loop frame each `for` pushes. A `Self.<embedded>` read inside a `for` body sits at
`depth + #forClauses` but was compared `== depth`, so the field was not collected → not selected
for Pass-2 → it reused its stale Pass-1 value. The fix threads the depth through the clause chain
via `selfReferencedLabelsClauses`, identically to `resolveClausesWithFuel` (and to the `remapConj*`
A5 fix above). These pins use REALISTICALLY-RESOLVED body refIds (depth reflecting the loop frame).
-/

-- A plain `.comprehension` with one `for` whose body struct reads `Self.#t` (`refId ⟨2,0⟩` — one
-- `for` frame + one struct-field frame above the `Self` slot at index 0): the label `#t` IS
-- collected. Flat recursion checks the ref at depth 1, misses it, returns `[]` → field skipped in
-- Pass-2 → stale value.
theorem self_referenced_labels_collects_through_for_body :
    (selfReferencedLabels evalFuel 0 0
        (.comprehension [.forIn none "x" (.list [])]
          (.struct [⟨"v", .regular, .selector (.refId ⟨2, 0⟩) "#t"⟩] .regularOpen none []))
      == ["#t"]) = true := by
  native_decide

-- A `guard` pushes no frame: a `Self.#t` read in a guard condition sits at the comprehension's own
-- `depth` (`refId ⟨0,0⟩`), and the body struct after the guard is still only the `for`-frame deep.
theorem self_referenced_labels_guard_no_frame :
    (selfReferencedLabels evalFuel 0 0
        (.comprehension [.guard (.selector (.refId ⟨0, 0⟩) "#g")]
          (.struct [⟨"v", .regular, .selector (.refId ⟨1, 0⟩) "#t"⟩] .regularOpen none []))
      == ["#g", "#t"]) = true := by
  native_decide

-- The gate twin `refsSelfEmbeddedLabel` (decides whether the two-pass fires at ALL) had the same
-- too-shallow comprehension-body scan, with a comment claiming it only over-fires (perf). That was
-- backwards: a too-shallow scan compares a deep `Self.<embedded>` read against `depth`, MISSES it,
-- returns `false`, and SKIPS the two-pass — a stale-value miss. Fixed via `refsSelfEmbeddedLabelClauses`
-- (depth threaded like resolution). Pre-fix this returns `false` (deep ref at ⟨2,0⟩ scanned at depth 1).
theorem refs_self_embedded_label_detects_through_for_body :
    refsSelfEmbeddedLabel evalFuel 0 0 ["#t"]
        (.comprehension [.forIn none "x" (.list [])]
          (.struct [⟨"v", .regular, .selector (.refId ⟨2, 0⟩) "#t"⟩] .regularOpen none [])) = true := by
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

/-! ### argocd link 4 — open struct (`...`) with embeddings no longer splits into a `.conj`.

An open struct that ALSO carries comprehensions/embeddings (`{ embed; …; ... }`) was parsed as
`.conj [.structComp(embeds), .structTail(fields, tail)]` — two OVERLAPPING-field arms. A
`Self.<field>` self-ref landed in the `.struct ` .defOpenViaTail (some arm) [], which never saw the embedding-contributed
fields, so a use-site narrowing collapsed to `.bottom` (argocd `defs.#ListenerSet`: `parts.#Metadata`
embedded + a def-level `...`). The parser now keeps it ONE node: the comprehension form already
carries `open_ = true`, exactly what the bare `...` (`.top` tail) means; a definition-context one is
closed by `normalizeDefinitionValueWithFuel` like any `.structComp`. The cross-package end-to-end
shape is pinned by the committed module fixture `open_embed_selfref_guard`; these are the parser +
same-file source pins. -/

-- SAME-FILE source pin: an open struct (`...`) embedding a self-ref def, with a nested-scope
-- `Self.#g` read, narrowed at the use site, resolves (no `.bottom`). Pre-fix the def-level `...`
-- split the body into a `.conj` whose `Self.#g` arm bottomed.
theorem open_embed_selfref_narrows :
    evalSourceMatches
        "#B: {#g: string, gw: #g}\n#R: Self={#B, who: Self.#g, ...}\nout: #R & {#g: \"x\"}\n"
        "#B: {#g: string, gw: string}\n#R: {who: string, #g: string, gw: string}\nout: {who: \"x\", #g: \"x\", gw: \"x\"}"
          = true := by
  native_decide

/-! ### argocd-secret-data sub-slice 1 — hidden-def embedding narrowing.

The argocd link-2 blocker: a hidden definition `_#OpaqueSecret` embedded into a host whose
use-site narrows a hidden field (`#data`). The embedded def's sibling self-ref (`data:
#data`, or a `for k,v in #data` comprehension) ran against the def's own ABSTRACT `#data`
before the use-site narrowing reached it → empty output instead of the populated map. Root
cause was a PARSER misclassification: `_#x` was tagged hidden-only (not a definition), so the
def-deferral path (`refDefClosureBody?`/`conjDefClosure?`) never fired for the embedding, and
the arm evaluated standalone (collapsing the self-ref) before the narrowing spliced in. Fixed
by classifying `_#x` as BOTH definition and hidden (see `parse_field_class_hidden_definition`).
Each pin is cue v0.16.1-exact. -/

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

/-! ### argocd-secret-data sub-slice 2 — embedded DEFAULT DISJUNCTION arm narrowing.

The exact argocd `#Secret` shape: a hidden-def `_#OpaqueSecret` in an embedded DEFAULT
DISJUNCTION arm `(*_#A | _#B)` whose body's `for k,v in #data` comprehension (or sibling
self-ref) is narrowed by the use-site. Pre-fix the disjunction evaluated standalone — its
default arm forced with NO use-operands collapsed the comprehension/self-ref BEFORE the
narrowing reached it (`resolveEmbeddedDisjDefault` picked the already-collapsed value).

Fix: DISTRIBUTE the narrowing into the disjunction arms at the UNEVALUATED level — both in
the `.conj` fold (`splitDisjConjunct`/`conjDisjArms?` → `*(_#A & narrow) | (_#B & narrow)`) and
in the embedded-disjunction merge (`meetEmbeddingsWithFuel` collapses to the default arm via
`conjDisjArms?` BEFORE deferral, so the arm force-splices the host's narrowing). `bodyNeedsDefer`
now recurses into a `.disj` embedding's default arm (`resolveEmbedDefBody?`), so the host defers.
Gated on a deferral-needing arm — a plain scalar/struct disjunction is untouched (no over-defer).
Each pin cue v0.16.1-exact. -/

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

/-- SATURATION GUARD (audit #6): `conjDisjArms?`'s `fuel = 0` arm returns `none` (declines to
    distribute) rather than dropping fields — it is NOT a truncation source, so it need not bump
    `truncCount`. Pin that the fuel-exhausted scan is a clean non-defer: at `fuel = 0` a
    `.refId`-bodied disjunction conjunct yields `none` (falls to the standard fold, which keeps
    its own bracketed truncation discipline). A regression that made it drop to a partial value
    without bumping would reopen the audit-#6 hole. -/
theorem conj_disj_arms_fuel_zero_declines :
    conjDisjArms? [(0, [])] 0 (.refId ⟨0, 0⟩) = none := by
  native_decide

/-! ### embed-disj-arm-fallthrough (audit #10 V2): a dead default arm FALLS THROUGH.

An embedded default disjunction (`(*_#A | _#B)`) used to collapse to its default arm BEFORE the
host narrowing spliced in, with no fall-through when the narrowing KILLED the default arm — kue
bottomed where cue picks the surviving arm. Fix: distribute the host narrowing into EVERY arm and
prune bottoms (`normalizeDisj` via `liveAlternatives`), then resolve. cue v0.16.1-exact. -/

-- HEADLINE: narrowing `v:"s"` kills the default arm `_#A` (`v:int`); kue must fall through to the
-- surviving `_#B` (`v:string`) — not bottom. Was kue BOTTOM pre-fix; cue `{kind:"b",v:"s"}`.
theorem embed_disj_dead_default_falls_through :
    evalSourceMatches
        "_#A: {kind: \"a\", v: int}\n_#B: {kind: \"b\", v: string}\n#S: {kind: string, (*_#A | _#B)}\nout: #S & {v: \"s\"}\n"
        "_#A: {kind: \"a\", v: int}\n_#B: {kind: \"b\", v: string}\n#S: *{kind: \"a\", v: int} | {kind: \"b\", v: string}\nout: {kind: \"b\", v: \"s\"}"
          = true := by
  native_decide

-- narrowing COMPATIBLE with the default arm (`v:1`): the default still wins (no spurious switch).
theorem embed_disj_live_default_kept :
    evalSourceMatches
        "_#A: {kind: \"a\", v: int}\n_#B: {kind: \"b\", v: string}\n#S: {kind: string, (*_#A | _#B)}\nout: #S & {v: 1}\n"
        "_#A: {kind: \"a\", v: int}\n_#B: {kind: \"b\", v: string}\n#S: *{kind: \"a\", v: int} | {kind: \"b\", v: string}\nout: *{kind: \"a\", v: 1}"
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


end Kue
