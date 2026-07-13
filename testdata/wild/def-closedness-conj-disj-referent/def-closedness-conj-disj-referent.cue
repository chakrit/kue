package repro

// SOUNDNESS over-accept — the 6th closedness-through-indirection residual, surviving the
// 8b19318 fold. A definition indirecting to a CONJUNCTION one of whose members is a
// DISJUNCTION (`#X: _foo`, `_foo: (disj) & struct`) does NOT distribute the def's
// closedness across the disjunction arms: the arms inline OPEN and admit a use-site extra.
//
// Root: `resolveDefBodyReferent` (`EvalBase.lean`) normalizes a disjunction only when a
// `.refId` resolves DIRECTLY to a `.disj` (the `.disj ..` arm calls
// `normalizeDefinitionValueWithFuel`). When the disjunction is a MEMBER of a resolved
// `.conj` referent, the `.conj cs => .conj (cs.map …)` recursion maps `resolveDefBodyReferent`
// over the members and a bare `.disj` member hits the `| _ => v` fall-through — returned
// UNNORMALIZED, so it never reaches the distributable closed form the gate's
// `disjArmCrossProduct` expects. The direct body `#X: (disj) & struct` splits to top-level
// conjuncts `[.disj, {c}]` and closes correctly; only the indirection buries the disj.
//
// Faces (same root):
//   over-accept (this fixture): `_foo: (*{a:1}|{b:2}) & {c:3}`, `#X & {a:1,c:3,q:99}` ⇒
//     kue emits `{a:1,c:3,q:99}` (default arm stays OPEN, admits `q`); cue rejects
//     (empty disjunction, `q`/`a` field not allowed). A closed default arm `{a:1,c:3}`
//     rejects `q` and the non-default arm `{b:2,c:3}` rejects `a`+`q` ⇒ empty disjunction ⇒ ⊥.
//   over-reject: `_foo: ({a:1}|{b:2}) & {c:3}`, `#X & {a:1,c:3}` ⇒ kue "ambiguous value"
//     (both arms leak OPEN, both survive); cue resolves `{a:1,c:3}`.
//
// Contrast (all GREEN after 8b19318): pure disj referent (`_foo: {a}|{b}`,
// def-closedness-disj-referent), conj of STRUCT referents (`#X: a0 & b0`,
// def-closedness-conj-referent-overclose), and the DIRECT `#X: (disj) & struct`. The gap is
// exactly a disjunction reached as a conj-MEMBER through indirection.
//
// Spec-adjudicated verdict: the value of `#X` is closed however reached; each arm of the
// referent disjunction closes over the union with the sibling struct literals, so a
// use-site extra rejects every arm ⇒ `y` is bottom (empty disjunction). Fixed kue emits the
// same "conflicting values (bottom)" as the DIRECT `#X: (*{a:1}|{b:2}) & {c:3}` face.
_foo: (*{a: 1} | {b: 2}) & {c: 3}
#X:   _foo
y: #X & {a: 1, c: 3, q: 99}
