<!-- not spec/decision because: live cross-session breadcrumb; disposable, superseded in place -->

# Session resume — 2026-07-11

`check.sh` GREEN. Standing keep-going loop governs.
HEAD: **DEF-CLOSEDNESS-NESTED-CONJ-ARM ✅ LANDED (`345f08b`, 2026-07-13, Phase B).** The sole residual
HIGH soundness leak Phase A found is closed — a def-body NORMAL FORM (`normalizeDefBodyConjunct`,
`Kue/EvalBase.lean`) applied BEFORE the closedness gate: a pure-struct-literal `.conj` conjunct is
SPLICED into its members, a `.disj` conjunct's pure-struct `.conj` arms are MERGED (normalized-to-closed
then `mergeDefinitionDecls`). Both faces green (conjunct + disjunction-arm wild seeds); neither
`isUnionableDefValue` nor `disjArmClass` gained a `.conj` case — special case deleted, not duplicated.
Bounded: def bodies + pure-struct `.conj`s only; refs/scalars/self-refs/mutual-cycles/mixed conjs untouched.
Test-org: DEF-FLATTEN-CLOSEDNESS + this section moved Bug2xTests→ClosednessTests (Bug2xTests was over the
1800-line cap). `check.sh` GREEN, zero L-series/Bug2/closedness flips. Pushed.
**Phase B audit (this session) IN PROGRESS:** TASK 1 (above) done; TASK 2 (infra/gates rotation, 3rd cycle)
+ TASK 3 (module graph + backlog) running. **With this leak closed, the "all soundness leaks closed"
milestone is RE-REACHABLE — next audit's adversarial sweep confirms; NOT claimed here.** Alpha HELD.

Prior HEAD: **LIST-BUILTIN-RESIDUALS — the last two known HIGH list-builtin soundness leaks CLOSED + the effectful
`EvalM` list path SWEPT for carrier-completeness (LANDED 2026-07-13).** (1) **LIST-SORT-EMBEDDED-CARRIER** (5th
carrier-miss): `runSort` (`Kue/Eval.lean`) matched only `.list items`, so `list.Sort`/`SortStable` on an
`.embeddedList`/`.listTail` DEFERRED ("incomplete value"); now routed through `listItems?` — all three carriers
descend to their concrete prefix, settled→bottom / abstract→defer fallback intact. `list.Sort({[3,1,2],_y:9},
list.Ascending)`, `SortStable`, open-tail all ⇒ `[1,2,3]` (cue AGREES, prefix-sorts). (2)
**LIST-UNIQUEITEMS-CALL-FORM-BOTTOM** (pre-existing): the `(list)` call form was unrouted ⇒ ⊥; added
`| "list.UniqueItems", [.list items] => .prim (.bool (!hasGroundDup items))` beside the validator form, deciding
uniqueness via the SAME `hasGroundDup`/`structuralEq` predicate over the `openListOperand`-normalized operand.
`([1,2,3])`⇒true, `([1,1])`⇒false, embedded/open-tail⇒true; `([1,1.0])`⇒false — the established
STRUCT-EQ-LEAF-TYPESENSE value-based-equality divergence (cue `true`; extended in `cue-divergences.md`).
**EvalM CARRIER SWEEP:** `runSort` is the SOLE list-consuming builtin site on the effectful path (Sort/SortStable
share it; the effectful-builtin population is exactly these two). Every other `.list`/`.listTail`/`.embeddedList`
match in `Eval.lean` is list-literal evaluation or a unification `meet` arm — carrier-preserving structural code,
not a builtin list-read. **The effectful path is now carrier-complete: NO 6th miss.** Wild
`list-sort-embedded-carrier/` + `list-uniqueitems-call/` RED→GREEN; `SortTests` `eval_list_sort_{embedded_list,
stable_embedded_list,open_tail}`; `FixtureTests` `uniqueitems_call_*` + `uniqueitems_validator_form_unaffected`.
`check.sh` GREEN, zero Sort/list/validator flips.
**Milestone "all soundness leaks closed" — REACHED for the list-carrier surface (pending audit confirmation).**
These were the last two known HIGH list-builtin leaks. (SUPERSEDED for the WHOLE-language claim: the 2026-07-13
Phase A milestone-reconfirmation found DEF-CLOSEDNESS-NESTED-CONJ-ARM — see HEAD. The closedness surface was
NOT fully closed.)

Prior HEAD: **DISJ-CLOSEDNESS-DISTRIBUTE-STRUCTURAL — the closedness-disjunction distribute leak CLASS closed
STRUCTURALLY (LANDED 2026-07-13).** Replaced the hand-enumerated `isDistributableDisjArm` whitelist (which
missed the bottoms-vs-struct arm class TWICE) with a DERIVED predicate `disjArmClass : Value → DisjArmClass`
(`Kue/EvalBase.lean`) — a COMPLETE match over every `Value` constructor (no catch-all), so a new shape is a
COMPILE error, not a silent leak. Four classes derived from how the arm meets the def's own struct literal:
`fieldCarryingClosed` (union+close), `fieldCarryingOpen` (`.refId`, ref governs), `bottomsVsStruct`
(scalar/kind/notPrim/regex/format/bound/uniqueItems/list-carriers/lengthConstraint/`error`/⊥ — carries no new
field), `blocking` (unknown result kind → disj stays raw). **Emission reframe:** the `bottomsVsStruct` branch
CONJ's the pick against the CLOSED literal, so a kind-mismatched pick bottoms AND a composes-closed pick
(`struct.MinFields`, `_`) rides the closed literal and rejects extras — this is what makes `.fields` correct
WITHOUT a special-case (falsifying EXCLUDED-ARM-LEAK-2's own `k != .fields` prescription: cue ⊥, a closed def
rejects the extra regardless of the validator). **Call-form validators** (`list.MinItems(2)`,
`struct.MinFields(2)`) reach flatten UNLOWERED; `disjArmClass` lowers them through the existing
`evalBuiltinCall` — no builtin-name hand-list. **bug214b DISSOLVED by layer separation:** distribution fires
only for DEFINITION fields (`isDefinition` gates `close`), so bug214b's REGULAR-field `structShape | error`
force-folds untouched; a def-context `error` arm is `bottomsVsStruct` (force-folds to ⊥). Closes
**DISJ-CLOSEDNESS-EXCLUDED-ARM-LEAK-2** (regex/format/unique/notprim/lengthConstraint) AND
**DISJ-CLOSEDNESS-ERROR-ARM-LEAK** by construction. Wild `def-closedness-disj-{excluded-arm-{regex,format,
unique,notprim,minitems,minfields},error-arm}/` RED→GREEN; 9 `Bug2xTests` `defflatten_*arm_*` guards. cue
error-arm diagnostic differs (cue `x` vs kue `conflicting values`) — result ⊥ agrees, message-only. `check.sh`
GREEN, zero L-series/Bug2/closedness/bug214b flips. (The closedness-disjunction distribute CLASS is closed;
the two list-carrier/call-form leaks it left open are the current HEAD, now LANDED.)

Prior HEAD: **LIST-SLICE-EMBEDDED-CARRIER — slice desugar now routes through `listItems?`; carrier completeness
covers slice too (LANDED 2026-07-13).** The 4th list-carrier miss (2026-07-13 Phase A audit): the `slice`
desugar of `x[lo:hi]` in `evalCoreBuiltin` (`Kue/Builtin.lean`) hand-enumerated `.list`+`.listTail` and MISSED
`.embeddedList` — `evalCoreBuiltin` never mapped `openListOperand` (only `evalListBuiltin` did), so `71598c6`'s
tightening never migrated this site. `({[1,2,3], _y:9})[0:2]` was kue `incomplete value: slice(…)`; `len`/index
on the same value already worked. Fix: collapsed the two hand-enumerated arms into ONE routed through the
classifier — `| "slice", [value, .prim (.int low), .prim (.int high)] => match listItems? value with | some
items => listSlice items low high | none => unresolvedOrBottom …` — so all three carriers descend by
construction, NO 3rd hand-added arm. Restores the LIST-OPS-EMBEDDED-CARRIER "every list-carrier read routes
through `listItems?`" invariant. Wild `list-slice-embedded-carrier/` (interior/open-low/open-high/whole/
embedded-open-tail) RED→GREEN; 10 `SliceTests` theorems incl. `embedded_len_still_agrees`/
`embedded_index_still_selects` regression guards. cue v0.16.1 DIVERGES (`[9,1]` — bleeds hidden `_y` into the
slice, a cue bug; its own len/index are correct); spec-correct `[1,2]`, logged `cue-divergences.md`. `check.sh`
GREEN, zero SliceTests/list-fixture flips.
> SUPERSEDED by the new HEAD (DISJ-CLOSEDNESS-DISTRIBUTE-STRUCTURAL, 2026-07-13): DISJ-CLOSEDNESS-ERROR-ARM-LEAK
> and DISJ-CLOSEDNESS-EXCLUDED-ARM-LEAK-2 are now ✅ CLOSED by the derived predicate — no incremental patch or
> Fable-5 escalation was needed (the bug214b tension dissolved by layer separation). See the current HEAD's NEXT.
→ Phase B / two-phase audit DUE in 2-3 slices (this + DISJ-CLOSEDNESS-EXCLUDED-ARM-LEAK are un-audited) → LOW
gaps (PATTERN-LABEL-ALIAS-SCALAR / UNREFERENCED-ALIAS / LIST-ISSORTED / DISJ-NESTED-ERROR-ARM-AMBIGUOUS) →
PB-EVALBASE-SPLIT → deferred float FDLIBM. **Alpha release HELD for chakrit (attended).**

Prior HEAD: **DISJ-CLOSEDNESS-EXCLUDED-ARM-LEAK — bound/list/kind disjunction arms now close (LANDED 2026-07-13).**
The `isDistributableDisj` whitelist was all-or-nothing: one non-whitelisted arm (`.bound` `>5`, list `[1,2]`)
made the WHOLE disjunction non-distributable, so the def flattened OPEN and a use-site extra leaked
(`#X: {a:1} & ({z:9} | >5)` · `#X & {w:7}` ⇒ kue `{a,z,w}`, cue ⊥; same with `[1,2]`). Fix
(`isDistributableDisjArm`, `Kue/EvalBase.lean`): a DISTRIBUTE-SAFE category beside `.prim` — `.kind`,
`.boundConstraint`, and list carriers `.list`/`.listTail`/`.embeddedList` — each DIES against the def's own
struct literal, so its cross-product combination emits an OPEN `.conj [literal, pick]` that bottoms at eval
(same as the working scalar path); the struct arms still close. `error(...)`/comprehension arms stay OUT
(force-fold / can-produce-a-struct), so bug214b is untouched. Wild
`def-closedness-disj-excluded-arm-{bound,list}` RED→GREEN; 7 `Bug2xTests` both-direction guards. cue v0.16.1
mixed-arm truth table in the implementation-log. `check.sh` GREEN, zero L-series/Bug2/closedness flips.
**RESIDUAL FOUND & FILED (pre-existing, NOT introduced): DISJ-CLOSEDNESS-ERROR-ARM-LEAK (HIGH)** — the
DIRECT `error(...)` arm still leaks (`#X: {a:1} & ({z:9} | error("x"))` · `#X & {w:7}` ⇒ kue `{a,z,w}`, cue ⊥);
the error arm is blocking, so the def stays OPEN. `git stash` confirmed the leak predates this fix.
**Do NOT re-claim "all soundness leaks closed"** — LIST-SLICE-EMBEDDED-CARRIER and DISJ-CLOSEDNESS-ERROR-ARM-LEAK
remain open.
**NEXT (ranked):** LIST-SLICE-EMBEDDED-CARRIER (HIGH — slice desugar misses `.embeddedList`) →
DISJ-CLOSEDNESS-ERROR-ARM-LEAK (HIGH — error-arm force-fold distribution) → Phase B audit (still due) →
LOW gaps (PATTERN-LABEL-ALIAS-SCALAR / UNREFERENCED-ALIAS / LIST-ISSORTED / DISJ-NESTED-ERROR-ARM-AMBIGUOUS) →
PB-PERFGUIDE-STALE → PB-EVALBASE-SPLIT → deferred FDLIBM. **Alpha release HELD for chakrit (attended).**

Prior HEAD: **Phase A audit (`ca2c147..f0ddb19`) — MILESTONE NOT substantiated; 2 residual HIGH leaks found
(no code change, filed 2026-07-13).** The "all known soundness leaks closed" claim is FALSIFIED. (1)
**DISJ-CLOSEDNESS-EXCLUDED-ARM-LEAK** (HIGH): the `f0ddb19` `isDistributableDisj` whitelist is
all-or-nothing — a disjunction with ONE non-whitelisted arm (`.bound` `>5`, list `[1,2]`) skips closing
ALL arms → `#X: {a:1} & ({z:9} | >5)` · `#X & {w:7}` leaks `{a,z,w}` (cue ⊥). Fix: distribute bound/list
arms that DIE against a struct literal (like scalars) while keeping error/comprehension excluded for the
L-series force-fold. (2) **LIST-SLICE-EMBEDDED-CARRIER** (HIGH): 4th carrier-miss — the `slice` desugar
in `evalCoreBuiltin` misses `.embeddedList` (never migrated by `71598c6`, which only touched
`evalListBuiltin`); `({[1,2,3],_y:9})[0:2]` ⇒ kue incomplete, spec `[1,2]`. Plus LOW
DISJ-NESTED-ERROR-ARM-AMBIGUOUS (divergent error, not a leak). Both HIGHs are fixture-first slices (one
risks L-series, one needs a wild fixture) — filed in `plan.md` Ranked OPEN backlog, NOT fixed inline.
`f0ddb19` whitelist otherwise SOUND (closed/open-ref, scalar, refId-to-scalar all match cue); `71598c6`
`listFlattenAll` termination sound, classifier complete except the one unmigrated slice site.
**NEXT (ranked):** DISJ-CLOSEDNESS-EXCLUDED-ARM-LEAK (HIGH) → LIST-SLICE-EMBEDDED-CARRIER (HIGH) →
Phase B audit (still due) → LOW gaps (PATTERN-LABEL-ALIAS-SCALAR / UNREFERENCED-ALIAS / LIST-ISSORTED) →
PB-PERFGUIDE-STALE → PB-EVALBASE-SPLIT → deferred FDLIBM. **Alpha release HELD (attended).**

Prior HEAD: **DEF-FLATTEN-CLOSEDNESS-DISJ-REF residual (ref/scalar + nested arms) — LANDED 2026-07-13**
(its "LAST HIGH soundness leak closed" claim RETRACTED by the Phase A audit above). A def unifying a disjunction with a def-REF/scalar arm, or a NESTED
disjunction arm, flattened OPEN and leaked past closedness. The FILED premise (needs per-arm eval
`resolveDisjArm`, risks L-series) was FALSIFIED: kue's eval already composes `[closed-struct-arm |
open-ref-conj-arm]` correctly. Fix (`flattenConjDefRef`, `Kue/EvalBase.lean`): the cross-product
distribution splits each combo — all-struct-literal combos union+close (existing); a combo with a
NON-struct pick (`.refId`/scalar) emits an OPEN `.conj [own-literals, ...picks]` UNCHANGED, so eval
composes it (closed ref rejects a foreign field, open ref admits, scalar dies against the struct). The
own literal stays OPEN under the ref (closing it to `{a}` would reject a ref-allowed field). `isClosableDisj`
RETIRED for `isDistributableDisj` — a default-deny WHITELIST (struct/structComp/refId/scalar/nested-disj);
`error(...)`/comprehension/bound arms are NOT distributed (stay in `rest`), preserving the L-series
force-fold (`bug214b_disj_arm_*`) — the regression a naive "distribute any `.disj`" tripped.
`flattenNestedDisjArms` splices nested disjunction arms flat before the cross-product (also cured the
nested case's `ambiguous`). Seeds `def-flatten-closedness-disj-{ref,nested}` GRADUATED (RED→GREEN); 7
`Bug2xTests` theorems (both-direction guards). Pre-existing ref-composition field-order divergence
(values spec-correct) logged `cue-divergences.md#REF-OPEN-COMPOSE-FIELD-ORDER`. **ALL KNOWN SOUNDNESS
LEAKS NOW CLOSED.** `check.sh` green, zero L-series/Bug2 flips. **NEXT (ranked):** a two-phase **AUDIT is
DUE** (Phase B pending; this + LIST-ELEM-EQ + LIST-OPS-EMBEDDED-CARRIER are the un-audited soundness fixes
to cover) → LOW gaps **PATTERN-LABEL-ALIAS-SCALAR** / **UNREFERENCED-ALIAS** / **LIST-ISSORTED** →
**PB-PERFGUIDE-STALE** (LOW doc) → **PB-EVALBASE-SPLIT** nav-debt → DEFERRED float FDLIBM (F5→F1→F3,
chakrit's prioritization). **Alpha release HELD for chakrit (attended).**

Prior HEAD: **LIST-OPS-EMBEDDED-CARRIER + Phase B audit — list-carrier completeness BY CONSTRUCTION (LANDED
2026-07-13d).** The recurring "hand-enumerate list carriers, miss one" defect is designed out: every
list-carrier read in `Kue/Builtin.lean` now routes through the ONE classifier `listItems?` (`Kue/Value.lean`)
— `listConcat`/`listFlattenFuel`/`lenValue`/`openListOperand` directly; `listNestingDepth` DELETED, replaced
by `listFlattenAll` (WF recursion through `listItems?`, terminating via new `sizeOf_listItems?_lt` +
`List.sizeOf_lt_of_mem`). Falsified the filing's "must be a direct pattern arm" claim. Found+fixed 2 sites
beyond the filing (`lenValue`, `openListOperand` — the latter's miss broke every `list.*` on an embedded-list
operand). Seed `list-ops-embedded-sublist/` GRADUATED + expanded to 6 facets; cue agrees, no divergence.
Phase B: equality boundary (`BEq`/`structuralEq`/`eqUpToFieldOrder`) documented in `architecture.md` § 3, no
misuse; graph healthy; pre-existing `| _ =>` arms not re-filed (clean-is-clean). **NEXT (ranked):**
**DEF-FLATTEN-CLOSEDNESS-DISJ-REF residual** (HIGH — the LAST silent soundness leak; ref/scalar + nested
disjunction arms; needs shared `resolveDisjArm`) → LOW gaps **PATTERN-LABEL-ALIAS-SCALAR** /
**UNREFERENCED-ALIAS** / **LIST-ISSORTED** → **PB-PERFGUIDE-STALE** (LOW doc) → **PB-EVALBASE-SPLIT** nav-debt
→ DEFERRED float FDLIBM (F5→F1→F3, chakrit's prioritization). **Alpha release HELD for chakrit (attended).**

Prior HEAD: **LIST-ELEM-EQ — unified structural equality: open-tail-stripping + VALUE-BASED (LANDED 2026-07-13).**
Fixed the coupled list-equality cluster with ONE `structuralEq` (`Kue/Value.lean`) shared by list `==`,
struct `==`, `list.Contains`, and `list.UniqueItems` dedup: recursive open-tail stripping via `listItems?`
(a `.listTail` element equals its concrete prefix at every depth, through structs) + VALUE-BASED prim leaves
(`primStructEq`: int→float conversion per spec, floats scale-insensitive, `string`≠`bytes`) + order-independent
struct compare. **CRUX / REFRAME:** the slice's "make it type-STRICT" hypothesis was FALSIFIED by the CUE spec
(verified verbatim: numeric `==` converts int→float; list/struct equality is "recursively equal" reusing `==`).
So structural equality is VALUE-BASED, and cue v0.16.1's structural strictness (`[1]==[1.0]`→false,
`Contains([1],1.0)`→false, `UniqueItems([1,1.0])`→unique) is the STRUCT-EQ-LEAF-TYPESENSE cue bug already
adjudicated 2026-07-04. **LIST-CONTAINS-OPENTAIL-EQ ✅** (open-tail was the real bug — `listContains` used raw
`BEq`); **LIST-ELEM-EQ-NUMERIC-STRICT REJECTED** (kue's `[1]==[1.0]`→true was already spec-correct; the filing
mis-read cue as spec). Seed `list-contains-open-sublist` RED→GREEN (its `strict` case spec-corrected to
`intVsFloat: true`). Scalar `==` UNCHANGED (`1==1.0`→true, guard holds). New spec-correct cue divergences
(logged under STRUCT-EQ-LEAF-TYPESENSE): `Contains([[1]],[1.0])`→true, `UniqueItems([1,1.0])`→⊥. `check.sh`
fully green, zero flips. New theorems: `BuiltinTests` `list_contains_open_tail_*`+`_int_matches_float`+
`_string_not_bytes`; `FixtureTests` `uniqueitems_{float_scale,int_float}_dup_bottoms`. **NEXT (ranked):**
a two-phase **AUDIT is DUE** (Phase B pending per 2026-07-13 Phase A; this + DEF-FLATTEN-DISJ-REF + this
LIST-ELEM-EQ are the un-audited soundness fixes to cover) → LOW gaps **PATTERN-LABEL-ALIAS-SCALAR** /
**UNREFERENCED-ALIAS** / **LIST-ISSORTED** / **DEF-FLATTEN-CLOSEDNESS-DISJ-REF** (ref/scalar-arm + nested-disj
residual, `.known-red` seeds) → **PB-EVALBASE-SPLIT** nav-debt → DEFERRED float FDLIBM (chakrit's
prioritization). **Alpha release HELD for chakrit (attended)** — committed + pushed; release awaits your
say-so.

Prior HEAD: **DEF-FLATTEN-CLOSEDNESS-DISJ-REF — multiple-disjunction cross-product closedness (PARTIAL: multi-disj
LANDED 2026-07-13; ref/scalar-arm + nested-disj residual FILED).** Closed the multiple-disjunction residual
of the DEF-FLATTEN-CLOSEDNESS-DISJ silent-leak cluster. A def unioning its own struct literal across TWO+
closable disjunctions (`#X: {a:1} & (*{b:2}|{c:3}) & (*{d:4}|{e:5})`) hit the single-disjunction close
branch's `| _ => expanded` fall-through → flattened OPEN → defaults collapsed to one arm → SILENTLY exported
`{a,b,d,f}` (cue ⊥). Fix (`Kue/EvalBase.lean`): `disjArmCrossProduct` distributes the own-literal union
across the cross-product of every closable disjunction, closing each of the four combinations; a combination
is a default iff EVERY component arm is a default (product-of-defaults → `{a,b,d}`). Single disjunction =
one-list cross-product (identity) → parent behavior byte-unchanged. Wild `def-flatten-closedness-disj-multidisj
{,-select,-open}` (RED→GREEN + both-direction guards); `Bug2xTests` `defflatten_multidisj_*` (4 native_decide).
SPEC (core closedness), cue-correct, NO divergence. **Filed (RED-seeded, `.known-red`):** the two arm-RESOLUTION
residuals — **ref/scalar arm** (`{a:1} & ({z:9} | #Base)`, `.refId` arm fails `isClosableDisj`; needs
resolving the arm to its closed-or-OPEN field set, an eval risking the L-series/Bug2 suite; over-close hazard:
an OPEN `#Base:{b,...}` arm must stay open) and **nested disjunction arm** (`{a:1} & ({b:2}|({c:3}|{e:5}))`,
also kue `ambiguous` — a distinct disjunction-resolution issue entangled; needs the nested disjunction
flattened first). Follow-up: a shared `resolveDisjArm` (arm eval + nested flatten) feeding the cross-product.
Seeds `testdata/wild/def-flatten-closedness-disj-{ref,nested}/`. **NEXT (ranked):** the coupled LIST-EQUALITY
fix — **LIST-CONTAINS-OPENTAIL-EQ** (HIGH) + **LIST-ELEM-EQ-NUMERIC-STRICT** (MED), shared root: list/struct
element equality needs a strict, type-aware, open-tail-stripping recursive compare (fix TOGETHER) → a two-phase
**AUDIT is DUE** (Phase B pending per 2026-07-13 Phase A; several slices since) → LOW gaps
**PATTERN-LABEL-ALIAS-SCALAR** / **UNREFERENCED-ALIAS** / **LIST-ISSORTED** → **PB-EVALBASE-SPLIT** nav-debt →
the DEFERRED float FDLIBM campaign (chakrit's prioritization, not auto-scheduled). **Alpha release HELD for
chakrit (attended)** — commit pushed; release awaits your say-so. The ref/nested residual is a filed follow-up,
not a release blocker (the multi-disj leak is closed; the residuals are quarantined RED seeds).

Prior HEAD: **LIST-OPS-NESTED-OPENTAIL — nested open-tail sublists in `list.*` ops normalized to prefix
(LANDED 2026-07-13).** Closed the Phase A follow-up to LIST-OPS-PROBE: the open-tail→prefix rule reached
only TOP-level operands, so `list.Concat`/`FlattenN` on a NESTED open-tail sublist gave wrong values —
`Concat([[1,2,...],[3,4]])` ⇒ ⊥ (cue `[1,2,3,4]`), `FlattenN([[1,2,...],[3]],1)` ⇒ `[[1,2],3]` SILENT WRONG
(cue `[1,2,3]`). Fix (`Kue/Builtin.lean`): the two destructure sites (`listConcat.collect`,
`listFlattenFuel`) + the full-flatten fuel sizer (`listNestingDepth`) each gain a `.listTail inner _` arm
mirroring `.list inner` — a DIRECT pattern-match (not an `openListOperand` wrapper, which breaks Lean
structural-recursion termination since the exposed `inner` must be a pattern subterm). Per-function, NOT
blanket: Reverse/Take/Drop/Repeat/Slice treat a nested sublist opaquely and the manifest strips its `...` on
export (verified kue==cue), so untouched. Wild `list-fn-concat-open-sublist/` + `list-fn-flattenn-open-sublist/`
(RED→GREEN); `BuiltinTests` `list_builtins_normalize_nested_open_tail`; spec-gap `open-list-value-ops`
extended to nested position. NO cue divergence. **Filed (not fixed):** LIST-CONTAINS-OPENTAIL-EQ (HIGH,
quarantined `list-contains-open-sublist/` .known-red) — `list.Contains` uses raw `BEq` so an open-tail
element/needle mismatches its prefix (`Contains([[1,2,...]],[1,2])` kue false, cue true); needs a recursive
strict-leaf open-tail-stripping equality. LIST-ELEM-EQ-NUMERIC-STRICT (MEDIUM, PRE-EXISTING, surfaced en
passant) — `[1]==[1.0]` kue true, cue false (`concreteEq` leaks decimal-aware leaf eq into list equality).
**NEXT (ranked):** **DEF-FLATTEN-CLOSEDNESS-DISJ-REF** (HIGH closedness silent leak, the other Phase A
finding) → a two-phase AUDIT is DUE (Phase B pending per the 2026-07-13 Phase A; ~4 slices since) → LOW gaps
**PATTERN-LABEL-ALIAS-SCALAR** / **UNREFERENCED-ALIAS** / **LIST-ISSORTED** + the new
**LIST-CONTAINS-OPENTAIL-EQ** / **LIST-ELEM-EQ-NUMERIC-STRICT** → **PB-EVALBASE-SPLIT** nav-debt → the
DEFERRED float FDLIBM campaign (F5→F1→F3, chakrit's prioritization, not auto-scheduled). **Alpha release HELD
for chakrit (attended)** — the Phase A audit flagged NO release until this silent-wrong-value path was fixed;
THIS slice clears that specific blocker, but the alpha remains HELD for chakrit's say-so. Handoff: committed +
pushed, release awaits your say-so.

Earlier HEAD: **LIST-OPS-PROBE — differential probe of the list-operation value family; one wrong-value defect
family found+fixed, rest measured GREEN (LANDED 2026-07-13).** Probed slicing, indexing, `list.*` builtins,
comprehensions, list unification/defaults vs cue v0.16.1. **Measured GREEN:** indexing (in-bounds/oob→⊥/
neg→⊥/non-int→⊥/float→⊥/open-tail resolves-or-defers), comprehensions over open lists (`[for v in
[1,2,3,...]{v}]=[1,2,3]`, index/filter/empty/nested), list unification (`[1,2]&[1,2,3]`→⊥, `[...int]&[1,2]`
→`[1,2]`, closed&open), list-disjunction defaults (export forces the marked default identically — the
eval-display diff where kue prints `*a | b` and cue prints the selected default is presentation-only).
**Defect (found+fixed, bounded):** value ops on an OPEN-TAIL list `[a,b,c,...]` leaked a non-CUE residual.
The `[lo:hi]` slice operator and every `list.*` fn (`Slice`/`Take`/`Drop`/`Reverse`/`Sum`/…) destructured
only `.list`, so a `.listTail` operand fell to `unresolvedOrBottom` → `slice([1,2,3,...],1,2)` residual that
FAILED export as "incomplete value" where cue resolves on the concrete prefix. Kue already commits
(pre-existing, cue-matching) to `len([1,2,3,...])=3`, so prefix-treatment is FORCED by consistency, not
cue-chasing. Fix (`Kue/Builtin.lean`): `openListOperand` normalizes `.listTail items _`→`.list items`,
`evalListBuiltin` maps it over args, core `slice` gains a `.listTail` arm. Spec-SILENT → spec-gap
`open-list-value-ops` (`cue-spec-gaps.md`); matches cue, NO divergence. Wild `slice-open-tail-list/` +
`list-fn-open-tail/` (RED→GREEN); `SliceTests` `slice_open_tail_*`; `BuiltinTests`
`list_builtins_operate_on_open_tail_prefix`. **Filed (not fixed):** LIST-ISSORTED (LOW) —
`list.IsSorted`/`IsSortedFunc` unimplemented (comparator-struct eval, same corner as `list.Sort`/
`SortStable`; land together). **NO ACTIVE WRONG-VALUE BUGS REMAIN; list family now measured.**
**NEXT (ranked):** a two-phase AUDIT is now DUE (BINARY-CMP-BYTES + STRING-BYTES-PROBE + BOUND-ORDEREDPRIM
+ DEF-FLATTEN-CLOSEDNESS-DISJ + this = 5 slices since 2026-07-13 Phase A/B) → **float F1/F3/F5 FDLIBM**
(narrow slices unblocked; the large transcendental campaign flagged for chakrit's prioritization, not
auto-scheduled) → LOW gaps **PATTERN-LABEL-ALIAS-SCALAR** / **UNREFERENCED-ALIAS** / **LIST-ISSORTED** /
**DEF-FLATTEN-CLOSEDNESS-DISJ-REF** → **PB-EVALBASE-SPLIT** nav-debt. **Alpha release HELD for chakrit
(attended)** — a datestamped alpha is due; handoff: this slice is committed + pushed, release awaits your
say-so.

Prior HEAD: **DEF-FLATTEN-CLOSEDNESS-DISJ — CONFIRMED under-close, then FIXED (LANDED 2026-07-13).** A closed def
unioning its own struct literals THROUGH a disjunction conjunct (`#X: {a:1} & ({b:2}|{c:3})`) flattened
OPEN — the `.disj` conjunct failed `isUnionableDefValue`, so `ownLiteralUnion` never fired. Confirmed real
vs cue v0.16.1: `#X & {d:4}` kept both arms alive ("ambiguous value"), and with a default arm (`*{b:2}`)
SILENTLY exported `{a:1,b:2,d:4}` (leak). Fix (`flattenConjDefRef`, `Kue/EvalBase.lean`): gate admits a
`.disj` all of whose arms are `isUnionableDefValue` (`isClosableDisj`); the close branch DISTRIBUTES the
literal union across a single such disjunction, closing each arm as `closeLiteralUnion (literals ++ [arm])`
→ `.disj [{a,b}(closed), {a,c}(closed)]`; eval's meet distributes the use-site fields per arm. Pure-literal
path refactored to share `closeLiteralUnion` (byte-identical). Both-direction guards: `...`-arm stays OPEN,
default marker preserved per arm. 4 wild fixtures (`def-flatten-closedness-disj{,-select,-default,-open-arm}`).
`check.sh` GREEN, zero closedness/L-series/Bug2-6..12 flips. **Scoped-out (LOW follow-up):** ref-arm /
scalar-arm disjunction (`#X: {a:1} & ({b:2} | #Base)`) stays OPEN where cue closes it; multiple closable
disjunctions (cross-product) stay OPEN. File DEF-FLATTEN-CLOSEDNESS-DISJ-REF if prioritized.
**NEXT (ranked):** a two-phase AUDIT is now DUE (BINARY-CMP-BYTES + STRING-BYTES-PROBE + BOUND-ORDEREDPRIM
+ this = 4 slices since 2026-07-13 Phase A/B) → **float F1/F3/F5** (narrow, unblocked; large campaign flagged
for chakrit's prioritization, not auto-scheduled) → LOW gaps **PATTERN-LABEL-ALIAS-SCALAR** /
**UNREFERENCED-ALIAS** → **PB-EVALBASE-SPLIT** nav-debt. **Alpha release HELD for chakrit (attended)** — a
datestamped alpha is due; handoff: this slice is committed + pushed, release awaits your say-so.

Prior HEAD: **BOUND-ORDEREDPRIM — illegal bound-operand states now unrepresentable (LANDED 2026-07-13,
`7c8eedc`).** `boundConstraint` retyped from `(bound : Prim) (kind) (domain : NumberDomain)` to
`(bound : OrderedPrim) (kind)`. `OrderedPrim` = ordered subset of Prim (int/float/string/bytes) with
`NumberDomain` folded into the numeric arms ONLY — a null/bool operand and a domain-bearing string/bytes
bound are both structurally impossible. `OrderedPrim.ofPrim?` (null/bool → none) is the single trust
boundary; `toPrim` the inverse for compare/render. Shipped a 4-arm mirror (not the plan's 3-arm `number`
sketch) because `formatBoundOperand`'s int-vs-float render is observable. DELETED the subsumed runtime
guards: null/bool arms of `boundKindLabel`/`boundAdmitsKind`, the `number` sentinel + null/bool conflict
arms in `meetBoundPrim`/`meetKindWithBound`, null/bool→⊥ arms in `evalBoundOp`/`parseBoundOperand`.
PA-BOUND-DOMAIN-TYPE DISCHARGED. Behavior-preserving — whole suite green, ZERO flipped theorems (the
proof); +4 `native_decide` unrepresentability theorems in `BoundTests.lean`. No `cue` divergence, no spec
gap. **A two-phase AUDIT is now DUE** (this refactor + BINARY-CMP-BYTES + STRING-BYTES-PROBE = 3 slices
since the 2026-07-13 Phase A/B). (NEXT pointer superseded by the live HEAD above;
DEF-FLATTEN-CLOSEDNESS-DISJ has since LANDED.)

Prior HEAD: **STRING-BYTES-PROBE — differential probe of the bytes/string value family; one wrong-value
defect found+fixed, rest measured GREEN (LANDED 2026-07-13).** Probed ~40 minimal cases vs cue v0.16.1
across the gap corners (interpolation of every operand type, multiline `"""`/`'''`, unicode `len`
[cue counts BYTES — both = 6 on `"héllo"`/`"a😀b"`], string slice/index [both ⊥], string↔bytes boundary
[`string & bytes` ⊥; `bytes(x)`/`string(x)` NOT callable in cue], concat + `"ab"*3` repetition,
bounds/regex/disj/default). **Defect:** a bytes value interpolated into a STRING literal (`b: 'ab';
x: "\(b)"`) — cue `"ab"`, kue errored `incomplete value`. `classifyInterpolationPart`
(`Kue/EvalBase.lean`) classified every `.prim (.bytes …)` `.incomplete`. FIX (bounded, test-first):
bytes arm decodes `String.fromUTF8?` — valid UTF-8 → `.text`, invalid UTF-8 still defers (Kue's
validated-`String` can't hold non-UTF-8; cue lossily → U+FFFD on export — spec-gap
`bytes-interp-invalid-utf8`, deferring not fabricating). Wild fixture
`testdata/wild/bytes-interp-into-string/` RED→GREEN; `Tests.lean` `evalInterpolation` `#guard`s updated.
Interpolation INSIDE a byte literal (`'\(x)'`) still parse-errors "not supported yet" — separate,
already-tracked `byte-literal-interpolation` seed, untouched. **NO ACTIVE WRONG-VALUE BUGS REMAIN.**
**A two-phase AUDIT is DUE in ~1 slice** (last Phase A/B 2026-07-13; BINARY-CMP-BYTES + this probe are
the 2 slices since). **NEXT (ranked):** the AUDIT → **BOUND-ORDEREDPRIM** (LOW illegal-states, ~60-site
`OrderedPrim` tightening) → **float F1/F3/F5** (narrow, unblocked) → LOW gaps **PATTERN-LABEL-ALIAS-SCALAR**
/ **UNREFERENCED-ALIAS** / **DEF-FLATTEN-CLOSEDNESS-DISJ** (needs `wild/` repro first) → **PB-EVALBASE-SPLIT**
nav-debt. **Alpha release remains HELD for chakrit (attended)** — a datestamped alpha is due; handoff:
this slice is committed + pushed, release awaits your say-so.

Prior HEAD: **LET-CYCLE-ERROR — a pure-`let` reference cycle now ERRORS instead of collapsing to top
(LANDED 2026-07-12).** `let a = a` was kue top (`b: _`), now `reference "a" not found`; mutual
`let a = c; let c = a` now `cyclic references in let clause or alias` (cue v0.16.1). FIX: the
let-vs-field nature is read AT the depth-0 `slotVisited` cycle guard (`Kue/Eval.lean`) off the live
frame — `buildFrame`/resolution UNCHANGED. `cycleSlots`/`allLetCycle` (`EvalBase.lean`) classify the
detected cycle: entirely-`letBinding` slots ⇒ `.bottomWith [.letClauseCycle label isMutual]`
(`isMutual := len>1`), any field on the cycle ⇒ keep `truncate .top` (over-correction guard). Manifest
surfaces the reason (`letClauseCycleReason?`, `ManifestError.letClauseCycle`) as cue's load-error text.
Both directions pinned: `let a=x; x:a` and `x:x` STILL top; `let a=1; let b=a` STILL resolves. Seed
`let-self-cycle-error` GRADUATED; new fixtures `let-{mutual-cycle-error,arith-self-cycle-error,cycle-
through-field-top,chain-valid}`; 6 theorems in `EvalTests.lean`. **A two-phase AUDIT is now DUE** (3
slices since last audit: SELF-SELECT-CYCLE-CROSSFRAME, RESOLVE-DEDUP-MIRROR-GUARD, LET-CYCLE-ERROR).
**NEXT (ranked):** run the AUDIT (phase A code-quality → phase B architecture) → **BINARY-CMP-BYTES**
(LOW, kue bug, `bytesOp` threading) → **BOUND-ORDEREDPRIM** (LOW, illegal-states, ~60-site tightening)
→ **PATTERN-LABEL-ALIAS-SCALAR** (LOW) → **UNREFERENCED-ALIAS** (LOW) → **PB-EVALBASE-SPLIT** (cohesion
filler). **Alpha release remains HELD for chakrit (attended) — handoff: this slice is committed, not
pushed/released pending your say-so.**

Prior HEAD: **RESOLVE-DEDUP-MIRROR-GUARD — field-collapse decision single-sourced in `Lattice`; drift now
impossible by construction (LANDED 2026-07-12).** `canonicalFieldLayout` (Resolve, lexical layout) and
`canonicalizeFields` (EvalBase, eval frame) hand-copied the SAME duplicate-collapse decision
(first-occurrence keying + `mergeFieldClass.isSome` keep/append); they had to agree or refs dangle (the
SELF-CONJ-CYCLE-INDIRECT class) but nothing pinned it. FIX (structural hoist, behavior-preserving):
extracted the fold-step to `Lattice.mergeFieldLayoutInto (combine) : List Field → Field → Option (List
Field)` — both modules already import `Lattice` where `mergeFieldClass` lives, no cycle. EvalBase folds
it with `mergeUnevaluatedFieldValue` (definition-vs-`.conj`); Resolve folds it with identity-keep
`fun _ current _ => current`. `mergeUnevaluatedFieldInto` DELETED (its body was that specialization).
Drift dies by construction — one decision, two callers cannot disagree on which slots exist. `check.sh`
fully GREEN, ZERO fixtures/theorems flipped (true refactor). Belt-and-suspenders guard
`canonical_layout_label_mirrors_canonicalize_fields` (`ResolveTests.lean`, in the tripwire) pins the
label projection across a dup/dup-hidden/dup-of-def/triple-dup/dup-optional/class-mismatch battery.
`buildFrame`'s collapse layout is now STABILIZED for LET-CYCLE-ERROR. **A two-phase AUDIT is DUE in
~2 slices** (last full audit was Phase A/B 2026-07-12; RESOLVE-DEDUP-MIRROR-GUARD + SELF-SELECT-CYCLE-
CROSSFRAME since). **NEXT (ranked, Phase B head):** **LET-CYCLE-ERROR** (MED, missing load error;
`Resolve.buildFrame`/`.letBinding`, now on the stabilized collapse layout) → **BINARY-CMP-BYTES** (LOW,
kue bug, `bytesOp` threading) → **BOUND-ORDEREDPRIM** (LOW, illegal-states, ~60-site tightening) →
**PB-EVALBASE-SPLIT** (cohesion filler). **Alpha release remains HELD for chakrit (attended) — handoff:
this slice is committed, not pushed/released pending your say-so.**

Prior HEAD: **SELF-SELECT-CYCLE-CROSSFRAME — cross-frame selector reference-cycle → top FIXED (LANDED
2026-07-12).** `x:{a:1}; x:{a:x.a}` was kue `{x:{a:_|_}}`, now `{x:{a:1}}` (cue v0.16.1). The
reference-cycle→top class is now CLOSED across same-frame + indirect (index-layout) + cross-frame
(+ nested chains `x.a.b`). OBSERVED (instrument-first, trace-diff vs preamble): `x`'s
two-declaration value is a `.conj`; `x.a` forces the WHOLE enclosing `x` and re-enters its
in-progress body; `.conj` is not struct-like so `structStack` never guards it → fuel-deep bottom
(single-`.struct` bodies bottom via `structStack` as a false structural cycle). FIX (frame-stable
identity): resolve `x.label` to `label`'s slot in the LIVE enclosing frame — found by `pushFrame`'s
deterministic `(parentIds, fields)` frame identity (`enclosingSelfSelectId?`, chains via
`selectChainId?`; helpers in `EvalBase.lean`), inheriting the depth-0 `slotVisited ⇒ truncate .top`
rule; a cross-struct select whose frame isn't live falls through to force-then-select. SOUND vs a
label heuristic: frame keys include the field list, so `z:{a:x.a}` (label coincides with `x`'s)
resolves `x.a=1`, not self-truncate. Both-direction guards green: real conflict still ⊥
(`x:{a:x.a&2}`, deeper `x.a.b&2`); valid cross-frame select resolves (`y:{b:x.a}`). Seed
`self-conj-cycle-fieldsel` GRADUATED; new fixtures `self-select-{cycle-deeper,crossframe-valid,
cycle-deeper-conflict}`; 9 `self_select_*` pins in `EvalTests.lean`. **A two-phase AUDIT is now DUE**
(3 slices since last audit: DEF-FLATTEN-CLOSEDNESS, PATTERN-LABEL-ALIAS, SELF-SELECT-CYCLE-CROSSFRAME).
**NEXT (ranked):** run the AUDIT (phase A code-quality → phase B architecture) → **RESOLVE-DEDUP-MIRROR-GUARD**
(MED drift, structural hoist into `Lattice`, stabilizes `buildFrame` — LAND BEFORE LET-CYCLE-ERROR)
→ **LET-CYCLE-ERROR** (MED, `buildFrame`/`.letBinding`) → **BINARY-CMP-BYTES** (LOW) →
**BOUND-ORDEREDPRIM** (LOW) → PB-EVALBASE-SPLIT. **Alpha release remains HELD for chakrit (attended).**

Prior HEAD: **PATTERN-LABEL-ALIAS — pattern-constraint label aliases; struct bodies FIXED (LANDED
2026-07-12).** `[Name=string]: {n: Name}` now binds `Name` to each matched field's label string.
kue previously could not PARSE the `ident=` prefix. MECHANISM (reuses letBinding/lexical frames, no
new binding path): parse (`patternAliasHead?`, skips `==`/`=~`) desugars the alias onto the struct
constraint via `bindPatternAlias` — a non-output `letBinding ⟨name, Value.patternLabel name⟩`
prepended so ordinary resolution routes `Name` refs to the new placeholder leaf; the placeholder
survives eval unchanged and is substituted to the matched label at application
(`applyPatternToFieldWith` via `substPatternLabel`, names from the constraint's own top-level alias
bindings). New `Value.patternLabel` handled at EVERY match site (compiler-guided: Format/Manifest/
meet/Resolve/Parse/EvalBase/EvalOps/Eval). Covers multiple/nested + cross-scope/top+comparator
patterns/concrete-field/scope-non-leak; `[x=~…]` stays a regex pattern. Seed
`testdata/wild/pattern-label-alias/` RED→GREEN; 10 theorems `Kue/Tests/PatternAliasTests.lean`.
SPLIT: non-struct constraint body (`[Name=string]: Name`, valid in cue → value) bottoms in kue
(nowhere to host the letBinding) — filed **PATTERN-LABEL-ALIAS-SCALAR** (LOW; `cue-divergences.md`;
fix = synthetic resolve+eval frame). (NEXT ranking superseded by the current HEAD block above;
SELF-SELECT-CYCLE-CROSSFRAME has since LANDED and its seed graduated.)

Prior HEAD: **DEF-FLATTEN-CLOSEDNESS — multi-conjunct def flattened OPEN, dropping closedness; FIXED
(LANDED 2026-07-12). Flatten/closedness cluster soundness CLOSED.** A CLOSED def unioning its OWN struct
literals (`#X: {a:1} & {b:3}`) leaked an undeclared use-site field (`#X & {c:4}` ⇒ kue `{a:1,b:3,c:4}`;
cue v0.16.1 rejects `c`). ROOT: `flattenConjDefRef` (`Kue/EvalBase.lean`) closed the flattened literals
only when `isDefinition && (isSelfRef || inCycle)` — the own-literal-union shape is neither, so the split
literals flattened OPEN and unioned into the use-site meet un-closed. FIX: widened `close` with an
`ownLiteralUnion` disjunct — fires when `cs.any isUnionableDefValue` AND every conjunct is either a
self-ref `.refId` (this depth-0 slot) or an `isUnionableDefValue` literal (i.e. the def's own literals,
NO cross-def ref composition); reuses the Bug2-12b union-then-close-once path. A def EXTENDING a ref
(`#LS: #Base & {extra}` — a cross-def `.refId` conjunct) does NOT fire it, staying on the OPEN-extension
fold (Bug2-6..9) — proven by the `defflatten_open_extension_still_admits` guard. Wild seed
`testdata/wild/def-flatten-closedness/` (RED→GREEN) + 9 `native_decide` both-direction guards
(`Bug2xTests.lean` `defflatten_*`: reject own-union extra/conflict/nested/closed-base-ext; admit
base/redeclare/opentail/open-extension/single-decl). kue == cue v0.16.1 on every swept variant; no
divergence. `check.sh` fully green; Bug2-6/2-7 + L-series + mutual/multi-ref closedness suites unflipped.
**NEXT (ranked — PIVOT to breadth, the flatten/closedness cluster is closed):** remaining scoping bugs
**PATTERN-LABEL-ALIAS** / **LET-CYCLE-ERROR** (MED) → **SELF-SELECT-CYCLE-CROSSFRAME** (MED, cross-frame
selector cycle, `testdata/wild/self-conj-cycle-fieldsel/` `.known-red`) → **UNREFERENCED-ALIAS** (LOW) →
**BOUND-ORDEREDPRIM** / **BINARY-CMP-BYTES** (LOW) → F1/F3/F5 float → LOW audit findings (PA-ESC-2 /
PA-SUB-4 / PA-TT-5 / PB-RELEASE-3 / PB-TESTORG-4 + the new PB module-split findings). A **two-phase AUDIT
is DUE in ~2 slices**. The **alpha release remains HELD for chakrit (attended)** — see the release note below.

Prior HEAD: **SELF-CONJ-CYCLE-INDIRECT — indirect reference-cycle wrong-value bug; index-layout shapes FIXED
(LANDED 2026-07-12). Indirect cycle class CLOSED (dominant root); one distinct sub-root split out.**
Instrument-first OBSERVED **two roots**, refuting Phase B's "two shapes, ONE root (thread `visited` through
`.conj`)" design. ROOT #1 (closed): resolve/eval index-layout mismatch — `resolveStructRefs`/`buildFrame`
indexed the RAW duplicate-bearing field layout while the evaluator indexes the DEDUPLICATED layout
(`canonicalizeFields`); collapsing a duplicate shifts later fields' indices down, so a forward reference
across the collapse (`x:1; x:y; y:1`; also a PLAIN sibling `x:1; x:1; y:5; z:y`) kept a stale index and
dangled into `unresolvedBinding` → `meet(concrete,⊥)=⊥`, BEFORE the existing `slotVisited⇒truncate .top`
guard could apply. `visited` was already threaded — Phase B misdiagnosed. FIX: `buildFrame` (`Kue/Resolve.lean`)
now indexes `canonicalFieldLayout fields` (class-level mirror of `canonicalizeFields` via `mergeFieldClass`;
imported `Kue.Lattice`), so resolve+eval agree by construction. Shapes closed: dupfield + sibling
(`x:1; x:y&int; y:x`). `valueMentionsSlotAtDepth` NOT removed (handles a nested-self-ref burial the fix
doesn't touch — retracts the PB-FOLD-PLACEMENT "may be removed" note). ROOT #2 (split out): shape 2
`x:{a:1}; x:{a:x.a}` is a cross-frame selector reference-cycle (`x.a` forces the whole enclosing struct via a
depth-1 self-ref, and the frame-relative `visited` resets across the frame → structural-cycle bottom instead
of ref-cycle top) — re-filed **SELF-SELECT-CYCLE-CROSSFRAME (MED)**, quarantined
`testdata/wild/self-conj-cycle-fieldsel/` `.known-red`. 6 wild seeds (5 GREEN incl. both-direction guards:
real conflict still ⊥, valid indirect resolve still resolves; 1 known-red) + 6 `native_decide` pins in
`EvalTests.lean`. `check.sh` fully green, zero fixtures/theorems flipped (cycle-detection core intact).
**NEXT (ranked):** **DEF-FLATTEN-CLOSEDNESS** (MED, now stands ALONE on `flattenConjDefRef` — the prior
"coordinate with the cycle fix" coupling is VOID, cycle fix landed in `Resolve.lean`) → remaining scoping
seeds **SELF-SELECT-CYCLE-CROSSFRAME** / **PATTERN-LABEL-ALIAS** / **LET-CYCLE-ERROR** (MED) →
**UNREFERENCED-ALIAS** (LOW). A **two-phase AUDIT is DUE** (≥5 slices since last: BINARY-CMP-OPERAND,
BOUND-OPERAND-CLASSIFY, SCOPING-PROBE, SELF-CONJ-CYCLE, SELF-CONJ-CYCLE-INDIRECT). Then the **DUE alpha
release** (HELD for chakrit — attended; see below). Then BOUND-ORDEREDPRIM / BINARY-CMP-BYTES / F1/F3/F5 /
LOW audit findings.

Prior HEAD: **SCOPING-PROBE — scoping / reference-resolution surface MEASURED, four defects seeded (2026-07-12).**
Systematic differential vs cue v0.16.1 over lexical scoping + reference resolution. Clean majority PINNED
(6 byte-identical `testdata/export/scoping_*.{cue,json}`: forward `let`→`let`/`let`→field visibility,
comprehension-var nested shadow, hidden-field ref scope, field value alias `X.b`, reducible field
self-cycle→top `x: x & {a:1}`⇒`{a:1}`). **Four RED defects seeded (`.known-red`, all filed in plan.md
§ SCOPING/REFERENCE-RESOLUTION PROBE):** (1) **SELF-CONJ-CYCLE (HIGH, wrong value)** — `x:1; x: x & int`
⇒ kue `_|_`, cue `{x:1}` **[✅ FIXED — see HEAD; root was `flattenConjDefRef` re-burying the ref, not the
merge path]**.
(2) **LET-CYCLE-ERROR (MED, too lenient)** — `let a = a` / mutual let cycles ⇒ cue errors, kue collapses to
top; `buildFrame` erases `.letBinding` so a struct-level `let` self-resolves like a field. (3)
**PATTERN-LABEL-ALIAS (MED, parse+feature)** — `[Name=string]: {n: Name}` unparseable (`parsePatternField`,
`Kue/Parse.lean:1788`); cue binds the label. (4) **UNREFERENCED-ALIAS (LOW, missing validation)** — `a: X=1`
unreferenced ⇒ cue errors, kue accepts. Spec-gap SELF-CYCLE-ARITH-RENDER recorded (`a: a+1` kue `_+1` vs
cue `a+1`, display-only). No product-code change (measurement slice). Committed on `main`.
🚨 **ALPHA RELEASE DUE (attended action at this checkpoint):** last cut `v0.1.0-alpha.20260707.1`; major work
landed since (F2 IEEE-float kernel, F4 float form, operand-typing soundness cluster, MANIFEST-FIELDCOUNT,
this probe). Recommend `scripts/release.sh` (+ `release-linux.sh`) at the next clean point — attended.
**NEXT (ranked):** the four seeded scoping fix-slices — **SELF-CONJ-CYCLE** first (HIGH, wrong value; trace
the merged-field self-cycle guard) → **PATTERN-LABEL-ALIAS** / **LET-CYCLE-ERROR** (MED) → **UNREFERENCED-ALIAS**
(LOW). Also remaining: structural-cycle spot-check (cycle-through-comprehension / disjunction-guarded);
**BOUND-ORDEREDPRIM** (LOW type-tightening), **BINARY-CMP-BYTES** (LOW); F1/F3/F5 float; LOW audit findings
(PA-ESC-2 / PA-SUB-4 / PA-TT-5 / PB-RELEASE-3 / PB-TESTORG-4).

Prior HEAD: **BINARY-CMP-OPERAND — ordered-comparison operand-typing soundness FIXED (LANDED 2026-07-12).**
`evalPrimitiveOrdering`'s retain-everything catch-all accepted a ground non-scalar in `< <= > >=` as
incomplete (`1 < [1,2]`, `{a:1} > 3` retained) where cue v0.16.1 errors. Split into
`.incomplete,_`/`_,.incomplete => .binary` (abstract-wins retain) BEFORE `.nonScalar,_`/`_,.nonScalar =>
.bottom` — ⊥ only when BOTH operands decided + one non-ordered; abstract on either side retains
(`[1,2] < a`, a abstract, KEPT — cue-confirmed). Matrix measured vs cue: cross-family ground pairs ⊥,
same-type bool/null/list/struct ⊥, ordered-comparable compute, abstract retains. EQUALITY left untouched
(total across types: `1==[1,2]`⇒false, `1!=[1,2]`⇒true). 2 wild fixtures RED→GREEN
(`binary-cmp-{list,struct}-operand`) + 7 EvalOpsTests theorems (⊥ + both-dir retain + 2 equality).
**Operand-typing soundness cluster is now CLOSED** — unary bound/regex/arith (BOUND-OPERAND-CLASSIFY)
AND binary comparison (this) both sound; the "flagged sibling follow-up" is discharged.
**Measured-but-not-fixed:** bytes ordered comparison `'a' < 'b'` ⇒ cue `true`, kue `_|_` — a kue BUG
(not a divergence), filed as **BINARY-CMP-BYTES (LOW)** in plan.md (add `bytesOp` across the four call sites).
**NEXT (ranked, PIVOT AWAY from operand-typing):** remaining core probes — **structural cycles**
(cycle-through-comprehension, disjunction-guarded cycles) and **scoping/reference-resolution** (shadowing
across `let`/field/comprehension-var/alias, hidden-field scope); then **BOUND-ORDEREDPRIM** (LOW
type-tightening, ~60-site `OrderedPrim` retype) and **BINARY-CMP-BYTES** (LOW); then F1/F3/F5 float; then
LOW audit findings (PA-ESC-2 / PA-SUB-4 / PA-TT-5 / PB-RELEASE-3 / PB-TESTORG-4).

Prior HEAD: **BOUND-OPERAND-CLASSIFY — soundness regression FIXED (LANDED 2026-07-12).** Split
`ScalarOperandClass.defer` into `.incomplete` (retain the residual `.unary`) vs `.nonScalar`
(`.list`/`.listTail`/`.embeddedList`/`.struct`). `evalBoundOp`/`evalRegexMatchOp`/`evalNumPos`/
`evalNumNeg` now ⊥ a ground list/struct (was fabricating `<[1,2]`/`<{a:1}`/`=~[1]`/`-[1,2]`);
`evalNeOp` retains (`.nonScalar` arm == `.incomplete` arm); `.top`/`.disj`/`.kind`/abstract-constraints
stay `.incomplete` (`<_`, `<(1|2)` RETAINED). 4 wild guards RED→GREEN + 13 EvalOpsTests theorems
(list/struct/embeddedList ⇒ ⊥ across the four ops, closing the `.bool`-only coverage gap; both-direction
retain guards for neOp/top/disj). `=~5` micro-divergence logged in cue-divergences.md. PA-BOUND-GROUND
discharged. **NEXT (ranked): `BOUND-ORDEREDPRIM` (LOW)** —
`OrderedPrim` bound-operand retype (~60-site refactor; complements, does NOT subsume, the classifier).
Then the flagged binary-comparison sibling (`1 < [1,2]` retains where cue errors — same class, different
path, filed by Phase B) [DISCHARGED: BINARY-CMP-OPERAND ✅ LANDED 2026-07-12, see HEAD above]; remaining
core probes (structural cycles, scoping); F1/F3/F5; LOW audit findings
(PA-ESC-2 / PA-SUB-4 / PA-TT-5 / PB-RELEASE-3 / PB-TESTORG-4).
Prior HEAD (last CODE slice): **PATTERN-BOUND-OPERAND — comparator bounds over any ordered type (LANDED 2026-07-12).**
Comparator bounds (`< <= > >= != =~`) now apply to ANY ordered type and to non-literal operands;
BOTH red seeds `pattern-bound-{string,reference}-operand` GRADUATED. `boundConstraint`'s operand
generalized `DecimalValue → Prim` (arity unchanged → ~30 wildcard match sites untouched); one total
`primOrdCompare?` (+ `BoundKind.admitsPrim?`) drives every bound comparison — numeric decimal, string
lexical by code point (`charsLt`), bytes by byte order (`bytesLt`). `domain` is numeric-only now (inert
`number` sentinel for string/bytes; family fixed by operand kind via `boundKindLabel`/`boundAdmitsKind`).
**Facet 2:** `UnaryOp` gained `boundOp`/`neOp`/`regexMatchOp`; parser lowers a literal operand
immediately, emits a deferred `.unary … operand` for a reference/call (`>k`, `{[=~_re]:int}`, `<len(x)`),
which `evalUnary` lowers to the concrete validator once ground (per CUE grammar `unary_op = … | rel_op`).
Byte-parity with cue v0.16.1: `<"m" & "apple"`→`"apple"`, `string & <"m"`→`<"m"`, `>"a" & >"m"`→`>"m"`,
`bytes & <'m'`→`<'m'`, `=~"^a" & <"m"`/`<"m" & !="a"` conjoin, `>k & "zebra"`→`"zebra"`; `int & <"m"` /
`>5 & >"m"`→⊥ (kue's terser `_|_`). Numeric bounds unchanged. Theorems: `BoundTests` ordered-type section
+ `EvalOpsTests` deferred-lowering section. NOT a cue-divergence (cue was spec-correct). Docs: plan.md
(✅ LANDED, both facets), compat-assumptions.md (bound repr rewritten), implementation-log. `check.sh`
GREEN, committed on `main`.
**Next (ranked):** remaining core-conformance probes — **structural cycles** (spot-check Bug2x for
cycle-through-comprehension / disjunction-guarded cycles), **scoping/reference-resolution** (shadowing
across `let`/field/comprehension-var/alias, hidden-field scope); then float follow-ups **F1**
(`math.Log1p`/`Expm1`) → **F3** (trig) → **F5** (`text/template` float render + `math.Float64bits`); then
LOWs PA-ESC-2 / PA-SUB-4 / PA-TT-5 / PB-RELEASE-3 / PB-TESTORG-4.
Prior HEAD CORE-CONFORMANCE-PROBE below.

## Prior HEAD — CORE-CONFORMANCE-PROBE — pattern-constraint core surface MEASURED (LANDED 2026-07-12).
Bounded differential hunt (~30 cases) over pattern constraints (`[pattern]: constraint`), the
least-recently-probed flagged core area (structural cycles are heavily covered by `Bug2xTests`;
closedness/comprehensions probed 2026-07-04). **Surface is CONFORMING** — regex label filtering,
overlapping-pattern constraint INTERSECTION (incl. comparator-bound values: `[=~"a"]:<10 &
[=~"b"]:>5` meets to `<10 & >5` on a doubly-matched field), recursive patterns, unification-
introduced patterns, disjunction-valued patterns — all byte-identical to cue v0.16.1. Now MEASURED
+ pinned: `testdata/export/pattern_constraints.{cue,json}` + 6 `native_decide` in `ClosednessTests`
(pattern-constraint conformance probe section). **ONE gap found (NEW facet of an already-filed
bug):** a LITERAL string/bytes bound operand (`x: <"m"`, `{[>"m"]: int}`, `>='a'`) fails to parse
("expected number digits") — `parseBoundValue` is numeric-literal-only and `boundConstraint` carries
`DecimalValue` (numeric by construction). SAME root cause as the filed **PATTERN-BOUND-REF-OPERAND**
(reference operands); both land together via the one core change (generalize bound operand →
`Prim`/expr + lexical string/byte-order compare in meet/order/manifest). Red-seeded
`testdata/wild/pattern-bound-string-operand/` (`.known-red`). NOT a cue-divergence (cue spec-correct).
No product-code change. Docs: plan.md (PATTERN-BOUND-REF-OPERAND facet + measured record),
implementation-log. `check.sh` GREEN, committed on `main`.
**Next (ranked):** remaining UNMEASURED core areas to probe — **structural cycles** (spot-check the
Bug2x coverage for gaps in cycle-through-comprehension / disjunction-guarded cycles), **scoping/
reference-resolution** (shadowing across `let`/field/comprehension-var/alias, hidden-field scope);
then the filed **PATTERN-BOUND-{REF,STRING}-OPERAND** core fix (attended, broad — generalizes the
bound operand, graduates BOTH red seeds); then float follow-ups **F1** (`math.Log1p`/`Expm1`) → **F3**
(trig) → **F5** (`text/template` float render + `math.Float64bits`); then LOWs PA-ESC-2 / PA-SUB-4 /
PA-TT-5 / PB-RELEASE-3 / PB-TESTORG-4.
Prior HEAD PA-FLOAT-TEST-6 below.

## Prior HEAD — PA-FLOAT-TEST-6 — permanent guards for the F2 kernel's hardest boundaries (LANDED 2026-07-12).
Turned the three UNPINNED adversarial boundaries (ephemeral in the out-of-tree 343-case Go battery) into
permanent committed guards: +20 `native_decide` theorems in `StrconvTests.lean`. Kernel-direct on
`decimalRatioToFloat`/`decimalToFloat`/`roundToSig` (localize a regression) + end-to-end `call` vs the cue
oracle. All expected values adjudicated against Go `strconv` AND cue v0.16.1 — **no kernel bug** (GREEN
first try). (1) float64 overflow half-even midpoint `(2^54−1)·2^970` ties-to-even ONTO inf, `−1` stays
maxfloat; (2) float32 overflow tie `(2^25−1)·2^103`→inf, `1e39`/`3.5e38`→`+Inf`, `-1e39`→`-Inf`;
(3) fixed-prec carry-growth `99.995`→"100.00", `0.9995`→"1.00", `999.5`→"1000", + `9.995`→"9.99" (nearest
double 9.9949… is BELOW 9.995, so NO carry — Go rounds the EXACT value). Docs: plan.md (✅ LANDED),
implementation-log. `check.sh` GREEN, committed on `main`.
**Next (ranked, unchanged):** **F1** (`math.Log1p`/`Expm1`, float64 via `Kue/Float.lean` + shortest-`'e'`
anchor, smallest F-follow-up) → **F3** (trig `Sin`/`Cos`/`Tan`/…) → **F5** (`text/template` float-in-data
render + `math.Float64bits`) → remaining LOWs: PA-ESC-2 (shared simple-escape table, `Parse.lean` DRY),
PA-SUB-4 (`net.IPv4()⊑net.IP()` subsumption), PA-TT-5 (template fuel-bound proof), PB-RELEASE-3
(`release.sh:43` CPU-cap bypass), PB-TESTORG-4 (BuiltinTests/TwoPassTests split).
Prior HEAD STDLIB-FLOAT-F2 below.

## Prior HEAD — STDLIB-FLOAT-F2 — the IEEE binary64/32 float kernel (LANDED 2026-07-12).
New leaf `Kue/Float.lean` (imports `Kue.Decimal`; built via `Kue.Builtin`). Finite floats modelled
EXACTLY as `BinFloat = (-1)^neg · mantissa · 2^binExp` — big-integer arithmetic, NO hardware `Float`.
Three kernels: `decimalToFloat` (correctly-rounded decimal→binary, round-half-to-even, overflow→err /
underflow→±0 / subnormal re-round), `shortestDigits` (Burger–Dybvig shortest-round-trip; even-inclusive
boundary, carry trailing-zero trim — the `1e23` even-boundary case), `exactDigits`+`roundToSig`
(fixed-prec rounds the EXACT finite decimal). `fmtE`/`fmtF`/`fmtG` = Go `strconv` byte-for-byte, verbs
`e E f F g G`, shortest-`'g'` switch `eprec = 6` (cue's linked Go, NOT the old `21`). Wired
`strconv.ParseFloat(s,{32,64})` (stores shortest-`'e'` = cue's `apd.SetFloat64` anchor → `ParseFloat("100")`
renders `1E+2`) + `strconv.FormatFloat(f,verb,prec,{32,64})` into `.strconv`. Deferred: verbs `b`/`x`/`X`,
bitSize∉{32,64}. Negative-zero renders `0` (divergence logged). Validated 343 kernel + 300 random CLI
cases byte-identical to Go/cue. Fixture `testdata/export/strconv_float`; theorems `parsefloat_*`/
`formatfloat_*` in `StrconvTests.lean`. Docs: plan.md (F2 ✅ + F1/F3/F5 UNBLOCKED), cue-spec-gaps
(STDLIB-FLOAT-F2), cue-divergences (-0), compat-assumptions §Numeric, implementation-log. `check.sh` GREEN.
**F2 UNBLOCKS F1/F3/F5 — all now schedulable.** Committed on `main`.
**Next (ranked):** the F2-unblocked float wirings are now the high-leverage frontier — **F1**
(`math.Log1p`/`Expm1`, float64 via `Kue/Float.lean` + shortest-`'e'` anchor, smallest), **F3** (trig
`Sin`/`Cos`/`Tan`/… in float64), **F5** (`text/template` T3 float-in-data render + `math.Float64bits`).
Then the remaining LOW audit findings: PA-ESC-2 (shared simple-escape table, `Parse.lean` DRY),
PA-SUB-4 (`net.IPv4()⊑net.IP()` subsumption, `Order.lean`), PA-TT-5 (template fuel-bound proof),
PB-RELEASE-3 (`release.sh:43` CPU-cap bypass), PB-TESTORG-4 (BuiltinTests/TwoPassTests split, under cap).
Rank: F1 first (unblocked, small, exercises the new kernel end-to-end); F3/F5 next; LOWs after.
Prior HEAD STRINGFORMAT-LEAF below.

## Prior HEAD — STRINGFORMAT-LEAF — NetAddr fixed-width + StringFormat leaf (PA-NET-1 + PA-SF-3 + PB-SF-3)
Two 2026-07-12 audit findings, one refactor, behavior-conserving. (1) `NetAddr.v6` retyped
`List UInt8 → Vector UInt8 16` (`Kue/Net.lean`): 16-byte width now a TYPE invariant, so every `netIs*`
classifier indexes `bs[i]` (literal <16, total) — all `bs.getD i 0` value-fallbacks gone. Smart ctor
`mkNetAddrV6?` is the single trust boundary refining `finalizeIPv6`'s exactly-16 list into the vector;
`parseNetAddr?` v6 arm `.bind`s it. `v4` carrier already tight (4 fields), untouched. (2)
`stringFormatValid` extracted from `Time.lean` into new leaf `Kue/StringFormat.lean` (imports `Time`+`Net`
as siblings); `Time.lean` now imports only `Value` — **`Time→Net` edge DELETED**; `Lattice`/`Order` swap
`import Kue.Time`→`import Kue.StringFormat`. New theorems `v6_width_by_construction`/`v6_embedded_width`/
`mkV6_{accepts_16,rejects_short,rejects_long}` in `NetTests`; +`#check @` anchor. All existing theorems
conserved. Docs: plan.md (PA-NET-1/PA-SF-3/PB-SF-3/PB-DOCGRAPH-2 ✅ + edge-list rewrite), architecture.md
§5 (5 stdlib leaves, `Time→Net` deleted), implementation-log. `check.sh` GREEN. Committed on `main`.
**Next (ranked): remaining LOW audit findings — (a) PA-ESC-2 shared simple-escape table
(`decode{String,Byte}Escape` DRY, `Parse.lean`); (b) PA-SUB-4 stringFormat subsumption precision
(`net.IPv4()⊑net.IP()` class hierarchy, `Order.lean`); (c) PA-TT-5 template fuel bound proof; (d)
PB-RELEASE-3 `release.sh:43` bypasses `./lake` CPU cap; (e) PB-TESTORG-4 BuiltinTests/TwoPassTests split
(both under cap, no urgent seam). OR the leverage float item F2 (IEEE float64 kernel — unblocks
`strconv.FormatFloat`, `text/template` T3, `Log1p`/`Expm1`, trig; F1/F3/F5 gate on it).** Rank: F2 is
highest-leverage but largest; among LOWs, PA-ESC-2 (real DRY, small) and PA-SUB-4 (precision) first.
Prior HEAD PB-TESTORG-1 below.

## Prior HEAD — PB-TESTORG-1 — split oversized `EvalTests.lean` under the 1800-line test-health cap
`EvalTests.lean` was 1792 lines (8 under cap, one slice from a hard gate failure). Split by THEME into
four sibling modules, verbatim move: `EvalTests.lean` (494 — refs/memo/structural-cycles/terminating-
disjuncts/embedding carriers), `EvalExprTests.lean` (581 — arithmetic/comparison/logical/unary/regex
eval, ref cycles, value aliases, default-disjunction resolve, F1 mark algebra, disj-meet sweep),
`EvalOpsTests.lean` (488 — float mul/div/add-sub, operator domain E#4, scalar op pins),
`EvalStructEqTests.lean` (283 — sibling merge, lazy meet, struct/list equality). 231 theorems
conserved exactly (65+62+76+28); all three new modules registered in `Kue/Tests.lean`; each carries a
`#check @` tripwire. `check.sh` GREEN (`test health ok`, full build). NO product-code change. Discharges
B-4; BuiltinTests(1669)/TwoPassTests(1542) deferred to PB-TESTORG-4 (under cap, no urgent seam).
Committed on `main`. Prior HEAD STDLIB-FLOAT-F4-DIV below.

## Prior HEAD — STDLIB-FLOAT-F4-DIV — closed the division half of F4
**STDLIB-FLOAT-F4-DIV — closed the division half of F4 (apd result-exponent
preservation for float `/`).** An exact-terminating float quotient now renders in cue's GDA ideal
form (`6e2 / 3 → 2.0e+2`, was `200.0`; `1e34/1 → 1e+34`) instead of the fully-expanded decimal;
VALUE was always correct, only FORM diverged. `apdDivide?` (`Kue/Decimal.lean`) + `removeNatFactor`;
`evalDecimalDivide?` tries the exact apd path first, falls to the unchanged 34-digit
`divideDecimalRational?` for non-terminating / >34-sig quotients. NO `DecimalValue` core change.
Rule (spec-silent DISPLAY → cue-compat, pinned via `cue export --out json`): for exact `±m·10^k`
(minimal, `d=digits(m)`), an integer value (`k≥0`) with adjusted exp `k+d−1 ≤ 32` gains one trailing
zero `(10m, k−1)` forcing `.0`/`X.0e+n`; else keep `(m,k)`; zero clamps ideal exp to `0`/`−1`.
Validated 3000+ random cases, zero mismatch. `EvalTests` div theorems → `formatValue` idiom; FORM pin
`float_div_apd_ideal_exponent` in `FloatTests`; wild fixture `float-apd-division-exponent/` (RED→GREEN).
Docs: plan.md (F4 ✅), cue-spec-gaps.md STDLIB-FLOAT-F4 (rule corrected + `/` landed), compat-assumptions.md.
Committed on `main`. **Next: F1–F5 residuals — F2 (IEEE float64 kernel) is the leverage item (unblocks
`strconv.FormatFloat`, `text/template` T3, `Log1p`/`Expm1`, trig), but gated per plan; F1/F3/F5 gate on F2.**
Prior HEAD DOCS-CLEANUP below.

## Prior HEAD — DOCS-CLEANUP — the docs now state a single goal
A correct, spec-conformant CUE implementation across the whole language + stdlib
surface (chakrit, 2026-07-12). CLAUDE.md § Project carries the north-star (spec-conformance is
the goal; `cue` is a fallible reference; no config corpus is a target/gate/floor/priority). Swept
every cert-manager / argocd / canary / prod9-as-goal reference out of the live docs — deleted
outright, never negated: retired the ~90%-dead `spec-conformance-audit.md` (its 3 live rows are in
plan.md, which now owns the ranked backlog); deleted plan.md's real-app-status block and reframed
the L1–L5 section as construct-level semantic fixes; genericized the perf / failure-modes /
slice-loop guides (kept the lessons, dropped the anecdotes); cleaned lean4-guide, compat-assumptions,
architecture, cue-spec-gaps, cue-divergences. `implementation-log.md` + `decisions/` left as
immutable history. **OPEN for chakrit (explicit go needed — working test infra, not docs):** remove
the `check-realworld.sh` real-config gate + `testdata/realworld/cert-manager/` fixture, the last
cert-manager tie. **Next: resume spec-conformance / robustness work — the language-surface coverage
the audits flagged unmeasured (comprehensions, closedness, pattern constraints, structural cycles,
scoping) + the F1–F5 float residuals, prioritized by conformance not usage.** Prior HEAD
MANIFEST-FIELDCOUNT below.

## Prior HEAD — MANIFEST-FIELDCOUNT — decouple manifest fuel from sibling breadth (HIGH audit fix)

`kue export` failed ENTIRELY on any struct with ≥99 top-level fields
(`incomplete value`), on trivial plain-int input. Root cause (by observation, NOT the
`manifestFuel=100` coincidence): `manifestFieldsWithFuel`/`manifestItemsWithFuel` (`Kue/Manifest.lean`)
peeled one fuel unit per SIBLING — the field at list-index `i` manifested at fuel `100-2-i`, hitting
0 (`.incomplete`) at `i=98` flat / `i=96` nested (the two-field offset = the enclosing struct's two
units). 500-field struct failed identically at index 98 → a constant bump is a pure cliff-move
(banned). Fuel must bound nesting DEPTH, not breadth. Fix: thread `fuel` UNCHANGED across siblings
(mirrors `evalFieldRefsListWithFuel`); only `manifestWithFuel`'s `fuel+1` descent into a value spends
a unit; termination via explicit lexicographic `(fuel, phase, len)`. Breadth now free (99/500/5000/
arbitrary counts byte-match `cue export --out json`); depth still capped at 100 (the legit totality
bound, shared with eval — noted, not the bug). WF recursion breaks `rfl`, so ~30 manifest `rfl` tests
migrated to the `(… == …) = true := by native_decide` BEq idiom (house standard; `Value` omits
`DecidableEq` by design) — whole surface in-slice (ManifestTests 23, FixtureTests 4, Closure/Eval 1
each). Wild fixtures `wide-struct-{export,nested,large}/` (RED→GREEN). Folded in a LOW audit
test-guard: `eval_add_context_rounding_half_up_even_tie` (apd half-UP tie rule, both signs, prior
coverage zero). **Class note: field-count/fuel cliffs — any fuel walk that decrements per list
element (not per depth) has this bug; the manifest was the last such site (eval was already correct).**
Committed on `main`, not pushed. **Next: F4-division form (derived rule ready in cue-spec-gaps.md),
then F1–F5 residuals.** Prior HEAD STDLIB-FLOAT-F4 below.

## Prior HEAD — STDLIB-FLOAT-F4 — apd result-exponent preservation for float `+ - *`.
Float arithmetic now threads the apd `(coefficient, exponent)` form (`ApdForm` +
`apdAdd`/`apdSub`/`apdMul` + `apdRoundToContext` + `apdCarrierText`, `Decimal.lean`) instead of
formatting the normalized `DecimalValue` (which erased a positive exponent), so `+ - *` byte-match
cue's GDA render: add/sub exp = `min(e₁,e₂)`, multiply = `e₁+e₂`, both rounded HALF-UP to the 34-digit
apd context. Fixes `2e2 * 3 → 6e+2`, `1e1 + 1e1 → 2e+1`, `1.20 + 1.30 → 2.50` (trailing zeros),
`1e34 + 1 → 1.000…e+34`, `1e1 - 1e1 → 0e+1`. NO change to the `DecimalValue` core type — the carrier
`text` round-trips through `floatApdForm` (the render anchor was always meant to carry the apd form;
only arithmetic failed to populate it). Removed dead `evalDecimalBinary?`/`evalDecimalMultiply?`.
**DIVISION DEFERRED** (subtler apd ideal-exponent) — `6e2 / 3 → 200.0` vs cue `2.0e+2` (VALUE correct,
FORM only); derived exact-division rule (reduce, shift exp −1 for integer results) recorded in
`cue-spec-gaps.md` STDLIB-FLOAT-F4 for a turn-key follow-up. Regression sweep: ZERO existing fixtures
flipped; 37-case manual kue-vs-cue sweep matches everywhere except the deferred division-form cases.
Wild fixture `float-apd-exponent-preservation/` (RED→GREEN) + `float_apd_arithmetic` cue fixture + 4
new EvalTests theorems (mul theorems reworked to assert `formatValue`). Committed on `main`, not pushed.
**Next: F4-division form (the derived rule is ready), then F1–F5 residuals (see plan § STDLIB-FLOAT);
F2 IEEE float64 kernel gated on real prod9 need.** Prior HEAD STDLIB-FLOAT F0 below.

## Prior HEAD — STDLIB-FLOAT F0 — wired the existing decimal `ln`/`exp` kernels
(`decimalLnScaled`/`decimalExpScaled`, already backing `math.Pow`'s general domain) to
`math.Log`/`Log2`/`Log10`/`Exp`/`Exp2`, all byte-identical to cue at 34-sig apd; shipped all 11 `math`
constants (`Pi`…`Log10E`) via `stdlibPackageValue?`. Fixed a latent trailing-zero trim bug: new shared
`renderTranscendentalScaled` (keeps significant trailing zeros, collapses only true integers) replaces
`collapseDecimalToValue` for both Pow + log/exp; corrected the mis-pinned `Pow(10,⅓)` test
(`…651935`→`…6519350`, cue-exact). Canonicalization item: `1.25e3` literal rendering CLOSED
(byte-identical eval+export); the `1.25e3 + 1`→`1251.0` vs cue `1251` arithmetic gap is REAL,
FILED as F4 (apd-exponent preservation), NOT claimed closed. `Log1p`/`Expm1` stay deferred (float64,
F2). 18 new BuiltinTests + `math_log` fixture. **Next: F1–F5 remain (see plan § Ranked OPEN backlog —
STDLIB-FLOAT); F2 (IEEE float64 kernel) is gated on real prod9 need, not speculative.** Committed on
`main`, not pushed. Prior HEAD BYTE-ESCAPE-STRICT below.

## Prior HEAD — BYTE-ESCAPE-STRICT + text/template nested-defer/fuel guards — one
slice folding three LOW audit findings. (1) `decodeByteEscape` (`Kue/Parse.lean`) brought to
cue-strict parity: dropped `\"`, added explicit `\/`, gated `\u`/`\U` on `Nat.isValidChar`; both
callers (`parseQuotedByteBody`, `parseMultilineByteBody`) now parse-error on `none` instead of the
lenient literal fallthrough; byte-context `\(` parse-errors "interpolation not supported yet" in both
byte forms. 18 new `byte_escape_*` `native_decide`; `BytesTests` `lex_bytes_interp_*` flipped to
`= none`. Quarantined `byte-literal-interpolation` seed's kue-output now a parse error (still red,
PROVENANCE annotated). (2) T1-LOW-1: 4 bridge theorems pin `manifestToTemplateData` float-defer at
list-element / struct-in-list / list-in-struct positions (+ int-nesting contrast). (3) T1-LOW-2: 2
byte-matched fuel guards (doubly-nested range + 24-elem single range) against a `runTemplate` fuel
weakening. plan.md BYTE-ESCAPE-STRICT ✅ CLOSED; spec-gap `STRING-ESCAPE-SET` byte-path clause closed.
Committed on `main`, not pushed. Prior HEAD STRING-ESCAPE-SET below.

## Prior HEAD — STRING-ESCAPE-SET — the CUE double-quoted string escape decoder.
The wild `\uXXXX`-dropped bug (below) is FIXED: `parseStringEscape` (decoded only `\n\r\t`, dropped
the `\` on everything else) is replaced by a total `decodeStringEscape` mirroring the byte path but
producing code points + raising a PARSE ERROR on bad escapes. Full set now decoded/rejected byte-for-byte
vs cue: `\uNNNN`/`\UNNNNNNNN` → code point (surrogate/out-of-range rejected via `Nat.isValidChar`),
`\a\b\f\v\n\r\t\\\/\"` simple, and `\xNN`/octal/`\'`/unknown/short-hex all parse errors. `\'` vs `\"`
is context-sensitive (string vs byte literal). Wild fixture promoted RED→GREEN (`.known-red` removed).
19 new `native_decide` in `ParseTests.lean`. Mirror BYTE-path leniency (accepts `\"`/unknown where cue
errors) filed as **BYTE-ESCAPE-STRICT (LOW)** in plan.md — NOT in this slice (blast-radius bound).
Spec-gap `STRING-ESCAPE-SET` records the `\/` cue-compat leniency. Committed on `main`, not pushed.
Prior HEAD STDLIB-TEXTTEMPLATE-T1 below.

## Prior HEAD — STDLIB-TEXTTEMPLATE-T1 — the `text/template` package's minimal
green core + escapers. cue v0.16.1 exposes EXACTLY three leaves: `Execute`/`HTMLEscape`/`JSEscape`
(all → string). New leaf module `Kue/TextTemplate.lean` (`import Kue.Value` only) = a total,
fuel-bounded lexer + parse-tree + tree-walk evaluator over its own `TemplateData` tree (float
UNREPRESENTABLE by construction) + the two pure escapers; `.textTemplate` `BuiltinFamily` arm +
`Kue.manifestToTemplateData` bridge (key-sorts struct fields). Shipped: text, `{{.F}}`/`{{.A.B}}`/
`{{.}}`, if/range(list/struct/null)/with + else, comment, `{{- -}}` trim, Go-`fmt` `map[k:v]`/`[a b c]`
rendering, missing/null ⇒ `<no value>` (nested null ⇒ `<nil>`). Deferred (`unsupportedBuiltin`):
FLOAT data (⇒ T3 float kernel), all FUNCS/pipelines/vars/printf/define (⇒ T2/T4), non-ASCII
`JSEscape` (IsPrint table); malformed template / field-on-scalar ⇒ bottom, nonexistent leaf ⇒ bare
bottom. 35-case differential byte-identical to cue. `Kue/Tests/TextTemplateTests.lean` (60+
`native_decide`) + `testdata/export/text_template_basic.{cue,json}`. **Wild-caught bug it seeded:**
`testdata/wild/cue-unicode-escape-dropped/` — the `\uXXXX`-dropped string-lexer bug — is now FIXED by
STRING-ESCAPE-SET (HEAD above; fixture promoted, `.known-red` removed). Retraction: wild
`stdlib-import-misrouted` guard stays at `uuid` (NOT repointed).
Committed on `main`, not pushed (attended-push pending). Prior HEAD STDLIB-NET below.

## Latest slice (2026-07-11) — STDLIB-TEXTTEMPLATE-T1 (`text/template`, minimal core + escapers)

New `.textTemplate` `BuiltinFamily`. `Kue/TextTemplate.lean` (leaf, imports `Kue.Value` only): lexer
(`{{`/`}}` + `{{-`/`-}}` trim), whitelist parser (`parseSeq`, fuel = item count — anything outside
the T1 grammar ⇒ `.unsupported`), fuel-bounded tree-walk evaluator (shared decreasing budget). Float
defer boundary = illegal-states-unrepresentable: `TemplateData` has NO float constructor, so
`manifestToTemplateData` (`Builtin.lean`) returns `none` on a `.prim (.float …)` anywhere in the
tree ⇒ `unsupportedBuiltin "text/template.Execute"`. Two render modes: `renderAction` (top-level
null ⇒ `<no value>`) vs `renderGoValue` (nested null ⇒ `<nil>`, Go-`fmt` `map[]`/`[]`). `JSEscape`
ASCII exact (7 named escapes + control `\u00XX` uppercase); non-ASCII ⇒ `unsupportedBuiltin
"text/template.JSEscape"` (IsPrint table deferred). Full detail: implementation-log. T2/T3/T4
roadmap in plan.md.

## Latest slice (2026-07-11) — STDLIB-NET (`net` package, scoped to IP validators)

New `.net` `BuiltinFamily`. `Kue/Net.lean` holds the `netip` parser (strict IPv4, IPv6 `::` +
embedded-v4 + `%zone`) + CIDR + `Addr.Is*` classification, all fuel-bounded/total. Extended
`StringFormat` with `netIP`/`netIPv4`/`netIPv6`/`netIPCIDR` + 7 class predicates (no new `Value`
ctor); `stringFormatValid` dispatches them (extracted to the `StringFormat.lean` leaf by
STRINGFORMAT-LEAF; was in `Time.lean`); meet unchanged
(ground bottoms, abstract retains). `evalNetBuiltin` + bare-validator/const resolution
(`Parse.lean`) + `net.` in `builtinImportPaths`. FQDN deferred (cue = idna `ToASCII`, full
IDNA2008 — `ab--cd`/`xn--a` reject). Full detail: implementation-log.

## Latest slice (2026-07-11) — STDLIB-TIME Phase-A audit followup

Three `56fe65e` audit findings closed in one slice. MEDIUM: `validRFC3339Offset` was
structural-only (any two digits passed); now range-checks hour ≤ 24 / minute ≤ 60 (boundary
verified against the cue v0.16.1 binary — 24 and 60 are the accepted maxima). LOW-1: over-range
offset theorems + `stringFormat` disj-arm-survival theorem; `manifestValueOk` promoted to shared
helper. LOW-2: the "fractional-division divergence" was undemonstrated — a hard probe CONFIRMED
a real one (kue exact-integer beats cue's float64 by 1 ns), now logged + pinned. Wild fixture
`rfc3339-offset-overrange` (red→green). Full detail: implementation-log.

## Latest slice (2026-07-11) — STDLIB-TIME (`time` package, scoped)

New `.time` `BuiltinFamily`. `Kue/Time.lean` holds the Go-duration lexer (`parseGoDuration`,
structural/fuel-bounded) + calendar-aware RFC3339 validator (leap-year days-in-month). New
`Value.stringFormat (fmt)` meet-participating string validator, threaded like `stringRegex`
everywhere (ground non-conforming string bottoms; ABSTRACT string RETAINS — `string &
time.Duration()` stays incomplete). Shipped: `ParseDuration`, the `Duration`/`Time` validators
(bare/`()`/bool-fn forms), `Format` for RFC3339/Nano layouts, all unit/layout/month/weekday
constants. Deferred (`unsupportedBuiltin`): `Unix`/`Parse`/`FormatString`/`Split`/`FormatDuration`
+ non-RFC3339 `Format` layouts (need epoch/format engine); `time.Date` bare-bottom. Duration
int64-bounded (Go type contract). `Kue/Tests/TimeTests.lean` (60+ `native_decide`) +
`testdata/export/time_basic.cue`. Retraction: wild `stdlib-import-misrouted-to-disk-loader`
repointed `time` → `net`. Full detail: implementation-log.

## Latest slice (2026-07-11) — STDLIB-B-PHASEB (Phase-B audit cleanup)

Four Phase-B findings folded into one low-risk slice. **2A (MEDIUM, latent drift):**
`finalizeLengthConj` matched only `.list` for uniqueness finalization, missing
`.listTail`/`.embeddedList` while meet-time `classifyUniqueTarget` covered all three — a
meet-vs-manifest divergence. Fixed by routing through the shared `listItems?` extractor, HOISTED
`EvalOps.lean → Value.lean` (lowest common module; `Lattice → EvalOps` would cycle). **1B (LOW):**
`isConcreteArg → isSettledArg` — pure rename + doc; it gates dispatch-settled SHAPE, not
groundness (use `Value.isGround` for that). **3A (LOW, retraction):** refreshed stale post-rename
symbols in `cue-spec-gaps.md` (`fieldCountConstraint → lengthConstraint .fields`, etc.). **Plan
hygiene:** B-3 dropped (moot), B-4 re-scoped+deferred, 2B filed deferred (coupled to next validator
shape). 2 new `native_decide` (listTail meet/manifest agree). Full detail: implementation-log.

## Latest slice (2026-07-11) — STDLIB-VALIDATORS-SOUND (Phase-A HIGH-1/HIGH-2 fix)

Two confirmed HIGH soundness bugs from the STDLIB-VALIDATORS (`5d9b65c`) Phase-A audit, one
shared root cause (conflating "structurally decided now" with "final/concrete" — eager
decisions sound only on GROUND values firing on ABSTRACT ones). HIGH-1: abstract-string length
→ `LengthMeasure.unknown` (was fabricated `lowerBound 0`), so `string & MinRunes(n)` retains
incomplete and `(string & MinRunes(5)) | "hi"` no longer collapses to a fabricated `"hi"`.
HIGH-2: `hasStructuralDup` → `hasGroundDup` gated on new total `Value.isGround`, so
`[int,int] & UniqueItems` retains rather than eager-bottoming; ground dups (`[1,1]`,
`[{a:1},{a:1}]`) still bottom. 4 RED-first wild fixtures + 11 new `native_decide`. Two
`cue-divergences.md` rows (cue export's own abstract-UniqueItems fabrication; disj render
delta). Full detail: implementation-log.

## This session (2026-07-10→11) — two LOW slices + a wild-caught STDLIB campaign

Attended. chakrit asked: do the queued LOW tasks, then test-drive kue on interesting
internet CUE examples. The test-drive (tour + cuetorials examples vs `cue` v0.16.1) matched
on simple cases and surfaced a whole frontier: **the CUE stdlib is ~1/3 implemented.** Ten
slices + a two-phase audit landed, all pushed, all green.

### Landed (git `00a706d..b00129e`)

- **AUD-B5 `8ed98e1`** — DRY'd the two BFS requirement-graph builders into
  `bfsRequirementGraphAux` (leaf-callback combinator, structural on fuel; AD4-1 shape).
- **B3d-B1 `be936dc`** — `Hash1` newtype for the cue.sum h1 digest; eliminated a latent
  fake-empty-h1 seed (real illegal-states win).
- **STDLIB-A `4625079`** — stdlib import ROUTING: `isStdlibImportPath` (dot-free first path
  element ⇒ builtin layer; dotted-domain ⇒ external module) + clear
  `unsupported builtin package "<path>"` error, no more misleading `no cue.mod`.
- **STDLIB-B `2c3ce9e`** — `struct.MinFields/MaxFields` as a `meet`-participating
  `fieldCountConstraint` validator (counts REGULAR fields only; optional/required/hidden/
  def/`let` excluded).
  - **FIELDCOUNT-DISJ `9a32bdb`** (Phase-A audit fix) — retained-min residual inside a
    disjunction arm wasn't finalized on collapse → spurious "ambiguous". `finalizeDisjArm`
    (`Manifest.lean`) finalizes each arm at manifest; accretion untouched.
- **STDLIB-C `326b8c4`** — `strconv` package (`Kue/Strconv.lean`, `.strconv` family).
  Shipped Atoi/FormatInt/FormatUint/ParseInt/ParseUint/FormatBool/ParseBool (arbitrary
  precision, base-0 prefixes + underscores + bitSize). Deferred → unsupported-fn error
  (real-but-not-computed): FormatFloat/ParseFloat (exact-decimal core), Quote/Unquote/QuoteToASCII
  (Unicode IsPrint table). Itoa is non-callable in cue → bottoms BARE, not "unsupported" (B-1
  2026-07-11). Divergence: base 2..36 vs cue's leaked 2..62.
- **STDLIB-D `d902e03`** — root cause was NOT import-specific: kue lacked CUE statement
  separation entirely. Implemented newline-as-implicit-comma (`skipSameLineTrivia` +
  `fieldSeparator`); `a: 1 b: 2` / late imports now rejected. Broad parser change, audit
  verified sound.
- **STDLIB-E `7707355`** — render-only: cue-shaped `imported and not used: "<path>"`
  (`" as <alias>"` aliased).
- **LIST-SEP `2c3659b`** — list-element separators (reuses D's `fieldSeparator`). `[1 2]`
  now errors; `[1\n2]`→`[1,2]` (spec auto-comma — **kue is more spec-correct than cue here:**
  cue rejects newline-elision in `[]` while accepting it in `{}`, its own inconsistency;
  recorded in `cue-divergences.md`).
- **audit-followup `b00129e`** — closed the two Phase-B LOW nits (doc-count drift;
  `every_builtin_package_resolves_to_family` sync theorem) + Phase-A #3 (strconv deferred-fn
  now renders `unsupported builtin function "strconv.Quote"`). Recorded (not fixed) the
  block-comment leniency.

### Two-phase audit (over the batch) — DONE

Phase A (code-quality) found the FIELDCOUNT-DISJ correctness bug (fixed) + its test gap +
the strconv-diagnostics nit; verified STDLIB-D's ASI change sound. Phase B (architecture)
clean — the builtin-package dispatch SCALES (~2 files + optional leaf per package), so the
stdlib campaign is cheap to continue. Both audits logged.

The BLOCK-COMMENT-REJECT + STDLIB-PATH batch's own two-phase audit filed B-1 (MEDIUM) + B-2/F1/F2
(LOW) + B-3/B-4 (test-org). **Followup slice landed (2026-07-11):** B-1 unified the three builtin
fallback shapes into one `unsupportedOrBottom` combinator and ADJUDICATED the marker — it's a
positive recognition claim, emitted only from explicit real-but-deferred arms; the catch-all bottoms
bare (nonexistent-leaf, cue-compatible). Fixed the mislabeled-nonexistent pins (Itoa, FindString).
B-2 (stale doc), F1 (collapsed duplicate trivia skippers), F2 (interpolation block-comment pin) done.
B-3/B-4 (test-org) DEFERRED to a future test-org pass. Detail: plan.md + implementation-log.

## Next steps — the STDLIB frontier (see `plan.md` § Ranked OPEN backlog)

Two tracks:

1. **Spec-conformance (unambiguous, no priority call):** `BLOCK-COMMENT-REJECT` ✅ LANDED
   (2026-07-11) — kue now rejects `/* */` (removed `dropBlockComment` + the `.block` Lex
   state in `ModCmd.lean`); every position errors `unexpected character`. Guarded by wild
   fixture `block-comment-rejected` + `ParseTests parse_block_comment_*`. Next spec-conformance
   items: none currently queued (cue-divergences.md § kue-side is now empty).
2. **New stdlib packages (priority-sensitive — key to which packages prod9 configs hit):**
   `time`, `net`, `uuid`, `crypto/*`, `encoding/hex|csv`, `text/template`; finish
   `strconv` (Quote/FormatFloat need a Unicode IsPrint table / float-format design); round
   out `strings`/`list`/`math`. Dispatch cost is low (audit-confirmed).
   - **STDLIB-PATH ✅ LANDED (2026-07-11)** — `path` package (was the highest-usage
     unimplemented, 11 prod9 hits). `Kue/Path.lean` + `.path` `BuiltinFamily`. Full unix/plan9:
     Clean/Join/Split/Dir/Base/Ext/IsAbs/SplitList/Resolve/Rel/Match(Go glob)/ToSlash/FromSlash/
     VolumeName + `path.Unix/Windows/Plan9` constants (no `path.OS` — not a real cue field).
     Windows os DEFERRED (`unsupportedBuiltin`); invalid os bottoms. 75 theorems. Spec-gap + log.
   - **STDLIB-VALIDATORS ✅ LANDED (2026-07-11)** — the `meet`-participating constraint validators:
     `list.MinItems`/`MaxItems`/`UniqueItems`, `strings.MinRunes`/`MaxRunes`. GENERALIZED the
     `struct.MinFields` validator: `fieldCountConstraint` → `Value.lengthConstraint (kind)(bound)(limit)`
     (`kind` ∈ fields/listItems/runes) + sibling `Value.uniqueItems`. Closed list / concrete string
     decides at meet; struct / open list / abstract string retains + finalizes (`finalizeLengthConj`).
     Runes = code points, not bytes. UniqueItems equality field-order-independent (`eqUpToFieldOrder`).
     Bare `list.UniqueItems` + `()` form both work. ~40 theorems + `export/list_string_validators`
     fixture (byte-identical to cue). `list.IsSorted` DEFERRED (comparator arg = BI-EFF corner).
   - **STDLIB-STRINGS-LEAVES ✅ LANDED (2026-07-11)** — the remaining PLAIN `strings` functions.
     Oracle diff (`pkg/strings/pkg.go` = 34 funcs) → 8 missing, all pure/total, none effectful:
     `ByteAt`/`ByteSlice` (BYTE-indexed; `ByteSlice` returns `bytes`; `Prim.bytes` already existed
     so the "byte-array-repr" filing was moot), `ContainsAny`/`IndexAny`/`LastIndexAny` (rune SET,
     BYTE offsets), `SplitAfter`/`SplitAfterN` (sep stays on preceding piece; trailing sep ⇒
     trailing empty; fuel-bounded, total), `ToCamel` (word-initial lower-case; shares
     `mapWordInitial` with `asciiToTitle`; ASCII-bounded, non-ASCII passthrough divergence in
     spec-gaps). Task candidates `SplitAny`/`IndexRune`/`Map` DON'T exist in cue's strings pkg —
     confirmed, nothing deferred. 25 theorems + `export/strings_leaves` fixture (byte-identical).
     Next stdlib: `time`, `net`, `uuid`, `crypto/*`, `encoding/hex|csv`; finish `strconv` Quote/Float.

Test-drive scratch files at `~/Documents/chakrit/kue-testdrive/` (outside the repo).

## Historical (not this session)

- ace-connect bridge (slug `chakrit.kue.claude`, control mode) was live in the 2026-07-07
  session; NOT touched this session — do not assume it's still running. Recover per
  ace-connect Flow step 4 if needed.
- 2026-07-07: AUD-B6 (`b1be061`), release `v0.1.0-alpha.20260707.1`. Detail in the log.

## Pending school changes

None this session.
