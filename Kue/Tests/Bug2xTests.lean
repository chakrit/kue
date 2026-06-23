import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

-- Bug2-x close-once / def-ref / structComp-narrowing / optional-selection family (the argocd
-- multi-decl + cross-package def-of-def narrowing chain). Carved out of `TwoPassTests.lean`
-- (Phase-B 2026-06-23 test-org split, item 3) — the foundational two-pass / argocd-link /
-- disjunction-selection / RESID-MASK pins stay in `TwoPassTests.lean`; this file holds the
-- contiguous Bug2-6..Bug2-13 sections. Org-only carve, zero behavior change, pin-count conserved.
-- TEST-HEALTH CONVENTION (durable): section headers are `--` LINE comments, never `/-- -/`/`/-! -/`
-- block comments (a line comment cannot swallow the next theorem); the end-of-file `#check`
-- coverage tripwire anchors the LAST theorem of every section.

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

-- ### Bug2-11 — use-site narrowing of a cross-package def-OF-def selector (RESOLVED).
--
-- `defaults.#ListenerSet & {#name, #passthrough}` where `defaults.#ListenerSet = defs.#ListenerSet
-- & {…}` and `defs.#ListenerSet` embeds the self-ref `parts.#Meta` — a TWO-LEVEL cross-package
-- def-of-def selector. The def-of-def body is a `.conj`; none of the deferral machinery
-- (`bodyNeedsDefer`/`followAliasDefBody?`) recursed into a `.conj`, so `importDefClosureBody?`
-- returned `none` and the conjunct forced STANDALONE with NO use-operands — the embedded `Self.#name`
-- froze at `string` AND a sibling default disjunction (`[...string] | *[]`) collapsed to `*[]`,
-- conflicting with the use-site list → `_|_`. A SINGLE-level cross-pkg selector narrows fine; the
-- failure needs the def-of-def indirection. Fixed by `conjBodyHasDeferringArm` (recognize a `.conj`
-- def-of-def whose arm reaches a deferral-needing struct, recursing through further `.conj` levels)
-- + capture the RAW `.conj` over its OWN package frame in `importDefClosureBody?` +
-- `forceClosureWithConjunctCore`'s `.conj` arm (re-fold arms ++ narrowing under `capturedEnv`, so
-- each arm resolves in ITS OWN package frame — the wrong-frame hazard). These `native_decide` pins
-- use the same-file INLINED def-of-def (`#Defs`/`#Defaults`); the cross-PACKAGE shape is pinned by
-- the `testdata/modules/crosspkg_defofdef_*` fixtures (the inlined and cross-pkg forms must agree).

-- TARGET (was the WITNESS of the bottom; FLIPPED): the def-of-def's embedded `Self.#name` narrows to
-- "x" AND the sibling default disjunction narrows to the use-site list (no spurious `*[]` collapse).
-- cue: `{kind: "ListenerSet", metadata: {name: "x"}}`.
theorem bug211_defofdef_disj_narrowed :
    evalSourceMatches
      "#Meta: Self={#name: string, metadata: name: Self.#name}\n#Defs: {#Meta, #gateway_name: string, #passthrough_hosts: [...string] | *[], kind: \"ListenerSet\"}\n#Defaults: #Defs & {#gateway_name: \"nginx\"}\nout: #Defaults & {#name: \"x\", #passthrough_hosts: [\"a.example.com\"]}\n"
      "#Meta: {#name: string, metadata: {name: string}}\n#Defs: {#gateway_name: string, #passthrough_hosts: [], kind: \"ListenerSet\", #name: string, metadata: {name: string}}\n#Defaults: {#gateway_name: \"nginx\", #passthrough_hosts: [], kind: \"ListenerSet\", #name: string, metadata: {name: string}}\nout: {#gateway_name: \"nginx\", #passthrough_hosts: [\"a.example.com\"], kind: \"ListenerSet\", #name: \"x\", metadata: {name: \"x\"}}"
        = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): closedness survives the def-of-def re-fold. A use-site field the
-- closed def-of-def does not declare (`notInDef`) is REJECTED — delivery is not laxity. cue: `field
-- not allowed`.
theorem bug211_defofdef_rejects_extra :
    exportJsonBottoms
      "#Meta: Self={#name: string, metadata: name: Self.#name}\n#Defs: {#Meta, #gateway_name: string, kind: \"ListenerSet\"}\n#Defaults: #Defs & {#gateway_name: \"nginx\"}\nout: #Defaults & {#name: \"x\", notInDef: true}\n"
        = true := by
  native_decide

-- SOUNDNESS GUARD (must STAY green): a real conflict still bottoms. The use-site `kind: "Other"` meets
-- the def's fixed `"ListenerSet"` → `_|_`. Delivery never masks a genuine conflict. cue: `conflicting
-- values`.
theorem bug211_defofdef_conflict_bottoms :
    exportJsonBottoms
      "#Meta: Self={#name: string, metadata: name: Self.#name}\n#Defs: {#Meta, #gateway_name: string, kind: \"ListenerSet\"}\n#Defaults: #Defs & {#gateway_name: \"nginx\"}\nout: #Defaults & {#name: \"x\", kind: \"Other\"}\n"
        = true := by
  native_decide

-- SINGLE-LEVEL CONTROL (must STAY green): a single-level cross-pkg-shaped selector (`#Defs & {…}`, no
-- `#Defaults` indirection) narrows fine BOTH before and after the fix — isolates the def-of-def
-- indirection as the cause. cue: `{kind: "ListenerSet", metadata: {name: "x"}}`.
theorem bug211_singlelevel_narrowed :
    evalSourceMatches
      "#Meta: Self={#name: string, metadata: name: Self.#name}\n#Defs: {#Meta, #gateway_name: string, kind: \"ListenerSet\"}\nout: #Defs & {#name: \"x\", #gateway_name: \"nginx\"}\n"
      "#Meta: {#name: string, metadata: {name: string}}\n#Defs: {#gateway_name: string, kind: \"ListenerSet\", #name: string, metadata: {name: string}}\nout: {#gateway_name: \"nginx\", kind: \"ListenerSet\", #name: \"x\", metadata: {name: \"x\"}}"
        = true := by
  native_decide

-- TERMINATION (Phase-A 2026-06-23 audit, added coverage): a SELF-referential `.conj` def-of-def
-- (`#LS: #LS & {#Meta, …}`) must TERMINATE — `conjBodyHasDeferringArm` recurses through `.conj`
-- arms and the force `.conj` arm re-enters eval, both fuel-bounded. The structural cycle on `#LS`
-- collapses to its non-recursive content WHILE the use-site `#name` still narrows the embedded
-- self-ref (`metadata.name → "x"`). A loop would hang the build; a wrong-frame collapse would
-- freeze `name` at `string`. cue: `{out: {metadata: {name: "x"}}}`. Cross-pkg analogue:
-- `testdata/modules/crosspkg_defofdef_selfconj_terminates`.
theorem bug211_selfconj_terminates_and_narrows :
    exportJsonMatches
      "#Meta: Self={#name: string, metadata: name: Self.#name}\n#LS: #LS & {#Meta, #gateway_name: \"nginx\"}\nout: #LS & {#name: \"x\"}\n"
      "{\n    \"out\": {\n        \"metadata\": {\n            \"name\": \"x\"\n        }\n    }\n}\n"
        = true := by
  native_decide

-- ### Bug2-13 — an UNSET OPTIONAL selection reads as ABSENT (`_|_`), not its declared type.
--
-- A presence-test on an unset optional field returned the WRONG polarity: kue resolved an
-- optional field reference to its declared TYPE (a present `.struct`/`.prim`), so `classifyDefinedness`
-- read `.defined` → `== _|_` wrongly false / `!= _|_` wrongly true. cue's model: an optional
-- declaration is a CONSTRAINT, not a value; until unification SUPPLIES the field it is ABSENT, and a
-- reference/presence-test against it is `_|_`. Fixed at the selection/resolution boundary —
-- `selectedFieldValue` (the eager `.selector` pluck) and the `.refId` eval arm (sibling reference)
-- both resolve an `.optional`-rung field to `.bottom`. The discriminator is the `.optional` presence
-- rung itself: supplying a regular conjunct downgrades optionality to `.regular` via `mergeFieldClass`
-- (`optional.meet regular = regular`), so a SET optional is no longer `.optional` and keeps resolving
-- to its value — the over-fire guard is structural, not a heuristic. Presence, not concreteness, so a
-- concrete-typed unset optional (`#opt?: 5`) is still absent. The selection-time analog of
-- `containsBottomFields`'s existing optional-skip (`Lattice.lean`). JSON-export witnesses also at
-- `testdata/export/bug213_*`.

-- TARGET (the bug, FLIPPED): unset optional `#opt?: {a:int}` reads ABSENT — `#opt == _|_` TRUE,
-- `#opt != _|_` FALSE. cue: `eq_bottom true, neq_bottom false`.
theorem bug213_unset_optional_reads_absent :
    evalSourceMatches
      "x: {#opt?: {a: int}, eq_bottom: #opt == _|_, neq_bottom: #opt != _|_}\n"
      "x: {#opt?: {a: int}, eq_bottom: true, neq_bottom: false}"
        = true := by
  native_decide

-- OVER-FIRE GUARD (must STAY green): a SET optional stays PRESENT. `#opt: {a:1}` downgrades the
-- rung to `.regular`, so selection reads `.defined` — `== _|_` FALSE, `!= _|_` TRUE. The absent rule
-- must not touch a supplied optional. cue: `set_eq false, set_neq true`.
theorem bug213_set_optional_stays_present :
    evalSourceMatches
      "y: {#opt?: {a: int}, #opt: {a: 1}, set_eq: #opt == _|_, set_neq: #opt != _|_}\n"
      "y: {#opt: {a: 1}, set_eq: false, set_neq: true}"
        = true := by
  native_decide

-- GENERALITY: a plain (non-definition) unset optional `opt?` reads the SAME as `#opt?` — the rule is
-- general to all optionals, orthogonal to definition-ness. cue: `eq_bottom true, neq_bottom false`.
theorem bug213_nondef_unset_optional_reads_absent :
    evalSourceMatches
      "z: {opt?: {a: int}, eq_bottom: opt == _|_, neq_bottom: opt != _|_}\n"
      "z: {opt?: {a: int}, eq_bottom: true, neq_bottom: false}"
        = true := by
  native_decide

-- PRESENCE-NOT-CONCRETENESS: a concrete-typed unset optional (`#opt?: 5`) is STILL absent — the
-- discriminator is the `.optional` rung, never whether the declared type is concrete. cue:
-- `eq_bottom true, neq_bottom false`.
theorem bug213_concrete_typed_unset_optional_absent :
    evalSourceMatches
      "w: {#opt?: 5, eq_bottom: #opt == _|_, neq_bottom: #opt != _|_}\n"
      "w: {#opt?: 5, eq_bottom: true, neq_bottom: false}"
        = true := by
  native_decide

-- ARGOCD PATH: a comprehension guard over an unset optional fires the CORRECT arm — the `if #opt ==
-- _|_` arm (absent), NOT the `if #opt != _|_` arm. The `attr.#ServiceRef` `#service?` shape that
-- gated `route.yaml`. cue: `{x: {out: {absent: true}}}`.
theorem bug213_comprehension_guard_fires_absent_arm :
    exportJsonMatches
      "x: {#opt?: {a: int}, out: {if #opt == _|_ {absent: true}, if #opt != _|_ {present: true}}}\n"
      "{\n    \"x\": {\n        \"out\": {\n            \"absent\": true\n        }\n    }\n}\n"
        = true := by
  native_decide

-- DEF-MEET narrowing through the absent/present fork: the SAME def, once with the optional UNSET
-- (`#D & {}` → `present: false`) and once SET (`#D & {#opt: {a:9}}` → `present: true`). Pins that the
-- fix fires AND its over-fire guard both hold across a definition meet, not just a literal struct.
theorem bug213_def_meet_unset_optional_absent :
    exportJsonMatches
      "#D: {#opt?: {a: int}, present: #opt != _|_}\nv: #D & {}\n"
      "{\n    \"v\": {\n        \"present\": false\n    }\n}\n"
        = true := by
  native_decide

theorem bug213_def_meet_set_optional_present :
    exportJsonMatches
      "#D: {#opt?: {a: int}, present: #opt != _|_}\nv: #D & {#opt: {a: 9}}\n"
      "{\n    \"v\": {\n        \"present\": true\n    }\n}\n"
        = true := by
  native_decide

-- DISCRIMINATOR — OPTIONAL-MEET-OPTIONAL stays ABSENT (the over-fire guard's exact boundary). A
-- second OPTIONAL conjunct (`#opt?: 5` over `#opt?: int`) NARROWS the constraint but does NOT
-- SUPPLY the field: `optional.meet optional = optional`, so the rung stays `.optional` and the
-- field reads ABSENT. This is the case a naive "declared value is concrete ⇒ present" heuristic
-- would wrongly fire on — pins that the discriminator is the PRESENCE RUNG, never concreteness or
-- the presence of a second conjunct. cue: `eq_bottom true, neq_bottom false` (the field never
-- materializes from two optional constraints). The over-fire guard fires ONLY on a `.regular`
-- downgrade (a real supplying conjunct), not on any narrowing.
theorem bug213_optional_meet_optional_stays_absent :
    evalSourceMatches
      "n: {#opt?: int, #opt?: 5, eq_bottom: #opt == _|_, neq_bottom: #opt != _|_}\n"
      "n: {#opt?: 5, eq_bottom: true, neq_bottom: false}"
        = true := by
  native_decide

-- RUNG-PRECISION — a REQUIRED unset field (`#req!`) is NOT swallowed by the `.optional` arm. The
-- match over `field.fieldClass.optionality` is exhaustive across the three rungs with no catch-all;
-- `required` falls into the `_ =>` non-optional branch and resolves to its declared TYPE (`int`),
-- which is INCOMPLETE — a presence-test bottoms the export, distinct from the optional `.bottom`
-- absent rule. Pins that the absent-for-unset rule is scoped to `.optional` exactly (a required
-- field is present-but-incomplete, never silently absent). cue: `field is required but not
-- present` (export error); kue: incomplete value — both bottom, neither swallows to absent.
theorem bug213_required_unset_not_swallowed_as_absent :
    exportJsonBottoms
      "x: {#req!: int, present: #req != _|_}\nout: x.present\n"
        = true := by
  native_decide

-- ### Bug2-14 — re-base an embed body's sibling/comprehension read onto the host-narrowed value.
--
-- An embed declares a label ABSTRACTLY (`bk: string`) which the HOST declares CONCRETELY (`bk:
-- "X"`). The embed body's sibling read — a plain `echo: bk` OR a comprehension guard `if bk == "X"`
-- — is bound to the EMBED-LOCAL frame (the embed is its OWN frame; the read is depth-0 into its own
-- slot, NOT the host's), so it reads the un-narrowed `string`: the plain ref exports `string`, the
-- guard never fires (the comprehension defers and `export` errors incomplete). The host's narrowing
-- reaches the embed-output only via the LATER `meet host (embed)` — too late for the already-captured
-- read. FIXED by `injectEmbedSiblingNarrowings` at `meetEmbeddingsWithFuel`'s plain-embed eval: the
-- host's (`current`'s) regular-output narrowing is MET into the embed body's same-label
-- read-and-declared slot BEFORE the body evaluates, so the read sees the merged value. Gated to the
-- read-and-declared × host-narrowed overlap exactly (`embedComprehensionReadLabels` ∩ host fields), so
-- an embed-INTERNAL field the host does NOT narrow stays embed-local (no over-rebase). The analog of
-- `injectLetLocalNarrowings` (Bug2-4) for an embed body rather than a let-local. General (not keyed to
-- argocd); cert-manager stays content-identical.

-- PLAIN sibling-ref form (the SCOPE-broadening witness — a comprehension-only fix would FAIL this):
-- `echo: bk` reads the embed-local `bk`, which the host narrows to `"X"`. cue `{bk:"X", echo:"X"}`;
-- kue formerly `echo: string`. Now `echo: "X"`.
theorem bug214_plain_sibling_ref_reads_host_narrowed :
    evalSourceMatches
      "host: {\n\tbk: \"X\"\n\t{\n\t\tbk: string\n\t\techo: bk\n\t}\n}\n"
      "host: {bk: \"X\", echo: \"X\"}"
        = true := by
  native_decide

-- COMPREHENSION form (the argocd `#Mixin` shape: `if kind == …` reads the embed-local abstract
-- field). The guard fires against the host-narrowed `bk == "X"` and the comprehension DRAINS. cue
-- `{bk:"X", hit:true}`; kue formerly left the `for`/`if` undrained (export error). Now `hit: true`.
theorem bug214_comprehension_guard_reads_host_narrowed :
    evalSourceMatches
      "host: {\n\tbk: \"X\"\n\t{\n\t\tbk: string\n\t\tfor k, v in {p: 1} {\n\t\t\tif bk == \"X\" { hit: true }\n\t\t}\n\t}\n}\n"
      "host: {bk: \"X\", hit: true}"
        = true := by
  native_decide

-- MULTI-LEVEL embed (a doubly-wrapped abstract field) — the injection recurses into nested embeds, so
-- a field declared abstractly two embed levels down still reads the host-narrowed value. cue
-- `{bk:"X", echo:"X"}`.
theorem bug214_multi_level_embed_reads_host_narrowed :
    evalSourceMatches
      "host: {\n\tbk: \"X\"\n\t{\n\t\t{\n\t\t\tbk: string\n\t\t\techo: bk\n\t\t}\n\t}\n}\n"
      "host: {bk: \"X\", echo: \"X\"}"
        = true := by
  native_decide

-- NESTED COMPREHENSION reading the embed-narrowed field (the guard sits under two `for` frames). The
-- injection narrows the embed-local `bk` slot regardless of how deeply the comprehension reads it.
theorem bug214_nested_comprehension_reads_host_narrowed :
    evalSourceMatches
      "host: {\n\tbk: \"X\"\n\t{\n\t\tbk: string\n\t\tfor k, v in {p: 1} {\n\t\t\tfor k2, v2 in {q: 2} {\n\t\t\t\tif bk == \"X\" { hit: true }\n\t\t\t}\n\t\t}\n\t}\n}\n"
      "host: {bk: \"X\", hit: true}"
        = true := by
  native_decide

-- NEGATIVE (must STAY drained, no regression) — embed reads its OWN concrete field (`bk: "X"` in the
-- embed, not abstract). Already correct; the injection must not change it. cue `{bk:"X", echo:"X"}`.
theorem bug214_embed_own_concrete_stays_drained :
    evalSourceMatches
      "host: {\n\t{\n\t\tbk: \"X\"\n\t\techo: bk\n\t}\n}\n"
      "host: {bk: \"X\", echo: \"X\"}"
        = true := by
  native_decide

-- NEGATIVE (must STAY drained) — embed reads a HOST-ONLY field (not declared in the embed at all), so
-- the read resolves up to the host frame and already sees `"X"`. cue `{bk:"X", echo:"X"}`.
theorem bug214_host_only_field_stays_drained :
    evalSourceMatches
      "host: {\n\tbk: \"X\"\n\t{\n\t\techo: bk\n\t}\n}\n"
      "host: {bk: \"X\", echo: \"X\"}"
        = true := by
  native_decide

-- OVER-REBASE GUARD — an embed-INTERNAL field (`other: string`) the host does NOT narrow stays
-- embed-local and INCOMPLETE; only the embed-declared × host-narrowed `bk` overlap re-bases. The
-- injection is gated on the host actually narrowing the label, so `echo: other` (reading the
-- never-host-narrowed `other`) keeps `string` — it MUST NOT be mis-rebased to the host's `bk`. cue
-- leaves `echo`/`other` incomplete (`string`); kue eval keeps them `string` (export errors
-- incomplete, matching cue). Pins that the re-base does NOT over-fire on a genuine embed-internal ref.
theorem bug214_over_rebase_guard_embed_internal_stays_local :
    evalSourceMatches
      "host: {\n\tbk: \"X\"\n\t{\n\t\tother: string\n\t\techo: other\n\t}\n}\n"
      "host: {bk: \"X\", other: string, echo: string}"
        = true := by
  native_decide

-- CONFLICT BOTTOMS — the embed declares the same label with a CONFLICTING type (`bk: int`) vs the
-- host's `bk: "X"`. The injection MEETS `int & "X"` = ⊥, so the struct bottoms (never a silent merge).
-- cue: `conflicting values "X" and int`. Pins that the injection narrows soundly (a real conflict
-- still bottoms — it does not widen past the use-site meet).
theorem bug214_conflicting_type_bottoms :
    exportJsonBottoms
      "host: {\n\tbk: \"X\"\n\t{\n\t\tbk: int\n\t\techo: bk\n\t}\n}\n"
        = true := by
  native_decide

-- Bug2-14b/c (the on-path argocd disjunction-arm let-local blocker, 2026-06-23). The argocd
-- `#Mixin` is a STRUCTURAL disjunction (`listShape | structShape | error`) embedding a `let _patch =
-- { kind: string; for … if kind == add.#kind … }` whose comprehension guard reads a host-narrowed
-- sibling `kind`. On the cross-package FORCE path the host's `kind` ("ListenerSet") never reached
-- `_patch.kind` through the surviving disjunction arm → the guard stayed incomplete → deferred →
-- `metadata.annotations` dropped. ROOT: `embedBodyEmbedsDisjDeep` was gated against the OUTER fold
-- `env`, so the body's own embed-refs (`.refId depth:=1`, relative to the def frame the force pushes)
-- resolved in the WRONG frame and the transitively-embedded disjunction was missed — dropping the
-- regular `kind` from the splice. FIXED by resolving the gate against the body's force frame
-- (`bodyForceFrameEnv`) at all three sites, PLUS a two-pass multi-closure force fold (Bug2-14c) that
-- splices a SIBLING closure's regular fields (`defs.#ListenerSet`'s `kind`) into a disjunction-bearing
-- closure (`parts.#UseCertManager`'s `#Mixin`). The cross-package FORCE behavior is pinned by the
-- module fixtures `bug214b_disjarm_letlocal_force` / `bug214c_disjarm_letlocal_crossconj`; the inline
-- pins below pin the disjunction-arm let-local SOUNDNESS at single-package granularity (the arm meet).

-- DRAINS — the disjunction's `structShape` arm survives, its `_patch` comprehension fires against the
-- host-narrowed `kind` ("ListenerSet"), and the kind-scoped patch (`ann: "le"`) merges. cue
-- `{kind:"ListenerSet", ann:"le"}`. Pins the let-local-through-disjunction-arm narrowing.
theorem bug214b_disj_arm_letlocal_drains :
    exportJsonMatches
      "out: {\n\t#additions: [string]: {#kind: string, #patch: _}\n\tlet _patch = {\n\t\tkind: string\n\t\tfor _, add in #additions {\n\t\t\tif kind == add.#kind { add.#patch }\n\t\t}\n\t\t...\n\t}\n\tlet structShape = {\n\t\t_patch\n\t\t...\n\t}\n\tstructShape | error(\"nope\")\n\t...\n} & {kind: \"ListenerSet\", #additions: ls: {#kind: \"ListenerSet\", #patch: {ann: \"le\"}}}\n"
      "{\n    \"out\": {\n        \"kind\": \"ListenerSet\",\n        \"ann\": \"le\"\n    }\n}\n"
        = true := by
  native_decide

-- INCOMPLETE-GUARD DEFERS — `kind` is ABSTRACT (`string`), so `if kind == add.#kind` is genuinely
-- undecidable: the comprehension must DEFER (export errors incomplete), NEVER force-drain a wrong
-- value. Pins that the disjunction-arm narrowing does not over-fire on an undecidable guard.
theorem bug214b_disj_arm_incomplete_guard_defers :
    exportJsonBottoms
      "out: {\n\t#additions: [string]: {#kind: string, #patch: _}\n\tlet _patch = {\n\t\tkind: string\n\t\tfor _, add in #additions {\n\t\t\tif kind == add.#kind { add.#patch }\n\t\t}\n\t\t...\n\t}\n\tlet structShape = {\n\t\t_patch\n\t\t...\n\t}\n\tstructShape | error(\"nope\")\n\t...\n} & {kind: string, #additions: ls: {#kind: \"ListenerSet\", #patch: {ann: \"le\"}}}\n"
        = true := by
  native_decide

-- CONFLICT BOTTOMS — the host narrows `ann` to a value CONFLICTING with the drained patch's
-- `ann: "le"`; a real conflict on the drained content MUST bottom (never a silent merge). Pins that
-- the disjunction-arm narrowing stays sound — it does not widen past the use-site meet.
theorem bug214b_disj_arm_conflict_bottoms :
    exportJsonBottoms
      "out: {\n\t#additions: [string]: {#kind: string, #patch: _}\n\tlet _patch = {\n\t\tkind: string\n\t\tfor _, add in #additions {\n\t\t\tif kind == add.#kind { add.#patch }\n\t\t}\n\t\t...\n\t}\n\tlet structShape = {\n\t\t_patch\n\t\t...\n\t}\n\tstructShape | error(\"nope\")\n\t...\n} & {kind: \"ListenerSet\", ann: \"OTHER\", #additions: ls: {#kind: \"ListenerSet\", #patch: {ann: \"le\"}}}\n"
        = true := by
  native_decide

-- OVER-SPLICE NEGATIVE (Phase-A audit, 2026-06-23). A DEF-FORM closure with an embedded disjunction
-- whose discriminator the host narrows, and NO sibling closure — so the Bug2-14c two-pass fold's
-- `siblingRegulars` carry only the closure's OWN regulars (dropped from the extra operand), leaving
-- NOTHING to splice and NO spurious re-force. The disjunction still resolves correctly via the base
-- force path (the `shape: "x"` arm wins, the `"y"` arm prunes). cue `{shape:"x", x:1}`. Pins that the
-- two-pass fold is byte-identical to the single-closure force when there is no cross-closure flow.
theorem bug214c_single_closure_disj_no_spurious_splice :
    exportJsonMatches
      "#D: {\n\tshape: string\n\t{shape: \"x\", x: 1} | {shape: \"y\", y: 2}\n}\nout: #D & {shape: \"x\"}\n"
      "{\n    \"out\": {\n        \"shape\": \"x\",\n        \"x\": 1\n    }\n}\n"
        = true := by
  native_decide

-- MULTI-LEVEL + COMPREHENSION COMBINED (Phase-A audit, 2026-06-23). A doubly-wrapped embed
-- (`{{ bk:string; for … if bk == "X" {hit} }}`) whose INNER abstract field is read by a
-- comprehension guard two embed levels down, host-narrowed at the top. Combines the multi-level
-- recursion (`rewriteEmbeds` into a nested embedding) AND the comprehension-guard form in ONE
-- witness — neither existing pin (single-level comprehension, or multi-level plain-ref) covered the
-- combination. PRE-fix this errored `incomplete` (the inner guard never saw the narrowed `bk`); the
-- `injectEmbedSiblingNarrowings` recursion now narrows the inner slot so the guard fires. cue
-- `{bk:"X", hit:true}`.
theorem bug214_multi_level_comprehension_combined :
    evalSourceMatches
      "host: {\n\tbk: \"X\"\n\t{\n\t\t{\n\t\t\tbk: string\n\t\t\tfor k, v in {p: 1} {\n\t\t\t\tif bk == \"X\" { hit: true }\n\t\t\t}\n\t\t}\n\t}\n}\n"
      "host: {bk: \"X\", hit: true}"
        = true := by
  native_decide

-- ### Bug2-12 — a SELF-recursive closed def must still reject use-site extras (RESOLVED).
--
-- `#X: #X & {a: 1}` is a CLOSED definition whose body REFERENCES itself. Self-recursion does NOT
-- re-open it: closedness is a property of the definition, independent of how its body refers to
-- itself. So `out: #X & {b: 2}` must REJECT `b` (cue v0.16.1: `out.b: field not allowed`), and the
-- INLINED form `(#X & {a: 1}) & {b: 2}` leaks identically — the gap was in the closing normalizer,
-- not a flatten path. Root cause: the def body here is a `.conj [#X, {a: 1}]` (a meet), and
-- `normalizeDefinitionValueWithFuel` (the def-body closer) had NO `.conj` arm — it fell through the
-- value-unchanged tail, so the def body's `{a: 1}` conjunct never closed. The structural-cycle path
-- (D#2a) then terminated `#X` to a shallow bottom and the surviving `{a: 1}` was OPEN, admitting the
-- use-site `b`. FIXED by a `.conj` arm in `normalizeDefinitionValueWithFuel` that closes each
-- conjunct (def-closedness distributes over a meet); cycle detection/termination is UNTOUCHED (the
-- fix runs at capture/normalize, never on `structStack`). cue REJECTS `b`.
theorem bug212_selfrec_closed_def_rejects_use_extra :
    exportJsonBottoms "#X: #X & {a: 1}\nout: #X & {b: 2}\n" = true := by
  native_decide

-- The INLINED form `(#X & {a: 1}) & {b: 2}` leaks identically pre-fix (it never reaches the flatten),
-- confirming the fix is in the cycle/closedness interaction, not `flattenConjDefRef`. cue REJECTS.
theorem bug212_selfrec_inlined_rejects_use_extra :
    exportJsonBottoms "#X: #X & {a: 1}\nout: (#X & {a: 1}) & {b: 2}\n" = true := by
  native_decide

-- ADMIT boundary (do NOT over-close): a field the closed body DECLARES (`a`) still admits + narrows.
theorem bug212_selfrec_closed_def_admits_declared :
    exportJsonMatches "#X: #X & {a: int}\nout: #X & {a: 5}\n"
      "{\n    \"out\": {\n        \"a\": 5\n    }\n}\n" = true := by
  native_decide

-- PATTERN boundary: a use-site field MATCHING the def's own pattern (`[=~\"^p\"]`) is ADMITTED even
-- under self-recursion; the closed-pattern allowed-set survives the cycle path. cue `{a:1, p1:5}`.
theorem bug212_selfrec_pattern_admits_match :
    exportJsonMatches "#X: #X & {a: 1, [=~\"^p\"]: int}\nout: #X & {p1: 5}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"p1\": 5\n    }\n}\n" = true := by
  native_decide

-- PATTERN boundary (reject): a NON-matching extra is still rejected under self-recursion. cue rejects.
theorem bug212_selfrec_pattern_rejects_nonmatch :
    exportJsonBottoms "#X: #X & {a: 1, [=~\"^p\"]: int}\nout: #X & {q1: 5}\n" = true := by
  native_decide

-- OPEN-TAIL boundary (do NOT over-close): a self-recursive def with an explicit `...` stays OPEN —
-- the use-site extra is admitted. The `.conj` closer must preserve a `defOpenViaTail` conjunct's
-- openness. cue `{a:1, b:2}`.
theorem bug212_selfrec_opentail_admits_extra :
    exportJsonMatches "#X: #X & {a: 1, ...}\nout: #X & {b: 2}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

-- NESTED boundary (reject): closedness propagates into a nested struct literal under self-recursion —
-- an extra in `sub` is rejected. cue `out.sub.extra: field not allowed`.
theorem bug212_selfrec_nested_rejects_extra :
    exportJsonBottoms "#X: #X & {a: 1, sub: {s: 1}}\nout: #X & {sub: {extra: 2}}\n" = true := by
  native_decide

-- NESTED boundary (admit): a declared nested field still admits. cue `{a:1, sub:{s:1}}`.
theorem bug212_selfrec_nested_admits_declared :
    exportJsonMatches "#X: #X & {a: 1, sub: {s: 1}}\nout: #X & {sub: {s: 1}}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"sub\": {\n            \"s\": 1\n        }\n    }\n}\n"
        = true := by
  native_decide

-- CONFORMING boundary (must stay green): a self-rec def whose declared fields live in ONE literal
-- conjunct (`{a:1, c:3}`) admits a use-site RE-DECLARATION of an existing field — `& {c:3}` is the
-- def's own field, so it is admitted + narrowed. cue `{a:1, c:3}`. Pins the close-over-UNION boundary
-- that the multi-conjunct (split-literal) form violates — see `bug212_multiconjunct_redeclare_OVERCLOSE`.
theorem bug212_singleliteral_redeclare_admits :
    exportJsonMatches "#X: #X & {a: 1, c: 3}\nout: #X & {c: 3}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- Bug2-12b RESOLVED (was a CONTAINED over-close). A self-rec def whose literals are SPLIT across `&`
-- (`#X & {a:1} & {c:3}`) must close its literals over their COMBINED allowed-set, not each separately:
-- a use-site re-declaring an existing field (`& {c:3}`) is the def's OWN field, so it ADMITS `{a:1,c:3}`
-- (cue agrees). Pre-fix `flattenConjDefRef`'s `close==true` branch `expanded.map`-closed each conjunct
-- SEPARATELY, yielding two `defClosed` structs whose `.conj`-meet concatenated the `closedClauses` (field
-- in BOTH sets) and wrongly bottomed. FIXED by partitioning `expanded` into union-able def-body literals
-- vs the rest (the self-ref `.refId`, untouched), `foldl mergeDefinitionDecls` the literals into ONE body
-- (closed-each-first so `unionDefOpenness` does not read a raw `regularOpen` as open), closing that single
-- union once, and re-emitting `rest ++ [closed]`. `mkStruct` derives the SINGLE self-clause over `{a,c}`.
theorem bug212_multiconjunct_redeclare_admits :
    exportJsonMatches "#X: #X & {a: 1} & {c: 3}\nout: #X & {c: 3}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- Bug2-12b GENUINE-EXTRA (must reject): a field in NO literal conjunct (`b`) is still rejected across the
-- split — the union closes over `{a,c}`, so `b` is `field not allowed`. cue rejects.
theorem bug212_multiconjunct_genuine_extra_rejects :
    exportJsonBottoms "#X: #X & {a: 1} & {c: 3}\nout: #X & {b: 2}\n" = true := by
  native_decide

-- Bug2-12b OPEN-TAIL across the split (do NOT over-close): a `...` in ONE split conjunct opens the UNION
-- (`unionDefOpenness` lets `defOpenViaTail` dominate), so a use-site extra is ADMITTED. cue `{a:1,b:2,c:3}`.
theorem bug212_multiconjunct_opentail_admits :
    exportJsonMatches "#X: #X & {a: 1} & {c: 3, ...}\nout: #X & {b: 2}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3,\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

-- Bug2-12b CONFLICT across the split (must bottom): a shared label declared with conflicting values in two
-- split conjuncts (`{a:1}` & `{a:2}`) still `.conj`-meets — `mergeDefinitionDecls` unions FIELDS, so a
-- shared label's values meet and conflict. cue `conflicting values 2 and 1`.
theorem bug212_multiconjunct_conflict_bottoms :
    exportJsonBottoms "#X: #X & {a: 1} & {a: 2}\nout: #X\n" = true := by
  native_decide

-- Bug2-12b THREE-WAY split admit: the union closes over `{a,c,e}` across THREE split conjuncts; a
-- re-declared existing field (`e`) admits. cue `{a:1,c:3,e:5}`.
theorem bug212_multiconjunct_threeway_admits :
    exportJsonMatches "#X: #X & {a: 1} & {c: 3} & {e: 5}\nout: #X & {e: 5}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"c\": 3,\n        \"e\": 5\n    }\n}\n" = true := by
  native_decide

-- Bug2-12b THREE-WAY split genuine-extra (reject): a field in none of the three literals (`z`) is rejected.
theorem bug212_multiconjunct_threeway_extra_rejects :
    exportJsonBottoms "#X: #X & {a: 1} & {c: 3} & {e: 5}\nout: #X & {z: 9}\n" = true := by
  native_decide

-- Bug2-12b SPLIT-WITH-PATTERN admit: a pattern living in ONE split conjunct (`[=~"^p"]`) survives the union
-- — a matching use-site field (`p1`) is ADMITTED. The pattern unions into the merged body's allowed-set.
-- cue `{a:1, p1:5}`.
theorem bug212_multiconjunct_split_pattern_admits :
    exportJsonMatches "#X: #X & {a: 1} & {[=~\"^p\"]: int}\nout: #X & {p1: 5}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"p1\": 5\n    }\n}\n" = true := by
  native_decide

-- Bug2-12b SPLIT-WITH-PATTERN reject: a use-site field matching NO pattern and in no literal (`q1`) is
-- rejected by the closed union. cue rejects.
theorem bug212_multiconjunct_split_pattern_rejects :
    exportJsonBottoms "#X: #X & {a: 1} & {[=~\"^p\"]: int}\nout: #X & {q1: 5}\n" = true := by
  native_decide

-- D#2 GUARDRAIL (must stay green): the structural-cycle DETECTION is untouched by the closer fix —
-- `#L: {n, next: #L}` still ERRORS (`.structuralCycle`), never unrolls. Pinned end-to-end here so a
-- Bug2-12 regression that perturbs cycle detection is caught in THIS file too.
theorem bug212_struct_cycle_still_bottoms :
    exportJsonBottoms "#L: {n: 1, next: #L}\nx: #L\n" = true := by
  native_decide

-- D#2 GUARDRAIL (must stay green): the terminating disjunction `#List | *null` still TERMINATES on
-- `*null` — the closer fix does not change when/whether the cycle bottoms. cue `{head:1, tail:null}`.
theorem bug212_list_disj_still_terminates :
    exportJsonMatches "#List: {head: int, tail: #List | *null}\ny: #List & {head: 1}\n"
      "{\n    \"y\": {\n        \"head\": 1,\n        \"tail\": null\n    }\n}\n" = true := by
  native_decide

-- ### Bug2-12 MUTUAL — closedness through a MUTUAL-recursion def cycle (RESOLVED 2026-06-23).
--
-- `#A: #B & {a:1}`, `#B: #A & {b:2}` is a CLOSED mutual cycle. Transitive expansion fixes each def's
-- allowed-set to the UNION of all cycle members' declared labels: `#A = #B & {a} = #A & {a,b}`, so
-- `allowed(#A) = {a,b}`. The lattice-principled behavior ADMITS the transitively-declared fields
-- (`a`, `b`) and REJECTS a genuine extra (`c`). cue v0.16.1 OVER-REJECTS — it rejects even `#A`'s OWN
-- declared field (`#A.a: field not allowed`), reading `#A`'s body as a use-site `{a}` added to an
-- already-closed `#B`; but `#B` is not yet closed mid-cycle, so a def rejecting a field it itself
-- declares is lattice-questionable. Kue conforms to the principled answer, NOT to cue — recorded in
-- `cue-divergences.md`. Pre-fix Kue UNDER-CLOSED (admitted `c`): the cross-def back-ref bottoms via
-- D#2, dropping `#B`'s closedness, so `#B & {a}` resolved to an OPEN body. FIXED by `defSlotInClosedCycle`:
-- the `flattenConjDefRef` `close` gate now fires for any depth-0 def→def cycle reaching this slot, not
-- only a DIRECT self-ref (Bug2-12). The transitive flatten already pulls every cycle member's literals
-- into `expanded`; the Bug2-12b union-then-close-once machinery fixes the allowed-set to `{a,b}`.

-- ADMIT (transitively-declared `a`, `b`): both in the union allowed-set. cue REJECTS even `a` (bug).
theorem bug212_mutual_admits_transitive_declared :
    exportJsonMatches "#A: #B & {a: 1}\n#B: #A & {b: 2}\nout: #A & {a: 1, b: 2}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- REJECT (genuine extra `c` ∉ {a,b}): the union closes the allowed-set, so `c` is `field not allowed`.
-- Pins the under-close fix — pre-fix Kue admitted `c`. cue also rejects `c` (but for the wrong reason).
theorem bug212_mutual_rejects_genuine_extra :
    exportJsonBottoms "#A: #B & {a: 1}\n#B: #A & {b: 2}\nout: #A & {c: 3}\n" = true := by
  native_decide

-- BASE (bare `#A`, no use-site narrow): the closed mutual cycle yields `{a:1,b:2}` — closedness over
-- the union does not reject the def's own declared fields. cue REJECTS even the base (bug).
theorem bug212_mutual_base_admits_declared :
    exportJsonMatches "#A: #B & {a: 1}\n#B: #A & {b: 2}\nout: #A\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- 3-WAY cycle ADMIT: `#A→#B→#C→#A` closes over `{a,b,c}`; all three transitively-declared fields admit.
-- Field ORDER is `c,b,a` (reverse-declaration, consistent with the 4-way `d,c,b,a` below) since the
-- flatten-fan-out BOUND collects each cycle member exactly once on the way down: value-identical to
-- the pre-bound `a,c,b` interleaving — an unordered map, order is not correctness (kue-performance.md).
theorem bug212_mutual_threeway_admits :
    exportJsonMatches "#A: #B & {a: 1}\n#B: #C & {b: 2}\n#C: #A & {c: 3}\nout: #A & {a: 1, b: 2, c: 3}\n"
      "{\n    \"out\": {\n        \"c\": 3,\n        \"b\": 2,\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- 3-WAY cycle REJECT: a field in NO cycle member (`d`) is rejected by the closed union.
theorem bug212_mutual_threeway_rejects_extra :
    exportJsonBottoms "#A: #B & {a: 1}\n#B: #C & {b: 2}\n#C: #A & {c: 3}\nout: #A & {d: 4}\n" = true := by
  native_decide

-- OPEN-TAIL across the cycle (do NOT over-close): a `...` in ONE cycle member opens the merged union
-- (`defOpenViaTail` dominates), so a use-site extra is ADMITTED. Pins that the cycle close preserves
-- a tail-opened body, exactly like the self-rec/split open-tail cases.
theorem bug212_mutual_opentail_admits_extra :
    exportJsonMatches "#A: #B & {a: 1, ...}\n#B: #A & {b: 2}\nout: #A & {c: 3}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"a\": 1,\n        \"c\": 3\n    }\n}\n" = true := by
  native_decide

-- ONE-WAY non-recursive boundary (must STAY on the distinct-meet path, NOT the cycle close): `#B` does
-- NOT ref back, so it is not a cycle — `#A: #B & {a}` is a use-site `{a}` added to closed `#B`, which
-- REJECTS (`a` ∉ {b}). cue agrees. Pins that `defSlotInClosedCycle` does not over-fire on a chain.
theorem bug212_mutual_oneway_nonrec_rejects :
    exportJsonBottoms "#A: #B & {a: 1}\n#B: {b: 2}\nout: #A\n" = true := by
  native_decide

-- 4-WAY cycle (depth beyond the 3-way pin): `#A→#B→#C→#D→#A` closes over `{a,b,c,d}`. Pins that the
-- fuel-bounded walk reaches every member at depth 4 — under-fire ruled out past the 3-way case.
theorem bug212_mutual_fourway_admits :
    exportJsonMatches
      "#A: #B & {a: 1}\n#B: #C & {b: 2}\n#C: #D & {c: 3}\n#D: #A & {d: 4}\nout: #A & {a: 1, b: 2, c: 3, d: 4}\n"
      "{\n    \"out\": {\n        \"d\": 4,\n        \"c\": 3,\n        \"b\": 2,\n        \"a\": 1\n    }\n}\n"
        = true := by
  native_decide

-- 4-WAY cycle REJECT: a field in NO cycle member (`e`) is rejected by the closed union.
theorem bug212_mutual_fourway_rejects_extra :
    exportJsonBottoms
      "#A: #B & {a: 1}\n#B: #C & {b: 2}\n#C: #D & {c: 3}\n#D: #A & {d: 4}\nout: #A & {e: 5}\n" = true := by
  native_decide

-- ENTRY FROM A NON-HEAD MEMBER: the use site references `#B` (not `#A`), yet `#B` must still close over the
-- full transitive `{a,b}` — `defSlotInClosedCycle` starts the walk from the ENTERED slot, so every member
-- carries the same closed allowed-set regardless of entry point. ADMIT `{a,b}`.
theorem bug212_mutual_entry_from_member_admits :
    exportJsonMatches "#A: #B & {a: 1}\n#B: #A & {b: 2}\nout: #B & {a: 1, b: 2}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

-- ENTRY FROM A NON-HEAD MEMBER REJECT: entering from `#B`, a genuine extra `z` ∉ {a,b} is still rejected.
theorem bug212_mutual_entry_from_member_rejects :
    exportJsonBottoms "#A: #B & {a: 1}\n#B: #A & {b: 2}\nout: #B & {z: 9}\n" = true := by
  native_decide

-- OPEN MEMBER opens the WHOLE cycle (the `...` lives on the NON-head member `#B`, distinct from
-- `bug212_mutual_opentail_admits_extra` where it is on `#A`): the open tail propagates through the
-- transitive union (`defOpenViaTail` dominates), so a use-site extra `z` is ADMITTED. cue OVER-REJECTS
-- (mid-cycle premature close — see `cue-divergences.md`); Kue conforms to the principled answer.
theorem bug212_mutual_open_member_admits_extra :
    exportJsonMatches "#A: #B & {a: 1}\n#B: #A & {b: 2, ...}\nout: #A & {z: 9}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"a\": 1,\n        \"z\": 9\n    }\n}\n" = true := by
  native_decide

-- ### Multi-ref cyclic flatten-fan-out BOUND (perf — RESOLVED 2026-06-23).
--
-- A closed cycle whose HEAD conjoins ≥2 back-referencing defs (`#A: #B & #C & {a}`, `#B: #A & {b}`,
-- `#C: #A & {c}`) was CORRECT but TIMED OUT (>40s): `flattenConjDefRef` re-expanded each cycle member
-- once per reference path, so with k back-refs the work multiplied along the cross-product of expansion
-- paths. These cases could NOT be pinned (the `native_decide` never finished). The `expanding`
-- visited-path bound — a depth-0 ref to a slot already on the current expansion path is returned
-- UNEXPANDED (its literals are already collected; the bare `.refId` is the leaf the unbounded recursion
-- bottoms to at fuel exhaustion) — collects each cycle member EXACTLY ONCE, making them fast pins.
-- VALUE-identical to the (correct-but-slow) pre-bound result; only the field ORDER is canonicalized
-- (unordered map, not correctness — kue-performance.md).

-- MULTI-REF 3-WAY ADMIT: head conjoins #B & #C, both loop back. Closes over `{a,b,c}`; all admit.
theorem bug212_multiref_threeway_admits :
    exportJsonMatches "#A: #B & #C & {a: 1}\n#B: #A & {b: 2}\n#C: #A & {c: 3}\nout: #A\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"c\": 3,\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- MULTI-REF 3-WAY REJECT: a genuine extra `z` ∉ {a,b,c} is rejected by the closed union.
theorem bug212_multiref_threeway_rejects_extra :
    exportJsonBottoms "#A: #B & #C & {a: 1}\n#B: #A & {b: 2}\n#C: #A & {c: 3}\nout: #A & {z: 9}\n" = true := by
  native_decide

-- MULTI-REF 4-WAY ADMIT: head conjoins #B & #C & #D, all loop back. Closes over `{a,b,c,d}`.
theorem bug212_multiref_fourway_admits :
    exportJsonMatches
      "#A: #B & #C & #D & {a: 1}\n#B: #A & {b: 2}\n#C: #A & {c: 3}\n#D: #A & {d: 4}\nout: #A\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"c\": 3,\n        \"d\": 4,\n        \"a\": 1\n    }\n}\n"
        = true := by
  native_decide

-- MULTI-REF OPEN-TAIL: a `...` on one back-referencing member (`#C`) opens the merged union, so a
-- use-site extra `z` is ADMITTED — the bound preserves the tail-opened body across the cycle.
theorem bug212_multiref_opentail_admits_extra :
    exportJsonMatches "#A: #B & #C & {a: 1}\n#B: #A & {b: 2}\n#C: #A & {c: 3, ...}\nout: #A & {z: 9}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"c\": 3,\n        \"a\": 1,\n        \"z\": 9\n    }\n}\n"
        = true := by
  native_decide

-- MULTI-REF SPLIT LITERAL: the head's own literal split across `&` (`{a:1} & {a2:11}`) unions into the
-- closed body (the Bug2-12b split-literal close-once), so both `a` and `a2` admit alongside `b`,`c`.
theorem bug212_multiref_split_literal_admits :
    exportJsonMatches "#A: #B & #C & {a: 1} & {a2: 11}\n#B: #A & {b: 2}\n#C: #A & {c: 3}\nout: #A\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"c\": 3,\n        \"a\": 1,\n        \"a2\": 11\n    }\n}\n"
        = true := by
  native_decide

-- DUPLICATED BACK-REF in ONE member (`#B: #A & #A & {b}`): the visited-path bound stops the re-entry,
-- so the duplicate `#A` ref does not re-expand — value-identical to the single-ref 2-way cycle `{a,b}`.
theorem bug212_multiref_dup_backref_admits :
    exportJsonMatches "#A: #B & {a: 1}\n#B: #A & #A & {b: 2}\nout: #A\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- ### missing-field-selection — a GENUINELY-MISSING field of a CONCRETE struct selects to ABSENT.
--
-- A presence-test on a never-declared field of a concrete struct (`x: {a:1}`, then `x.b == _|_`)
-- returned the WRONG state: `selectFromDecls`'s miss arm DEFERRED to `.selector base label`, which
-- `classifyDefinedness` reads `.incomplete`, so the comparison stayed unresolved → `export` errored
-- `incomplete value` where cue yields ABSENT (`x.b == _|_` true / `x.b != _|_` false). cue's model:
-- selecting a field absent from a CONCRETE struct is absence, not a deferral — every conjunct is
-- merged into the struct value BEFORE selection runs (`x: base & extra` supplies `b` at unification),
-- so a field absent from the merged decls can never arrive later. Fixed at the same selection
-- boundary as Bug2-13: `selectFromDecls`'s `none` arm yields `.bottom` (`classifyDefinedness`
-- `.error`), not the deferred `.selector`. The over-fire guard is structural — only carrier shapes
-- that reach `selectFromDecls` are ALREADY-EVALUATED struct/embed carriers (and resolved disjunction
-- DEFAULT arms); the PROVISIONAL case (an unresolved disjunction with no unique default, where a
-- later arm could supply the field) never reaches here, staying the deferred `.selector base label`
-- in `selectEvaluatedField`'s `.disj` `_ =>` arm. JSON-export witnesses at `testdata/export/mfs_*`.

-- TARGET (the bug, FLIPPED): a missing field of a concrete struct reads ABSENT —
-- `sub.b == _|_` TRUE, `sub.b != _|_` FALSE. cue: `eq true, neq false`.
theorem mfs_concrete_missing_reads_absent :
    evalSourceMatches
      "x: {sub: {a: 1}, eq: sub.b == _|_, neq: sub.b != _|_}\n"
      "x: {sub: {a: 1}, eq: true, neq: false}"
        = true := by
  native_decide

-- DEEP missing (`a.c`): a missing field NESTED inside a concrete struct is ALSO absent. Pins the
-- deep form noted in the audit (the intermediate `a` is itself a struct `{b:1}`, so the miss routes
-- through `selectFromDecls`, not the non-struct-carrier `.bottom` catch-all). cue: `eq true,
-- neq false`.
theorem mfs_deep_missing_reads_absent :
    evalSourceMatches
      "x: {a: {b: 1}, eq: a.c == _|_, neq: a.c != _|_}\n"
      "x: {a: {b: 1}, eq: true, neq: false}"
        = true := by
  native_decide

-- OVER-FIRE GUARD (must STAY green): a PRESENT field still reads `.defined` — `a != _|_` TRUE.
-- The absent rule fires only on a genuine miss; a found field is unchanged. cue: `pa true`.
theorem mfs_present_field_stays_present :
    evalSourceMatches
      "x: {a: 1, pa: a != _|_}\n"
      "x: {a: 1, pa: true}"
        = true := by
  native_decide

-- OPEN-TAIL: a missing field of an OPEN (`...`) struct is STILL absent — the `...` does NOT make a
-- not-yet-declared field provisional at selection time (cue treats it absent too). cue: `eq true,
-- neq false`.
theorem mfs_opentail_missing_reads_absent :
    evalSourceMatches
      "x: {sub: {a: 1, ...}, eq: sub.b == _|_, neq: sub.b != _|_}\n"
      "x: {sub: {a: 1, ...}, eq: true, neq: false}"
        = true := by
  native_decide

-- SOUNDNESS (the CRUX): a field supplied by a LATER conjunct must have been PROVISIONAL, never
-- pre-bottomed. `sub: {a:1}` then `sub: {b:2}` MERGES before selection, so `sub.b` is PRESENT —
-- `== _|_` false, `!= _|_` true. Pins that the absent rule fires on FINAL absence, not on a field
-- the struct's own conjuncts supply. cue: `eq false, neq true`.
theorem mfs_later_conjunct_supplies_field :
    evalSourceMatches
      "x: {sub: {a: 1}, sub: {b: 2}, eq: sub.b == _|_, neq: sub.b != _|_}\n"
      "x: {sub: {a: 1, b: 2}, eq: false, neq: true}"
        = true := by
  native_decide

-- SOUNDNESS (narrow-elsewhere): narrowing a COPY of `base` (`z: base & {b:2}`) does NOT supply `b`
-- on `base` itself — `base.b` stays absent while `z.b` is present. Pins that absence is
-- per-struct-value, not leaked across a sibling meet. cue: `xeq true, zneq true`.
theorem mfs_narrow_elsewhere_leaves_original_absent :
    evalSourceMatches
      "x: {base: {a: 1}, z: base & {b: 2}, xeq: base.b == _|_, zneq: z.b != _|_}\n"
      "x: {base: {a: 1}, z: {a: 1, b: 2}, xeq: true, zneq: true}"
        = true := by
  native_decide

-- COMPREHENSION GUARD over a missing field: the guard now RESOLVES (the absent field reads `.error`,
-- not `.incomplete`), firing the `== _|_` arm. Pre-fix the deferred `.selector` made the guard
-- incomplete and BOTH arms dropped (`{}`). cue: `{out: {absent: true}}`.
theorem mfs_comprehension_guard_fires_absent_arm :
    exportJsonMatches
      "x: {a: 1}\nout: {if x.b != _|_ {present: true}, if x.b == _|_ {absent: true}}\n"
      "{\n    \"x\": {\n        \"a\": 1\n    },\n    \"out\": {\n        \"absent\": true\n    }\n}\n"
        = true := by
  native_decide

-- DISJUNCTION DEFAULT: selecting a missing field through a resolved DEFAULT arm is absent too — the
-- default `{a:1}` is a concrete struct, `b` absent. cue: `eq true, neq false`.
theorem mfs_disj_default_missing_reads_absent :
    evalSourceMatches
      "x: {d: *{a: 1} | {a: 1, b: 2}, eq: d.b == _|_, neq: d.b != _|_}\n"
      "x: {d: *{a: 1} | {a: 1, b: 2}, eq: true, neq: false}"
        = true := by
  native_decide

-- PROVISIONAL (over-fire guard, must NOT bottom): an UNRESOLVED disjunction with no unique default
-- where one arm HAS `b` and the other does not is PROVISIONAL — selection must stay DEFERRED, never
-- pre-bottomed to absent. The whole value is incomplete/ambiguous (cue `incomplete value`; kue
-- `ambiguous value`) — both NON-export, neither resolves the presence-test. Pins the discriminator
-- boundary: a resolved struct ⇒ absent; an unresolved disjunction ⇒ defer.
theorem mfs_unresolved_disj_stays_provisional :
    exportJsonBottoms
      "x: {a: 1} | {a: 1, b: 2}\nout: x.b != _|_\n"
        = true := by
  native_decide

-- DISCRIMINATOR (default arm SUPPLIES the field): the complement of `mfs_disj_default_missing` — a
-- resolved DEFAULT arm that CONTAINS `b` selects it as PRESENT (`val: 9`), not absent. Pins that
-- the resolved-arm route through `selectFromDecls` reads the arm's OWN fields, so a default-supplied
-- field stays present. cue: `eq false, neq true, val 9`.
theorem mfs_disj_default_supplies_field :
    evalSourceMatches
      "x: {d: *{a: 1, b: 9} | {a: 2}, eq: d.b == _|_, neq: d.b != _|_, val: d.b}\n"
      "x: {d: *{a: 1, b: 9} | {a: 2}, eq: false, neq: true, val: 9}"
        = true := by
  native_decide

-- CHAINED selection (selector-result base): `z: y.inner` selects `inner` first (a deferral), and a
-- MISSING field of the chained result (`z.b`) is still FINAL-absent — the chained base is a resolved
-- concrete struct by the time `selectFromDecls` runs. Pins the "select chained after another
-- deferral" path the discriminator audit enumerated. cue: `eq true, neq false`.
theorem mfs_chained_selection_missing_absent :
    evalSourceMatches
      "x: {y: {inner: {a: 1}}, z: y.inner, eq: z.b == _|_, neq: z.b != _|_}\n"
      "x: {y: {inner: {a: 1}}, z: {a: 1}, eq: true, neq: false}"
        = true := by
  native_decide

-- ALIASED-BUILTIN call resolution (item-6 LATENT, A2-y audit). `import j "encoding/json"` aliases
-- the package locally; the parser lowers `j.Marshal` off the LITERAL head, so a post-parse alias
-- canonicalization rewrites the head to `json.Marshal` before the alias-blind `BuiltinFamily.ofName?`
-- dispatch. EXPORT observable (not just eval) so a regression to `incomplete`/bottom fails. The
-- unaliased form is unaffected; an aliased user import is never misdispatched to a builtin.
theorem aliased_builtin_call_marshals_like_unaliased :
    exportJsonMatches
      "import j \"encoding/json\"\nout: j.Marshal({a: 1})\n"
      "{\n    \"out\": \"{\\\"a\\\":1}\"\n}\n"
        = true := by
  native_decide

-- COVERAGE TRIPWIRE (test-health hardening, Phase-B 2026-06-23). Anchors the LAST theorem of every
-- section carved into this file. If a stray block comment (`/-` … runaway) or an editing slip ever
-- swallows a section, the anchor name becomes unknown and `#check` fails to ELABORATE — a hard build
-- error, not a silently-dead green build. Headers in THIS file are `--` line comments (cannot run
-- away); the tripwire backstops any future regression. Keep one anchor per section; add a line when a
-- section is added.
#check @bug26_four_decl_conflict_bottoms                      -- Bug2-6
#check @bug27_closed_pattern_multi_decl_rejects_int_via_ref   -- Bug2-7
#check @bug28_embed_closed_pattern_field_stays_meet           -- Bug2-8
#check @bug28_scalar_def_across_embed_stays_meet              -- Bug2-9 tail (Bug2-8 boundary witness)
#check @bug29_alias_cycle_narrow_terminates                   -- Bug2-9
#check @bug210_no_self_ref_unchanged                          -- Bug2-10
#check @bug211_selfconj_terminates_and_narrows                -- Bug2-11
#check @bug213_required_unset_not_swallowed_as_absent         -- Bug2-13
#check @bug214_conflicting_type_bottoms                       -- Bug2-14
#check @bug214b_disj_arm_conflict_bottoms                     -- Bug2-14b/c
#check @bug214_multi_level_comprehension_combined             -- Bug2-14 audit (multi-level + comprehension)
#check @bug212_list_disj_still_terminates                     -- Bug2-12
#check @bug212_mutual_oneway_nonrec_rejects                   -- Bug2-12 MUTUAL
#check @bug212_multiref_threeway_admits                       -- multi-ref flatten-fan-out BOUND
#check @bug212_multiref_dup_backref_admits                    -- multi-ref dup back-ref bound
#check @mfs_chained_selection_missing_absent                  -- missing-field-selection
#check @aliased_builtin_call_marshals_like_unaliased          -- aliased-builtin call resolution

end Kue
