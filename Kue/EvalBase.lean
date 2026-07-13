import Kue.Builtin
import Kue.Decimal
import Kue.EvalOps
import Kue.Lattice
import Kue.Regex
import Kue.Normalize
import Std.Data.HashMap

namespace Kue

/--
Evaluation mirrors resolution's lexical scope chain: the environment is a stack of
frames (innermost first), each frame the syntactic field list of an enclosing struct.
A `refId ⟨depth, index⟩` selects the field at `index` in the frame `depth` steps out.
Cycle detection tracks visited slot indices within the current frame; following an
outer reference (`depth > 0`) re-bases onto the outer stack, where lexical cycles back
into a deeper frame cannot form, so the visited set resets.
-/
def findEvalField (label : String) : List Field -> Option Field
  | [] => none
  | field :: fields =>
      if Field.label field = label then
        some field
      else
        findEvalField label fields

def indexedFieldsFrom (index : Nat) : List Field -> List (Nat × Field)
  | [] => []
  | field :: fields => (index, field) :: indexedFieldsFrom (index + 1) fields

def indexedFields (fields : List Field) : List (Nat × Field) :=
  indexedFieldsFrom 0 fields

def nthField (index : Nat) : List Field -> Option Field
  | [] => none
  | field :: fields =>
      match index with
      | 0 => some field
      | n + 1 => nthField n fields

def slotVisited (index : Nat) : List Nat -> Bool
  | [] => false
  | visited :: rest =>
      if visited == index then
        true
      else
        slotVisited index rest

/-- The reference cycle a re-entered slot closes: the prefix of `visited` up to and INCLUDING
    the first occurrence of `slot` (the repeated slot). Every slot on that segment lies on the
    cycle. `slot` is guaranteed present (the caller checks `slotVisited` first). -/
def cycleSlots (slot : Nat) : List Nat -> List Nat
  | [] => []
  | visited :: rest =>
      if visited == slot then [visited]
      else visited :: cycleSlots slot rest

/-- Are ALL slots on a detected reference cycle `let` bindings? A pure-`let` cycle is a CUE load
    error; a cycle touching any field truncates to top. -/
def allLetCycle (fields : List Field) : List Nat -> Bool
  | [] => true
  | slot :: rest =>
      match nthField slot fields with
      | some field => field.fieldClass == .letBinding && allLetCycle fields rest
      | none => false

def fieldLabelIndexFrom (label : String) (index : Nat) : List Field -> Option Nat
  | [] => none
  | field :: fields =>
      if Field.label field = label then
        some index
      else
        fieldLabelIndexFrom label (index + 1) fields

/-- Resolve a `Self.label` selection on a value-alias binding. When `id` points at a
    `.thisStruct` binding (a `label: Self={…}` value alias), `Self.label` is just a sibling
    reference resolved in the aliased struct's own frame, so this rewrites it to the
    `BindingId` of `label` in that frame — inheriting the ordinary same-struct cycle and
    resolution machinery. `none` when `id` is not a `thisStruct` binding or `label` is
    absent, leaving the generic selector path to handle it. -/
def thisStructFieldIndex? (env : List (Nat × List Field)) (id : BindingId) (label : String) : Option BindingId :=
  match env.drop id.depth.val with
  | [] => none
  | frame :: _ =>
      match nthField id.index.val frame.snd with
      | some field =>
          match Field.value field with
          | .thisStruct =>
              match fieldLabelIndexFrom label 0 frame.snd with
              | some labelIndex => some ⟨id.depth, ⟨labelIndex⟩⟩
              | none => none
          | _ => none
      | none => none

def evalFuel : Nat :=
  100

/-- The slot index of the `Self=` value-alias binding (`.thisStruct`) in a frame's field list,
    or `none` if the struct has no such alias. -/
def thisStructBindingIndex? : List Field -> Option Nat
  | fields =>
      let rec go (index : Nat) : List Field -> Option Nat
        | [] => none
        | field :: rest =>
            match Field.value field with
            | .thisStruct => some index
            | _ => go (index + 1) rest
      go 0 fields

mutual
/-- Generic depth-threading structural fold over the full `Value` constructor tree (A-EN3). The
    three def-frame scanners — `refsSelfEmbeddedLabel` (monoid `Bool`/`||`), `selfReferencedLabels`
    (`List String`/`++`), `defFrameRefIndices` (`List Nat`/`++`) — are the SAME recursion, differing
    only in (a) the monoid `(combine, empty)` and (b) the `leaf` hook deciding which node
    contributes. They become thin instantiations of this fold.

    `leaf depth node` is a PRE-ORDER hook: `some x` makes `node` a leaf contributing `x` (no further
    descent); `none` recurses structurally into `node`'s children, each at its frame depth (`+1` per
    frame-pusher — struct/structComp/pattern/embed-decls; `+0` otherwise) with the clause chain
    threaded by `descendClauses` (`+1` per `for`/`let`, `+0` per guard). Frame-pusher discipline
    mirrors `hasSelfRefAtDepth`/`resolveClausesWithFuel`.

    A `.dynamicField`'s VALUE is scanned at the SAME depth as its key (no `+1`): the resolver pushes
    NO frame for a dynamic field — `Resolve.lean` resolves both key and value in the parent scope —
    so a ref in the value resolves to the parent's frames, exactly as the fold's depth records. -/
def foldValueWithDepth {β : Type}
    (combine : β → β → β) (empty : β)
    (leaf : Nat → Value → Option β)
    (fuel : Nat) (depth : Nat) : Value → β
  | v =>
      match leaf depth v with
      | some x => x
      | none =>
        let rec' := fun (d : Nat) (child : Value) => match fuel with
          | 0 => empty
          | f + 1 => foldValueWithDepth combine empty leaf f d child
        match v with
        | .selector base _ => rec' depth base
        | .index base key => combine (rec' depth base) (rec' depth key)
        | .unary _ inner => rec' depth inner
        | .binary _ l r => combine (rec' depth l) (rec' depth r)
        | .conj cs => cs.foldl (fun acc c => combine acc (rec' depth c)) empty
        | .disj alts => alts.foldl (fun acc a => combine acc (rec' depth a.snd)) empty
        | .interpolation parts => parts.foldl (fun acc p => combine acc (rec' depth p)) empty
        | .list items => items.foldl (fun acc i => combine acc (rec' depth i)) empty
        | .listTail items tail =>
            combine (items.foldl (fun acc i => combine acc (rec' depth i)) empty) (rec' depth tail)
        | .builtinCall _ args => args.foldl (fun acc a => combine acc (rec' depth a)) empty
        | .dynamicField l _ inner => combine (rec' depth l) (rec' depth inner)
        | .structComp fields cs _ =>
            combine
              (fields.foldl (fun acc fl => combine acc (rec' (depth + 1) (Field.value fl))) empty)
              (cs.foldl (fun acc c => combine acc (rec' (depth + 1) c)) empty)
        | .struct fields _ tail patterns _ =>
            combine
              (combine
                (fields.foldl (fun acc fl => combine acc (rec' (depth + 1) (Field.value fl))) empty)
                (match tail with | some t => rec' (depth + 1) t | none => empty))
              (patterns.foldl (fun acc p =>
                combine acc (combine (rec' (depth + 1) p.fst) (rec' (depth + 1) p.snd))) empty)
        | .embeddedList items tail decls =>
            combine
              (combine
                (items.foldl (fun acc i => combine acc (rec' depth i)) empty)
                (match tail with | some t => rec' depth t | none => empty))
              (decls.foldl (fun acc fl => combine acc (rec' (depth + 1) (Field.value fl))) empty)
        | .embeddedScalar scalar decls =>
            combine
              (rec' depth scalar)
              (decls.foldl (fun acc fl => combine acc (rec' (depth + 1) (Field.value fl))) empty)
        | .comprehension clauses body =>
            match fuel with
            | 0 => empty
            | f + 1 => foldValueWithDepthClauses combine empty leaf f depth clauses body
        | .listComprehension clauses body =>
            match fuel with
            | 0 => empty
            | f + 1 => foldValueWithDepthClauses combine empty leaf f depth clauses body
        | _ => empty

/-- Thread a comprehension's clause chain via `descendClauses` (`+1` per `for`/`let`, `+0` per
    guard), folding `foldValueWithDepth` over each clause source/guard and the body at its depth —
    the single clause-depth authority shared by all three scanners. -/
def foldValueWithDepthClauses {β : Type}
    (combine : β → β → β) (empty : β)
    (leaf : Nat → Value → Option β)
    (fuel : Nat) (depth : Nat) (clauses : List (Clause Value)) (body : Value) : β :=
  descendClauses combine
    (fun d source => foldValueWithDepth combine empty leaf fuel d source)
    (fun d cond => foldValueWithDepth combine empty leaf fuel d cond)
    (fun d => foldValueWithDepth combine empty leaf fuel d body)
    depth clauses
end

/-- Does `value` reference `Self.<label>` for some `label ∈ labels`, where `Self` is the
    binding at `selfIndex` in the def's OWN frame, reachable from `depth` frame-pushers deep? A
    resolved `Self.a` read from the def's own frame is `.selector (.refId ⟨0, selfIndex⟩) a`; read
    from a NESTED struct (`spec: { hostnames: Self.#hosts }`) it is `.selector (.refId ⟨d,
    selfIndex⟩) a` with `d` = the number of intervening frames. Descending a frame-pusher
    (`.struct`/`.structTail`/`.structComp`/pattern) increments `depth`, so a self-ref lands iff
    `id.depth == depth`, exactly mirroring `hasSelfRefAtDepth`. Fuel-bounded structural scan; used
    to gate the embedding-`Self` two-pass so it fires when ANY field (at any nesting depth) selects
    an embedding-supplied label through the host's `Self`.

    Thin `foldValueWithDepth` instantiation (monoid `Bool`/`||`): the `.selector (.refId id) label`
    arm is the leaf; clause-chain depth (`for` source at `depth`, body `#for` deeper) is threaded by
    the fold's shared `descendClauses` handler. -/
def refsSelfEmbeddedLabel (fuel : Nat) (depth selfIndex : Nat) (labels : List String) : Value → Bool :=
  foldValueWithDepth (· || ·) false
    (fun d v => match v with
      | .selector (.refId id) label =>
          some (id.depth.val == d && id.index.val == selfIndex && labels.contains label)
      | _ => none)
    fuel depth

/-- Should the embedding-`Self` two-pass fire? Only when (a) embeddings contributed labels NOT
    declared static, AND (b) some static field actually selects one through the host's `Self`
    alias. Both conditions spare the common embedding case (a `parts.#Metadata` that supplies
    `metadata` but is never read via `Self.metadata`) from the re-evaluation cost. -/
def needsEmbeddedSelfPass (canonical : List Field) (newEmbeddedLabels : List String) : Bool :=
  !newEmbeddedLabels.isEmpty &&
    match thisStructBindingIndex? canonical with
    | none => false
    | some selfIndex =>
        canonical.any fun fl =>
          refsSelfEmbeddedLabel evalFuel 0 selfIndex newEmbeddedLabels (Field.value fl)

/-- Does any EMBEDDING value read `Self.<label>` for a label contributed by a SIBLING embedding
    (a label in `newEmbeddedLabels` no static field declares)? An embedding sits at the host's
    frame depth (same as a static field's value), so the scanner runs at `depth 0` against the
    host's `Self` alias — identically to `needsEmbeddedSelfPass`. Gates the embedding-`Self`
    re-fold: a list-embedded `Self.#hidden` read (`[{name: Self.#name}]` where `#name` comes from
    a `#Meta` embed) is in an EMBEDDING, not a static field, so the static-field two-pass misses
    it — the embeddings must be re-evaluated against the augmented frame for it to resolve. -/
def embeddingsReadEmbeddedSelf (canonical : List Field) (embeddings : List Value)
    (newEmbeddedLabels : List String) : Bool :=
  !newEmbeddedLabels.isEmpty &&
    match thisStructBindingIndex? canonical with
    | none => false
    | some selfIndex =>
        embeddings.any fun e =>
          refsSelfEmbeddedLabel evalFuel 0 selfIndex newEmbeddedLabels e

/-- The set of `Self.<label>` reads in `value` whose `Self` is the alias at `selfIndex` `depth`
    frame-pushers deep — the label-collecting twin of `refsSelfEmbeddedLabel` (same structural
    descent, same depth discipline). Used to compute which static fields the Pass-2 re-eval must
    touch: a field reads `Self.<L>` (this set) and depends on `L`'s value, which the Pass-2 frame
    change alters iff `L` is an embedded label or itself transitively depends on one.

    Thin `foldValueWithDepth` instantiation (monoid `List String`/`++`): the `.selector (.refId id)
    label` arm is the leaf (yields `[label]` on a self-frame hit, `[]` otherwise). -/
def selfReferencedLabels (fuel : Nat) (depth selfIndex : Nat) : Value → List String :=
  foldValueWithDepth (· ++ ·) []
    (fun d v => match v with
      | .selector (.refId id) label =>
          some (if id.depth.val == d && id.index.val == selfIndex then [label] else [])
      | _ => none)
    fuel depth

/-- The slot indices read by a `.refId` that resolves to frame `depth` (the def's own frame),
    scanning `value` in full and threading frame depth through every frame-pusher — struct/struct-
    Comp/pattern (`+1`) and a comprehension's clause chain (`+1` per `for`, `+0` per guard). The bug
    this serves: a comprehension guard `if kind == add.#kind { … }` inside an EMBEDDED def reads the
    def's regular sibling `kind` by a bare reference; that sibling is narrowed at the host/use site,
    but `hiddenFieldsOnly` drops regular fields from the splice, so the guard fires against the
    un-narrowed `kind: string`, stays incomplete, and the guarded body is silently dropped — the
    outer `meet` cannot re-fire a comprehension that already collapsed. Collecting the def-frame
    indices a guard reads lets the splice carry exactly those regular siblings, so the guard sees
    the narrowed value at expansion time (matching cue, which defers the comprehension until its
    referenced fields are concrete). A static field's ordinary ref to a regular sibling may also be
    collected — harmless: the sibling merges by label into the embed's own declaration, the same
    `meet` the outer fold does, just early enough for a guard. Depth threading mirrors
    `hasSelfRefAtDepth`.

    Thin `foldValueWithDepth` instantiation (monoid `List Nat`/`++`): the bare `.refId id` arm is
    the leaf (yields `[id.index]` on a def-frame hit). A `.dynamicField`'s value is scanned at the
    parent's depth (the resolver pushes no frame for it) — so a def sibling read solely through a
    dyn-field value (`[for x in [..] {("k"): kind}]`) is collected and spliced (A-EN3-DYN). -/
def defFrameRefIndices (fuel : Nat) (depth : Nat) : Value → List Nat :=
  foldValueWithDepth (· ++ ·) []
    (fun d v => match v with
      | .refId id => some (if id.depth.val == d then [id.index.val] else [])
      | _ => none)
    fuel depth

/-- Pass-2 selective re-eval (perf, audit PART B): the static field INDICES (into `canonical`)
    whose value the embedding-`Self` Pass-2 frame change can alter — to be re-evaluated against the
    augmented frame; every OTHER index reuses its Pass-1 value, byte-identically (its value does not
    depend, even transitively through a sibling `Self.<L>` read, on any embedded label, so the only
    Pass-2 difference — the frame id — never reaches the value, only the memo key).

    Returns `[]` when the two-pass need not fire at all (matching `needsEmbeddedSelfPass = false`).
    Otherwise the TRANSITIVE-CLOSURE seed-set: a field is included iff it reads `Self.<embedded>`
    directly, OR reads `Self.<L>` for a static label `L` whose own field is already included. The
    closure is computed by iterating to a fixpoint, bounded by the field count. -/
def embeddedSelfPassFieldIndices (canonical : List Field) (newEmbeddedLabels : List String) : List Nat :=
  if newEmbeddedLabels.isEmpty then []
  else match thisStructBindingIndex? canonical with
    | none => []
    | some selfIndex =>
        let indexed := canonical.zipIdx
        -- Per field: the self-frame labels it reads (`Self.<L>`), and the labels it CONTRIBUTES
        -- (its own label) — a field's value lives under its own label in the self frame.
        let refsOf := fun (fl : Field) => (selfReferencedLabels evalFuel 0 selfIndex (Field.value fl)).eraseDups
        -- Seed: indices that read an embedded label directly.
        let seed := indexed.filterMap fun (fl, i) =>
          if (refsOf fl).any (newEmbeddedLabels.contains ·) then some i else none
        -- Iterate: a field is "tainted" if it reads `Self.<L>` for a label `L` owned by a tainted
        -- field. Fixpoint in ≤ |fields| rounds (each round adds ≥1 or stabilizes).
        let step := fun (tainted : List Nat) =>
          let taintedLabels := indexed.filterMap fun (fl, i) =>
            if tainted.contains i then some (Field.label fl) else none
          indexed.filterMap fun (fl, i) =>
            if tainted.contains i then some i
            else if (refsOf fl).any (taintedLabels.contains ·) then some i
            else none
        let rec fix (fuel : Nat) (tainted : List Nat) : List Nat :=
          match fuel with
          | 0 => tainted
          | f + 1 =>
              let next := (step tainted).eraseDups
              if next.length == tainted.length then tainted else fix f next
        if seed.isEmpty then [] else fix canonical.length seed.eraseDups

/-- The invalid/deferred regex carried by a concrete pattern-label predicate, if any. A
    `[=~"a("]:` label predicate is a `.stringRegex` (a `.conj` carries it after a meet combines
    predicates); an invalid concrete pattern there bottoms the whole struct (cue errors),
    mirroring the 4 `matchRegex` dispatch sites. An ABSTRACT predicate (a `.ref`, `.kind`, …)
    is not a `.stringRegex` literal and so never trips — it stays unresolved. -/
def stringRegexError? : Value -> Option (String × RegexParseError)
  | .stringRegex pattern => (regexParseError? pattern).map (fun err => (pattern, err))
  | _ => none

def labelPatternRegexError? : Value -> Option (String × RegexParseError)
  | .stringRegex pattern => (regexParseError? pattern).map (fun err => (pattern, err))
  | .conj constraints => constraints.findSome? stringRegexError?
  | _ => none

def patternsRegexError? (patterns : List (Value × Value)) : Option (String × RegexParseError) :=
  patterns.findSome? (fun pattern => labelPatternRegexError? pattern.fst)

/-- Re-emit an evaluated normalized struct, applying its evaluated patterns to the
    evaluated fields by meeting a pattern-only struct against the field-only struct. A
    no-pattern struct skips the meet and is `mkStruct`-built directly; a pattern struct
    routes through `meet`, which applies the patterns to the fields. `closedClauses`
    (SC-1/SC-1b) are preserved on the pattern-only struct so a meet-result's per-conjunct
    closed allowed-set survives re-evaluation (without it, every pattern would re-mark as a
    fresh self-clause and re-open a closed absorbed-pattern result). An invalid concrete
    pattern-label predicate bottoms the struct before any application (RX-2b). -/
def applyEvaluatedStructN
    (fields : List Field)
    (openness : StructOpenness)
    (tail : Option Value)
    (patterns : List (Value × Value))
    (closedClauses : List ClosedClause) : Value :=
  match patternsRegexError? patterns with
  | some (pattern, err) => .bottomWith [.invalidRegex pattern err]
  | none =>
  match patterns with
  | [] => mkStruct fields openness tail [] closedClauses
  -- The fields AND the tail stay on the pattern-bearing struct so the closedness check sees
  -- the fields as DECLARED (its own fields are always allowed) and keeps the `...` tail's
  -- openness. Splitting fields onto a separate open struct lost them from `declaredFields` (a
  -- closed pattern def `#A: {x, [=~"a"]}` wrongly bottomed its own declared `x`); dropping the
  -- tail re-closed an open-via-tail pattern def (`#A: {[=~"a"], ...}` wrongly rejected extras).
  -- Both are SC-1c. The empty open right side only routes the result through the
  -- pattern-application meet arm.
  | _ => meet (mkStruct fields openness tail patterns closedClauses) (mkStruct [] .regularOpen none [])

def allRegularAlternatives : List (Mark × Value) -> Bool
  | [] => true
  | alternative :: alternatives =>
      alternative.fst == .regular && allRegularAlternatives alternatives

def joinValues : List Value -> Value
  | [] => .bottom
  | value :: values => values.foldl join value

def mergeEvaluatedFields (fields : List Field) : Option (List Field) :=
  mergeFieldListWith meet fields

/-- Combine two *unevaluated* bodies for the same label into a deferred conjunction. The
    bodies have not been evaluated yet (field-ref `BindingId`s are unresolved), so they
    cannot be `meet`-ed; `.conj` re-evaluates them lazily once the frame is in scope. -/
def joinUnevaluated (left right : Value) : Value :=
  .conj [left, right]

/-- The openness of the UNION of two same-def declarations (Bug2-6). Repeated declarations of
    ONE definition path unify their field-sets and close ONCE over the union — so openness
    UNIONS, with OPEN dominating (if EITHER decl is open via `...`, the merged body is open).
    This is the DUAL of `StructOpenness.meet` (use-site `#A & #B`, where CLOSED dominates):
    same-def decls are one definition's parts, not two independent closed constraints. -/
def unionDefOpenness (left right : StructOpenness) : StructOpenness :=
  if left.isOpen || right.isOpen then .defOpenViaTail else .defClosed

/-- Merge two *unevaluated* bodies that are repeated declarations of the SAME definition path
    (Bug2-6 close-once). cue unifies a definition's multiple declarations BEFORE closing, then
    closes ONCE over the UNION of their field-sets (`#Foo: {a:1}` + `#Foo: {c:3}` → `{a:1,c:3}`,
    closed to `{a,c}`). Closing each decl's body SEPARATELY then `.conj`-ing them makes the meet
    mutually reject each side's fields; instead this unions the two decls into ONE def body that the
    eval close then closes ONCE (the single-clause `closedClauses` path), so the union admits
    exactly `a ∪ c` and rejects anything else.

    Distinct from a use-site `#A & #B` meet, which CONCATENATES `closedClauses` (conjunction →
    reject extras): that path never reaches here. This is reached ONLY from
    `canonicalizeFields`/`mergeConjFields` when the merged field-class `isDefinition` — same-decl
    provenance is present exactly there and nowhere else, so the same-decl-vs-use-site
    distinction is STRUCTURAL (a merged body here vs a `.conj` at the meet), not a flag.

    Shapes (post-`normalizeDefinitions` a plain def body is a closed `.struct`; an
    embed/comprehension-bearing one is a `.structComp`):
    - `.struct × .struct`: union fields (`mergeFieldListWith joinUnevaluated`, so a SHARED label's
      values still `.conj`-meet — `#Foo:{a:1}`+`#Foo:{a:2}` keeps the conflict), union patterns,
      union openness; `mkStruct` re-derives the SINGLE union clause when the result is closed.
    - `.structComp × .structComp`: union fields, append comprehensions/embeddings, union openness.
    A shape this cannot cleanly union (a def body that is a ref/disj/selector, or a mixed
    struct/structComp pair) falls back to `.conj` — preserving the prior behavior for cases the
    close-once union does not cover. -/
def mergeDefinitionDecls (left right : Value) : Value :=
  match left, right with
  | .struct fa oa _ pa _, .struct fb ob _ pb _ =>
      let mergedFields := (mergeFieldListWith joinUnevaluated (fa ++ fb)).getD (fa ++ fb)
      mkStruct mergedFields (unionDefOpenness oa ob) none (pa ++ pb)
  | .structComp fa ca oa, .structComp fb cb ob =>
      let mergedFields := (mergeFieldListWith joinUnevaluated (fa ++ fb)).getD (fa ++ fb)
      .structComp mergedFields (ca ++ cb) (unionDefOpenness oa ob)
  | _, _ => joinUnevaluated left right

/-- The unevaluated value-merge for a collapsing duplicate slot, selected by the MERGED
    field-class: two DEFINITION-class decls close ONCE over their union (`mergeDefinitionDecls`,
    Bug2-6); every other class (regular/hidden/optional/required/let) keeps the deferred `.conj`
    (`joinUnevaluated`), which `meet`s lazily once the frame is in scope. -/
def mergeUnevaluatedFieldValue (fieldClass : FieldClass) (current field : Field) : Field :=
  let value :=
    if fieldClass.isDefinition then
      mergeDefinitionDecls (Field.value current) (Field.value field)
    else
      joinUnevaluated (Field.value current) (Field.value field)
  { current with fieldClass := fieldClass, value := value }

/-- Canonicalize a syntactic field list by collapsing duplicate-label slots into a single
    first-occurrence slot. A duplicate slot's body is the unevaluated `.conj` of the conjuncts
    (so the frame the evaluator indexes is deduplicated), EXCEPT two DEFINITION-class decls of
    the same path, which close ONCE over their UNION (`mergeDefinitionDecls`, Bug2-6) instead of
    `.conj`-ing two separately-closed bodies. `mergeFieldLayoutInto` (Lattice) single-sources the
    keep-or-append DECISION shared with the resolver's `canonicalFieldLayout`; this side supplies
    only the value-merge. Preserves first-occurrence order and shifts no earlier index — `b`'s
    `refId ⟨0,0⟩` still lands on slot 0, now carrying the merged body. A class mismatch keeps the
    slots separate. Total: foldl over a finite list. -/
def canonicalizeFields (fields : List Field) : List Field :=
  fields.foldl
    (fun merged field =>
      match mergeFieldLayoutInto mergeUnevaluatedFieldValue merged field with
      | some fields => fields
      | none => merged ++ [field])
    []

def labelIndexMapFrom (index : Nat) : List Field -> List (String × Nat)
  | [] => []
  | field :: fields => (Field.label field, index) :: labelIndexMapFrom (index + 1) fields

/-- A label→slot-index map over a (canonicalized) field list, used to rebase a conjunct's
    own sibling references onto their position in the merged frame. -/
def labelIndexMap (fields : List Field) : List (String × Nat) :=
  labelIndexMapFrom 0 fields

def lookupLabelIndex (label : String) : List (String × Nat) -> Option Nat
  | [] => none
  | entry :: rest => if entry.fst == label then some entry.snd else lookupLabelIndex label rest

/--
Rebase a single conjunct's body so its frame-local sibling references point at their new
slot in the merged conjunction frame. `frameDepth` counts the struct frames descended from
the conjunction site; a `refId ⟨d, i⟩` with `d == frameDepth` targets the merged frame, so
its index `i` is remapped from the conjunct's own layout (`oldIndexLabel i`) to the merged
layout (`mergedIndex label`). References to outer scopes (`d > frameDepth`, or `d <
frameDepth` into a struct the body itself introduces) are left untouched — the merged frame
sits exactly where the conjunct's frame would have sat, so only the merged-frame layer
shifts. Total via structural fuel; descending a struct increments `frameDepth`, and
descending a comprehension body shifts it via `clauseChainDepth` (the shared
`descendClauses` fold — one frame per `for` clause, none per `guard`).
-/
def remapFuel : Nat :=
  100

mutual
  def remapConjRefs
      (fuel : Nat)
      (frameDepth : Nat)
      (oldLabels : List Field)
      (mergedMap : List (String × Nat))
      (value : Value) : Value :=
    match fuel, value with
    | _, .refId id =>
        if id.depth.val == frameDepth then
          match (nthField id.index.val oldLabels).map Field.label with
          | some label =>
              match lookupLabelIndex label mergedMap with
              | some mergedIndex => .refId ⟨id.depth, ⟨mergedIndex⟩⟩
              | none => .refId id
          | none => .refId id
        else
          .refId id
    | fuel + 1, .conj constraints =>
        .conj (remapConjValues fuel frameDepth oldLabels mergedMap constraints)
    | fuel + 1, .builtinCall name args =>
        .builtinCall name (remapConjValues fuel frameDepth oldLabels mergedMap args)
    | fuel + 1, .unary op operand =>
        .unary op (remapConjRefs fuel frameDepth oldLabels mergedMap operand)
    | fuel + 1, .binary op left right =>
        .binary op
          (remapConjRefs fuel frameDepth oldLabels mergedMap left)
          (remapConjRefs fuel frameDepth oldLabels mergedMap right)
    | fuel + 1, .selector base label =>
        .selector (remapConjRefs fuel frameDepth oldLabels mergedMap base) label
    | fuel + 1, .index base key =>
        .index
          (remapConjRefs fuel frameDepth oldLabels mergedMap base)
          (remapConjRefs fuel frameDepth oldLabels mergedMap key)
    | fuel + 1, .disj alternatives =>
        .disj (remapConjAlternatives fuel frameDepth oldLabels mergedMap alternatives)
    | fuel + 1, .struct fields openness tail patterns closedClauses =>
        -- 1:1 ref-remap preserving the already-coherent struct shape (openness/tail/patterns
        -- are invariant under remapping, so rebuild directly rather than through `mkStruct`).
        .struct
          (remapConjFields fuel (frameDepth + 1) oldLabels mergedMap fields)
          openness
          (tail.map (remapConjRefs fuel (frameDepth + 1) oldLabels mergedMap))
          (remapConjPatterns fuel (frameDepth + 1) oldLabels mergedMap patterns)
          (closedClauses.map (ClosedClause.mapPatterns (remapConjRefs fuel (frameDepth + 1) oldLabels mergedMap)))
    | fuel + 1, .list items =>
        .list (remapConjValues fuel frameDepth oldLabels mergedMap items)
    | fuel + 1, .listTail items tail =>
        .listTail
          (remapConjValues fuel frameDepth oldLabels mergedMap items)
          (remapConjRefs fuel frameDepth oldLabels mergedMap tail)
    | fuel + 1, .interpolation parts =>
        .interpolation (remapConjValues fuel frameDepth oldLabels mergedMap parts)
    | fuel + 1, .structComp fields comprehensions openness =>
        .structComp
          (remapConjFields fuel (frameDepth + 1) oldLabels mergedMap fields)
          (remapConjValues fuel (frameDepth + 1) oldLabels mergedMap comprehensions)
          openness
    | fuel + 1, .comprehension clauses body =>
        .comprehension
          (remapConjClauses fuel frameDepth oldLabels mergedMap clauses)
          (remapConjRefs fuel (clauseChainDepth frameDepth clauses) oldLabels mergedMap body)
    | fuel + 1, .listComprehension clauses body =>
        .listComprehension
          (remapConjClauses fuel frameDepth oldLabels mergedMap clauses)
          (remapConjRefs fuel (clauseChainDepth frameDepth clauses) oldLabels mergedMap body)
    | fuel + 1, .embeddedList items tail decls =>
        .embeddedList
          (remapConjValues fuel frameDepth oldLabels mergedMap items)
          (tail.map (remapConjRefs fuel frameDepth oldLabels mergedMap))
          (remapConjFields fuel (frameDepth + 1) oldLabels mergedMap decls)
    | fuel + 1, .embeddedScalar scalar decls =>
        .embeddedScalar
          (remapConjRefs fuel frameDepth oldLabels mergedMap scalar)
          (remapConjFields fuel (frameDepth + 1) oldLabels mergedMap decls)
    | fuel + 1, .dynamicField label fieldClass value =>
        .dynamicField
          (remapConjRefs fuel frameDepth oldLabels mergedMap label)
          fieldClass
          (remapConjRefs fuel frameDepth oldLabels mergedMap value)
    | _, value => value
  termination_by (fuel, 0, 0)

  def remapConjValues
      (fuel : Nat)
      (frameDepth : Nat)
      (oldLabels : List Field)
      (mergedMap : List (String × Nat)) : List Value -> List Value
    | [] => []
    | value :: rest =>
        remapConjRefs fuel frameDepth oldLabels mergedMap value
          :: remapConjValues fuel frameDepth oldLabels mergedMap rest
  termination_by values => (fuel, 1, values.length)

  def remapConjFields
      (fuel : Nat)
      (frameDepth : Nat)
      (oldLabels : List Field)
      (mergedMap : List (String × Nat)) : List Field -> List Field
    | [] => []
    | field :: rest =>
        { field with value := remapConjRefs fuel frameDepth oldLabels mergedMap field.value }
          :: remapConjFields fuel frameDepth oldLabels mergedMap rest
  termination_by fields => (fuel, 1, fields.length)

  def remapConjAlternatives
      (fuel : Nat)
      (frameDepth : Nat)
      (oldLabels : List Field)
      (mergedMap : List (String × Nat)) : List (Mark × Value) -> List (Mark × Value)
    | [] => []
    | alternative :: rest =>
        (alternative.fst, remapConjRefs fuel frameDepth oldLabels mergedMap alternative.snd)
          :: remapConjAlternatives fuel frameDepth oldLabels mergedMap rest
  termination_by alternatives => (fuel, 1, alternatives.length)

  def remapConjPatterns
      (fuel : Nat)
      (frameDepth : Nat)
      (oldLabels : List Field)
      (mergedMap : List (String × Nat)) : List (Value × Value) -> List (Value × Value)
    | [] => []
    | pattern :: rest =>
        (
          remapConjRefs fuel frameDepth oldLabels mergedMap pattern.fst,
          remapConjRefs fuel frameDepth oldLabels mergedMap pattern.snd
        ) :: remapConjPatterns fuel frameDepth oldLabels mergedMap rest
  termination_by patterns => (fuel, 1, patterns.length)

  def remapConjClauses
      (fuel : Nat)
      (frameDepth : Nat)
      (oldLabels : List Field)
      (mergedMap : List (String × Nat)) : List (Clause Value) -> List (Clause Value)
    | [] => []
    | .forIn key value source :: rest =>
        -- The source is resolved in the scope BEFORE this `for`'s own frame is pushed, so it
        -- sits at `frameDepth`; subsequent clauses and the body are one frame deeper.
        Clause.forIn key value (remapConjRefs fuel frameDepth oldLabels mergedMap source)
          :: remapConjClauses fuel (frameDepth + 1) oldLabels mergedMap rest
    | .guard condition :: rest =>
        Clause.guard (remapConjRefs fuel frameDepth oldLabels mergedMap condition)
          :: remapConjClauses fuel frameDepth oldLabels mergedMap rest
    | .letClause name value :: rest =>
        -- Like `for`: the bound value is in the scope BEFORE the let's frame is pushed
        -- (`frameDepth`); subsequent clauses + the body are one frame deeper.
        Clause.letClause name (remapConjRefs fuel frameDepth oldLabels mergedMap value)
          :: remapConjClauses fuel (frameDepth + 1) oldLabels mergedMap rest
  termination_by clauses => (fuel, 1, clauses.length)
end

/-- Rebase every field in a conjunct against the merged frame layout (see `remapConjRefs`).
    `frameDepth` starts at 0: the conjunct's own fields sit directly in the merged frame. -/
def rebaseConjunctFields (oldFields : List Field) (mergedMap : List (String × Nat)) : List Field :=
  remapConjFields remapFuel 0 oldFields mergedMap oldFields

/-- Merge a conjunct's declarations into the accumulated frame (deferred `.conj` on label
    collisions), preserving first-occurrence order. Uses plain `joinUnevaluated` (NOT
    `canonicalizeFields`'s definition-aware combiner): this is the conj-of-EMBEDS path, where two
    same-label def decls coming from DISTINCT conjuncts (a host's `#data` + an embedded mixin's
    `#data`) must `.conj`-MEET, not close-once-union — close-once is for repeated decls of ONE def
    path within ONE struct body (`canonicalizeFields`), not for a host's field meeting an embed's.
    Unioning here wrongly re-opened a closed pattern def (`#data: [string]: string` gained a stray
    `...`). The merged frame still matches duplicate-label canonicalization for non-definition
    labels (which `.conj`-meet identically either way). -/
def mergeConjFields (accumulated : List Field) (fields : List Field) : List Field :=
  fields.foldl
    (fun current field =>
      match mergeFieldIntoWith joinUnevaluated current field with
      | some merged => merged
      | none => current ++ [field])
    accumulated

/-- Merge one PROVENANCE-tagged operand's fields into the accumulated frame, choosing the
    value-combiner per label collision by class + cross-provenance (Bug2-8). Two same-label
    DEFINITION-class decls whose operands have DIFFERENT provenance (`ownDecl` × `embeddedDecl`
    — the def's own `#m` decl met by a host narrowing routed through the embed) close ONCE over
    their UNION (`mergeDefinitionDecls`, the Bug2-6 lever): they are repeated declarations of the
    ONE definition path, merged across the embed boundary. Every other collision — a regular/
    pattern/optional field, OR two same-provenance decls — keeps the plain `.conj`
    (`mergeConjFields` semantics), so a host's `data: [string]:string` meeting an embed's same
    regular pattern field stays a cross-conjunct value-MEET (the cert-manager canary), and a
    genuine distinct-def `#A & #B` (each its own operand, both `ownDecl` at a use-site meet) never
    unions. The cross-provenance test is what makes the union fire for exactly the same-def-PATH
    decl pair and nothing else. -/
def mergeConjOperandFields
    (accumulated : List Field) (incomingProv : DeclProvenance)
    (accProv : List (String × DeclProvenance)) (fields : List Field) :
    List Field × List (String × DeclProvenance) :=
  fields.foldl
    (fun (state : List Field × List (String × DeclProvenance)) field =>
      let (current, provMap) := state
      let label := Field.label field
      let existingProv := (provMap.find? (·.fst == label)).map Prod.snd
      let crossProvenance := match existingProv with
        | some prov => prov != incomingProv
        | none => false
      let unionsAsDef := (Field.fieldClass field).isDefinition && crossProvenance
      if unionsAsDef then
        match mergeFieldIntoWith mergeDefinitionDecls current field with
        | some merged => (merged, provMap)
        | none => (current ++ [field], (label, incomingProv) :: provMap)
      else
        match mergeFieldIntoWith joinUnevaluated current field with
        | some merged =>
            let provMap := if existingProv.isSome then provMap else (label, incomingProv) :: provMap
            (merged, provMap)
        | none => (current ++ [field], (label, incomingProv) :: provMap))
    (accumulated, accProv)

/-- Apply each closed conjunct's closedness against the merged fields, folding outward just
    as `applyStructClosedness` does for a binary meet — a field absent from a closed
    conjunct's declared labels is marked not-allowed. -/
def applyConjClosedness (conjuncts : List (List Field × Bool)) (mergedFields : List Field) : List Field :=
  conjuncts.foldl
    (fun fields conjunct => applyClosednessFrom conjunct.fst conjunct.snd fields)
    mergedFields

def allClosednessOpen : List (List Field × Bool) -> Bool
  | [] => true
  | conjunct :: rest => conjunct.snd && allClosednessOpen rest

/-- Normalize an evaluated disjunction for the value/display path. The all-regular case
    folds through `join` (the lattice union, which already sheds top-level `.bottom` arms and
    subsumes comparable values). The has-default case prunes via `liveAlternatives`
    (flatten + drop-`containsBottom` + dedup) so a bottomed arm — including a deep
    `.structuralCycle` arm from a terminating recursive def like `#List | *null` — never
    lingers in the value: with the cyclic arm gone, a lone surviving arm collapses to its
    value (`{…} | *null` ⇒ `null`, the spec's "valid if any conjunct is not cyclic" rule).
    A multi-arm live disjunction KEEPS its marks unresolved — collapsing `*1 | 2` to its
    default `1` here would be unsound: a later meet (`b: a & 2`) must still see the `2` arm
    (default selection is a manifest/force-time projection via `resolveDisjDefault?`, not a
    value rewrite). Mark-agnostic lone-arm collapse is sound because a single live arm is the
    disjunction's only inhabited value. -/
def normalizeEvaluatedDisj (alternatives : List (Mark × Value)) : Value :=
  if allRegularAlternatives alternatives then
    joinValues (alternatives.map Prod.snd)
  else
    -- The has-default tail (prune-then-collapse, mark-agnostic lone-arm rule) is exactly
    -- `normalizeDisj` (Lattice) — AD2-1's shared lone-arm rule, reused rather than restated.
    normalizeDisj alternatives

/-- The value a selected field yields — the SINGLE closing decision shared by every eager
    selection (`selectFromConcrete`'s three carrier pluck sites) AND, by intent, the force path's
    `importDefClosureBody?`/`refDefClosureBody?` producers, which run the same
    `normalizeDefinitionValueWithFuel` when they pluck a def body. Selecting a DEFINITION
    (`#Def`) yields its body CLOSED as a definition body, so the eager and force paths cannot
    disagree about closedness: an imported package's def bodies are NOT closed at load (the
    `importBinding` arm of `normalizeFieldWithFuel` skips a bound package to stay cue-lazy — it
    must not re-close unreferenced nested defs, the A2 trap), so without closing HERE an eager
    `pkg.#Def & {extra}` silently admits the extra (and skips the def's own patterns). Closing is
    idempotent for a same-file def (already closed at load), load-bearing for an imported one, and
    preserves a `...`/`defOpenViaTail` body OPEN (`normalizeDefinitionValueWithFuel` returns it
    unchanged), so an open def keeps admitting use-site fields. A non-definition field is yielded
    raw — a regular field's struct value stays open, as CUE keeps it.

    An UNSET OPTIONAL field (`fieldClass.optionality == .optional`) selects to ABSENT (`.bottom`),
    not its declared type — the selection-time analog of `containsBottomFields`'s optional-skip
    (`Lattice.lean`): an optional declaration is a CONSTRAINT, not a value, so until unification
    SUPPLIES the field it is absent, and a reference/presence-test against it is `_|_` (Bug2-13).
    The discriminator is the `.optional` rung itself: supplying a regular conjunct (`#opt: v`)
    downgrades optionality to `.regular` via `mergeFieldClass` (`lo.meet ro`, and
    `optional.meet regular = regular`), so a SET optional is no longer `.optional` and keeps
    resolving to its value. Presence, not concreteness — `#opt?: 5` unset is still `.optional`,
    hence still absent, matching cue. -/
def selectedFieldValue (field : Field) : Value :=
  match field.fieldClass.optionality with
  | .optional => .bottom
  | _ =>
    if field.fieldClass.isDefinition then
      normalizeDefinitionValueWithFuel normalizeFuel (Field.value field)
    else
      Field.value field

/-- Select `label` from a carrier's decl/field list: the found field's `selectedFieldValue`
    (the single closing decision) or ABSENT (`.bottom`) on a miss. Shared by every decl-bearing
    carrier shape (`.struct`/`.embeddedList`/`.embeddedScalar`) — they all reach their decls
    identically, so selection is identical regardless of carrier.

    A miss is FINAL-ABSENT, not a deferral (missing-field-selection): every caller reaches here
    with `base` an ALREADY-EVALUATED concrete struct carrier (`selectFromConcrete`'s struct/embed
    arms, or a resolved disjunction DEFAULT arm) — all conjuncts are merged before the struct
    value exists (`x: base & extra` supplies `b` at unification, BEFORE selection), so a field
    absent from the merged decls can never arrive later. Selecting it is absence, not an
    incomplete deferral: `.bottom` ⇒ `classifyDefinedness` `.error` ⇒ `x.b == _|_` true / `!= _|_`
    false, matching cue (a missing field on a concrete struct is ABSENT even with an open `...`
    tail). The PROVISIONAL case — an UNRESOLVED disjunction with no unique default, where a later
    arm could supply the field — never reaches here: `selectEvaluatedField`'s `.disj` arm only
    routes to `selectFromConcrete` once `resolveDisjDefault?` picks a concrete (non-disjunction)
    arm, and otherwise keeps the deferred `.selector base label` itself. Same family as Bug2-13: a
    deferral was masking final absence. -/
def selectFromDecls (label : String) (decls : List Field) : Value :=
  match findEvalField label decls with
  | some field => selectedFieldValue field
  | none => .bottom

/-- Select `label` from an already-collapsed (non-disjunction) carrier — the single shared
    dispatch for every concrete shape selection can land on, used directly by
    `selectEvaluatedField` and by its `.disj` arm once a default is resolved. A decl-bearing
    carrier plucks via `selectFromDecls`; any non-carrier (scalar, list, kind, …) is `.bottom`
    — selecting a field off a non-struct/non-list is a type error (cue: `invalid operand …
    want list or struct`), and `.bottom` ⇒ the field's arm sheds, matching cue. -/
def selectFromConcrete (base : Value) (label : String) : Value :=
  match base with
  | .struct fields _ _ _ _ => selectFromDecls label fields
  | .embeddedList _ _ decls => selectFromDecls label decls
  | .embeddedScalar _ decls => selectFromDecls label decls
  | .bottomWith reasons => .bottomWith reasons
  | .top | .bottom | .prim _ | .kind _ | .notPrim _
  | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _ | .builtinCall _ _
  | .unary _ _ | .binary _ _ _ | .ref _ | .refId _ | .patternLabel _ | .thisStruct
  | .selector _ _ | .index _ _ | .disj _ | .list _ | .listTail _ _
  | .comprehension _ _ | .structComp _ _ _ | .listComprehension _ _
  | .interpolation _ | .dynamicField _ _ _ | .closure _ _ => .bottom

def selectEvaluatedField (base : Value) (label : String) : Value :=
  match base with
  | .disj alternatives =>
      -- Selecting INTO a disjunction collapses it to its default arm first, then selects the
      -- field off that arm via the shared `selectFromConcrete` dispatch — CUE's default rule
      -- (`d.a` where `d: *{a:1} | {a:2}` is `1`). A unique marked default (or a lone regular
      -- alternative) resolves. A default that is ITSELF a disjunction (the doubly-nested
      -- default the one-level `liveAlternatives` flatten leaves un-collapsed, unreachable from
      -- source since eval-time flatten pre-collapses) keeps the deferred `.selector`, as does
      -- `none` (no unique default): both leave the disjunction unresolved so manifest reports
      -- the ambiguity rather than a spurious `bottom`.
      match resolveDisjDefault? alternatives with
      | some (.disj _) => .selector base label
      | some default => selectFromConcrete default label
      | none => .selector base label
  | .top | .bottom | .bottomWith _ | .prim _ | .kind _
  | .notPrim _ | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _
  | .builtinCall _ _ | .unary _ _ | .binary _ _ _ | .ref _ | .refId _ | .patternLabel _
  | .thisStruct | .selector _ _ | .index _ _ | .struct _ _ _ _ _ | .list _
  | .listTail _ _ | .embeddedList _ _ _ | .embeddedScalar _ _ | .comprehension _ _
  | .structComp _ _ _ | .listComprehension _ _ | .interpolation _
  | .dynamicField _ _ _ | .closure _ _ => selectFromConcrete base label

def getListValue? : Nat -> List Value -> Option Value
  | _, [] => none
  | 0, value :: _ => some value
  | index + 1, _ :: values => getListValue? index values

def selectEvaluatedListIndex (base key : Value) (items : List Value) : Value :=
  match key with
  | .prim (.int index) =>
      if index < 0 then
        .bottomWith [.invalidIndex index]
      else
        match getListValue? index.toNat items with
        | some item => item
        | none => .bottomWith [.indexOutOfRange index items.length]
  | .prim _ => .bottom
  | .top | .bottom | .bottomWith _ | .kind _ | .notPrim _
  | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _ | .builtinCall _ _
  | .unary _ _ | .binary _ _ _ | .ref _ | .refId _ | .patternLabel _ | .thisStruct
  | .selector _ _ | .index _ _ | .disj _ | .struct _ _ _ _ _ | .list _
  | .listTail _ _ | .embeddedList _ _ _ | .embeddedScalar _ _ | .comprehension _ _
  | .structComp _ _ _ | .listComprehension _ _ | .interpolation _
  | .dynamicField _ _ _ | .closure _ _ => .index base key

def selectEvaluatedListTailIndex (base key : Value) (items : List Value) : Value :=
  match key with
  | .prim (.int index) =>
      if index < 0 then
        .bottomWith [.invalidIndex index]
      else
        match getListValue? index.toNat items with
        | some item => item
        | none => .index base key
  | .prim _ => .bottom
  | .top | .bottom | .bottomWith _ | .kind _ | .notPrim _
  | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _ | .builtinCall _ _
  | .unary _ _ | .binary _ _ _ | .ref _ | .refId _ | .patternLabel _ | .thisStruct
  | .selector _ _ | .index _ _ | .disj _ | .struct _ _ _ _ _ | .list _
  | .listTail _ _ | .embeddedList _ _ _ | .embeddedScalar _ _ | .comprehension _ _
  | .structComp _ _ _ | .listComprehension _ _ | .interpolation _
  | .dynamicField _ _ _ | .closure _ _ => .index base key

def selectEvaluatedFieldIndex (base key : Value) (fields : List Field) : Value :=
  match key with
  | .prim (.string label) =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .index base key
  | .prim _ => .bottom
  | .top | .bottom | .bottomWith _ | .kind _ | .notPrim _
  | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _ | .builtinCall _ _
  | .unary _ _ | .binary _ _ _ | .ref _ | .refId _ | .patternLabel _ | .thisStruct
  | .selector _ _ | .index _ _ | .disj _ | .struct _ _ _ _ _ | .list _
  | .listTail _ _ | .embeddedList _ _ _ | .embeddedScalar _ _ | .comprehension _ _
  | .structComp _ _ _ | .listComprehension _ _ | .interpolation _
  | .dynamicField _ _ _ | .closure _ _ => .index base key

def selectEvaluatedIndex (base key : Value) : Value :=
  match base with
  | .struct fields _ _ _ _ => selectEvaluatedFieldIndex base key fields
  | .list items => selectEvaluatedListIndex base key items
  | .listTail items _ => selectEvaluatedListTailIndex base key items
  | .embeddedList items none _ => selectEvaluatedListIndex base key items
  | .embeddedList items (some _) _ => selectEvaluatedListTailIndex base key items
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | .top | .prim _ | .kind _ | .notPrim _ | .stringRegex _ | .stringFormat _
  | .boundConstraint _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _ | .builtinCall _ _ | .unary _ _
  | .binary _ _ _ | .ref _ | .refId _ | .patternLabel _ | .thisStruct | .selector _ _
  | .index _ _ | .disj _ | .embeddedScalar _ _ | .comprehension _ _
  | .structComp _ _ _ | .listComprehension _ _ | .interpolation _
  | .dynamicField _ _ _ | .closure _ _ => .bottom

/--
Definedness classes for the `e == _|_` / `e != _|_` presence test (CUE's "is this
defined" idiom, as in `if Self.#field != _|_`). The test is NOT value equality against a
sentinel: CUE evaluates the non-`_|_` operand and asks which of three states it landed in.
- `defined`: a resolved, present value (prim, struct, list, …) — `== _|_` is `false`.
- `error`: an evaluated bottom (absent field, conflict, …) — `== _|_` is `true`.
- `incomplete`: a residual/unresolved form (kind, bound, ref, unresolved disj, …) — the
  comparison itself stays incomplete and propagates, so a comprehension guard drops.
-/
inductive Definedness where
  | defined
  | error
  | incomplete
deriving DecidableEq

def classifyDefinedness : Value -> Definedness
  | .bottom => .error
  | .bottomWith _ => .error
  | .prim _ => .defined
  | .list _ => .defined
  | .listTail _ _ => .defined
  | .embeddedList _ _ _ => .defined
  | .embeddedScalar _ _ => .defined
  | .structComp _ _ _ => .defined
  -- A no-patterns struct is a present concrete value → `.defined`; a pattern-bearing struct
  -- (a residual constraint) is `.incomplete`. The discriminator is `patterns.isEmpty`.
  | .struct _ _ _ [] _ => .defined
  | .struct _ _ _ (_ :: _) _ => .incomplete
  -- A DISJUNCTION with ≥1 LIVE arm is a PRESENT value (CUE: `(*"argocd" | string) != _|_` is
  -- `true`, `("a"|"b") != _|_` is `true`); without it a presence guard over a default/plain
  -- disjunction (argocd `#ArgoRepo`/`parts.#Metadata` `#ns: *"argocd" | string` then
  -- `if Self.#ns != _|_ {namespace: Self.#ns}`) dropped the guarded field cue emits. The
  -- "≥1 live arm" condition is the runtime invariant `liveAlternatives` is meant to preserve,
  -- but it is NOT type-enforced: a `.disj []` / `.disj [all-bottom]` slipping past pruning into
  -- this test would misclassify an absent value `.defined` (`X != _|_` wrongly `true`). Classify
  -- by the LIVE arms so the invariant is checked HERE, where soundness depends on it: no live arm
  -- ⇒ the disjunction IS bottom ⇒ `.error`.
  | .disj alternatives =>
      match liveAlternatives alternatives with
      | [] => .error
      | _ => .defined
  -- Residual / unresolved forms: the comparison itself stays incomplete and propagates. Enumerated
  -- (no catch-all) so a future CONCRETE present-value constructor cannot silently fall through to
  -- `.incomplete` — it forces a compile error here, where its definedness must be decided. (`top`
  -- is incomplete: cue rejects `_ != _|_`, "requires concrete value".)
  | .top => .incomplete
  | .kind _ => .incomplete
  | .notPrim _ => .incomplete
  | .stringRegex _ => .incomplete
  | .stringFormat _ => .incomplete
  | .boundConstraint _ _ => .incomplete
  | .lengthConstraint _ _ _ => .incomplete
  | .uniqueItems => .incomplete
  | .conj _ => .incomplete
  | .builtinCall _ _ => .incomplete
  | .unary _ _ => .incomplete
  | .binary _ _ _ => .incomplete
  | .ref _ => .incomplete
  | .refId _ => .incomplete
  | .patternLabel _ => .incomplete
  | .thisStruct => .incomplete
  | .selector _ _ => .incomplete
  | .index _ _ => .incomplete
  | .comprehension _ _ => .incomplete
  | .listComprehension _ _ => .incomplete
  | .interpolation _ => .incomplete
  | .dynamicField _ _ _ => .incomplete
  | .closure _ _ => .incomplete

def isPresenceTestOp : BinaryOp -> Bool
  | .eq => true
  | .ne => true
  | _ => false

/--
Evaluate one side of an `== _|_` / `!= _|_` presence test against the literal `_|_`.
`equality` is `true` for `==`, `false` for `!=`. The non-`_|_` operand `value` is already
evaluated. An `incomplete` operand yields a residual comparison node against `_|_` (so the
shape round-trips), which a comprehension guard treats as not-true.
-/
def evalPresenceTest (equality : Bool) (value : Value) : Value :=
  match classifyDefinedness value with
  | .defined => .prim (.bool (!equality))
  | .error => .prim (.bool equality)
  | .incomplete =>
      if equality then .binary .eq value .bottom else .binary .ne value .bottom

/-- The verdict for a comprehension `if` guard's evaluated condition. CUE requires the guard
    to be `bool`; `classifyGuard` sorts the (already default-resolved) condition into the five
    spec-distinguished cases — an exhaustive split, no catch-all `drop`:
    - `concreteTrue`/`concreteFalse` — a concrete `bool`: admit / drop the body.
    - `bottom` — an evaluated error: propagate (D#1a; a nested bottom guard must not vanish).
    - `nonBool` — a concrete value of non-`bool` type (`if "x"`/`if 3`/`if {…}`/`if [..]`): a
      type error (D#1c). CUE: `cannot use … as type bool`.
    - `incomplete` — an unresolved/abstract guard (a ref, kind, bound, builtin, or unresolved
      disjunction): the comprehension cannot be decided yet, so it DEFERS (D#1b) — it stays
      residual rather than dropping to `{}`. -/
inductive GuardVerdict where
  | concreteTrue
  | concreteFalse
  | bottom (value : Value)
  | nonBool (type : ConcreteTypeName)
  | incomplete
deriving BEq

/-- Classify a guard condition, enumerating EVERY `Value` constructor (no catch-all) so a new
    arm forces a decision here. Three non-`incomplete` outcomes:
    - `concreteTrue`/`concreteFalse` — a concrete `bool`, OR a residual PRESENCE test `X == _|_`
      / `X != _|_` (the shape `evalPresenceTest` emits for an incomplete operand). The presence
      could not be confirmed, so the guard is not satisfied ⇒ drop — the pre-existing
      cue-eval-correct behavior (`if base.g != _|_ {…}` with `g` absent, and `if y != _|_ {…}`
      with abstract `y`, both yield `out: {}`).
    - `nonBool` — a fully-concrete present value of non-`bool` type (non-bool prim / no-pattern
      struct / any list): a type error (D#1c). CUE: `cannot use … as type bool`.
    Everything else is genuinely ABSTRACT and DEFERS (D#1b): a kind, bound, unresolved disjunction
    (cue: `unresolved disjunction … (type bool)`, even all-bool `true | false`), a NON-presence
    comparison (`if x > 5`), a ref/selector/builtin, etc. — the comprehension stays residual
    rather than silently dropping. A pattern-bearing struct is a residual constraint, so it
    defers. -/
def classifyGuard : Value -> GuardVerdict
  | .prim (.bool true) => .concreteTrue
  | .prim (.bool false) => .concreteFalse
  | .prim p => .nonBool (.scalar p.kind)
  | .bottom => .bottom .bottom
  | .bottomWith reasons => .bottom (.bottomWith reasons)
  | .struct _ _ _ [] _ => .nonBool .struct
  | .list _ => .nonBool .list
  | .listTail _ _ => .nonBool .list
  | .embeddedList _ _ _ => .nonBool .list
  -- A scalar carrier (`{#a:1, true}`) guards as its inner scalar — cue: `if {#a:1,true}` sees
  -- the bool. The inner scalar is terminal (`isTerminalScalar` at construction), so this recurses
  -- exactly once onto a non-carrier value.
  | .embeddedScalar scalar _ => classifyGuard scalar
  -- A residual presence test (`eq`/`ne` against `.bottom`) is not satisfied ⇒ drop (NOT defer);
  -- every OTHER `.binary` (e.g. `x > 5`) is an abstract guard that defers.
  | .binary .eq _ .bottom => .concreteFalse
  | .binary .ne _ .bottom => .concreteFalse
  | .binary _ _ _ => .incomplete
  -- Unresolved / abstract forms → DEFER (keep the comprehension residual):
  | .struct _ _ _ (_ :: _) _ => .incomplete
  | .structComp _ _ _ => .incomplete
  | .top => .incomplete
  | .kind _ => .incomplete
  | .notPrim _ => .incomplete
  | .stringRegex _ => .incomplete
  | .stringFormat _ => .incomplete
  | .boundConstraint _ _ => .incomplete
  | .lengthConstraint _ _ _ => .incomplete
  | .uniqueItems => .incomplete
  | .conj _ => .incomplete
  | .builtinCall _ _ => .incomplete
  | .unary _ _ => .incomplete
  | .ref _ => .incomplete
  | .refId _ => .incomplete
  | .patternLabel _ => .incomplete
  | .thisStruct => .incomplete
  | .selector _ _ => .incomplete
  | .index _ _ => .incomplete
  | .disj _ => .incomplete
  | .comprehension _ _ => .incomplete
  | .listComprehension _ _ => .incomplete
  | .interpolation _ => .incomplete
  | .dynamicField _ _ _ => .incomplete
  | .closure _ _ => .incomplete

/-- The verdict for a dynamic field's evaluated label `(expr): v`. CUE requires a field label
    to be a string; `classifyDynLabel` sorts the evaluated label into the three spec-distinguished
    cases — an exhaustive split, no silent `drop` of the field:
    - `concreteString` — re-key the field to this label.
    - `bottom` — an evaluated error: propagate (a bottom key must not vanish; cue surfaces the
      underlying conflict).
    - `nonString` — a CONCRETE value of non-`string` type (`(3)`, `(true)`, `({})`, `([])`): a
      type error (cue: `invalid index … (invalid type …)`).
    - `incomplete` — an unresolved/abstract label (a kind, ref, bound, builtin, unresolved
      disjunction, even the abstract `string` kind): the field cannot be keyed yet, so it DEFERS
      — it stays a residual `.dynamicField` rather than dropping (cue holds it under eval, errors
      under export). -/
inductive DynLabelVerdict where
  | concreteString (name : String)
  | bottom (value : Value)
  | nonString (type : ConcreteTypeName)
  | incomplete
deriving BEq

/-- Classify a dynamic field's evaluated label, enumerating EVERY `Value` constructor (no
    catch-all) so a new arm forces a decision here. Mirrors `classifyGuard`. -/
def classifyDynLabel : Value -> DynLabelVerdict
  | .prim (.string name) => .concreteString name
  | .prim p => .nonString (.scalar p.kind)
  | .bottom => .bottom .bottom
  | .bottomWith reasons => .bottom (.bottomWith reasons)
  -- A concrete value of non-string type can never be a label ⇒ type error (NOT defer):
  | .struct _ _ _ [] _ => .nonString .struct
  | .list _ => .nonString .list
  | .listTail _ _ => .nonString .list
  | .embeddedList _ _ _ => .nonString .list
  -- A scalar carrier (`{#a:1, "k"}`) labels as its inner scalar — cue: `({#a:1,"k"}): v` keys on
  -- `"k"`. The inner scalar is terminal, so this recurses exactly once onto a non-carrier value.
  | .embeddedScalar scalar _ => classifyDynLabel scalar
  -- Unresolved / abstract forms → DEFER (keep the field residual). The abstract `string` kind
  -- lands here: it may still narrow to a concrete string at a use site.
  | .top => .incomplete
  | .kind _ => .incomplete
  | .notPrim _ => .incomplete
  | .stringRegex _ => .incomplete
  | .stringFormat _ => .incomplete
  | .boundConstraint _ _ => .incomplete
  | .lengthConstraint _ _ _ => .incomplete
  | .uniqueItems => .incomplete
  | .conj _ => .incomplete
  | .builtinCall _ _ => .incomplete
  | .unary _ _ => .incomplete
  | .binary _ _ _ => .incomplete
  | .ref _ => .incomplete
  | .refId _ => .incomplete
  | .patternLabel _ => .incomplete
  | .thisStruct => .incomplete
  | .selector _ _ => .incomplete
  | .index _ _ => .incomplete
  | .disj _ => .incomplete
  -- A pattern-bearing struct is a residual constraint, not a concrete value ⇒ defer.
  | .struct _ _ _ (_ :: _) _ => .incomplete
  | .structComp _ _ _ => .incomplete
  | .comprehension _ _ => .incomplete
  | .listComprehension _ _ => .incomplete
  | .interpolation _ => .incomplete
  | .dynamicField _ _ _ => .incomplete
  | .closure _ _ => .incomplete

/-- Collapse an evaluated dynamic-field label that is a DEFAULT disjunction to its default before
    classification, exactly as a default disjunction collapses as an `if` guard (`expandClauseChain`)
    or under manifestation: `(*"a" | "b"): v` keys on `"a"`, so `classifyDynLabel` still DEFERS an
    AMBIGUOUS one. A non-`.disj` label is returned unchanged. -/
def resolveDynLabelDefault (label : Value) : Value :=
  collapseDefaultDisjunction label

/--
The synthetic env frame a `for` iteration introduces. Mirrors `clauseLoopFrame`
in `Resolve`: keyed iterations bind the key at index 0 and the value at index 1,
unkeyed iterations bind the value at index 0. The bound values are already
evaluated, so referencing them re-evaluates a concrete value.
-/
def loopFrame (key : Option String) (keyValue : Value) (value : String) (element : Value) : List Field :=
  match key with
  | some key => [⟨key, .regular, keyValue, false⟩, ⟨value, .regular, element, false⟩]
  | none => [⟨value, .regular, element, false⟩]

/-- The verdict on one evaluated interpolation hole, mirroring `DynLabelVerdict`/`classifyGuard`:
    an exhaustive split with no silent passthrough.
    - `text` — a concrete operand of interpolatable type (`bool|string|number`), rendered to its
      natural string form (a string contributes its raw content, numbers/booleans their spelling).
    - `bottom` — an evaluated error: propagate.
    - `nonInterpolatable` — a CONCRETE value of a type interpolation forbids (`null`, list, struct):
      a type error (cue: `cannot use … as type (bool|string|bytes|number)`), NOT a passthrough.
    - `incomplete` — an unresolved/abstract operand (ref, kind, bound, builtin, unresolved
      disjunction, or a bytes value pending render support): the hole cannot render yet, so it
      DEFERS — the interpolation stays a residual `.interpolation` rather than erroring. -/
inductive InterpVerdict where
  | text (s : String)
  | bottom (value : Value)
  | nonInterpolatable (type : ConcreteTypeName)
  | incomplete
deriving BEq

/-- Classify one evaluated interpolation hole, enumerating EVERY `Value` constructor (no
    catch-all) so a new arm forces a decision here. Mirrors `classifyDynLabel`.

    `bytes` is a spec-interpolatable type: the enclosing literal kind fixes the result and the
    operand is coerced to its string form. Valid-UTF-8 byte content decodes to text; invalid
    UTF-8 is unrepresentable as a Lean `String`, so it DEFERS rather than fabricating (cue
    lossily replaces invalid runes with U+FFFD on export — an obscure edge left deferred). -/
def classifyInterpolationPart : Value -> InterpVerdict
  | .prim (.string value) => .text value
  | .prim (.int value) => .text (toString value)
  | .prim (.float _ text) => .text text
  | .prim (.bool true) => .text "true"
  | .prim (.bool false) => .text "false"
  | .bottom => .bottom .bottom
  | .bottomWith reasons => .bottom (.bottomWith reasons)
  -- Concrete values of a forbidden interpolation type ⇒ type error (NOT defer, NOT passthrough):
  | .prim .null => .nonInterpolatable (.scalar .null)
  | .list _ => .nonInterpolatable .list
  | .listTail _ _ => .nonInterpolatable .list
  | .embeddedList _ _ _ => .nonInterpolatable .list
  | .struct _ _ _ _ _ => .nonInterpolatable .struct
  -- A scalar carrier interpolates as its inner scalar — mirrors `classifyDynLabel`.
  | .embeddedScalar scalar _ => classifyInterpolationPart scalar
  -- A bytes operand coerces to its string form; valid UTF-8 renders, invalid UTF-8 defers.
  | .prim (.bytes value) =>
      match String.fromUTF8? (ByteArray.mk value) with
      | some text => .text text
      | none => .incomplete
  -- Every unresolved/abstract form ⇒ DEFER:
  | .top => .incomplete
  | .kind _ => .incomplete
  | .notPrim _ => .incomplete
  | .stringRegex _ => .incomplete
  | .stringFormat _ => .incomplete
  | .boundConstraint _ _ => .incomplete
  | .lengthConstraint _ _ _ => .incomplete
  | .uniqueItems => .incomplete
  | .conj _ => .incomplete
  | .builtinCall _ _ => .incomplete
  | .unary _ _ => .incomplete
  | .binary _ _ _ => .incomplete
  | .ref _ => .incomplete
  | .refId _ => .incomplete
  | .patternLabel _ => .incomplete
  | .thisStruct => .incomplete
  | .selector _ _ => .incomplete
  | .index _ _ => .incomplete
  | .disj _ => .incomplete
  | .structComp _ _ _ => .incomplete
  | .comprehension _ _ => .incomplete
  | .listComprehension _ _ => .incomplete
  | .interpolation _ => .incomplete
  | .dynamicField _ _ _ => .incomplete
  | .closure _ _ => .incomplete

/-- Fold two hole verdicts with precedence `bottom > nonInterpolatable > incomplete > text`:
    an error anywhere sinks the whole interpolation, an incomplete hole defers it, and only an
    all-`text` interpolation renders. Left-biased on the error/incomplete carriers. -/
def combineInterpVerdict : InterpVerdict -> InterpVerdict -> InterpVerdict
  | .bottom v, _ => .bottom v
  | _, .bottom v => .bottom v
  | .nonInterpolatable t, _ => .nonInterpolatable t
  | _, .nonInterpolatable t => .nonInterpolatable t
  | .incomplete, _ => .incomplete
  | _, .incomplete => .incomplete
  | .text a, .text b => .text (a ++ b)

def evalInterpolation (parts : List Value) : Value :=
  match parts.foldl (fun acc p => combineInterpVerdict acc (classifyInterpolationPart p)) (.text "") with
  | .text text => .prim (.string text)
  | .bottom value => value
  | .nonInterpolatable type => .bottomWith [.nonInterpolatable type]
  | .incomplete => .interpolation parts

/--
A `structComp` carries three kinds of member in its `comprehensions` bucket: field
comprehensions, dynamic fields, and plain embeddings. The first two expand to fields
merged into the struct; an embedding is an arbitrary value unified (`meet`) with the
whole struct, so a struct embedding merges its fields and a non-struct embedding
conflicts. Both kinds resolve in the enclosing struct's lexical frame.
-/
def isEmbeddingValue : Value -> Bool
  | .comprehension _ _ => false
  | .dynamicField _ _ _ => false
  | _ => true

/-- A struct-like body, for structural-cycle detection (D#2a): a `.struct`/`.structComp` whose
    re-entrant evaluation through a reference is a structural cycle. EXCLUDES list bodies — a
    recursion through an open list tail (`#L: {kids: [...#L]}`) is the standard recursive-tree
    idiom and is NOT cyclic (the tail defers, so the list is finite), confirmed against `cue`. A
    bare `.refId` is likewise excluded: a self-ref with no struct layer is a REFERENCE cycle
    (`x: x` → `_`), not a structural one. -/
def isStructLikeBody : Value -> Bool
  | .struct _ _ _ _ _ => true
  | .structComp _ _ _ => true
  | _ => false

/-- Re-wrap a resolved struct that still has DEFERRED (incomplete-guard) comprehensions (D#1b) as
    a residual `.structComp`, so the undecidable comprehension round-trips (cue holds it under eval,
    errors incomplete under export) instead of being dropped. With no deferred comprehensions the
    resolved value is returned UNCHANGED (byte-identical to the pre-D#1b path). A non-struct
    `resolved` (e.g. a bottom from the embedding meet) dominates and is returned as-is — a bottom is
    a stronger verdict than an unresolved comprehension. `fields` come from the resolved struct so
    embeddings already meet in; the deferred `if`/`for` residuals re-expand on a later re-eval. -/
def withDeferredComprehensions (resolved : Value) (deferred : List Value)
    (openness : StructOpenness) : Value :=
  match deferred with
  | [] => resolved
  | _ :: _ =>
      match resolved with
      | .struct fields _ _ _ _ => .structComp fields deferred openness
      | .top | .bottom | .bottomWith _ | .prim _ | .kind _
      | .notPrim _ | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _
      | .builtinCall _ _ | .unary _ _ | .binary _ _ _ | .ref _ | .refId _ | .patternLabel _
      | .thisStruct | .selector _ _ | .index _ _ | .disj _ | .list _
      | .listTail _ _ | .embeddedList _ _ _ | .embeddedScalar _ _
      | .comprehension _ _ | .structComp _ _ _ | .listComprehension _ _
      | .interpolation _ | .dynamicField _ _ _ | .closure _ _ => resolved

def listPairsFrom (index : Nat) : List Value -> List (Value × Value)
  | [] => []
  | item :: items => (.prim (.int index), item) :: listPairsFrom (index + 1) items

def structPairs : List Field -> List (Value × Value)
  | [] => []
  | field :: fields =>
      if Field.fieldClass field == .regular then
        (.prim (.string (Field.label field)), Field.value field) :: structPairs fields
      else
        structPairs fields

/-- The domain status of an evaluated `for` source, mirroring `classifyArithOperand`'s
    concrete-wrong → error / incomplete → defer discipline. The CUE spec mandates `for` range
    over a list or struct:
    - `iterable` — a list/struct/embedded-list carrier: carries the (key, value) pairs to walk.
      An `.embeddedList` (`{#a:1,[1,2]}`) iterates the EMBEDDED LIST (B3), cue: `[1,2]`.
    - `concreteNonIterable` — a CONCRETE scalar (or scalar carrier `{#a:1,5}`): definitively
      outside the list/struct domain ⇒ a TYPE ERROR (cue: `cannot range over 5 …`). Carries the
      offending type for the `nonIterableSource` reason.
    - `bottom` — a source that EVALUATES to bottom (`1 & 2`): a definite error, propagated
      (D#1a — short-circuits the comprehension, mirroring `classifyGuard`'s `.bottom` arm).
    - `incomplete` — an unresolved/abstract form (ref, kind, bound, unresolved disjunction, …):
      it may still resolve to a list/struct, so the comprehension DEFERS (residual), exactly as
      an incomplete `if` guard defers (D#1b). Enumerated with no catch-all so a new ctor forces a
      decision here. -/
inductive ForSourceClass where
  | iterable (pairs : List (Value × Value))
  | concreteNonIterable (type : ConcreteTypeName)
  | bottom (value : Value)
  | incomplete

def classifyForSource : Value -> ForSourceClass
  | .list items => .iterable (listPairsFrom 0 items)
  | .listTail items _ => .iterable (listPairsFrom 0 items)
  | .embeddedList items _ _ => .iterable (listPairsFrom 0 items)
  | .struct fields _ _ _ _ => .iterable (structPairs fields)
  -- A value whose type is DECIDABLY disjoint from list/struct is outside the domain NOW, even if
  -- not fully concrete: it can never unify to a list/struct, so cue errors it (`found int, want
  -- list or struct`) rather than holding. That covers a concrete scalar (`.prim`), a scalar
  -- carrier (`{#a:1,5}` — recurse onto its terminal scalar), an abstract scalar TYPE (`.kind`,
  -- `Kind` holds only scalar kinds), a string-regex constraint, and a numeric bound. `.notPrim`
  -- (`!=5`) admits non-scalars, so it is NOT decidable here → defers.
  | .prim p => .concreteNonIterable (.scalar p.kind)
  | .embeddedScalar scalar _ => classifyForSource scalar
  | .kind k => .concreteNonIterable (.scalar k)
  | .stringRegex _ => .concreteNonIterable (.scalar .string)
  | .stringFormat _ => .concreteNonIterable (.scalar .string)
  | .boundConstraint _ _ => .concreteNonIterable (.scalar .number)
  | .lengthConstraint _ _ _ => .incomplete
  | .uniqueItems => .incomplete
  -- A source that EVALUATES to bottom (`1 & 2`) is a definite value, not a maybe: propagate it
  -- (D#1a — a bottom `for` source short-circuits the comprehension, mirroring the bottom `if`
  -- guard `classifyGuard` routes through its `.bottom` arm). Masking it as `.incomplete` is a
  -- soundness bug — the dead arm would survive a disjunction (`⊥ | x = x`) instead of dropping.
  | .bottom => .bottom .bottom
  | .bottomWith reasons => .bottom (.bottomWith reasons)
  -- Genuinely-unresolved forms may still resolve to a list/struct → DEFER (residual). `.top` (any),
  -- a `.notPrim` exclusion, an unresolved ref/selector/disjunction/conjunction, a residual
  -- comprehension/builtin/interpolation — each can still concretize into an iterable.
  | .top => .incomplete
  | .notPrim _ => .incomplete
  | .conj _ => .incomplete
  | .builtinCall _ _ => .incomplete
  | .unary _ _ => .incomplete
  | .binary _ _ _ => .incomplete
  | .ref _ => .incomplete
  | .refId _ => .incomplete
  | .patternLabel _ => .incomplete
  | .thisStruct => .incomplete
  | .selector _ _ => .incomplete
  | .index _ _ => .incomplete
  | .disj _ => .incomplete
  | .comprehension _ _ => .incomplete
  | .structComp _ _ _ => .incomplete
  | .listComprehension _ _ => .incomplete
  | .interpolation _ => .incomplete
  | .dynamicField _ _ _ => .incomplete
  | .closure _ _ => .incomplete

/--
Memoization key. Evaluation of a `Value` is a pure function of `(fuel, env, visited,
value)`: the same tuple always yields the same result, so caching on the full tuple is
behavior-preserving — it shares an already-computed result rather than re-deriving it.
The `visited` slot set is part of the key, so a binding caught mid-cycle is keyed
separately from the same binding reached fresh; cycle detection is untouched.

The hash is deliberately *shallow* — `fuel`, `visited`, the env frame-count, and the
value's top constructor tag — so a cache probe never traverses the (large) env/value
subtree. Structural `BEq` only runs on a hash-bucket match, i.e. on a genuine hit or a
tag collision; misses stay O(1) on the hash.

The fan-out this kills: a `Self.#components.X` selector re-evaluates the entire
`#components` struct per selection; three sibling selections in a struct embedding (the
`packs.#Argo` shape) re-derive it three times, multiplying per fuel level. Cached,
`#components` is computed once and shared.
-/
def valueTag : Value -> UInt64
  | .top => 0
  | .bottom => 1
  | .bottomWith _ => 2
  | .prim _ => 3
  | .kind _ => 4
  | .notPrim _ => 5
  | .stringRegex _ => 6
  | .stringFormat _ => 35
  | .boundConstraint _ _ => 7
  | .lengthConstraint _ _ _ => 33
  | .uniqueItems => 34
  | .conj _ => 8
  | .builtinCall _ _ => 9
  | .unary _ _ => 10
  | .binary _ _ _ => 11
  | .ref _ => 12
  | .refId _ => 13
  | .patternLabel _ => 36
  | .thisStruct => 14
  | .selector _ _ => 15
  | .index _ _ => 16
  | .disj _ => 17
  | .list _ => 22
  | .listTail _ _ => 23
  | .comprehension _ _ => 24
  | .structComp _ _ _ => 25
  | .interpolation _ => 26
  | .dynamicField _ _ _ => 27
  | .embeddedList _ _ _ => 28
  | .closure _ _ => 29
  | .listComprehension _ _ => 30
  | .struct _ _ _ _ _ => 31
  | .embeddedScalar _ _ => 32

/-- A value whose `evalValueCoreWithFuel` reduction is the IDENTITY, independent of
    `fuel`/`env`/`visited`: the constructors that fall through to the core's trailing
    `| _, value => pure value` arm (which reads none of those inputs). Exactly: `.prim`,
    `.kind`, `.top`, `.bottom`, `.bottomWith`, `.notPrim`, `.stringRegex`, `.boundConstraint`,
    `.thisStruct`. These are scalar/closed leaves carrying no reference into the env, so
    evaluating them yields themselves at any fuel. `evalValueWithFuel` short-circuits them
    before the (env-keyed) cache, skipping a `valueDigest`-hashed probe+insert per occurrence —
    pure speed, value-identical. MUST stay in sync with the core's catch-all arm: a constructor
    listed here that the core handles non-trivially would skip real work (a correctness bug); one
    omitted here merely keeps the (sound) slow path. Every constructor NOT listed has an explicit
    core arm that consumes `env`/`fuel`/`visited` (refs, structs, conjunctions, selectors, …). -/
def selfEvaluatingLeaf? : Value -> Bool
  | .prim _ => true
  | .kind _ => true
  | .top => true
  | .bottom => true
  | .bottomWith _ => true
  | .notPrim _ => true
  | .stringRegex _ => true
  | .stringFormat _ => true
  | .boundConstraint _ _ => true
  | .lengthConstraint _ _ _ => true
  | .uniqueItems => true
  | .thisStruct => true
  | _ => false

/--
A TOTAL, fuel-free, BOUNDED-DEPTH structural digest of a `Value`, for use as a cache-key
HASH (never as an equality test). Recurses `depth` levels into the value's children,
mixing each constructor's tag with its scalar payload (label, prim, refId, selector
label, etc.) and the digests of its child values; at `depth = 0` it stops and returns the
tag alone.

Why this exists: keying the cache hashes (`EvalKey`/`SatKey`) on `valueTag` ALONE — the
top constructor tag (0–31) with no subtree traversal — collapses the cache. At a deep app's
steady state the population is overwhelmingly `.struct`/`.selector` at the same ceiling fuel,
so every distinct value falls into ONE hash bucket; each `cache.get?` then runs derived
structural `BEq` over the full value tree against every colliding entry → O(N) per lookup,
O(N²) total. A depth-bounded digest gives each distinct k8s-shaped struct a distinct
bucket (depth 3 separates 1000 distinct resource-shaped structs into ~1000 buckets,
measured by the spike), collapsing the lookup back to O(1) amortized.

SOUNDNESS: this is a HASH, not equality. `Std.HashMap` uses `BEq` (derived-structural,
UNCHANGED) as the sole arbiter of whether `get?` returns an entry; the hash only selects a
bucket. A lossy/colliding digest can therefore only cause a recompute-miss or a
collide-scan (SLOWER), never a wrong value. Two `BEq`-distinct keys can never compare equal
through this.

TOTALITY: structural recursion on `depth` (a plain `Nat`); every recursive call passes the
predecessor `d`, so the measure strictly decreases and the function is total — no `partial`,
no fuel. The list children fold `valueDigest d` over their elements (a lower-depth call),
which terminates for the same reason. `digestPrim` is non-recursive.

The `DIGEST_DEPTH` constant (3) is the starting point the spike justified: deep enough to
separate the field-name + nested-value shape of k8s resources (each resource is a struct of
a few fields whose values are themselves shallow structs/scalars), shallow enough that the
per-key cost stays effectively O(1) (a struct of K fields costs K digest-mixes per level,
3 levels). -/
def DIGEST_DEPTH : Nat := 3

private def digestPrim : Prim → UInt64
  | .null => 101
  | .bool b => mixHash 102 (hash b)
  | .int n => mixHash 103 (hash n)
  | .float _ text => mixHash 104 (hash text)
  | .string s => mixHash 105 (hash s)
  | .bytes s => mixHash 106 (hash s)

def valueDigest : Nat → Value → UInt64
  | 0, v => valueTag v
  | _ + 1, .top => valueTag .top
  | _ + 1, .bottom => valueTag .bottom
  | _ + 1, v@(.bottomWith _) => valueTag v
  | _ + 1, .prim p => mixHash (valueTag (.prim p)) (digestPrim p)
  | _ + 1, v@(.kind _) => valueTag v
  | _ + 1, .notPrim p => mixHash (valueTag (.notPrim p)) (digestPrim p)
  | _ + 1, v@(.stringRegex pat) => mixHash (valueTag v) (hash pat)
  | _ + 1, v@(.stringFormat fmt) => mixHash (valueTag v) (hash fmt)
  | _ + 1, v@(.boundConstraint _ _) => valueTag v
  | _ + 1, v@(.lengthConstraint _ _ _) => valueTag v
  | _ + 1, v@(.uniqueItems) => valueTag v
  | d + 1, .conj cs =>
      cs.foldl (fun acc c => mixHash acc (valueDigest d c)) (valueTag (.conj cs))
  | d + 1, .builtinCall name args =>
      args.foldl (fun acc a => mixHash acc (valueDigest d a))
        (mixHash (valueTag (.builtinCall name args)) (hash name))
  | d + 1, .unary op v => mixHash (valueTag (.unary op v)) (valueDigest d v)
  | d + 1, .binary op l r =>
      mixHash (mixHash (valueTag (.binary op l r)) (valueDigest d l)) (valueDigest d r)
  | _ + 1, v@(.ref label) => mixHash (valueTag v) (hash label)
  | _ + 1, v@(.refId id) => mixHash (valueTag v) (mixHash (hash id.depth.val) (hash id.index.val))
  | _ + 1, v@(.patternLabel name) => mixHash (valueTag v) (hash name)
  | _ + 1, .thisStruct => valueTag .thisStruct
  | d + 1, .selector base label =>
      mixHash (mixHash (valueTag (.selector base label)) (hash label)) (valueDigest d base)
  | d + 1, .index base key =>
      mixHash (mixHash (valueTag (.index base key)) (valueDigest d base)) (valueDigest d key)
  | d + 1, .disj alts =>
      alts.foldl (fun acc (_, v) => mixHash acc (valueDigest d v)) (valueTag (.disj alts))
  | d + 1, .struct fields openness tail patterns closedClauses =>
      let acc0 := mixHash (valueTag (.struct fields openness tail patterns closedClauses)) (hash fields.length)
      fields.foldl (fun acc f => mixHash (mixHash acc (hash f.label)) (valueDigest d f.value)) acc0
  | d + 1, .list items =>
      items.foldl (fun acc i => mixHash acc (valueDigest d i)) (valueTag (.list items))
  | d + 1, .listTail items tail =>
      mixHash (items.foldl (fun acc i => mixHash acc (valueDigest d i))
        (valueTag (.listTail items tail))) (valueDigest d tail)
  | d + 1, .embeddedList items _ decls =>
      let acc0 := items.foldl (fun acc i => mixHash acc (valueDigest d i))
        (valueTag (.embeddedList items none decls))
      decls.foldl (fun acc f => mixHash (mixHash acc (hash f.label)) (valueDigest d f.value)) acc0
  | d + 1, .embeddedScalar scalar decls =>
      let acc0 := mixHash (valueTag (.embeddedScalar scalar decls)) (valueDigest d scalar)
      decls.foldl (fun acc f => mixHash (mixHash acc (hash f.label)) (valueDigest d f.value)) acc0
  | d + 1, .comprehension _ body =>
      mixHash (valueTag (.comprehension [] body)) (valueDigest d body)
  | d + 1, .structComp fields _ openness =>
      let acc0 := mixHash (valueTag (.structComp fields [] openness)) (hash fields.length)
      fields.foldl (fun acc f => mixHash (mixHash acc (hash f.label)) (valueDigest d f.value)) acc0
  | d + 1, .listComprehension _ body =>
      mixHash (valueTag (.listComprehension [] body)) (valueDigest d body)
  | d + 1, .interpolation parts =>
      parts.foldl (fun acc p => mixHash acc (valueDigest d p)) (valueTag (.interpolation parts))
  | d + 1, .dynamicField label fc v =>
      mixHash (mixHash (valueTag (.dynamicField label fc v)) (valueDigest d label)) (valueDigest d v)
  | d + 1, .closure _ body =>
      mixHash (valueTag (.closure [] body)) (valueDigest d body)

/--
A scope frame paired with a process-unique identity. Each frame push allocates a fresh
`id` from the evaluation state's counter; the id is the frame's identity for caching.
Two evaluations that thread the *same* frame object (the depth-0 self-reference and the
`env.drop` rebase both reuse an existing frame) carry the same id, so they share a cache
entry; independently-built frames get distinct ids and never falsely share.
-/
abbrev Frame := Nat × List Field

namespace Frame
def id (frame : Frame) : Nat := frame.fst
def fields (frame : Frame) : List Field := frame.snd
end Frame

abbrev Env := List Frame

/-- Build-time tripwire that `Value.closure`'s `capturedEnv : List (Nat × List Field)`
    (`Value.lean`) stays *defeq* to `Env`, so the producer threads a real `Env` into a
    closure and the force arm threads it back out with ZERO coercion. If `Frame`/`Env` ever
    changes shape, this `rfl` fails the build instead of silently desyncing the closure rep
    (Phase-A finding `closure-env-sync-guard`, folded into the producer slice). -/
example : (List (Nat × List Field)) = Env := rfl

/-- The id stack of an env — its cheap identity for cache-key equality. -/
def Env.ids (env : Env) : List Nat := env.map Frame.id

/--
Memoization key. Evaluation is a pure function of `(fuel, env, visited, value)`, so
caching on it is behavior-preserving. The env is keyed by its *id stack* (`envIds`), not
its (deep) frame contents — frame ids uniquely identify frame objects within one run, so
`List Nat` equality is sound and O(depth). `visited` is part of the key, so a binding
caught mid-cycle is keyed apart from the same binding reached fresh; cycle detection is
untouched. The hash is shallow (fuel, visited, env depth, value's top tag) so a probe
never traverses the value subtree; `BEq` runs only on a hash-bucket match.

The fan-out this kills: a `Self.#components.X` selector re-evaluates the whole
`#components` struct per selection; three sibling selections in a struct embedding (the
`packs.#Argo` shape) re-derive it three times, multiplying per fuel level. Cached,
`#components` is computed once and shared.
-/
structure EvalKey where
  fuel : Nat
  envIds : List Nat
  visited : List Nat
  value : Value
deriving BEq

instance : Hashable EvalKey where
  hash key := mixHash (hash key.fuel) (mixHash (hash key.visited)
    (mixHash (hash key.envIds) (valueDigest DIGEST_DEPTH key.value)))

/-- Whether an eval result's ENTIRE (transitive) computation avoided every fuel-truncation
    base case (`fuel = 0`; cycle-bound `.top`; the comprehension/embedding-expansion helpers'
    fuel-exhausted drops). A `saturated` result is fuel- INSENSITIVE: re-evaluating at any fuel
    `≥` the one that produced it yields the identical value, so it may be cached FUEL-FREE (see
    `SatKey`). A `truncated` result bottomed on fuel somewhere in its subtree, so it is one of the
    263 fuel-truncation cases and stays keyed by `fuel` in `EvalKey` — never served across fuel
    levels. Classification is by BRACKETING the monotonic `EvalState.truncCount` in the single
    cached wrapper (`evalValueWithFuel`), not by a per-arm boolean join: every fuel-exhaustion arm
    bumps the counter, so the bracket sees them all — no arm can drop fields and stay saturated.
    The six bump sites are the `evalValueCoreWithFuel` `fuel=0` base, the cycle `.top`, and the
    fuel=0 arms of `evalEmbeddingFieldsWithFuel`/`meetEmbeddingsWithFuel`/`expandComprehension-
    WithFuel`/`expandClausesWithFuel` (which else drop comprehension/embedding fields silently). -/
inductive Saturation where
  | saturated
  | truncated
deriving BEq, DecidableEq, Repr

/-- Fuel-FREE memo key for SATURATED results. A saturated result is identical at all fuel, so
    `fuel` is deliberately ABSENT — a hit serves the result for ANY remaining fuel, collapsing
    the ~84 wasted re-derivations of a converged value to one. Keyed on `(envIds, visited,
    value)`: the same inputs minus the (now-irrelevant) fuel axis. Insertion is gated to the
    `saturated` branch of `evalValueWithFuel`'s bracket — a truncated result can NEVER reach this
    cache (the type forces classification; the single insertion site forces the gate). -/
structure SatKey where
  envIds : List Nat
  visited : List Nat
  value : Value
deriving BEq

instance : Hashable SatKey where
  hash key := mixHash (hash key.visited)
    (mixHash (hash key.envIds) (valueDigest DIGEST_DEPTH key.value))

/-- Push-site key for canonical frame-id sharing. Two `pushFrame` calls denote the SAME
    evaluation iff they push the SAME fields under the SAME parent id-stack — then (and only
    then) reusing the id makes the downstream `EvalKey` (which keys on `env.ids`) hit the memo
    instead of re-deriving an identical subtree.

    SOUNDNESS — why id reuse cannot change any value. `evalValueCoreWithFuel` is a pure
    function of `(fuel, env, visited, value)`, and `env` enters the memo key ONLY through
    `env.ids`. The id stack is a *proxy* for the frame contents: two frames carry the same id
    only when this key matches, i.e. same `fields` (the frame's payload) AND same `parentIds`
    (the proxy for the whole outer chain, inductively). So any two envs sharing an id stack are
    proven contents-equal frame-by-frame — the memo never returns a value computed for a
    *different* env. The id is therefore a sound canonical name for "this frame's contents in
    this scope," not merely an allocation token. The PARENT id-stack is load-bearing in the key:
    identical fields under DIFFERENT parents are different evaluations (their depth>0 refs walk
    different outer frames) and must NOT share — hence `parentIds` is part of the key.

    `fuel`, `visited`, and the closed-vs-open closure state are NOT in this key and need not be:
    they ride in `EvalKey` already. Sharing only canonicalizes the *id* a frame gets; the memo
    still separates two evals of the same frame at different `fuel`/`visited` (fuel is
    load-bearing — 263 measured fuel-truncation cases — and stays in `EvalKey` untouched). A
    forced-closure body and an eager body differ as `fields` (the force path closes the body via
    `normalizeDefinitionValueWithFuel` at capture, changing the field `Value`s), so they key
    apart here too — no closed/open collision. -/
structure FrameKey where
  parentIds : List Nat
  fields : List Field
deriving BEq

/-- Shallow hash for the canonical-frame table — mix the parent id stack with the field count
    and each field's top value-tag, never traversing the field subtrees. Unlike `EvalKey`/`SatKey`
    (which item 7 deepened to a `valueDigest` because their populations collapsed to one bucket and
    scanned O(N) at scale), profiling cert-manager with this hash deepened to `valueDigest` showed
    ZERO wall-clock change (30.6s → 30.6s): the frame table does NOT accumulate same-shaped/
    distinct-value frames into giant buckets, because canonical frame sharing already collapses
    identical re-pushes and `parentIds` discriminates the rest. So the deepening buys nothing here
    and is omitted (no unjustified `valueDigest` on the hot `pushFrame` path). `BEq` (derived,
    structural) runs only on a hash-bucket match, so this coarse hash costs collisions, never
    correctness — if a future workload makes the frame table the wall, swap in `valueDigest` (same
    sound, hash-only change). -/
instance : Hashable FrameKey where
  hash key :=
    key.fields.foldl (fun acc f => mixHash acc (valueTag f.value))
      (mixHash (hash key.parentIds) (hash key.fields.length))

/-- Memo key for `forceClosureWithConjunct`. Forcing a deferred def body is a pure function of
    `(fuel, capturedEnv, body, useOperands)`: it splices `useOperands` into `body`, pushes one
    frame onto `capturedEnv`, and evaluates — no other input, no effect beyond the (id-allocating
    but value-irrelevant) frame counter. So memoizing it on these four is behavior-preserving,
    by the SAME argument as `EvalKey`. `capturedEnv` enters via `envIds` only (the id stack is a
    sound proxy for env contents once `pushFrame` canonicalizes ids — see `FrameKey`). This is
    the load-bearing perf memo for real apps: a `pkg.#Def` selected/referenced N times re-forces
    the body N times pre-memo (the closure-force path bypasses the `EvalKey` cache entirely);
    keyed, it forces once.

    `fuel` stays in the key (load-bearing — fuel-truncation differs by level, same as `EvalKey`).
    `body` already carries the closed-vs-open state (the producer closes imported def bodies via
    `normalizeDefinitionValueWithFuel` at capture, so a closed and an open body differ AS VALUES
    here) — constraint (b) is satisfied without an extra key field. `useOperands` distinguishes a
    standalone force (`[]`) from a narrowed one (`pkg.#Def & {x:1}`). -/
structure ForceKey where
  fuel : Nat
  envIds : List Nat
  body : Value
  useOperands : List (List Field × Bool)
deriving BEq

instance : Hashable ForceKey where
  hash key := mixHash (hash key.fuel)
    (mixHash (hash key.envIds) (mixHash (valueTag key.body) (hash key.useOperands.length)))

/-- Evaluation state: the eval memo cache, the next frame id to hand out, the canonical
    frame-id table that lets structurally-identical re-pushes share an id (and thus a memo
    entry), and the closure-force memo (the load-bearing real-app cache — closure forces bypass
    `cache`). `evalCalls`/`cacheHits` are transient instrumentation: bumped per core eval and per
    memo hit so a deterministic `native_decide` pin can witness exponential→linear. -/
structure EvalState where
  cache : Std.HashMap EvalKey (Value × Saturation)
  nextFrameId : Nat
  frames : Std.HashMap FrameKey Nat := ∅
  forceCache : Std.HashMap ForceKey (Value × Saturation) := ∅
  /-- Ancestor stack of in-progress STRUCT-BODY evaluations re-entered through a reference
      (structural-cycle detection, D#2a). A structural cycle is a struct value whose evaluation
      requires its own evaluation to complete (`#L: {next: #L}`, `a: {next: a}`, mutual `#A`/`#B`)
      — i.e. the SAME struct body re-entered while still on the stack. The `.refId` eval arm pushes
      a resolved struct-like body before re-evaluating it and restores the saved stack afterward; a
      body already present on re-entry is the cycle, yielding `.bottomWith [.structuralCycle]`
      instead of unrolling fuel-deep. Identity is the `Value` itself (exact `BEq`, never a hash — a
      collision would be a false cycle). DISTINCT from a bare REFERENCE cycle (`x: x`, whose resolved
      body is a `.refId`, not a struct, so it is never pushed and stays `_` via the depth-0 `visited`
      slot check): the struct layer between re-entries is what makes a cycle structural, not
      referential. Finite-deep nesting never collides — each layer is a DISTINCT body, pushed then
      popped; only genuine re-entrancy puts a body on the stack twice. -/
  structStack : List Value := []
  /-- Transient sticky error for an in-progress `list.Sort`/`list.SortStable`: a comparator
      whose `less` field does not evaluate to a concrete `bool` for some pair (an incomplete or
      incomparable comparator — a CUE error) records that bottom HERE, and `sortWithComparator`
      surfaces it as the sort's result. Eval-scoped like `structStack`: saved before each sort and
      restored after, so a nested sort cannot leak its failure to the outer one. `none` = no failure
      seen on the current sort. (The merge sort's comparator must be total `EvalM Bool`; this carries
      the out-of-band "this comparison was not a real bool" signal that a `Bool` cannot.) -/
  sortError : Option Value := none
  /-- Fuel-free cache for SATURATED results only (see `SatKey`). The soundness-critical second
      store: a hit serves a converged value for any remaining fuel, collapsing fuel
      multiplication. Insertion is gated to the `saturated` bracket arm. -/
  satCache : Std.HashMap SatKey Value := ∅
  evalCalls : Nat := 0
  cacheHits : Nat := 0
  /-- Monotonic count of fuel-truncation base cases consulted: the `fuel = 0` core base, the
      cycle `.top`, and the fuel=0 arms of the comprehension/embedding-expansion helpers that
      else drop fields silently. Every such site bumps through the single `EvalState.truncate`
      primitive (fusing the bump with the drop — see its invariant note), so a dropped result
      can never escape uncounted. Bracketed by `evalValueWithFuel`/`forceClosureWithConjunct`
      to classify each result's `Saturation`: a result is `saturated` iff this counter did not
      move across its core eval. A cached `truncated` hit re-bumps it so the bracketing parent
      stays honest. Load-bearing for the fuel-saturation cache — not transient instrumentation. -/
  truncCount : Nat := 0

abbrev EvalM := StateM EvalState

/-- The fuel-truncation PRIMITIVE: the single operation that emits a fuel-truncated result.
    Bumps the monotonic `truncCount` (so the bracketing `evalValueWithFuel`/
    `forceClosureWithConjunct` classifies the enclosing result `truncated` and keeps it
    fuel-keyed) and returns the supplied incomplete `result`. Bump and drop are FUSED into
    one call: a `fuel=0` arm that drops fields cannot split them out of sync, so a truncated
    value can never be emitted without its counter move (the audit-#6 corruption). Polymorphic
    over the dropped result's type — each truncation arm returns a different incomplete shape
    (`Value`, `List Field`, `Except …`, the clause-expansion sums). -/
def EvalState.truncate {α : Type} (result : α) : EvalM α := do
  modify (fun state => { state with truncCount := state.truncCount + 1 })
  pure result

/- INVARIANT (truncate-primitive). Every `fuel=0` arm that DROPS fields/elements/meets MUST
   emit via `EvalState.truncate`, never a bare `pure`/`modify` — the seven sites below
   (the two `evalValueCoreWithFuel` arms + the five expansion helpers) all do. This keeps
   the truncation counted so the bracketing wrapper never serves a truncated value fuel-free
   (the audit-#6 corruption). Full type-level enforcement — a `withFuel` dispatch that makes
   the bump physically unskippable — was attempted and abandoned: routing the `fuel=0`
   dispatch through a combinator hides the `fuel = n+1` pattern behind a lambda, so the
   mutual block's well-founded `termination_by` measure loses the structural-decrease
   equation (`fuel < fuel✝` becomes unprovable). The primitive localizes the bump to one
   choke point; the routing stays disciplinary by necessity. -/

/-- Push a frame onto the env, reusing the id of a structurally-identical earlier push under
    the same parent id-stack (canonical frame identity), else allocating a fresh id and
    recording it. Sharing is keyed on `(parentIds, fields)` — see `FrameKey`; reuse is sound
    because that key proves the two frames have identical contents in identical scope, so the
    memo (which keys on the id stack) can only ever return the matching evaluation. -/
def pushFrame (fields : List Field) (env : Env) : EvalM Env := do
  let state <- get
  let key : FrameKey := ⟨env.ids, fields⟩
  match state.frames.get? key with
  | some id => pure ((id, fields) :: env)
  | none =>
      let id := state.nextFrameId
      set { state with
        nextFrameId := id + 1,
        frames := state.frames.insert key id }
      pure ((id, fields) :: env)

/--
Reduce a conjunction operand to the *unevaluated* struct declarations it contributes,
following same-frame (`depth == 0`) sibling references to their struct bodies. Returns the
declared fields and the struct's closedness, or `none` when the operand is not a plain
struct (lists, primitives, patterns, tails, disjunctions, outer references) — those keep the
ordinary eval-then-`meet` path. `depth == 0` is the safety boundary: a sibling's body frame
shares the conjunction site's enclosing scope, so its declarations splice into the merged
frame without disturbing any outer reference; an outer (`depth > 0`) reference does not, so
it is refused.
-/
def conjStructOperand? (env : Env) (fuel : Nat) : Value -> Option (List Field × Bool)
  -- A plain struct (no tail, no patterns) is a same-scope struct operand; a tail/pattern-bearing
  -- struct is not (→ `none`).
  | .struct fields openness none [] _ => some (fields, openness.isOpen)
  | .refId id =>
      match fuel with
      | 0 => none
      | fuel + 1 =>
          if id.depth != 0 then
            none
          else
            match env with
            | [] => none
            | frame :: _ =>
                match nthField id.index.val frame.snd with
                | some field => conjStructOperand? env fuel (Field.value field)
                | none => none
  | _ => none

/-- Does a value carry FIELD CONTENT that `mergeDefinitionDecls` genuinely close-once-UNIONS — a
    field/pattern-bearing struct (the `#m: {a:1}` decl shape), not a scalar/kind def value
    (`#x: string`, which `mergeDefinitionDecls` would only `.conj`-meet, doubling the display)? -/
def isUnionableDefValue : Value -> Bool
  | .struct _ _ _ _ _ => true
  | .structComp _ _ _ => true
  | _ => false

/-- The depth-0 def-ref conjuncts of a slot's `.conj` body — the other same-frame def slots its
    body references. Used by `defSlotInClosedCycle` to walk the mutual-reference graph. Empty for a
    non-`.conj` body. -/
def defConjRefSlots (frame : List Field) (index : Nat) : List Nat :=
  match nthField index frame with
  | some field =>
      match Field.value field with
      | .conj cs => cs.filterMap fun c =>
          match c with
          | .refId rid => if rid.depth.val == 0 then some rid.index.val else none
          | _ => none
      | _ => []
  | none => []

/-- Bug2-12 MUTUAL: is the DEFINITION slot `start` part of a closed mutual-reference cycle whose
    every hop is a depth-0 def→def ref (`#A: #B & {a}`, `#B: #A & {b}`)? Walks the same-frame
    reference graph from `start`, following each slot's depth-0 def-ref conjuncts; reports `true`
    once the walk returns to `start` after at least one hop. `seen` (visited slots) + `fuel` (= the
    field count suffices) bound the walk total. A direct self-ref (`#X: #X & {a}`, handled by the
    Bug2-12 `isSelfRef` gate) is NOT reported here — its sole hop is to `start` itself, so the
    one-hop frontier hits the `start` membership immediately, which is exactly the cycle. The
    cross-def chain (`#A: #B & {a}`, `#B: {b}` non-recursive) returns `false`: the walk reaches `#B`,
    whose body has no def-ref conjunct, so it never returns to `start`. -/
def defSlotInClosedCycle (fuel : Nat) (frame : List Field) (start : Nat)
    (seen : List Nat) : List Nat -> Bool
  | [] => false
  | frontier =>
      match fuel with
      | 0 => false
      | f + 1 =>
          let nextHops := frontier.flatMap (defConjRefSlots frame)
          if nextHops.contains start then true
          else
            let fresh := nextHops.filter (fun i => !slotVisited i seen)
            match fresh with
            | [] => false
            | _ => defSlotInClosedCycle f frame start (frontier ++ seen) fresh

/-- Does `value` reference the depth-0 slot `slot` — the same frame, same field it inhabits?
    A `foldValueWithDepth` scan: the `.refId` leaf matches when the ref lands on frame depth `d`
    (incremented per frame-pusher) at index `slot`. Used to detect a self-reference BURIED below
    the top-level conjuncts of a field body, which `flattenConjDefRef` must not inline. -/
def valueMentionsSlotAtDepth (fuel : Nat) (slot : Nat) : Value -> Bool :=
  foldValueWithDepth (· || ·) false
    (fun d v => match v with
      | .refId id => some (id.depth.val == d && id.index.val == slot)
      | _ => none)
    fuel 0

/-- The cross-product of a list of disjunction arm-lists: one pick from each list, in every
    combination. `[[b,c],[d,e]]` yields `[[b,d],[b,e],[c,d],[c,e]]`. Structural on the outer
    list; the empty product is the single empty combination `[[]]` (identity), so a one-list
    input reproduces that list's arms. Used to distribute a def's own-literal union across the
    cross-product of MULTIPLE closable disjunction conjuncts. -/
def disjArmCrossProduct : List (List (Mark × Value)) -> List (List (Mark × Value))
  | [] => [[]]
  | alts :: rest =>
      let restProduct := disjArmCrossProduct rest
      alts.flatMap fun a => restProduct.map fun combo => a :: combo

/-- The distribution class of a disjunction arm, DERIVED from how the arm meets the def's own
    non-empty struct literal `{…}`. Replaces a hand-enumerated distribute-safe whitelist that
    twice missed an arm shape which bottoms against a struct: the `match` is COMPLETE over every
    `Value` constructor, so a NEW shape is a compile error, not a silent closedness leak.
    - `fieldCarryingClosed` — a struct literal / struct comprehension: `{a:1} & {z:9}` UNIONS to a
      struct closed with the literal's allowed-set.
    - `fieldCarryingOpen` — a def-`.refId`: the ref governs its OWN closedness, so the literal
      composes OPEN under it (`{a:1} & #Base` — `#Base` decides which fields are allowed).
    - `bottomsVsStruct` — an arm that carries NO new allowed field, because met with the CLOSED
      literal it either BOTTOMS (a scalar/kind/bound/regex/format/list/`uniqueItems`/`notPrim`/
      list-or-rune-length arm mismatches the struct kind; an `error(…)` force-folds; a `⊥`) or
      COMPOSES-CLOSED (a `struct.MinFields` length arm rides the CLOSED literal as a residual). The
      literal is closed around this pick, so the arm rejects a use-site extra exactly as a closed
      struct does. `error(…)` is the one `.builtinCall` here — it force-folds to `⊥` with its
      message preserved through the meet; every other builtin could return a struct, so is `blocking`.
    - `blocking` — an unevaluated expression whose result kind is unknown (it could yield a
      new-field struct, or `_` composes OPEN): the def cannot distribute, so the whole disjunction
      stays UNEVALUATED in `rest` and its existing eval path is unchanged. -/
inductive DisjArmClass where
  | fieldCarryingClosed
  | fieldCarryingOpen
  | bottomsVsStruct
  | blocking
  deriving BEq

/-- Does `v` carry NO new allowed struct field — a validator / scalar / list value that, met with a
    non-empty struct literal, either bottoms (kind mismatch) or composes-closed (a length residual)?
    A Bool PROBE (catch-all permitted) used to classify a `.builtinCall` arm AFTER lowering it
    through `evalBuiltinCall`: a call-form validator (`list.MinItems(2)`, `struct.MinFields(2)`)
    reaches the def-flatten level as an unlowered `.builtinCall`, so it must be lowered before its
    distribute-safety is visible. -/
def bottomsVsStructValue : Value -> Bool
  | .prim _ | .kind _ | .notPrim _ | .stringRegex _ | .stringFormat _
  | .boundConstraint _ _ | .lengthConstraint _ _ _ | .uniqueItems
  | .list _ | .listTail _ _ | .embeddedList _ _ _ | .embeddedScalar _ _
  | .bottom | .bottomWith _ => true
  | _ => false

def disjArmClass : Value -> DisjArmClass
  | .struct _ _ _ _ _ => .fieldCarryingClosed
  | .structComp _ _ _ => .fieldCarryingClosed
  | .refId _ => .fieldCarryingOpen
  | .prim _ => .bottomsVsStruct
  | .kind _ => .bottomsVsStruct
  | .notPrim _ => .bottomsVsStruct
  | .stringRegex _ => .bottomsVsStruct
  | .stringFormat _ => .bottomsVsStruct
  | .boundConstraint _ _ => .bottomsVsStruct
  | .lengthConstraint _ _ _ => .bottomsVsStruct
  | .uniqueItems => .bottomsVsStruct
  | .list _ => .bottomsVsStruct
  | .listTail _ _ => .bottomsVsStruct
  | .embeddedList _ _ _ => .bottomsVsStruct
  | .embeddedScalar _ _ => .bottomsVsStruct
  | .bottom => .bottomsVsStruct
  | .bottomWith _ => .bottomsVsStruct
  | .builtinCall name args =>
      if name == "error" then .bottomsVsStruct
      -- A call-form validator (`list.MinItems(2)`, `struct.MinFields(2)`) is an unlowered
      -- `.builtinCall` here; lower it and classify the validator. A builtin whose lowering is a
      -- residual `.builtinCall` (abstract args) or a struct is unknown → `blocking`.
      else if bottomsVsStructValue (evalBuiltinCall name args) then .bottomsVsStruct
      else .blocking
  | .top => .blocking
  | .conj _ => .blocking
  | .unary _ _ => .blocking
  | .binary _ _ _ => .blocking
  | .ref _ => .blocking
  | .thisStruct => .blocking
  | .selector _ _ => .blocking
  | .index _ _ => .blocking
  | .disj _ => .blocking
  | .comprehension _ _ => .blocking
  | .listComprehension _ _ => .blocking
  | .interpolation _ => .blocking
  | .dynamicField _ _ _ => .blocking
  | .closure _ _ => .blocking
  | .patternLabel _ => .blocking

/-- Can a def DISTRIBUTE its own-literal union across this arm and close/compose it? True iff the
    arm's `disjArmClass` is not `blocking`. A nested distributable disjunction is flattened before
    distribution, so it recurses here (fuel-bounded); at fuel exhaustion the conservative `blocking`
    default (`disjArmClass (.disj _)`) holds, leaving the disjunction raw. -/
def isDistributableDisjArm : Nat -> Value -> Bool
  | fuel + 1, .disj alts => alts.all fun a => isDistributableDisjArm fuel a.snd
  | _, v => disjArmClass v != .blocking

/-- Is `c` a `.disj` every arm of which is `isDistributableDisjArm` — a disjunction the def can
    distribute its own-literal union across (per-arm close for struct literals, open-compose for
    ref/scalar arms)? `fuel` bounds the nesting depth. -/
def isDistributableDisj (fuel : Nat) : Value -> Bool
  | .disj alts => alts.all fun a => isDistributableDisjArm fuel a.snd
  | _ => false

/-- Flatten a disjunction's arm-list, splicing a NESTED `.disj` arm's own arms into the flat list —
    disjunction is associative, so `{b}|({c}|{e})` is the three-arm `{b}|{c}|{e}`. A nested arm's
    default marker composes with its parent's: an inner arm is `default` only when BOTH the outer and
    inner marks are `default`. `fuel` bounds the nesting depth. -/
def flattenNestedDisjArms : Nat -> List (Mark × Value) -> List (Mark × Value)
  | 0, arms => arms
  | fuel + 1, arms =>
      arms.flatMap fun a =>
        match a.snd with
        | .disj inner =>
            (flattenNestedDisjArms fuel inner).map fun ia =>
              let mark := if a.fst == Mark.default && ia.fst == Mark.default
                then Mark.default else Mark.regular
              (mark, ia.snd)
        | _ => [a]

/-- Splice a nested `.conj` into a flat member list — conjunction is associative, so
    `{a} & ({b} & {c})` and `{a} & {b} & {c}` denote the same meet. `fuel` bounds nesting. -/
def flattenConjMembers : Nat -> Value -> List Value
  | fuel + 1, .conj cs => cs.flatMap (flattenConjMembers fuel)
  | _, v => [v]

/-- A `.conj` ALL of whose (recursively flattened) members are own struct literals
    (`isUnionableDefValue`) — `{b:2} & {d:4}`. Returns its members for splicing into the def
    body's flat conjunct list. A `.conj` mixing a ref/scalar (`{b:2} & #Base`) governs closedness
    differently, so it is NOT one (`none`) — it stays a single conjunct and composes via eval. -/
def pureStructConjMembers (fuel : Nat) (v : Value) : Option (List Value) :=
  match v with
  | .conj _ =>
      let members := flattenConjMembers fuel v
      if !members.isEmpty && members.all isUnionableDefValue then some members else none
  | _ => none

/-- Merge a pure-struct-literal `.conj` disjunction arm (`{b:2} & {d:4}`) into the single struct it
    denotes (`{b:2,d:4}`), so `disjArmClass` classifies it `fieldCarryingClosed` and the def can
    distribute-and-close it. Each member is normalized-to-closed BEFORE merging (mirroring
    `closeLiteralUnion`): `mergeDefinitionDecls` unions openness, so merging two raw `regularOpen`
    members would union-OPEN the result (`unionDefOpenness`) and leave the arm admitting extras — an
    explicit `...`-tail member stays open through `normalizeDefinitionValueWithFuel`, a plain one
    closes. A nested `.disj` arm recurses (associative); any other arm is unchanged. `fuel` bounds
    nesting. -/
def mergeDefBodyDisjArm : Nat -> Value -> Value
  | fuel + 1, .disj alts => .disj (alts.map fun a => (a.fst, mergeDefBodyDisjArm fuel a.snd))
  | fuel + 1, v =>
      match (pureStructConjMembers fuel v).map
          (List.map (normalizeDefinitionValueWithFuel normalizeFuel)) with
      | some (first :: more) =>
          normalizeDefinitionValueWithFuel normalizeFuel (more.foldl mergeDefinitionDecls first)
      | _ => v
  | _, v => v

/-- Normalize ONE def-body conjunct to the flat form the own-literal-union close expects: a
    pure-struct-literal `.conj` is SPLICED into its members (`{a} & ({b}&{c})` → `{a},{b},{c}`), a
    `.disj` has each arm's pure-struct `.conj` MERGED (so `({b}&{d}) | {c}` is distributable), and
    every other conjunct is unchanged. `.conj` associativity makes this semantics-preserving — it
    only exposes to the closedness gate a struct-literal meet that a `&`-grouping otherwise hides
    behind a `.conj`/`disjArmClass` neither predicate accepts. -/
def normalizeDefBodyConjunct (fuel : Nat) (v : Value) : List Value :=
  match pureStructConjMembers fuel v with
  | some members => members
  | none =>
      match v with
      | .disj alts => [.disj (alts.map fun a => (a.fst, mergeDefBodyDisjArm fuel a.snd))]
      | other => [other]

/-- Merge a definition `.conj` body that CONJOINS a comprehension embedding with struct literals
    (`#X: {for…} & {b:2}`) into ONE `.structComp`, so the comprehension-produced labels and the
    sibling literals' fields close JOINTLY over a single field set — the standalone `.structComp`
    def-close derives the allowed set AFTER the comprehension runs. Without this the flatten splits
    the comprehension `.structComp` from its sibling literal, each self-closes, and the two disjoint
    closed structs mutually reject each other's fields (`close{p} & close{b}` ⊥) — an over-rejection
    that bottoms even a `& {}` use-site meet. `ownLiteralUnion` handles a pure-literal body but a
    `.structComp` is not `isUnionableDefValue`, so this covers the mixed comprehension+literal shape.
    `none` (keep the existing flatten) UNLESS at least one conjunct is a real comprehension embedding
    AND every conjunct is a plain struct/structComp (no tail value, no pattern constraints — neither
    fits a `.structComp` slot). Fields union via `mergeFieldListWith joinUnevaluated` (a shared label
    still `.conj`-meets, so `{for b:1} & {b:2}` keeps the conflict), comprehensions append, openness
    unions. -/
def mergeCompDefBody (fuel : Nat) (cs : List Value) : Option Value :=
  let members := (cs.flatMap (flattenConjMembers fuel)).map
    (normalizeDefinitionValueWithFuel normalizeFuel)
  let asPart : Value -> Option (List Field × List Value × StructOpenness) := fun c =>
    match c with
    | .structComp f comps o => some (f, comps, o)
    | .struct f o none [] _ => some (f, [], o)
    | _ => none
  let hasComprehension := members.any fun c =>
    match c with
    | .structComp _ comps _ =>
        comps.any fun e => match e with | .comprehension .. => true | _ => false
    | _ => false
  if !hasComprehension then none
  else match members.mapM asPart with
    | some (first :: rest) =>
        let combined := rest.foldl
          (fun acc part =>
            ((mergeFieldListWith joinUnevaluated (acc.1 ++ part.1)).getD (acc.1 ++ part.1),
             acc.2.1 ++ part.2.1,
             unionDefOpenness acc.2.2 part.2.2))
          first
        some (.structComp combined.1 combined.2.1 combined.2.2)
    | _ => none

/-- Close a set of a definition's own struct-literals into ONE fixed field set: each is
    normalized-to-closed (so a `...`-tail literal stays open, a plain one closes), then merged via
    `mergeDefinitionDecls` (unions fields/patterns/openness — a shared label still `.conj`-meets),
    and the union re-closed once. `none` for an empty set. Shared by the def-body flatten close and
    the buried-self-ref closedness re-derivation. -/
def closeDefLiteralUnion (vs : List Value) : Option Value :=
  match vs.map (normalizeDefinitionValueWithFuel normalizeFuel) with
  | [] => none
  | first :: more => some (normalizeDefinitionValueWithFuel normalizeFuel
      (more.foldl mergeDefinitionDecls first))

/-- Under a definition, resolve a body conjunct that INDIRECTS to the definition's OWN content, so
    an INDIRECT def body presents to the closedness machinery exactly like a DIRECT one — the fold
    that unifies the two closedness paths. A non-def `.refId` to a struct inlines it OPEN (it unions
    ONCE with sibling conjuncts via the own-literal-union gate, exactly as a direct struct literal
    does — so `#X: a & b` closes over the UNION, not each referent separately); to a disjunction
    inlines it CLOSED per arm (self-contained, as a direct `.disj` body is closed at capture — so
    `#X: foo`, `foo: {a}|{b}` distributes closedness across the arms); a `.conj` referent resolves
    each member (a conj of struct referents unions). A DEFINITION referent (`#Base`) GOVERNS its own
    closedness, so it is left as the `.refId` for the meet to compose (the open-extension pattern).
    A `.selector`/`.index` (unresolvable without eval), a non-zero-depth ref, an on-path (cyclic)
    ref, and a scalar are left unchanged (the bare `.refId` survives to the eval arm's
    `closeResolved`). Fuel- and path-bounded against reference cycles. -/
def resolveDefBodyReferent (frame : List Field) (expanding : List Nat) : Nat -> Value -> Value
  | 0, v => v
  | fuel + 1, v =>
      match v with
      | .refId id =>
          if id.depth.val != 0 || expanding.contains id.index.val then v
          else match nthField id.index.val frame with
            | none => v
            | some field =>
                if field.fieldClass.isDefinition then v
                else match Field.value field with
                  | .struct .. | .structComp .. => Field.value field
                  | .disj .. => normalizeDefinitionValueWithFuel normalizeFuel (Field.value field)
                  | .conj cs =>
                      .conj (cs.map (resolveDefBodyReferent frame (id.index.val :: expanding) fuel))
                  | .refId .. | .selector .. | .index .. =>
                      resolveDefBodyReferent frame (id.index.val :: expanding) fuel (Field.value field)
                  | _ => v
      | .conj cs => .conj (cs.map (resolveDefBodyReferent frame expanding fuel))
      | _ => v

/-- Bug2-9: flatten a referenced multi-conjunct NAMED def into its constituent conjuncts at the
    UNEVALUATED constraint level, so `#LS & {narrow}` (where `#LS: #A & #B & {…}`) becomes
    `#A & #B & {…} & {narrow}` operand-wise — byte-identical to the INLINED meet, which the
    `.conj` fold (lazy-merge + closure-deferral) already evaluates correctly.

    Without this the ref `#LS` resolves STANDALONE through the `.refId` eval arm: its `.conj`
    body forces with NO use-operands, so a conjunct's sibling self-ref / comprehension guard
    (`vis: #name`, `if kind == add.#kind`) collapses against the un-narrowed abstract value
    BEFORE the use-site `& {narrow}` arrives, then meets too late (`incomplete value` / a
    spuriously-bottomed `_patch`). Flattening puts the def's conjuncts and the use-site decls in
    ONE fold so every conjunct sees the narrowing — exactly the inlined behavior.

    Only a bare same-frame (`id.depth == 0`) ref to a `.conj`-bodied field is expanded: the def's
    body refs are written in its enclosing scope, which is the SAME scope as the use site (a
    top-level def and its use site share the package frame), so the spliced conjuncts' depth-0
    refs (and package-selector conjuncts like `defs.#ListenerSet`, which re-resolve their own
    import binding) stay valid in place. Anything else (an outer ref, a non-`.conj` body, a
    literal non-ref conjunct) is returned UNCHANGED, so non-multi-conjunct-def conjuncts keep
    their existing path. Recurses so a chain of named multi-conjunct defs (`#C: #B & …`,
    `#B: #A & …`) flattens fully; fuel-bounded against alias cycles (`#A: #A & {…}`). -/
def flattenConjDefRef (env : Env) (fuel : Nat) (expanding : List Nat) (underDef : Bool)
    (constraint : Value) : List Value :=
  match fuel, constraint with
  | fuel + 1, .refId id =>
      if id.depth.val != 0 then [constraint]
      -- BOUND the cyclic fan-out: a depth-0 ref to a slot already on the current expansion
      -- PATH (`#A: #B & #C`, `#B: #A`, `#C: #A` — flattening `#A` expands `#B`, which
      -- re-references `#A`) is returned UNEXPANDED. Its literals are already being collected
      -- by the ancestor that put it on the path, and the bare `.refId` returned here is
      -- EXACTLY the leaf the unbounded recursion bottoms to at fuel exhaustion (the
      -- structural-cycle path D#2a bottoms a re-entrant ref). `mergeDefinitionDecls` is
      -- idempotent over a member's literal and the re-entrant `.refId`s `.conj`-meet
      -- idempotently under D#2, so collecting each cycle member ONCE — instead of along the
      -- exponential cross-product of expansion paths — yields the SAME finite literal union
      -- and `rest` ref set: byte-identical, just bounded.
      else if expanding.contains id.index.val then [constraint]
      else
        match env with
        | [] => [constraint]
        | frame :: _ =>
            match nthField id.index.val frame.snd with
            | some field =>
                -- SINGLE FLOW POINT for def-body closedness. Every DEFINITION body flows through
                -- the closedness machinery: a `.conj` splits to its conjuncts, and EVERY other body
                -- shape (`.disj`, `.refId`, `.struct`, `.structComp`, `.builtinCall`, scalar, …)
                -- becomes a single-conjunct list `[body]`. A body shape that carries no closedness
                -- (a scalar, a bare non-self `.refId` whose referent isn't flatten-closed) stays a
                -- fixed point of the flatten below (`close` false ⇒ it flattens to itself), so
                -- routing it through is inert; but a `.refId` to a FLATTEN-DERIVED-closed def
                -- (`#X: #Y`, `#Y: {b}&{d}`) now recurses into the referent's own flatten and carries
                -- its derived closedness — the entry-path leak the per-arm dispatch kept relocating.
                -- The `| _ => none` that silently dropped closedness for a non-`.conj` def body IS
                -- the bug class; defaulting a definition to `some [body]` (the closed-preserving
                -- side) designs it out — a new body constructor cannot bypass normalization. Only a
                -- NON-definition non-`.conj` body gets `none` (closedness is a def-only property; it
                -- keeps its standalone-resolution path).
                let defBodyConjuncts : Option (List Value) :=
                  match Field.value field with
                  -- A definition `.conj` body mixing a COMPREHENSION embedding with struct literals
                  -- (`#X: {for…} & {b:2}`) is merged to ONE `.structComp` so the comprehension-produced
                  -- labels and the sibling literals close JOINTLY — otherwise flattening splits them and
                  -- each self-closes, the two disjoint closed structs mutually rejecting each other's
                  -- fields (`close{p} & close{b}` ⊥), an over-rejection that bottoms even a `& {}` meet.
                  | .conj rawCs =>
                      if field.fieldClass.isDefinition then
                        match mergeCompDefBody normalizeFuel rawCs with
                        | some merged => some [merged]
                        | none => some rawCs
                      else some rawCs
                  -- A DEFINITION struct-shaped body is ALREADY its own closed form — standalone eval
                  -- closes a lone struct literal / comprehension def. Routing it through the
                  -- derived-closedness machinery would re-close it and misfire the buried-self-ref
                  -- detector on a legitimately-recursive struct (`{kids: [...#T]}`, `{vis: #name}`),
                  -- so it keeps its standalone-resolution path. A NON-definition struct body keeps its
                  -- standalone OPEN path here: a struct REFERENT under a def is close-folded into the
                  -- enclosing def's own-literal union by `resolveDefBodyReferent` (which inlines the
                  -- referent's value into the conjunct list BEFORE the closedness gate), never reaching
                  -- flatten as a bare struct-bodied ref.
                  | .struct .. | .structComp .. => none
                  -- A `.selector`/`.index` def body is an indirection flatten cannot RESOLVE (it needs
                  -- eval to select from the base). Returned UNROUTED (`none` ⇒ the bare use-site
                  -- `.refId` survives), so the `.refId` eval arm resolves it and closes the result —
                  -- the definition's closedness applied at the resolution point.
                  | .selector .. | .index .. => none
                  -- A `.refId` def body recurses into the referent's own flatten to carry its derived
                  -- closedness (a def-ref referent composes its own closedness at the meet). Under a def
                  -- (`underDef`) a NON-def `.refId` binding is followed; `resolveDefBodyReferent`
                  -- resolves a non-def struct/disjunction referent to own-content before the gate, and
                  -- a def-ref stays a `.refId` the recursion expands. Outside a def a plain `.refId`
                  -- field keeps its standalone path (`none`).
                  | .refId .. =>
                      if field.fieldClass.isDefinition || underDef then some [Field.value field]
                      else none
                  -- Every OTHER definition body is an INDIRECT / COMPOSITIONAL shape whose closedness
                  -- is flatten-DERIVED: `.disj` distributes-and-closes per arm. Defaulting to the
                  -- routed (closedness-preserving) side designs out the entry-path leak class: the
                  -- `| _ => none` that silently dropped a bare body's derived closedness IS the bug,
                  -- and a new indirection constructor now cannot bypass it.
                  | body => if field.fieldClass.isDefinition then some [body] else none
                match defBodyConjuncts with
                | none => [constraint]
                | some rawCs =>
                    -- DEF-CLOSEDNESS-NESTED-CONJ-ARM: a def body's conjuncts are normalized to the
                    -- flat form the own-literal-union close expects — a pure-struct-literal `.conj`
                    -- conjunct (`{a} & ({b}&{d})`) is spliced into its struct members, and a `.disj`
                    -- conjunct's pure-struct `.conj` arms are merged — BEFORE the closedness gate, so
                    -- a `&`-grouped nested struct meet closes exactly as the flat `{a}&{b}&{d}` does.
                    -- Conjunction associativity keeps this semantics-preserving; it fires only for a
                    -- DEFINITION body (closedness is a def property), leaving every non-def conjunct,
                    -- ref, scalar, self-ref, and mixed `.conj` on its existing path.
                    -- DEF-CLOSEDNESS-INDIRECT-DISJ-CONJ: RESOLVE each non-def indirection conjunct
                    -- to its own-content value FIRST, so an indirect def body's referent structure
                    -- (a struct → unioned once; a disjunction → closed per arm) reaches the SAME
                    -- own-literal-union / disj-distribute machinery a DIRECT body flows through —
                    -- the fold that unifies the two closedness paths. A def-ref is left untouched
                    -- (it governs its own closedness / composes at the meet).
                    let resolvedCs := if field.fieldClass.isDefinition || underDef
                      then rawCs.map
                        (resolveDefBodyReferent frame.snd (id.index.val :: expanding) normalizeFuel)
                      else rawCs
                    let cs := if field.fieldClass.isDefinition
                      then resolvedCs.flatMap (normalizeDefBodyConjunct normalizeFuel)
                      else resolvedCs
                    -- SELF-CONJ-CYCLE: a self-reference BURIED below the body's top-level conjuncts
                    -- (`x: (x & int) & 1`, whose body is `.conj [(x & int), 1]` — the self-ref sits
                    -- inside the nested `(x & int)` conjunct) must NOT be inlined. Inlining replaces
                    -- the bare `refId x` with x's body, re-burying the self-ref one level deeper each
                    -- pass; the `expanding` guard bounds only TOP-LEVEL self-ref conjuncts, so a
                    -- nested one escapes and unrolls to fuel exhaustion, bottoming instead of
                    -- collapsing to top. Returned UNEXPANDED, the bare ref flows to the `.refId` eval
                    -- arm, whose `slotVisited` check applies the reference-cycle rule (self → top).
                    -- A DIRECT top-level self-ref conjunct (`#X: #X & {a:1}`, Bug2-12) is excluded —
                    -- it is already bounded by `expanding` and needs the close-over-literals path.
                    let directSelfRef := fun (c : Value) =>
                      match c with
                      | .refId rid => rid.depth.val == 0 && rid.index.val == id.index.val
                      | _ => false
                    if cs.any (fun c => !directSelfRef c
                        && valueMentionsSlotAtDepth fuel id.index.val c) then
                      -- DEF-CLOSEDNESS-NESTED-CONJ-RESIDUAL (b): the self-ref sits BURIED below a
                      -- top-level conjunct (`#X: {a:1} & (#X & {b:2})`), so the body is returned
                      -- UNEXPANDED to keep the cycle→top VALUE rule (the bare ref flows to the
                      -- `.refId` eval arm). That drop of expansion also drops the def's CLOSEDNESS,
                      -- leaking a use-site extra. Re-derive it ORTHOGONALLY: the buried self-ref
                      -- contributes no new field, so the def's own struct-literals (flattened out of
                      -- their `&`-grouping, self-ref dropped) fix the allowed-set. Close their union
                      -- and emit it ALONGSIDE the untouched ref — closedness restored, cycle value
                      -- unchanged. Only for a DEFINITION (closedness is a def property); a regular
                      -- self-conj-cycle field (`x: (x & int) & 1`) keeps the bare unexpanded ref.
                      if field.fieldClass.isDefinition then
                        let ownLiterals := (cs.flatMap (flattenConjMembers normalizeFuel)).filter
                          isUnionableDefValue
                        match closeDefLiteralUnion ownLiterals with
                        | some closed => [constraint, closed]
                        | none => [constraint]
                      else [constraint]
                    else
                    -- Bug2-12: a SELF-RECURSIVE CLOSED definition (`#X: #X & {a:1}`, whose body is
                    -- the `.conj [#X, {a:1}]` reached here) loses its closedness on this flatten. A
                    -- bare depth-0 self-ref conjunct (`#X` pointing back at THIS slot) is the
                    -- structural-cycle fixpoint — the cycle path (D#2a) bottoms it, contributing no
                    -- live fields — so the def's OWN closedness must come from the remaining
                    -- struct-literal conjuncts (`{a:1}`). When the def is closed (its field
                    -- `isDefinition` AND the body is genuinely self-referential), close those
                    -- struct-literal conjuncts so a use-site `& {b:2}` meets a CLOSED struct
                    -- (rejected). The self-ref conjunct is a `.refId`, which the closer leaves
                    -- untouched, so cycle DETECTION/termination is unchanged (this runs at the
                    -- flatten, never on `structStack`). A non-self-recursive multi-conjunct def
                    -- (`#LS: #Base & {#extra}` — `#Base` is a DIFFERENT slot) is NOT self-referential,
                    -- so its narrowing conjuncts stay OPEN and the close-once-via-`closedClauses`
                    -- fold (Bug2-6..9) is preserved unchanged.
                    --
                    -- Bug2-12b: the def's own struct literals may be SPLIT across `&`
                    -- (`#X: #X & {a:1} & {c:3}`). Closing each literal SEPARATELY yields two
                    -- independently-`defClosed` structs whose `.conj`-meet CONCATENATES the two
                    -- `closedClauses` (clause `{a}` AND clause `{c}`), so a field must be in BOTH
                    -- allowed-sets — re-declaring the def's OWN field across the split
                    -- (`& {c:3}`) wrongly bottoms. The literals are repeated decls of ONE def path
                    -- (the def body split across `&`), so they must close ONCE over their COMBINED
                    -- allowed-set (the Bug2-6/2-7 close-once lever): UNION them via
                    -- `mergeDefinitionDecls` (unions fields — a shared label still `.conj`-meets, so
                    -- a real conflict survives; unions patterns; unions openness — a `...` in any
                    -- literal keeps the merged body OPEN), close the SINGLE merged body once, and
                    -- re-emit the untouched conjuncts (the self-ref `.refId` + any non-literal)
                    -- alongside it. `mkStruct` inside the closer then derives the SINGLE self-clause
                    -- over the union (`{a,c}`), admitting `a`, `c`, and a re-declared `c`; rejecting
                    -- `b`. The self-ref `.refId` is in the untouched partition, so cycle detection
                    -- and self-ref bottoming are unchanged.
                    let isSelfRef := cs.any fun c =>
                      match c with
                      | .refId rid => rid.depth.val == 0 && rid.index.val == id.index.val
                      | _ => false
                    -- Bug2-12 MUTUAL: the body's closedness must come from its OWN literals not just
                    -- for a DIRECT self-ref but for any depth-0 def→def cycle reaching this slot
                    -- (`#A: #B & {a}`, `#B: #A & {b}`). The cross-def back-ref bottoms via D#2, so
                    -- the def would otherwise resolve to an OPEN body (under-close, admitting a
                    -- genuine extra). The transitive flatten below already pulls every cycle member's
                    -- literals into `expanded`; closing them once over their UNION fixes the
                    -- allowed-set to the transitive declared labels (`{a,b}`) — admitting transitively
                    -- declared fields, rejecting genuine extras — the lattice-principled answer (cue
                    -- over-rejects the def's own field; see `cue-divergences.md`). A non-recursive
                    -- cross-def chain (`#A: #B & {a}`, `#B: {b}`) is NOT a cycle so it stays on its
                    -- existing (distinct-meet) path.
                    let inCycle := defSlotInClosedCycle (frame.snd).length frame.snd
                      id.index.val [] [id.index.val]
                    -- DEF-FLATTEN-CLOSEDNESS: a non-recursive def whose body UNIONS its OWN
                    -- struct literals (`#X: {a:1} & {b:3}` — every conjunct a struct literal,
                    -- no cross-def ref composition) has a FIXED field set, exactly like the
                    -- single-decl `#X: {a:1, b:3}`. Without closing here those split literals
                    -- flatten OPEN and a use-site `& {c:4}` leaks past closedness (an
                    -- over-acceptance soundness bug). It closes over the COMBINED allowed-set via
                    -- the same Bug2-12b union-then-close-once path. A def EXTENDING a reference
                    -- (`#LS: #Base & {extra}` — a `.refId` conjunct to a DIFFERENT slot, or an
                    -- outer-scope ref) is the legitimate OPEN-extension pattern: its closedness
                    -- is composed by the outer close-once fold (Bug2-6..9), so it stays OPEN here.
                    -- A self-ref conjunct (`.refId` to THIS depth-0 slot) is not cross-def
                    -- composition, so it does not block the own-literal union (the isSelfRef
                    -- case remains its subcase).
                    -- DEF-FLATTEN-CLOSEDNESS-DISJ: a closable disjunction conjunct (a `.disj` all
                    -- of whose arms are own struct literals) also carries the def's own fields
                    -- and must close. It is neither `isUnionableDefValue` nor a self-ref, so the
                    -- gate admits it explicitly; the close branch below distributes the literal
                    -- union across its arms so closedness is fixed per arm.
                    let ownLiteralUnion :=
                      cs.any isUnionableDefValue
                      && cs.all fun c =>
                        match c with
                        | .refId rid => rid.depth.val == 0 && rid.index.val == id.index.val
                        | .disj _ => isDistributableDisj normalizeFuel c
                        | _ => isUnionableDefValue c
                    let close := field.fieldClass.isDefinition
                      && (isSelfRef || inCycle || ownLiteralUnion)
                    let expanded := cs.flatMap
                      (flattenConjDefRef env fuel (id.index.val :: expanding)
                        (underDef || field.fieldClass.isDefinition))
                    if close then
                      let disjEmbeds := expanded.filter (isDistributableDisj normalizeFuel)
                      let literals := expanded.filter isUnionableDefValue
                      let rest := expanded.filter
                        (fun c => !isUnionableDefValue c && !isDistributableDisj normalizeFuel c)
                      let closeLiteralUnion := closeDefLiteralUnion
                      let disjAltLists := disjEmbeds.filterMap fun c =>
                        match c with
                        | .disj alts => some (flattenNestedDisjArms normalizeFuel alts)
                        | _ => none
                      match disjAltLists with
                      -- Pure own-literal union (no disjunction): close at flatten.
                      | [] =>
                          match closeLiteralUnion literals with
                          | none => expanded
                          | some closed => rest ++ [closed]
                      -- DEF-FLATTEN-CLOSEDNESS-DISJ(-REF): DISTRIBUTE the def's own struct-literal
                      -- union across the CROSS-PRODUCT of every disjunction conjunct and close/compose
                      -- each combination — so `#X: {a:1} & ({b:2}|{c:3})` flattens to
                      -- `{a:1,b:2}(closed) | {a:1,c:3}(closed)`, and
                      -- `#X: {a:1} & (*{b:2}|{c:3}) & (*{d:4}|{e:5})` flattens to the four closed
                      -- combinations `{a,b,d}|{a,b,e}|{a,c,d}|{a,c,e}`, fixing the field set per
                      -- combination (a use-site `& {f:6}` bottoms all four; `& {c:3,e:5}` resolves
                      -- to the `{a,c,e}` combination). Closing each combination TOGETHER with the
                      -- literal union gives each arm's own declared field the combined allowed-set,
                      -- so it is admitted, not rejected. An arm carrying a `...` tail stays open
                      -- through the union (its extras admitted). The default marker of a combination
                      -- is `default` iff EVERY component arm is a default (`*{b}` & `*{d}` → the
                      -- default combination), matching cue's product-of-defaults collapse. A single
                      -- disjunction is the one-list cross-product (identity).
                      --
                      -- A combination containing a NON-struct-literal pick (a def-REF arm `#Base`, a
                      -- scalar) does NOT close the union: the pick governs its own closedness, so the
                      -- combination is emitted as an OPEN `.conj` of the def's literals + every pick,
                      -- UNCHANGED, and normal eval composes it. A CLOSED ref rejects a foreign literal
                      -- field (`{a:1} & #Base{b}` ⇒ ⊥); an OPEN ref (`#Base{b, ...}`) admits it; a
                      -- scalar dies against the struct literal (`{a:1} & 3` ⇒ ⊥). Independently closing
                      -- the literal (to `{a}`) would wrongly reject a field the ref DOES allow
                      -- (`#Base{a,q}` admits `q`), so the literal stays open under the ref.
                      | _ =>
                          match literals with
                          | [] => expanded
                          | _ =>
                              let closedArms := (disjArmCrossProduct disjAltLists).filterMap
                                fun combo =>
                                  let mark := if combo.all (fun p => p.fst == Mark.default)
                                    then Mark.default else Mark.regular
                                  let picks := combo.map (·.snd)
                                  if picks.all (fun p => disjArmClass p == .fieldCarryingClosed) then
                                    (closeLiteralUnion (literals ++ picks)).map (fun v => (mark, v))
                                  -- A `fieldCarryingOpen` pick (a def-`.refId`) GOVERNS its own
                                  -- closedness, so the literal composes OPEN under it — closing the
                                  -- literal would wrongly reject a field the ref admits.
                                  else if picks.any (fun p => disjArmClass p == .fieldCarryingOpen) then
                                    some (mark, .conj (literals ++ picks))
                                  -- No open pick and not all unionable ⇒ some pick is
                                  -- `bottomsVsStruct`. CLOSE the literal so a composes-closed pick
                                  -- (`struct.MinFields`, `_`) rejects a use-site extra, and a
                                  -- kind-mismatched pick (scalar/list/`error`) bottoms the combination.
                                  else
                                    match closeLiteralUnion literals with
                                    | some closed => some (mark, .conj (closed :: picks))
                                    | none => some (mark, .conj (literals ++ picks))
                              rest ++ [.disj closedArms]
                    else expanded
            | none => [constraint]
  | _, _ => [constraint]

/-- Merge a list of per-conjunct `(fields, open)` operands into the single merged-frame field
    list. The layout (`label → slot`) is fixed by first-occurrence across conjuncts; each
    conjunct's bodies are rebased onto that layout, then merged into deferred `.conj`s on label
    collisions, and closedness is folded outward. The pure core shared by `lazyConjMergedFields`
    (same-scope struct conjunction) and the closure-meet splice (`forceClosureWithConjunct`):
    one `pushFrame` + eval over the result lets a body referencing a sibling a later conjunct
    narrows see the narrowed slot.

    Bug2-7 (def multi-decl close-once on the force-fold path): each operand's OWN fields are
    `canonicalizeFields`-ed FIRST, so two repeated DEFINITION-class decls of one path declared
    WITHIN a single struct body (`#Use: {#m:{a}; #m:{c}; …}`) UNION via `mergeDefinitionDecls`
    (Bug2-6 close-once) instead of `.conj`-ing two separately-closed bodies. This is the
    within-operand vs cross-operand soundness boundary: the close-once union fires ONLY for
    repeated decls inside ONE operand; the cross-operand merge (`mergeConjFields`, plain `.conj`)
    is unchanged, so a host's `#data` meeting an EMBED's `#data` (distinct operands) still
    `.conj`-MEETs — never unions. Without it the force-fold reconstruction (`forceClosureWithConjunct`)
    `.conj`-collapsed the within-operand decls before `canonicalizeFields` downstream could union,
    re-closing each separately and mutually rejecting (`{cert_gw:_|_, cert_ing:_|_}`). Canonicalizing
    here preserves first-occurrence layout for every slot at-or-before a collapsed duplicate, so the
    `mergedMap` (built from the canonicalized operands) and the rebased refs stay coherent — exactly
    the direct-eval `.struct` arm's treatment, now applied per-operand on the force path too. -/
def mergeConjOperands (operands : List ConjOperand) : List Field × Bool :=
  let operands := operands.map fun op => { op with fields := canonicalizeFields op.fields }
  let layoutFrame := operands.foldl (fun acc op => mergeConjFields acc op.fields) []
  let mergedMap := labelIndexMap layoutFrame
  let rebased := operands.map fun op => { op with fields := rebaseConjunctFields op.fields mergedMap }
  -- Cross-operand fold: a same-def-PATH decl pair whose operands differ in provenance
  -- (`ownDecl` × `embeddedDecl`) close-once-UNIONS (Bug2-8 — `mergeConjOperandFields`); every
  -- other collision keeps the plain `.conj`, so the cert-manager closed pattern stays a meet.
  let (mergedFields, _) := rebased.foldl
    (fun (state : List Field × List (String × DeclProvenance)) op =>
      mergeConjOperandFields state.fst op.provenance state.snd op.fields)
    ([], [])
  let closednessOperands := operands.map fun op => (op.fields, op.open_)
  let closed := applyConjClosedness closednessOperands mergedFields
  (closed, allClosednessOpen closednessOperands)

/-- Reduce a struct conjunction to its merged-frame fields + closedness, or `none` when any
    operand is not a plain same-scope struct (deferring to the eval-then-`meet` path). -/
def lazyConjMergedFields (env : Env) (constraints : List Value) :
    Option (List Field × Bool) := do
  let operands <- constraints.mapM (conjStructOperand? env evalFuel)
  -- Same-scope `{…} & {…}`: every conjunct is a sibling decl written at the use site, so all
  -- are `ownDecl` — the cross-operand decl-union (Bug2-8) is for the EMBED force-fold, never a
  -- plain use-site conjunction. A `#A & #B` distinct-def meet does not reach here (it routes
  -- through the use-site `meet` that concatenates `closedClauses`).
  pure (mergeConjOperands (operands.map ConjOperand.ofPair))

/-- The canonical field layout that evaluating `v` as a struct body pushes as a frame, or
    `none` when `v` is not a plain struct / same-scope conj (a deferral, disjunction, or
    tail/pattern-bearing form). Mirrors the `canonicalizeFields` layout the struct arm and
    `evalConjStandard` push, so looking the layout up in `pushFrame`'s deterministic frame
    table finds the SAME frame id. A probe (returns `Option`, not a `Value`), so the `| _ =>`
    catch-all is admissible. -/
def structFrameLayout? (env : Env) : Value -> Option (List Field)
  | .struct fields _ none [] _ => some (canonicalizeFields fields)
  | .conj cs =>
      match lazyConjMergedFields env cs with
      | some (mergedFields, _) => some (canonicalizeFields mergedFields)
      | none => none
  | _ => none

/-- Frame offset (depth) in `env` of the frame whose process-unique id is `fid`, or `none`. -/
def frameDepthOfId (env : Env) (fid : Nat) : Option Nat :=
  let rec go (d : Nat) : Env -> Option Nat
    | [] => none
    | frame :: rest => if Frame.id frame == fid then some d else go (d + 1) rest
  go 0 env

/-- Resolve `x.label` to a direct sibling `BindingId` when `x` (`id`) points to the struct we
    are CURRENTLY evaluating inside — i.e. `x`'s own struct-body frame is live on `env`. The
    frame is found by IDENTITY: `x`'s body layout (`structFrameLayout?`) keyed against `x`'s
    declaring scope (`env.drop id.depth`) is looked up in the `pushFrame` frame table; if that
    frame is on the stack and declares `label`, `x.label` is a same-frame sibling reference, so
    it inherits the ordinary `slotVisited` reference-cycle rule instead of force-collapsing the
    whole `x`. `none` when `x`'s frame is not live (a genuine cross-struct select) or `label` is
    absent — both leave the generic force-then-select path in charge. -/
def enclosingSelfSelectId? (frames : Std.HashMap FrameKey Nat) (env : Env)
    (id : BindingId) (label : String) : Option BindingId :=
  let outer := env.drop id.depth.val
  match outer with
  | [] => none
  | frame :: _ =>
      match nthField id.index.val frame.snd with
      | some field =>
          match structFrameLayout? outer (Field.value field) with
          | some layout =>
              match frames.get? ⟨Env.ids outer, layout⟩ with
              | some fid =>
                  match frameDepthOfId env fid with
                  | some d =>
                      match env.drop d with
                      | targetFrame :: _ =>
                          (fieldLabelIndexFrom label 0 targetFrame.snd).map
                            (fun labelIndex => ⟨⟨d⟩, ⟨labelIndex⟩⟩)
                      | [] => none
                  | none => none
              | none => none
          | none => none
      | none => none

/-- Resolve a selector CHAIN `x.f.g…` to a direct `BindingId` when every step lands in a struct
    frame currently live on `env` — the multi-level generalization of `enclosingSelfSelectId?`.
    The bare-`refId` base yields the reference's own binding; each `.selector inner label` step
    resolves `label` against the live frame of `inner`'s resolved binding. `none` at the first
    step whose frame is not live (a genuine cross-struct select) — leaving the generic
    force-then-select path to handle it. A probe (`Option`), so `| _ =>` is admissible. -/
def selectChainId? (frames : Std.HashMap FrameKey Nat) (env : Env) : Value -> Option BindingId
  | .refId id => some id
  | .selector inner label =>
      (selectChainId? frames env inner).bind (fun innerId =>
        enclosingSelfSelectId? frames env innerId label)
  | _ => none

/-- Reopen an evaluated struct value (`open_ := true`) so it contributes its fields by `meet`
    WITHOUT imposing its own closedness on the host — an embedding UNIONS labels into the
    enclosing def's closed set rather than restricting it. Non-struct values pass through. -/
def openStructValue : Value -> Value
  -- A plain struct reopens; tail/pattern-bearing forms pass through.
  | .struct fields _ none [] _ => mkStruct fields .regularOpen none []
  -- Every other value (incl. a tail/pattern/clause-bearing struct) is the identity.
  -- Enumerated (not `other => other`) so a NEW `Value` constructor forces a decision here
  -- — reopen-like or pass-through — rather than being silently identity.
  | value@(.struct _ _ _ _ _) => value
  | value@(.top) => value
  | value@(.bottom) => value
  | value@(.bottomWith _) => value
  | value@(.prim _) => value
  | value@(.kind _) => value
  | value@(.notPrim _) => value
  | value@(.stringRegex _) => value
  | value@(.stringFormat _) => value
  | value@(.boundConstraint _ _) => value
  | value@(.lengthConstraint _ _ _) => value
  | value@(.uniqueItems) => value
  | value@(.conj _) => value
  | value@(.builtinCall _ _) => value
  | value@(.unary _ _) => value
  | value@(.binary _ _ _) => value
  | value@(.ref _) => value
  | value@(.refId _) => value
  | value@(.patternLabel _) => value
  | value@(.thisStruct) => value
  | value@(.selector _ _) => value
  | value@(.index _ _) => value
  | value@(.disj _) => value
  | value@(.list _) => value
  | value@(.listTail _ _) => value
  | value@(.embeddedList _ _ _) => value
  | value@(.embeddedScalar _ _) => value
  | value@(.comprehension _ _) => value
  | value@(.structComp _ _ _) => value
  | value@(.listComprehension _ _) => value
  | value@(.interpolation _) => value
  | value@(.dynamicField _ _ _) => value
  | value@(.closure _ _) => value

/-- Is `label` a same-def-PATH collision between the two field lists — both declare it
    DEFINITION-class AND both values are union-able struct bodies (`isUnionableDefValue`)? Such a
    pair is two decls of the ONE def path that close-once-UNION; a scalar/kind def value
    (`#x: string`) is left to the ordinary meet (a `.conj` there would double the display, e.g.
    `string & string`). -/
def isSameDefPathLabel (hostFields embedFields : List Field) (label : String) : Bool :=
  match findEvalField label hostFields, findEvalField label embedFields with
  | some hostField, some embedField =>
      (Field.fieldClass hostField).isDefinition && (Field.fieldClass embedField).isDefinition
        && isUnionableDefValue (Field.value hostField) && isUnionableDefValue (Field.value embedField)
  | _, _ => false

/-- Meet a host struct against an EMBEDDING, honouring the same-def-PATH `#m` decls already
    close-once-UNIONED into the host's `#m` slot by the static `.structComp` fold (Bug2-8, eager +
    force arms). The host's `#m` already carries the union BEFORE this meet, so the embed's matching
    `#m` is simply STRIPPED — the generic `meet` must NOT re-meet the union against the embed's
    narrower arm (which would re-close-REJECT the host's other labels, or double an equal shared
    field to `1 & 1`). Every non-same-def-path field still meets normally; the embed is OPENED
    (`openStructValue`) so it widens the host's allowed set without imposing its own closedness (a
    REGULAR closed pattern stays a meet). A non-struct host or embed falls back to the plain meet. -/
def meetEmbedUnioningDefDecls (host embed : Value) : Value :=
  match host, embed with
  | .struct hostFields _ _ _ _, .struct embedFields eo et ep ec =>
      let sharedLabels := hostFields.filterMap fun f =>
        if isSameDefPathLabel hostFields embedFields (Field.label f) then some (Field.label f) else none
      -- No same-def-path collision: leave the embed untouched (preserve its patterns/tail/closedness)
      -- and meet plainly — the cert-manager closed PATTERN path and every ordinary embed meet stay
      -- byte-identical.
      if sharedLabels.isEmpty then meet host (openStructValue embed)
      else
        -- Strip the embed's same-def-path `#m`s (the host already has their union via the static
        -- fold); the embed's OTHER fields/patterns/tail still meet (kept on the opened embed-rest).
        let embedRest := Value.struct (embedFields.filter (fun f => !sharedLabels.contains (Field.label f)))
          eo et ep ec
        meet host (openStructValue embedRest)
  | _, _ => meet host (openStructValue embed)

/-- Collapse an EMBEDDED disjunction to its default arm before it merges into the host.
    An embedded default disjunction (`(*{a:1} | {a:2})`) contributes its DEFAULT arm's fields
    to the host struct — both for the merge (so a sibling `Self.a` sees `a`) and for the
    closedness union (so the host admits the embedded label). A non-default disjunction with
    no unique winner stays a `.disj` (CUE distributes the host across it; left untouched here).
    Non-disjunction values pass through. -/
def resolveEmbeddedDisjDefault : Value -> Value
  | value => collapseDefaultDisjunction value

/-- Drop a struct operand's lexical alias bindings (`let`/`Self=` — `FieldClass.letBinding`)
    before splicing it into ANOTHER struct's frame. An alias is scoped to the struct that
    declares it; an embedded def has its OWN `Self`, so carrying the host's `Self` (a
    `.thisStruct`) into the embed's merged frame collides with the embed's `Self` and breaks the
    embed's `Self.label` selections (→ `.bottom`). Field values (incl. ones the host narrowed)
    are kept — only the alias bindings are removed. -/
def stripLetBindings (operand : List Field × Bool) : List Field × Bool :=
  (operand.fst.filter (fun f => f.fieldClass != .letBinding), operand.snd)

/-- Keep ONLY the hidden/definition fields (`#x`, `_x` — `Field.ignoresClosedness`) of a host
    struct operand when splicing it INTO an embedded def. An embed self-references the host's
    SHARED hidden fields (`pname: Self.#name`, where `#name` flows from the use-site), so those
    must reach the embed's frame. But the host's REGULAR output fields (`apiVersion`, `kind`) are
    NOT the embed's — splicing them in makes the embed carry, re-evaluate, and conflict on them
    (the host's `kind: Self.#name` re-evaluated in the embed frame → `.bottom`). Regular fields
    unify with the embed's at the outer `meet`, not via the splice. -/
def hiddenFieldsOnly (operand : List Field × Bool) : List Field × Bool :=
  (operand.fst.filter (fun f => f.fieldClass != .letBinding && Field.ignoresClosedness f), operand.snd)

/-- Transitively close a frontier of def-frame slot indices by FOLLOWING `letBinding` slots into
    their bound value. `defFrameRefIndices` treats a `.refId` as a LEAF, so a comprehension reading
    a regular sibling THROUGH a `let` (`let _patch = { … if kind == … }`; the top-level `cs` holds
    only the `_patch` embed-ref, a `.refId` to the let slot) is invisible to a single scan. For each
    index already discovered that names a `let` slot in `fields`, scan that let's VALUE at the def
    frame (depth 0 — the let value is lexically a sibling, same as the top-level `cs`/fields are
    scanned) for further def-frame reads, and recurse on the newly-found let slots. `seen` is the
    visited-set of let slots already followed; it bounds the recursion so a self/mutually-referential
    `let` (`let a = b; let b = a`) cannot loop — at most one follow per slot. `fuel` is a second
    bound (= field count suffices) keeping the function structurally total. Returns the full closed
    index set (the seeds plus everything reachable through lets). -/
def closeDefFrameReadIndices
    (fuel : Nat) (fields : List Field) (seen : List Nat) : List Nat -> List Nat
  | [] => []
  | frontier =>
      match fuel with
      | 0 => frontier
      | f + 1 =>
          -- Lets in the frontier not yet followed; their bound values may read more def siblings.
          let newLets := frontier.filter fun i =>
            !slotVisited i seen && (match nthField i fields with
              | some fl => fl.fieldClass == .letBinding
              | none => false)
          let nextReads := newLets.flatMap fun i =>
            match nthField i fields with
            | some fl => defFrameRefIndices evalFuel 0 (Field.value fl)
            | none => []
          let seen' := newLets ++ seen
          frontier ++ closeDefFrameReadIndices f fields seen' nextReads

/-- Bug2-4: the regular-output labels a FOLLOWED let's OWN comprehension reads from the let's OWN
    frame — labels the let PROMOTES to the embed frame when it is embedded, and which the host
    therefore narrows. Distinct from `closeDefFrameReadIndices`, which collects reads resolving to
    the EMBED's def frame (depth 0). When a let buries BOTH the read and the declaration of the
    narrowed sibling (`let _patch = { kind: string; for … { if kind == add.#kind {…} } }`), the
    guard's `kind` resolves to `_patch`'s OWN frame (not `#M`'s), and `kind` is declared there too,
    so no `#M`-def-frame index names it — the one-frame `closeDefFrameReadIndices` follow misses it.
    But `_patch` embeds into `#M`, so its `kind` is promoted to `#M`'s frame and the use-site narrows
    it; the guard must see the narrowed value. This walks a let's struct-like value, collects the
    regular labels its OWN comprehensions read, and recurses into nested let slots (a let embedding a
    let) to a FIXPOINT. `seen` (the visited let-VALUEs, by structural `BEq`) + `fuel` bound the
    recursion total: a self/mutual let-cycle re-encounters a visited value and stops. Only WIDENS the
    spliced label set (merges by label = the outer meet — recovers a dropped narrowing, never
    over-splices a value), the same soundness as Bug2-1/Gap-1. -/
def letPromotedReadLabels (fuel : Nat) (seen : List Value) : Value -> List String
  | v =>
      match fuel with
      | 0 => []
      | f + 1 =>
          if seen.contains v then []
          else
            let seen' := v :: seen
            -- A let value is a `.structComp` (unevaluated embed body) or `.struct` (evaluated). Its
            -- OWN comprehension reads resolve to ITS frame (depth 0); keep the regular-output ones,
            -- then recurse into the value's own let slots (a let-in-let) for further buried reads.
            let go := fun (innerFields : List Field) (innerCs : List Value) =>
              let ownReads := innerCs.flatMap (defFrameRefIndices evalFuel 0)
                ++ innerFields.flatMap (fun fl => defFrameRefIndices evalFuel 0 (Field.value fl))
              let ownLabels := ownReads.filterMap (fun i =>
                match nthField i innerFields with
                | some fl => if Field.isRegularOutput fl then some (Field.label fl) else none
                | none => none)
              let nestedLabels := innerFields.flatMap (fun fl =>
                if fl.fieldClass == .letBinding then
                  letPromotedReadLabels f seen' (Field.value fl)
                else [])
              (ownLabels ++ nestedLabels).eraseDups
            match v with
            | .structComp innerFields innerCs _ => go innerFields innerCs
            | .struct innerFields _ tail _ _ =>
                go innerFields (match tail with | some t => [t] | none => [])
            | _ => []

/-- Bug2-4 (argocd Mixin): meet a host narrowing INTO a let-local field that both DECLARES and (via
    the let's own comprehension) READS the narrowed label. `letPromotedReadLabels` surfaces the
    label so the host splices its narrowed value into the def frame, but when the let DECLARES its
    own copy (`let _patch = { kind: string; for … { if kind == … } }`), that splice lands at the
    def frame as a SIBLING — the let-local `kind: string` is a distinct binding the guard reads, so
    the comprehension still fires against `string` and drops. cue promotes the let's `kind` to the
    embed output and narrows it lazily; this rewrites the let's value so the local `kind` carries the
    host's narrowing before the comprehension expands. `narrowings` is the use-operand's regular
    `(label, value)` pairs; only a let-local that is read by the let's comprehension is touched
    (gated by `letPromotedReadLabels` ⊇ its label), so a let that merely declares an unrelated field
    is untouched (byte-identical). `seen`/`fuel` bound the recursion total over nested lets/cycles.
    Sound: it only MEETS the host narrowing into a field the host narrows anyway — never invents a
    value, never widens beyond the use-site meet. -/
def injectLetLocalNarrowings (fuel : Nat) (narrowings : List (String × Value)) (seen : List Value) :
    Value -> Value
  | v =>
      match fuel with
      | 0 => v
      | f + 1 =>
          if seen.contains v then v
          else
            let seen' := v :: seen
            -- The labels this let's OWN comprehension reads from its OWN frame (so only a
            -- read-and-declared local is narrowed, not an incidental same-named field).
            let readLabels := letPromotedReadLabels evalFuel [] v
            let rewriteFields := fun (innerFields : List Field) =>
              innerFields.map fun fl =>
                if Field.isRegularOutput fl && readLabels.contains (Field.label fl) then
                  match narrowings.find? (fun p => p.fst == Field.label fl) with
                  | some (_, nv) => { fl with value := meet (Field.value fl) nv }
                  | none => fl
                else if fl.fieldClass == .letBinding then
                  -- A nested let may itself declare-and-read a narrowed label.
                  { fl with value := injectLetLocalNarrowings f narrowings seen' (Field.value fl) }
                else fl
            match v with
            | .structComp innerFields innerCs o => .structComp (rewriteFields innerFields) innerCs o
            | .struct innerFields o tail p e => .struct (rewriteFields innerFields) o tail p e
            | .top | .bottom | .bottomWith _ | .prim _ | .kind _
            | .notPrim _ | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _
            | .builtinCall _ _ | .unary _ _ | .binary _ _ _ | .ref _ | .refId _ | .patternLabel _
            | .thisStruct | .selector _ _ | .index _ _ | .disj _ | .list _
            | .listTail _ _ | .embeddedList _ _ _ | .embeddedScalar _ _
            | .comprehension _ _ | .listComprehension _ _ | .interpolation _
            | .dynamicField _ _ _ | .closure _ _ => v

/-- The labels of an embed body's OWN top-level fields that a comprehension inside it reads by a
    bare reference (`defFrameRefIndices` at the def frame, mapped index → label), FOLLOWING `let`
    bindings transitively (`closeDefFrameReadIndices`). These are the regular siblings a guard/source
    depends on (`if kind == add.#kind` reads `kind`; `for … in items` reads `items`), possibly
    THROUGH one or more `let`s (`let _patch = { … if kind == … }`, even nested
    `let structShape = { _patch }`); the host narrows them at the use site, so they must reach the
    embed's splice or the comprehension fires against the un-narrowed value and drops. `none` for a
    non-struct-like body (no top-level frame to index). -/
def embedComprehensionReadLabels : Value -> List String
  | .structComp fields cs _ =>
      -- A comprehension guard/source reads a regular sibling by a BARE reference resolving to the
      -- def frame (`if kind == add.#kind`: `kind` is `.refId ⟨d, idx⟩` with `d` = the frame-pushers
      -- between the read and the def — `for`-body struct + clause pushes). `defFrameRefIndices`
      -- threads that depth; `closeDefFrameReadIndices` then follows any `let` slot the seed reads
      -- (the `_patch`/`structShape` embed-refs are `.refId`s to let slots) into the let's value to
      -- find the buried `kind`/`items` read. Map index → label and keep them. A `Self=` alias slot
      -- read by a `for` SOURCE (`Self.#additions`) may also appear — harmless, since
      -- `spliceOperandForEmbed` only adds REGULAR operand fields with these labels.
      let seeds := cs.flatMap (defFrameRefIndices evalFuel 0)
      embedReadLabelsClosing fields seeds
  | .struct fields _ tail _ _ =>
      let seeds := fields.flatMap (fun f => defFrameRefIndices evalFuel 0 (Field.value f))
        ++ (match tail with | some t => defFrameRefIndices evalFuel 0 t | none => [])
      embedReadLabelsClosing fields seeds
  | _ => []
where
  /-- Close `seeds` over the def frame's let slots, then collect TWO label sets: the def-frame
      labels the comprehension reads (`closeDefFrameReadIndices`, the Bug2-1 set), PLUS the
      let-PROMOTED regular labels a followed let buries both the read AND declaration of
      (`letPromotedReadLabels`, Bug2-4). The closed index set names every let slot that was
      followed; feed each such let's value to `letPromotedReadLabels`. -/
  embedReadLabelsClosing (fields : List Field) (seeds : List Nat) : List String :=
    let closed := closeDefFrameReadIndices fields.length fields [] seeds
    let defFrameLabels := closed.filterMap (fun i => (nthField i fields).map Field.label)
    let promoted := closed.flatMap (fun i =>
      match nthField i fields with
      | some fl => if fl.fieldClass == .letBinding then
          letPromotedReadLabels fields.length [] (Field.value fl)
        else []
      | none => [])
    (defFrameLabels ++ promoted).eraseDups

/-- Bug2-14: meet a host narrowing INTO an embed body's OWN field that both DECLARES a label the
    HOST narrows AND reads it from a sibling (a plain `echo: bk`) or its comprehension (`if bk ==
    …`). When an embed declares `bk: string` (ABSTRACT) while the host declares `bk: "X"`
    (CONCRETE), the embed body's `echo: bk` / `if bk == "X"` resolves against the EMBED-LOCAL
    `string` (the embed is a separate frame; its sibling ref is depth-0 into its OWN slot, not the
    host's), so the read sees the un-narrowed type — the value is wrong / the guard never fires.
    The host's narrowing reaches the embed-output only via the LATER `meet` of the embed's fields
    against the host (too late for the already-captured read). This rewrites the embed body so the
    embed-local same-label slot carries the host-narrowed value BEFORE the body evaluates.

    The analog of `injectLetLocalNarrowings` (Bug2-4), but for an embed body rather than a
    let-local. Gated to the SAME-LABEL embed-abstract × host-concrete overlap exactly: only a
    regular-output field the embed declares AND `embedComprehensionReadLabels` surfaces (so a plain
    sibling ref `echo: bk` and a comprehension read both qualify) AND the host's `narrowings`
    actually carries — so an embed-INTERNAL field the host does NOT narrow (`other: string` read by
    `echo: other`) is untouched (stays embed-local), and a host-only field is irrelevant. Recurses
    into NESTED embeds (a doubly-wrapped `{{bk:string,echo:bk}}`) and let bodies. Sound: it only
    MEETS the host narrowing into a field the host narrows anyway (the embed's same label) — never
    invents a value, never widens beyond the use-site meet (`int & "X"` still bottoms). `seen`/`fuel`
    bound the recursion total over nested embeds/cycles. -/
def injectEmbedSiblingNarrowings (fuel : Nat) (narrowings : List (String × Value)) (seen : List Value) :
    Value -> Value
  | v =>
      match fuel with
      | 0 => v
      | f + 1 =>
          if seen.contains v then v
          else
            let seen' := v :: seen
            -- The embed body's OWN labels read by a sibling/comprehension (plain `echo: bk` is a
            -- depth-0 ref, captured by `embedComprehensionReadLabels`).
            let readLabels := embedComprehensionReadLabels v
            let rewriteFields := fun (innerFields : List Field) =>
              innerFields.map fun fl =>
                if Field.isRegularOutput fl && readLabels.contains (Field.label fl) then
                  match narrowings.find? (fun p => p.fst == Field.label fl) with
                  | some (_, nv) => { fl with value := meet (Field.value fl) nv }
                  | none => fl
                else if fl.fieldClass == .letBinding then
                  { fl with value := injectLetLocalNarrowings f narrowings seen' (Field.value fl) }
                else fl
            -- Recurse into a NESTED embedding (a plain embed of an embed) so a doubly-wrapped
            -- abstract field is narrowed at its own level.
            let rewriteEmbeds := fun (cs : List Value) =>
              cs.map fun c =>
                if isEmbeddingValue c then injectEmbedSiblingNarrowings f narrowings seen' c else c
            match v with
            | .structComp innerFields innerCs o =>
                .structComp (rewriteFields innerFields) (rewriteEmbeds innerCs) o
            | .struct innerFields o tail p e => .struct (rewriteFields innerFields) o tail p e
            | .top | .bottom | .bottomWith _ | .prim _ | .kind _
            | .notPrim _ | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _
            | .builtinCall _ _ | .unary _ _ | .binary _ _ _ | .ref _ | .refId _ | .patternLabel _
            | .thisStruct | .selector _ _ | .index _ _ | .disj _ | .list _
            | .listTail _ _ | .embeddedList _ _ _ | .embeddedScalar _ _
            | .comprehension _ _ | .listComprehension _ _ | .interpolation _
            | .dynamicField _ _ _ | .closure _ _ => v

/-- The DISCRIMINATOR labels of an embed body's embedded disjunction (Gap-2, Bug2-2): a regular
    sibling the body declares (`shape: string`) that the disjunction's arms also DECLARE as a
    field (`{shape:"struct",…} | {shape:"list",…}`). When such an embedded def is itself embedded
    one layer down (`#U:{#M}`, then `#U & {shape:"struct"}`), the outer use-site narrowing of the
    discriminator reaches the host frame but is NOT spliced into `#M` by `embedComprehensionReadLabels`
    (the arms MATCH `shape`, they don't READ it) — so `#M`'s force-time disjunction sees no `shape`,
    every arm survives, and the outer meet then conflicts (kue bottom; cue selects the struct arm).
    Surfacing these labels lets the host's narrowed discriminator splice into `#M` so its force-time
    arm distribution prunes the dead arms exactly as a DIRECT `#M & {shape:"struct"}` does — the same
    `liveAlternatives` pruning, just re-driven behind the force tier.

    GATE (mandatory, the cert-manager byte-identity guard): returns `[]` UNLESS the body's `cs` holds
    a `.disj` embedding (no disjunction embedding → no extra splice → byte-identical). A label
    qualifies only if it is BOTH a top-level regular field of the body AND declared by some arm — so
    only the genuine def-frame discriminator the host narrows is added, never an unrelated host
    field. The spliced value is the SAME use-site narrowing (merged by label), so a real conflict on
    the discriminator still bottoms and no arm that should be pruned survives. -/
def embedDisjArmDeclLabels : Value -> List String
  | .structComp fields cs _ =>
      -- The non-alias, non-hidden (regular output) labels a struct-like value declares.
      let regularLabels := fun (fs : List Field) =>
        fs.filterMap fun f =>
          if Field.isRegularOutput f then some (Field.label f) else none
      let bodyLabels := regularLabels fields
      -- The regular labels an arm VALUE declares directly. A `.refId ⟨0, i⟩` arm names a `let` slot
      -- in THIS body frame (`shapeD`: `structShape | listShape | error`, each a let holding
      -- `{shape: "struct"/"list", …}`); follow it into the body's own let value at index `i`.
      let armDeclLabels := fun (arm : Value) =>
        let declOf := fun (v : Value) =>
          match v with
          | .struct armFields _ _ _ _ => regularLabels armFields
          | .structComp armFields _ _ => regularLabels armFields
          | _ => []
        match arm with
        | .refId id =>
            if id.depth == 0 then
              match nthField id.index.val fields with
              | some fl => declOf (Field.value fl)
              | none => []
            else []
        | _ => declOf arm
      let armLabels := cs.flatMap fun c =>
        match c with
        | .disj alternatives => alternatives.flatMap fun alt => armDeclLabels alt.snd
        | _ => []
      (bodyLabels.filter armLabels.contains).eraseDups
  | _ => []

/-- Does an embed body embed a DISJUNCTION (a bare `(a | b | …)` in its comprehension/embedding
    list `cs`)? Gap-2b: such a disjunction is discriminated STRUCTURALLY (`listShape |
    structShape`), so the arms' shape (list vs struct) — not a regular discriminator label — picks
    the surviving arm. A direct `.disj` embedding counts; so does a `.refId ⟨0,i⟩` embedding whose
    THIS-frame let slot holds a `.disj` (the arms themselves may be further let-refs, followed by
    the meet). Used to GATE the Gap-2b regular-field splice: only a disjunction-embedding body
    needs the host's regular output fields routed into its arms; every other body keeps the
    narrow hidden+comprehension-read splice (byte-identical). -/
def embedBodyEmbedsDisj : Value -> Bool
  | .structComp fields cs _ =>
      cs.any fun c =>
        match c with
        | .disj _ => true
        | .refId id =>
            id.depth == 0 &&
              (match (nthField id.index.val fields).map Field.value with
               | some (.disj _) => true
               | _ => false)
        | _ => false
  | _ => false

/-- The splice operand a use/host struct contributes INTO an embedded def whose body is
    `embedBody`. Normally `hiddenFieldsOnly` (the shared hidden/def bindings the embed
    self-references) PLUS the regular fields a comprehension reads or a disjunction's arms declare
    (`spliceOperandForEmbed`'s `extraLabels`). Gap-2b adds: when `embedBody` embeds a STRUCTURAL
    disjunction (`embedBodyEmbedsDisj`), splice ALL the host's REGULAR OUTPUT fields too, so they
    reach the embedded disjunction's arms as a value — letting the SOUND `meet`-distribution prune
    a list-shaped arm against the struct host (`list & {regular fields} = ⊥`) while a
    struct-compatible arm survives untouched (meet is idempotent on a field it already carries).
    The prune is the existing type-conflict primitive, not a shape heuristic, so two
    struct-compatible arms stay ambiguous (cue-exact). -/
def spliceOperandForEmbed (embedsDisjDeep : Bool) (embedBody : Value) (operand : List Field × Bool) :
    List Field × Bool :=
  let extraLabels := (embedComprehensionReadLabels embedBody ++ embedDisjArmDeclLabels embedBody).eraseDups
  -- Gap-2b: a STRUCTURAL-disjunction-embedding body needs ALL the host's regular output fields
  -- routed into its arms (so the sound `list & {regular fields} = ⊥` meet prunes a list arm);
  -- otherwise keep the narrow comprehension-read/discriminator splice (byte-identical). Bug2-5: the
  -- disjunction may be embedded TRANSITIVELY (a re-embed of a disjunction-bodied def), surfaced by
  -- the caller's `embedBodyEmbedsDisjDeep` — so the regular-field splice (here, the sibling `kind`
  -- that narrows a buried `_patch.kind`) reaches a disjunction two embed levels down.
  let keepLabel := fun (f : Field) =>
    Field.isRegularOutput f && (embedsDisjDeep || extraLabels.contains (Field.label f))
  if extraLabels.isEmpty && !embedsDisjDeep then hiddenFieldsOnly operand
  else
    let (hidden, open_) := hiddenFieldsOnly operand
    let extraRegulars := operand.fst.filter keepLabel
    (hidden ++ extraRegulars, open_)

/-- Apply the def's closedness over the embedding UNION to an already-meet-folded struct: the
    single definition of CUE's embedding-closedness rule (shared by the eager `.structComp` eval
    arm and the `.structComp` closure-force arm). The host was met OPEN against each (opened)
    embedding, so its closedness must be re-applied ONCE over `def static labels ∪ each
    embedding's evaluated labels` — an embedding widens the allowed set without imposing its own
    closedness, and pre-closing the static frame would wrongly reject the embed's own fields. -/
def closeEmbeddedOver (defFields embeddingFields : List Field) (defOpen : Bool) : Value -> Value
  -- A plain struct gets the def's closedness re-applied; tail/pattern forms pass through.
  | .struct fields _ none [] _ =>
      mkStruct (applyClosednessFrom (defFields ++ embeddingFields) defOpen fields) (.ofBool defOpen) none []
  -- Every other value (incl. a tail/pattern/clause-bearing struct) is the identity.
  -- Enumerated (not `other => other`) so a NEW `Value` constructor forces a decision here
  -- — reclose-like or pass-through — rather than being silently identity.
  | value@(.struct _ _ _ _ _) => value
  | value@(.top) => value
  | value@(.bottom) => value
  | value@(.bottomWith _) => value
  | value@(.prim _) => value
  | value@(.kind _) => value
  | value@(.notPrim _) => value
  | value@(.stringRegex _) => value
  | value@(.stringFormat _) => value
  | value@(.boundConstraint _ _) => value
  | value@(.lengthConstraint _ _ _) => value
  | value@(.uniqueItems) => value
  | value@(.conj _) => value
  | value@(.builtinCall _ _) => value
  | value@(.unary _ _) => value
  | value@(.binary _ _ _) => value
  | value@(.ref _) => value
  | value@(.refId _) => value
  | value@(.patternLabel _) => value
  | value@(.thisStruct) => value
  | value@(.selector _ _) => value
  | value@(.index _ _) => value
  | value@(.disj _) => value
  | value@(.list _) => value
  | value@(.listTail _ _) => value
  | value@(.embeddedList _ _ _) => value
  | value@(.embeddedScalar _ _) => value
  | value@(.comprehension _ _) => value
  | value@(.structComp _ _ _) => value
  | value@(.listComprehension _ _) => value
  | value@(.interpolation _) => value
  | value@(.dynamicField _ _ _) => value
  | value@(.closure _ _) => value

/-- Extract an evaluated value's struct-conjunct operand `(fields, open)` for splicing into a
    forced closure body. Returns `none` for non-struct values (primitives, lists, …), which
    cannot be spliced and fall back to a plain `meet` against the forced body. -/
def evaluatedStructOperand? : Value -> Option (List Field × Bool)
  -- An explicit `...` tail is OPEN: as a use/conjunct operand it imposes no closedness on the
  -- host (`applyClosednessFrom` is a no-op when open), so it contributes `true`. A closed sibling
  -- operand still restricts the merged set via its own `false`; an open operand never reopens it
  -- (closedness ANDs). Mapping `defOpenViaTail → false` wrongly closed an open host to the
  -- operand's own (often empty) label set, bottoming the host's sibling-referencing fields.
  | .struct fields openness _ _ _ => some (fields, openness.isOpen)
  | _ => none

/-- The host's REGULAR-OUTPUT `(label, value)` pairs — the concrete narrowing a host struct
    contributes when an embed declares the same label abstractly (Bug2-14). Empty for a
    non-struct host (a scalar/list host has no field to narrow an embed sibling). -/
def hostNarrowingPairs (host : Value) : List (String × Value) :=
  match evaluatedStructOperand? host with
  | some (fields, _) =>
      fields.filterMap fun f =>
        if Field.isRegularOutput f then some (Field.label f, Field.value f) else none
  | none => []

/-- The narrowing fields a use operand splices into a forced def's frame. Extends
    `evaluatedStructOperand?` with the `.embeddedList` case: a use operand that is a
    struct-embedding-a-list (`packs.#Argo & { [...]; #name: "web" }`) evaluates to an
    `.embeddedList` whose `decls` carry the hidden-field narrowing (`#name: "web"`). That
    narrowing must still reach the def's frame so a `Self.#name` read inside the def's OWN
    list embed (`[Self.#name]`) resolves against the use-site value, not the def default.
    `evaluatedStructOperand?` returns `none` for an `.embeddedList`, so the deferral fold dropped
    the narrowing and the def's list embed saw `string`/the def default (argocd `packs.#Argo`,
    link 5). Surfacing the decls here splices them; the `.embeddedList`'s LIST portion still
    unifies via the value-level `meet` (`nonClosureNonStructOperands` keeps it — it is not a
    plain struct operand), so concrete use-site list items are not lost. -/
def spliceNarrowingOperand? : Value -> Option (List Field × Bool)
  | .embeddedList _ _ decls => some (decls, true)
  | .embeddedScalar _ decls => some (decls, true)
  | other => evaluatedStructOperand? other

/-- Every `.closure (capturedEnv, body)` among evaluated conjunction operands (slice A:
    multi-operand fold). `#M & #N & {narrow}` yields TWO closures; each is force-spliced with the
    SHARED use-operand set so both defs' siblings see the use-site narrowing. -/
def allClosures : List Value -> List (Env × Value)
  | [] => []
  | .closure capturedEnv body :: rest => (capturedEnv, body) :: allClosures rest
  | _ :: rest => allClosures rest

/-- The evaluated operands that are NEITHER a `.closure` NOR a splice-able struct operand
    (primitives, lists, …). These `meet` against the folded forced result(s); the struct
    operands are absorbed by the splice (`evaluatedStructOperand?`) and the closures are forced. -/
def nonClosureNonStructOperands : List Value -> List Value
  | [] => []
  | .closure _ _ :: rest => nonClosureNonStructOperands rest
  | other :: rest =>
      match evaluatedStructOperand? other with
      | some _ => nonClosureNonStructOperands rest
      | none => other :: nonClosureNonStructOperands rest

end Kue
