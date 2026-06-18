import Kue.Builtin
import Kue.Decimal
import Kue.Lattice
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
  match env.drop id.depth with
  | [] => none
  | frame :: _ =>
      match nthField id.index frame.snd with
      | some field =>
          match Field.value field with
          | .thisStruct =>
              match fieldLabelIndexFrom label 0 frame.snd with
              | some labelIndex => some ⟨id.depth, labelIndex⟩
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
/-- Does `value` reference `Self.<label>` for some `label ∈ labels`, where `Self` is the
    binding at `selfIndex` in the def's OWN frame, reachable from `depth` frame-pushers deep? A
    resolved `Self.a` read from the def's own frame is `.selector (.refId ⟨0, selfIndex⟩) a`; read
    from a NESTED struct (`spec: { hostnames: Self.#hosts }`) it is `.selector (.refId ⟨d,
    selfIndex⟩) a` with `d` = the number of intervening frames. Descending a frame-pusher
    (`.struct`/`.structTail`/`.structComp`/pattern) increments `depth`, so a self-ref lands iff
    `id.depth == depth`, exactly mirroring `hasSelfRefAtDepth`. Fuel-bounded structural scan; used
    to gate the embedding-`Self` two-pass so it fires when ANY field (at any nesting depth) selects
    an embedding-supplied label through the host's `Self`. -/
def refsSelfEmbeddedLabel (fuel : Nat) (depth selfIndex : Nat) (labels : List String) : Value -> Bool
  | .selector (.refId id) label =>
      id.depth == depth && id.index == selfIndex && labels.contains label
  | .selector base _ =>
      match fuel with | 0 => false | f + 1 => refsSelfEmbeddedLabel f depth selfIndex labels base
  | .index base key =>
      match fuel with
      | 0 => false
      | f + 1 => refsSelfEmbeddedLabel f depth selfIndex labels base || refsSelfEmbeddedLabel f depth selfIndex labels key
  | .unary _ v =>
      match fuel with | 0 => false | f + 1 => refsSelfEmbeddedLabel f depth selfIndex labels v
  | .binary _ l r =>
      match fuel with
      | 0 => false
      | f + 1 => refsSelfEmbeddedLabel f depth selfIndex labels l || refsSelfEmbeddedLabel f depth selfIndex labels r
  | .conj cs =>
      match fuel with | 0 => false | f + 1 => cs.any (refsSelfEmbeddedLabel f depth selfIndex labels)
  | .disj alts =>
      match fuel with | 0 => false | f + 1 => alts.any (fun a => refsSelfEmbeddedLabel f depth selfIndex labels a.snd)
  | .interpolation parts =>
      match fuel with | 0 => false | f + 1 => parts.any (refsSelfEmbeddedLabel f depth selfIndex labels)
  | .struct fields _ =>
      match fuel with | 0 => false | f + 1 => fields.any (fun fl => refsSelfEmbeddedLabel f (depth + 1) selfIndex labels (Field.value fl))
  | .structTail fields tail =>
      match fuel with
      | 0 => false
      | f + 1 => fields.any (fun fl => refsSelfEmbeddedLabel f (depth + 1) selfIndex labels (Field.value fl))
          || refsSelfEmbeddedLabel f (depth + 1) selfIndex labels tail
  | .structComp fields cs _ _ =>
      match fuel with
      | 0 => false
      | f + 1 => fields.any (fun fl => refsSelfEmbeddedLabel f (depth + 1) selfIndex labels (Field.value fl))
          || cs.any (refsSelfEmbeddedLabel f (depth + 1) selfIndex labels)
  | .list items =>
      match fuel with | 0 => false | f + 1 => items.any (refsSelfEmbeddedLabel f depth selfIndex labels)
  | .listTail items tail =>
      match fuel with
      | 0 => false
      | f + 1 => items.any (refsSelfEmbeddedLabel f depth selfIndex labels) || refsSelfEmbeddedLabel f depth selfIndex labels tail
  | .comprehension clauses body =>
      -- Clause sources/guards resolve in the comprehension's enclosing frame; the body resolves
      -- `#forClauses` frames deeper (`for` pushes one, `guard` none). The depth is threaded by
      -- `refsSelfEmbeddedLabelClauses`, matching `resolveClausesWithFuel`: a too-shallow body scan
      -- would compare a deep `Self.<embedded>` read (at `depth+#for`) against `depth`, MISS it, and
      -- fail to fire the two-pass — a stale-value miss, not a perf-only over-fire (the A5 sibling).
      match fuel with
      | 0 => false
      | f + 1 => refsSelfEmbeddedLabelClauses f depth selfIndex labels clauses body
  | .listComprehension clauses body =>
      -- List-context comprehension (`listeners: [for h in Self.#hosts {…}]` — the ListenerSet
      -- shape): the `Self.<embedded-label>` source must trigger the two-pass exactly as a struct
      -- comprehension's does, else the source iterates the un-narrowed (empty) embedded value.
      match fuel with
      | 0 => false
      | f + 1 => refsSelfEmbeddedLabelClauses f depth selfIndex labels clauses body
  | .dynamicField l _ v =>
      match fuel with
      | 0 => false
      | f + 1 => refsSelfEmbeddedLabel f depth selfIndex labels l || refsSelfEmbeddedLabel f depth selfIndex labels v
  | .builtinCall _ args =>
      -- Args resolve in the enclosing frame (same `depth`): `count: len(Self.#x)` reads the
      -- embedded label through the host `Self` from inside the call.
      match fuel with | 0 => false | f + 1 => args.any (refsSelfEmbeddedLabel f depth selfIndex labels)
  | .embeddedList items tail decls =>
      -- Items/tail are list elements (same frame); decls are the embedding struct's surviving
      -- member fields (one frame deeper, like `.struct`).
      match fuel with
      | 0 => false
      | f + 1 => items.any (refsSelfEmbeddedLabel f depth selfIndex labels)
          || (match tail with | some t => refsSelfEmbeddedLabel f depth selfIndex labels t | none => false)
          || decls.any (fun fl => refsSelfEmbeddedLabel f (depth + 1) selfIndex labels (Field.value fl))
  | .structPattern fields labelPattern constraint _ =>
      match fuel with
      | 0 => false
      | f + 1 => fields.any (fun fl => refsSelfEmbeddedLabel f (depth + 1) selfIndex labels (Field.value fl))
          || refsSelfEmbeddedLabel f (depth + 1) selfIndex labels labelPattern
          || refsSelfEmbeddedLabel f (depth + 1) selfIndex labels constraint
  | .structPatterns fields patterns _ =>
      match fuel with
      | 0 => false
      | f + 1 => fields.any (fun fl => refsSelfEmbeddedLabel f (depth + 1) selfIndex labels (Field.value fl))
          || patterns.any (fun p =>
              refsSelfEmbeddedLabel f (depth + 1) selfIndex labels p.fst
                || refsSelfEmbeddedLabel f (depth + 1) selfIndex labels p.snd)
  | _ => false

/-- Does any clause source/guard or the body reference `Self.<embedded>` (see
    `refsSelfEmbeddedLabel`), threading frame depth through the clause chain exactly as
    `resolveClausesWithFuel` does: each `forIn` source is scanned at the current `depth` and pushes
    one frame for subsequent clauses and the body; a `guard` condition scans at `depth` and pushes
    none. So a body read at `depth + #forClauses` is detected, not missed. -/
def refsSelfEmbeddedLabelClauses
    (fuel : Nat) (depth selfIndex : Nat) (labels : List String)
    (clauses : List (Clause Value)) (body : Value) : Bool :=
  descendClauses (· || ·)
    (fun d source => refsSelfEmbeddedLabel fuel d selfIndex labels source)
    (fun d cond => refsSelfEmbeddedLabel fuel d selfIndex labels cond)
    (fun d => refsSelfEmbeddedLabel fuel d selfIndex labels body)
    depth clauses
end

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

mutual
/-- The set of `Self.<label>` reads in `value` whose `Self` is the alias at `selfIndex` `depth`
    frame-pushers deep — the label-collecting twin of `refsSelfEmbeddedLabel` (same structural
    descent, same depth discipline). Used to compute which static fields the Pass-2 re-eval must
    touch: a field reads `Self.<L>` (this set) and depends on `L`'s value, which the Pass-2 frame
    change alters iff `L` is an embedded label or itself transitively depends on one. -/
def selfReferencedLabels (fuel : Nat) (depth selfIndex : Nat) : Value -> List String
  | .selector (.refId id) label =>
      if id.depth == depth && id.index == selfIndex then [label] else []
  | .selector base _ =>
      match fuel with | 0 => [] | f + 1 => selfReferencedLabels f depth selfIndex base
  | .index base key =>
      match fuel with
      | 0 => []
      | f + 1 => selfReferencedLabels f depth selfIndex base ++ selfReferencedLabels f depth selfIndex key
  | .unary _ v =>
      match fuel with | 0 => [] | f + 1 => selfReferencedLabels f depth selfIndex v
  | .binary _ l r =>
      match fuel with
      | 0 => []
      | f + 1 => selfReferencedLabels f depth selfIndex l ++ selfReferencedLabels f depth selfIndex r
  | .conj cs =>
      match fuel with | 0 => [] | f + 1 => cs.flatMap (selfReferencedLabels f depth selfIndex)
  | .disj alts =>
      match fuel with | 0 => [] | f + 1 => alts.flatMap (fun a => selfReferencedLabels f depth selfIndex a.snd)
  | .interpolation parts =>
      match fuel with | 0 => [] | f + 1 => parts.flatMap (selfReferencedLabels f depth selfIndex)
  | .struct fields _ =>
      match fuel with | 0 => [] | f + 1 => fields.flatMap (fun fl => selfReferencedLabels f (depth + 1) selfIndex (Field.value fl))
  | .structTail fields tail =>
      match fuel with
      | 0 => []
      | f + 1 => fields.flatMap (fun fl => selfReferencedLabels f (depth + 1) selfIndex (Field.value fl))
          ++ selfReferencedLabels f (depth + 1) selfIndex tail
  | .structComp fields cs _ _ =>
      match fuel with
      | 0 => []
      | f + 1 => fields.flatMap (fun fl => selfReferencedLabels f (depth + 1) selfIndex (Field.value fl))
          ++ cs.flatMap (selfReferencedLabels f (depth + 1) selfIndex)
  | .list items =>
      match fuel with | 0 => [] | f + 1 => items.flatMap (selfReferencedLabels f depth selfIndex)
  | .listTail items tail =>
      match fuel with
      | 0 => []
      | f + 1 => items.flatMap (selfReferencedLabels f depth selfIndex) ++ selfReferencedLabels f depth selfIndex tail
  | .comprehension clauses body =>
      match fuel with
      | 0 => []
      | f + 1 => selfReferencedLabelsClauses f depth selfIndex clauses body
  | .listComprehension clauses body =>
      match fuel with
      | 0 => []
      | f + 1 => selfReferencedLabelsClauses f depth selfIndex clauses body
  | .dynamicField l _ v =>
      match fuel with
      | 0 => []
      | f + 1 => selfReferencedLabels f depth selfIndex l ++ selfReferencedLabels f depth selfIndex v
  | .builtinCall _ args =>
      match fuel with | 0 => [] | f + 1 => args.flatMap (selfReferencedLabels f depth selfIndex)
  | .embeddedList items tail decls =>
      match fuel with
      | 0 => []
      | f + 1 => items.flatMap (selfReferencedLabels f depth selfIndex)
          ++ (match tail with | some t => selfReferencedLabels f depth selfIndex t | none => [])
          ++ decls.flatMap (fun fl => selfReferencedLabels f (depth + 1) selfIndex (Field.value fl))
  | .structPattern fields labelPattern constraint _ =>
      match fuel with
      | 0 => []
      | f + 1 => fields.flatMap (fun fl => selfReferencedLabels f (depth + 1) selfIndex (Field.value fl))
          ++ selfReferencedLabels f (depth + 1) selfIndex labelPattern
          ++ selfReferencedLabels f (depth + 1) selfIndex constraint
  | .structPatterns fields patterns _ =>
      match fuel with
      | 0 => []
      | f + 1 => fields.flatMap (fun fl => selfReferencedLabels f (depth + 1) selfIndex (Field.value fl))
          ++ patterns.flatMap (fun p =>
              selfReferencedLabels f (depth + 1) selfIndex p.fst
                ++ selfReferencedLabels f (depth + 1) selfIndex p.snd)
  | _ => []

/-- Collect `Self.<label>` reads across a comprehension's clause chain and body, threading the
    frame depth the same way `resolveClausesWithFuel` does: each `forIn` source is read at the
    current `depth`, then the loop frame is pushed (`depth + 1`) for subsequent clauses and the
    body; `guard` conditions read at the current `depth` and push no frame. A `Self.<L>` inside a
    `for` body thus sits at `depth + #forClauses` and is correctly collected — flat recursion would
    compare it against `depth`, miss it, and leave the field out of Pass-2 (reusing a stale value). -/
def selfReferencedLabelsClauses
    (fuel : Nat) (depth selfIndex : Nat)
    (clauses : List (Clause Value)) (body : Value) : List String :=
  descendClauses (· ++ ·)
    (fun d source => selfReferencedLabels fuel d selfIndex source)
    (fun d cond => selfReferencedLabels fuel d selfIndex cond)
    (fun d => selfReferencedLabels fuel d selfIndex body)
    depth clauses
end

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

def applyEvaluatedStructPattern
    (fields : List Field)
    (labelPattern constraint : Value)
    (open_ : Bool) : Value :=
  meet (.structPattern [] labelPattern constraint open_) (.struct fields true)

def applyEvaluatedStructPatterns
    (fields : List Field)
    (patterns : List (Value × Value))
    (open_ : Bool) : Value :=
  meet (.structPatterns [] patterns open_) (.struct fields true)

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

/-- Canonicalize a syntactic field list by collapsing duplicate-label slots into a single
    first-occurrence slot whose body is the unevaluated `.conj` of the conjuncts, so the
    frame the evaluator indexes is deduplicated. `mergeFieldListWith` folds
    merge-into-existing-else-append, which preserves first-occurrence order and shifts no
    earlier index — `b`'s `refId ⟨0,0⟩` still lands on slot 0, now carrying the merged body.
    Field class is combined via `mergeFieldClass` (same logic as `mergeEvaluatedFields`); a
    class mismatch keeps the slots separate, matching merge semantics. Total: foldl over a
    finite list. -/
def canonicalizeFields (fields : List Field) : List Field :=
  (mergeFieldListWith joinUnevaluated fields).getD fields

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
        if id.depth == frameDepth then
          match (nthField id.index oldLabels).map Field.label with
          | some label =>
              match lookupLabelIndex label mergedMap with
              | some mergedIndex => .refId ⟨id.depth, mergedIndex⟩
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
    | fuel + 1, .struct fields open_ =>
        .struct (remapConjFields fuel (frameDepth + 1) oldLabels mergedMap fields) open_
    | fuel + 1, .structTail fields tail =>
        .structTail
          (remapConjFields fuel (frameDepth + 1) oldLabels mergedMap fields)
          (remapConjRefs fuel (frameDepth + 1) oldLabels mergedMap tail)
    | fuel + 1, .structPattern fields labelPattern constraint open_ =>
        .structPattern
          (remapConjFields fuel (frameDepth + 1) oldLabels mergedMap fields)
          (remapConjRefs fuel (frameDepth + 1) oldLabels mergedMap labelPattern)
          (remapConjRefs fuel (frameDepth + 1) oldLabels mergedMap constraint)
          open_
    | fuel + 1, .structPatterns fields patterns open_ =>
        .structPatterns
          (remapConjFields fuel (frameDepth + 1) oldLabels mergedMap fields)
          (remapConjPatterns fuel (frameDepth + 1) oldLabels mergedMap patterns)
          open_
    | fuel + 1, .list items =>
        .list (remapConjValues fuel frameDepth oldLabels mergedMap items)
    | fuel + 1, .listTail items tail =>
        .listTail
          (remapConjValues fuel frameDepth oldLabels mergedMap items)
          (remapConjRefs fuel frameDepth oldLabels mergedMap tail)
    | fuel + 1, .interpolation parts =>
        .interpolation (remapConjValues fuel frameDepth oldLabels mergedMap parts)
    | fuel + 1, .structComp fields comprehensions open_ hasTail =>
        .structComp
          (remapConjFields fuel (frameDepth + 1) oldLabels mergedMap fields)
          (remapConjValues fuel (frameDepth + 1) oldLabels mergedMap comprehensions)
          open_ hasTail
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
        ⟨Field.label field, Field.fieldClass field,
          remapConjRefs fuel frameDepth oldLabels mergedMap (Field.value field)⟩
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
  termination_by clauses => (fuel, 1, clauses.length)
end

/-- Rebase every field in a conjunct against the merged frame layout (see `remapConjRefs`).
    `frameDepth` starts at 0: the conjunct's own fields sit directly in the merged frame. -/
def rebaseConjunctFields (oldFields : List Field) (mergedMap : List (String × Nat)) : List Field :=
  remapConjFields remapFuel 0 oldFields mergedMap oldFields

/-- Merge a conjunct's declarations into the accumulated frame (deferred `.conj` on label
    collisions), preserving first-occurrence order. Mirrors `canonicalizeFields`'s combiner
    so the merged frame matches what duplicate-label canonicalization would produce. -/
def mergeConjFields (accumulated : List Field) (fields : List Field) : List Field :=
  fields.foldl
    (fun current field =>
      match mergeFieldIntoWith joinUnevaluated current field with
      | some merged => merged
      | none => current ++ [field])
    accumulated

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

def normalizeEvaluatedDisj (alternatives : List (Mark × Value)) : Value :=
  if allRegularAlternatives alternatives then
    joinValues (alternatives.map Prod.snd)
  else
    .disj alternatives

def selectEvaluatedField (base : Value) (label : String) : Value :=
  match base with
  | .struct fields _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .structTail fields _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .structPattern fields _ _ _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .structPatterns fields _ _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .embeddedList _ _ decls =>
      match findEvalField label decls with
      | some field => Field.value field
      | none => .selector base label
  | .disj alternatives =>
      -- Selecting INTO a disjunction collapses it to its default arm first, then selects
      -- the field from that arm — CUE's default rule (`d.a` where `d: *{a:1} | {a:2}` is
      -- `1`). A unique marked default (or a lone regular alternative) resolves; otherwise
      -- `none` leaves the disjunction unresolved and selection stays deferred, so manifest
      -- reports the ambiguity rather than a spurious `bottom`.
      match resolveDisjDefault? alternatives with
      | some (.struct fields _) =>
          match findEvalField label fields with
          | some field => Field.value field
          | none => .selector base label
      | some (.structTail fields _) =>
          match findEvalField label fields with
          | some field => Field.value field
          | none => .selector base label
      | some (.structPattern fields _ _ _) =>
          match findEvalField label fields with
          | some field => Field.value field
          | none => .selector base label
      | some (.structPatterns fields _ _) =>
          match findEvalField label fields with
          | some field => Field.value field
          | none => .selector base label
      | some (.embeddedList _ _ decls) =>
          match findEvalField label decls with
          | some field => Field.value field
          | none => .selector base label
      | _ => .selector base label
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | _ => .bottom

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
  | _ => .index base key

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
  | _ => .index base key

def selectEvaluatedFieldIndex (base key : Value) (fields : List Field) : Value :=
  match key with
  | .prim (.string label) =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .index base key
  | .prim _ => .bottom
  | _ => .index base key

def selectEvaluatedIndex (base key : Value) : Value :=
  match base with
  | .struct fields _ => selectEvaluatedFieldIndex base key fields
  | .structTail fields _ => selectEvaluatedFieldIndex base key fields
  | .structPattern fields _ _ _ => selectEvaluatedFieldIndex base key fields
  | .structPatterns fields _ _ => selectEvaluatedFieldIndex base key fields
  | .list items => selectEvaluatedListIndex base key items
  | .listTail items _ => selectEvaluatedListTailIndex base key items
  | .embeddedList items none _ => selectEvaluatedListIndex base key items
  | .embeddedList items (some _) _ => selectEvaluatedListTailIndex base key items
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | _ => .bottom

def evalAdd (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left + right))
  | .prim (.string left), .prim (.string right) => .prim (.string (left ++ right))
  | .prim (.bytes left), .prim (.bytes right) => .prim (.bytes (left ++ right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalBinary? addDecimalValues left right with
      | some value => .prim value
      | none => .bottom
  | _, _ => .binary .add left right

def evalSub (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left - right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalBinary? subDecimalValues left right with
      | some value => .prim value
      | none => .bottom
  | _, _ => .binary .sub left right

def evalMul (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left * right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalMultiply? left right with
      | some value => .prim value
      | none => .bottom
  | _, _ => .binary .mul left right

def evalDiv (left right : Value) : Value :=
  match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalDivide? left right with
      | .ok text => .prim (.float text)
      | .divByZero => .bottomWith [.divisionByZero]
      | .nonNumeric => .bottom
  | _, _ => .binary .div left right

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
  | .struct _ _ => .defined
  | .structTail _ _ => .defined
  | .list _ => .defined
  | .listTail _ _ => .defined
  | .embeddedList _ _ _ => .defined
  | .structComp _ _ _ _ => .defined
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
  | .boundConstraint _ _ _ => .incomplete
  | .conj _ => .incomplete
  | .builtinCall _ _ => .incomplete
  | .unary _ _ => .incomplete
  | .binary _ _ _ => .incomplete
  | .ref _ => .incomplete
  | .refId _ => .incomplete
  | .thisStruct => .incomplete
  | .selector _ _ => .incomplete
  | .index _ _ => .incomplete
  | .structPattern _ _ _ _ => .incomplete
  | .structPatterns _ _ _ => .incomplete
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

def evalEq (left right : Value) : Value :=
  match left, right with
  | .prim left, .prim right =>
      match evalDecimalCompare? decimalEqValues left right with
      | some value => .prim (.bool value)
      | none => .prim (.bool (left == right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | _, _ => .binary .eq left right

def evalNe (left right : Value) : Value :=
  match evalEq left right with
  | .prim (.bool value) => .prim (.bool (!value))
  | .binary .eq left right => .binary .ne left right
  | value => value

def charsLt : List Char -> List Char -> Bool
  | [], [] => false
  | [], _ :: _ => true
  | _ :: _, [] => false
  | left :: leftRest, right :: rightRest =>
      if left.toNat == right.toNat then
        charsLt leftRest rightRest
      else
        left.toNat < right.toNat

def stringsLt (left right : String) : Bool :=
  charsLt left.toList right.toList

def evalPrimitiveOrdering
    (decimalOp : DecimalValue -> DecimalValue -> Bool)
    (stringOp : String -> String -> Bool)
    (op : BinaryOp)
    (left right : Value) : Value :=
  match left, right with
  | .prim left, .prim right =>
      match evalDecimalCompare? decimalOp left right with
      | some value => .prim (.bool value)
      | none =>
          match left, right with
          | .string left, .string right => .prim (.bool (stringOp left right))
          | _, _ => .bottom
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | _, _ => .binary op left right

def evalRegexMatch (left right : Value) : Value :=
  match left, right with
  | .prim (.string value), .prim (.string pattern) => .prim (.bool (stringRegexMatches pattern value))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary .regexMatch left right

def evalRegexNotMatch (left right : Value) : Value :=
  match evalRegexMatch left right with
  | .prim (.bool value) => .prim (.bool (!value))
  | .binary .regexMatch left right => .binary .regexNotMatch left right
  | value => value

def evalIntKeywordBinary
    (op : BinaryOp)
    (intEval : Value -> Value -> Value)
    (left right : Value) : Value :=
  match intEval left right with
  | .builtinCall _ _ => .binary op left right
  | value => value

def evalBoolBinary (op : BinaryOp) (boolOp : Bool -> Bool -> Bool) (left right : Value) : Value :=
  match left, right with
  | .prim (.bool left), .prim (.bool right) => .prim (.bool (boolOp left right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary op left right

def evalBoolNot (value : Value) : Value :=
  match value with
  | .prim (.bool value) => .prim (.bool (!value))
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | .prim _ => .bottom
  | _ => .unary .boolNot value

def negateFloatText (value : String) : String :=
  match value.toList with
  | '-' :: rest => String.ofList rest
  | _ => "-" ++ value

def evalNumPos (value : Value) : Value :=
  match value with
  | .prim (.int value) => .prim (.int value)
  | .prim (.float value) => .prim (.float value)
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | .prim _ => .bottom
  | _ => .unary .numPos value

def evalNumNeg (value : Value) : Value :=
  match value with
  | .prim (.int value) => .prim (.int (-value))
  | .prim (.float value) => .prim (.float (negateFloatText value))
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | .prim _ => .bottom
  | _ => .unary .numNeg value

def evalUnary (op : UnaryOp) (value : Value) : Value :=
  match op with
  | .boolNot => evalBoolNot value
  | .numPos => evalNumPos value
  | .numNeg => evalNumNeg value

def evalBinary (op : BinaryOp) (left right : Value) : Value :=
  match op with
  | .add => evalAdd left right
  | .sub => evalSub left right
  | .mul => evalMul left right
  | .div => evalDiv left right
  | .intDiv => evalIntKeywordBinary .intDiv divValue left right
  | .intMod => evalIntKeywordBinary .intMod modValue left right
  | .intQuo => evalIntKeywordBinary .intQuo quoValue left right
  | .intRem => evalIntKeywordBinary .intRem remValue left right
  | .eq => evalEq left right
  | .ne => evalNe left right
  | .lt => evalPrimitiveOrdering decimalLtValues stringsLt .lt left right
  | .le =>
      evalPrimitiveOrdering
        (fun left right => decimalEqValues left right || decimalLtValues left right)
        (fun left right => !stringsLt right left)
        .le
        left
        right
  | .gt => evalPrimitiveOrdering (fun left right => decimalLtValues right left) (fun left right => stringsLt right left) .gt left right
  | .ge =>
      evalPrimitiveOrdering
        (fun left right => decimalEqValues left right || decimalLtValues right left)
        (fun left right => !stringsLt left right)
        .ge
        left
        right
  | .regexMatch => evalRegexMatch left right
  | .regexNotMatch => evalRegexNotMatch left right
  | .boolAnd => evalBoolBinary .boolAnd (fun left right => left && right) left right
  | .boolOr => evalBoolBinary .boolOr (fun left right => left || right) left right

/-- Resolve a disjunction operand to the concrete value an arithmetic / comparison /
    unary op demands. CUE forces such operands to a *single* default (or lone live regular)
    BEFORE applying the scalar op — it does NOT distribute the op across the disjunction
    (`(int | *1) + 1 → 2`, not `int+1 | *2`). A disjunction that does not resolve (multiple
    distinct defaults, or multiple live regulars) is left untouched, so `evalBinary`/
    `evalUnary` returns a stuck node (`(1|2)+10 → (1 | 2) + 10`) — CUE's "unresolved
    disjunction" form, which manifest reports as incomplete. -/
def resolveOperand (value : Value) : Value :=
  match value with
  | .disj alternatives => (resolveDisjDefault? alternatives).getD value
  | value => value

/-- Apply a unary op, resolving a disjunction operand to its default first. -/
def distributeUnary (op : UnaryOp) (value : Value) : Value :=
  evalUnary op (resolveOperand value)

/-- Apply a binary op, resolving each disjunction operand to its default first. No
    cross-product: CUE arithmetic/comparison forces each operand concrete independently. -/
def distributeBinary (op : BinaryOp) (left right : Value) : Value :=
  evalBinary op (resolveOperand left) (resolveOperand right)

/--
The synthetic env frame a `for` iteration introduces. Mirrors `clauseLoopFrame`
in `Resolve`: keyed iterations bind the key at index 0 and the value at index 1,
unkeyed iterations bind the value at index 0. The bound values are already
evaluated, so referencing them re-evaluates a concrete value.
-/
def loopFrame (key : Option String) (keyValue : Value) (value : String) (element : Value) : List Field :=
  match key with
  | some key => [⟨key, .regular, keyValue⟩, ⟨value, .regular, element⟩]
  | none => [⟨value, .regular, element⟩]

/--
CUE renders interpolation holes by their natural string form: a string contributes its
raw content, numbers and booleans and null their literal spelling. Non-string-coercible
primitives (bytes) and non-primitive holes have no interpolation rendering.
-/
def interpolationText? : Value -> Option String
  | .prim (.string value) => some value
  | .prim (.int value) => some (toString value)
  | .prim (.float value) => some value
  | .prim (.bool true) => some "true"
  | .prim (.bool false) => some "false"
  | .prim .null => some "null"
  | _ => none

def interpolatePartsText? : List Value -> Option String
  | [] => some ""
  | part :: parts =>
      match interpolationText? part, interpolatePartsText? parts with
      | some head, some rest => some (head ++ rest)
      | _, _ => none

def partIsBottom : Value -> Bool
  | .bottom => true
  | .bottomWith _ => true
  | _ => false

def evalInterpolation (parts : List Value) : Value :=
  if parts.any partIsBottom then
    .bottom
  else
    match interpolatePartsText? parts with
    | some text => .prim (.string text)
    | none => .interpolation parts

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

/-- The (key, value) iteration pairs a source produces, or `none` if it is not iterable. -/
def comprehensionPairs : Value -> Option (List (Value × Value))
  | .list items => some (listPairsFrom 0 items)
  | .listTail items _ => some (listPairsFrom 0 items)
  | .struct fields _ => some (structPairs fields)
  | .structTail fields _ => some (structPairs fields)
  | .structPattern fields _ _ _ => some (structPairs fields)
  | .structPatterns fields _ _ => some (structPairs fields)
  | _ => none

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
  | .boundConstraint _ _ _ => 7
  | .conj _ => 8
  | .builtinCall _ _ => 9
  | .unary _ _ => 10
  | .binary _ _ _ => 11
  | .ref _ => 12
  | .refId _ => 13
  | .thisStruct => 14
  | .selector _ _ => 15
  | .index _ _ => 16
  | .disj _ => 17
  | .struct _ _ => 18
  | .structTail _ _ => 19
  | .structPattern _ _ _ _ => 20
  | .structPatterns _ _ _ => 21
  | .list _ => 22
  | .listTail _ _ => 23
  | .comprehension _ _ => 24
  | .structComp _ _ _ _ => 25
  | .interpolation _ => 26
  | .dynamicField _ _ _ => 27
  | .embeddedList _ _ _ => 28
  | .closure _ _ => 29
  | .listComprehension _ _ => 30

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
    (mixHash (hash key.envIds.length) (valueTag key.value)))

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
    (mixHash (hash key.envIds.length) (valueTag key.value))

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

/-- Shallow hash for the canonical-frame table — same discipline as `EvalKey`'s hash: mix the
    parent id stack with the field count and each field's top value-tag, never traversing the
    field subtrees. `BEq` (derived, structural) runs only on a hash-bucket match, so a coarse
    hash costs collisions, never correctness. -/
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
  /-- Fuel-free cache for SATURATED results only (see `SatKey`). The soundness-critical second
      store: a hit serves a converged value for any remaining fuel, collapsing fuel
      multiplication. Insertion is gated to the `saturated` bracket arm. -/
  satCache : Std.HashMap SatKey Value := ∅
  evalCalls : Nat := 0
  cacheHits : Nat := 0
  /-- Monotonic count of fuel-truncation base cases consulted (`fuel = 0`; cycle `.top`; the
      fuel=0 arms of the comprehension/embedding-expansion helpers that else drop fields silently).
      Bracketed by `evalValueWithFuel`/`forceClosureWithConjunct` to classify each result's
      `Saturation`: a result is `saturated` iff this counter did not move across its core eval.
      A cached `truncated` hit re-bumps it so the bracketing parent stays honest. Load-bearing
      for the fuel-saturation cache — not transient instrumentation. -/
  truncCount : Nat := 0

abbrev EvalM := StateM EvalState

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
  | .struct fields open_ => some (fields, open_)
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
                match nthField id.index frame.snd with
                | some field => conjStructOperand? env fuel (Field.value field)
                | none => none
  | _ => none

/-- Merge a list of per-conjunct `(fields, open)` operands into the single merged-frame field
    list. The layout (`label → slot`) is fixed by first-occurrence across conjuncts; each
    conjunct's bodies are rebased onto that layout, then merged into deferred `.conj`s on label
    collisions, and closedness is folded outward. The pure core shared by `lazyConjMergedFields`
    (same-scope struct conjunction) and the closure-meet splice (`forceClosureWithConjunct`):
    one `pushFrame` + eval over the result lets a body referencing a sibling a later conjunct
    narrows see the narrowed slot. -/
def mergeConjOperands (operands : List (List Field × Bool)) : List Field × Bool :=
  let layoutFrame := operands.foldl (fun acc op => mergeConjFields acc op.fst) []
  let mergedMap := labelIndexMap layoutFrame
  let rebased := operands.map fun op => rebaseConjunctFields op.fst mergedMap
  let mergedFields := rebased.foldl mergeConjFields []
  let closed := applyConjClosedness operands mergedFields
  (closed, allClosednessOpen operands)

/-- Reduce a struct conjunction to its merged-frame fields + closedness, or `none` when any
    operand is not a plain same-scope struct (deferring to the eval-then-`meet` path). -/
def lazyConjMergedFields (env : Env) (constraints : List Value) :
    Option (List Field × Bool) := do
  let operands <- constraints.mapM (conjStructOperand? env evalFuel)
  pure (mergeConjOperands operands)

/-- Reopen an evaluated struct value (`open_ := true`) so it contributes its fields by `meet`
    WITHOUT imposing its own closedness on the host — an embedding UNIONS labels into the
    enclosing def's closed set rather than restricting it. Non-struct values pass through. -/
def openStructValue : Value -> Value
  | .struct fields _ => .struct fields true
  | other => other

/-- Collapse an EMBEDDED disjunction to its default arm before it merges into the host.
    An embedded default disjunction (`(*{a:1} | {a:2})`) contributes its DEFAULT arm's fields
    to the host struct — both for the merge (so a sibling `Self.a` sees `a`) and for the
    closedness union (so the host admits the embedded label). A non-default disjunction with
    no unique winner stays a `.disj` (CUE distributes the host across it; left untouched here).
    Non-disjunction values pass through. -/
def resolveEmbeddedDisjDefault : Value -> Value
  | .disj alternatives => (resolveDisjDefault? alternatives).getD (.disj alternatives)
  | other => other

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

/-- Apply the def's closedness over the embedding UNION to an already-meet-folded struct: the
    single definition of CUE's embedding-closedness rule (shared by the eager `.structComp` eval
    arm and the `.structComp` closure-force arm). The host was met OPEN against each (opened)
    embedding, so its closedness must be re-applied ONCE over `def static labels ∪ each
    embedding's evaluated labels` — an embedding widens the allowed set without imposing its own
    closedness, and pre-closing the static frame would wrongly reject the embed's own fields. -/
def closeEmbeddedOver (defFields embeddingFields : List Field) (defOpen : Bool) : Value -> Value
  | .struct fields _ => .struct (applyClosednessFrom (defFields ++ embeddingFields) defOpen fields) defOpen
  | other => other

/-- Extract an evaluated value's struct-conjunct operand `(fields, open)` for splicing into a
    forced closure body — `.struct`/`.structTail`/the pattern structs all carry an evaluated
    field list. Returns `none` for non-struct values (primitives, lists, …), which cannot be
    spliced and fall back to a plain `meet` against the forced body. -/
def evaluatedStructOperand? : Value -> Option (List Field × Bool)
  | .struct fields open_ => some (fields, open_)
  | .structTail fields _ => some (fields, false)
  | .structPattern fields _ _ open_ => some (fields, open_)
  | .structPatterns fields _ open_ => some (fields, open_)
  | _ => none

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

mutual
/-- Does `value` reference the def's OWN top frame from `depth` frame-pushers deep — a
    `refId ⟨depth, _⟩` reachable by descending `depth` struct/comprehension frames? Generalizes
    `hasDepth0Ref` (the `depth == 0` case) to the DEEP self-references real defs use: a hidden
    field read from a nested struct (`spec: acme: email: Self.#email`, where `#email` is a
    top-level def field referenced from 3 frames deep → `refId ⟨3, _⟩`). Descending a
    frame-pusher increments `depth`; a `refId ⟨d, _⟩` is a self-ref iff `d == depth` (it lands
    exactly on the def's frame). Refs to shallower (`d < depth`, an intervening struct's own
    sibling) or outer (`d > depth`, a cross-package/enclosing scope) frames are NOT def
    self-refs. Fuel-bounded for totality. -/
def hasSelfRefAtDepth (fuel : Nat) (depth : Nat) : Value -> Bool
  | .refId id => id.depth == depth
  | .conj constraints =>
      match fuel with
      | 0 => false
      | fuel + 1 => constraints.any (hasSelfRefAtDepth fuel depth)
  | .builtinCall _ args =>
      match fuel with
      | 0 => false
      | fuel + 1 => args.any (hasSelfRefAtDepth fuel depth)
  | .unary _ value =>
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepth fuel depth value
  | .binary _ left right =>
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepth fuel depth left || hasSelfRefAtDepth fuel depth right
  | .selector base _ =>
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepth fuel depth base
  | .index base key =>
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepth fuel depth base || hasSelfRefAtDepth fuel depth key
  | .disj alternatives =>
      match fuel with
      | 0 => false
      | fuel + 1 => alternatives.any (fun alt => hasSelfRefAtDepth fuel depth alt.snd)
  | .list items =>
      match fuel with
      | 0 => false
      | fuel + 1 => items.any (hasSelfRefAtDepth fuel depth)
  | .listTail items tail =>
      match fuel with
      | 0 => false
      | fuel + 1 =>
          items.any (hasSelfRefAtDepth fuel depth) || hasSelfRefAtDepth fuel depth tail
  | .interpolation parts =>
      match fuel with
      | 0 => false
      | fuel + 1 => parts.any (hasSelfRefAtDepth fuel depth)
  | .struct fields _ =>
      match fuel with
      | 0 => false
      | fuel + 1 => fields.any (fun f => hasSelfRefAtDepth fuel (depth + 1) (Field.value f))
  | .structTail fields tail =>
      match fuel with
      | 0 => false
      | fuel + 1 =>
          fields.any (fun f => hasSelfRefAtDepth fuel (depth + 1) (Field.value f))
            || hasSelfRefAtDepth fuel (depth + 1) tail
  | .structComp fields comprehensions _ _ =>
      match fuel with
      | 0 => false
      | fuel + 1 =>
          fields.any (fun f => hasSelfRefAtDepth fuel (depth + 1) (Field.value f))
            || comprehensions.any (hasSelfRefAtDepth fuel (depth + 1))
  | .structPattern fields labelPattern constraint _ =>
      match fuel with
      | 0 => false
      | fuel + 1 =>
          fields.any (fun f => hasSelfRefAtDepth fuel (depth + 1) (Field.value f))
            || hasSelfRefAtDepth fuel (depth + 1) labelPattern
            || hasSelfRefAtDepth fuel (depth + 1) constraint
  | .structPatterns fields patterns _ =>
      match fuel with
      | 0 => false
      | fuel + 1 =>
          fields.any (fun f => hasSelfRefAtDepth fuel (depth + 1) (Field.value f))
            || patterns.any (fun p =>
                 hasSelfRefAtDepth fuel (depth + 1) p.fst
                   || hasSelfRefAtDepth fuel (depth + 1) p.snd)
  | .comprehension clauses body =>
      -- Clause sources/guards resolve in the comprehension's enclosing frame; the body resolves
      -- `#forClauses` frames deeper (`for` pushes one, `guard` none). `hasSelfRefAtDepthClauses`
      -- threads the depth exactly as `resolveClausesWithFuel` does: a too-shallow body scan would
      -- compare a deep `Self.<own-field>` read (resolved at `depth + #for`) against `depth`, MISS
      -- it, and skip the deferral the use-site narrowing needs — a stale-value miss (A5-followup).
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepthClauses fuel depth clauses body
  | .listComprehension clauses body =>
      -- List-context comprehension (`out: [for x in xs {v: Self.#t}]`): same clause/body scoping
      -- as `.comprehension`. The body read of `Self.#t` lands `#forClauses` frames deeper, so it
      -- must be scanned there, not at `depth`.
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepthClauses fuel depth clauses body
  | .dynamicField _ _ value =>
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepth fuel (depth + 1) value
  | _ => false

/-- Does any clause source/guard or the body reference the def's OWN frame at `depth` (see
    `hasSelfRefAtDepth`), threading frame depth through the clause chain exactly as
    `resolveClausesWithFuel` does: each `forIn` source is scanned at the current `depth` and pushes
    one frame for subsequent clauses and the body; a `guard` condition scans at `depth` and pushes
    none. So a body self-ref at `depth + #forClauses` is detected, not missed. -/
def hasSelfRefAtDepthClauses
    (fuel : Nat) (depth : Nat) (clauses : List (Clause Value)) (body : Value) : Bool :=
  descendClauses (· || ·)
    (fun d source => hasSelfRefAtDepth fuel d source)
    (fun d cond => hasSelfRefAtDepth fuel d cond)
    (fun d => hasSelfRefAtDepth fuel d body)
    depth clauses
end

/-- Does this unevaluated definition body reference one of its OWN top-level fields — directly
    (`out: #name`) OR from a nested position (`spec: acme: email: Self.#email`, the real-app
    shape)? Scans each top-level field's body for a self-ref landing on the def frame, descending
    nested frames via `hasSelfRefAtDepth` (depth 0 = the def's own frame). This is the exact set
    that collapses under the eager import-selector path: the use-site narrows a top-level hidden
    field, but an eager eval resolves the (possibly deep) reference to it BEFORE the narrowing. -/
def defBodyHasSiblingSelfRef : Value -> Bool
  | .struct fields _ => fields.any (fun f => hasSelfRefAtDepth evalFuel 0 (Field.value f))
  | .structTail fields tail =>
      fields.any (fun f => hasSelfRefAtDepth evalFuel 0 (Field.value f))
        || hasSelfRefAtDepth evalFuel 0 tail
  | .structComp fields comprehensions _ _ =>
      fields.any (fun f => hasSelfRefAtDepth evalFuel 0 (Field.value f))
        || comprehensions.any (hasSelfRefAtDepth evalFuel 0)
  | _ => false

/-- Resolve an embedding expression (`.refId` to a sibling/outer def, or a `pkg.#Def` selector
    into a package binding) to the UNEVALUATED def body it names, looked up in `env`. Returns the
    body struct/structComp/structTail or `none` for anything that is not a direct def reference.
    Used to decide whether an embedding's OWN body needs deferral — the host must defer too so the
    use-site narrowing reaches the embed before it collapses. -/
def resolveEmbedDefBody? (env : Env) : Value -> Option Value
  | .refId id =>
      match env.drop id.depth with
      | [] => none
      | frame :: _ =>
          match nthField id.index frame.snd with
          | some f => some (Field.value f)
          | none => none
  | .selector (.refId id) label =>
      match env.drop id.depth with
      | [] => none
      | frame :: _ =>
          match nthField id.index frame.snd with
          | some baseField =>
              match Field.value baseField with
              | .struct pkgFields _ =>
                  match findEvalField label pkgFields with
                  | some defField => some (Field.value defField)
                  | none => none
              | _ => none
          | none => none
  -- An embedded DEFAULT DISJUNCTION (`(*_#A|_#B)`) contributes its default arm to the host
  -- (argocd `#OpaqueSecret`). Resolve through to the default arm's def body, so `bodyNeedsDefer`
  -- recurses into it — the host must defer if the default arm's sibling self-ref/comprehension
  -- depends on a use-site-narrowed field. One level: the default arm is a single `.refId`.
  | .disj alternatives =>
      match resolveDisjDefault? alternatives with
      | some (.refId id) =>
          match env.drop id.depth with
          | [] => none
          | frame :: _ =>
              match nthField id.index frame.snd with
              | some f => some (Field.value f)
              | none => none
      | _ => none
  | _ => none

/-- Does a body need deferral to a `.closure` — either a DIRECT sibling self-ref/guard
    (`defBodyHasSiblingSelfRef`), OR an EMBEDDING whose own referenced def needs deferral? The
    second clause is the embed-chain case (`Outer: {#Inner}` where `#Inner` has a guard whose
    output depends on a use-site-narrowed field): the embed is NOT a self-ref of `Outer`, so the
    direct check misses it, yet `Outer` must defer so the narrowing reaches `#Inner` before its
    guard is evaluated. Fuel-bounded; recurses through embeddings (each resolved against `env`). -/
def bodyNeedsDefer (env : Env) (fuel : Nat) (body : Value) : Bool :=
  defBodyHasSiblingSelfRef body ||
    match fuel, body with
    | nextFuel + 1, .structComp _ comprehensions _ _ =>
        (comprehensions.filter isEmbeddingValue).any fun embed =>
          match resolveEmbedDefBody? env embed with
          | some embedBody => bodyNeedsDefer env nextFuel embedBody
          | none => false
    | _, _ => false
  termination_by fuel

/-- Follow a def body that is itself an alias/import-selector indirection to the terminal
    struct-like body it ultimately names, paired with the package frame that body's refs
    resolve against. `frameEnv` is the env in which `body`'s refs resolve, with `body`'s own
    enclosing package frame at depth 0; `capturedFrame` is the field list of that enclosing
    frame (what the caller must `pushFrame` to force the returned body).

    The headline shape (`#A: parts.#M`, then `defs.#A & {…}`): `#A`'s body is the selector
    `parts.#M`, not a struct — so the direct producers (`importDefClosureBody?`/`refDefClosureBody?`)
    see no struct body and take the eager path, resolving `parts.#M` in the `defs` frame BEFORE
    the use-site narrows. Following the indirection here discovers the real `#M` body AND the
    `parts` package frame it captures, so the caller defers to a `.closure` over the RIGHT frame
    and the use-site conjunct splices at force time exactly as a direct `defs.#M & {…}` does.

    Two indirection arms, both fuel-bounded against cyclic alias chains (`#A: #A`):
    - `.selector (.refId baseId) label`: resolve `baseId` in `frameEnv` to a package `.struct`,
      find `label`, and recurse with that package's fields as the new captured frame.
    - `.refId id`: resolve `id` in `frameEnv` to a sibling/outer def and recurse (two-level
      `#B: #A`, `#A: parts.#M`), keeping the captured frame at the resolved binding's scope.

    Returns `(capturedFrame, terminalBody)` when the terminal is struct-like AND needs deferral
    (`bodyNeedsDefer`); `none` for a non-indirection body (left to the direct producers), a
    terminal that does not defer, or fuel exhaustion. The terminal is NOT re-normalized here —
    the callers normalize a definition body once they own it. -/
def followAliasDefBody? (fuel : Nat) (frameEnv : Env) (capturedFrame : List Field) :
    Value -> Option (List Field × Value)
  | .selector (.refId baseId) label =>
      match fuel with
      | 0 => none
      | fuel + 1 =>
          match frameEnv.drop baseId.depth with
          | [] => none
          | baseFrame :: _ =>
              match nthField baseId.index baseFrame.snd with
              | none => none
              | some baseField =>
                  match Field.value baseField with
                  | .struct pkgFields _ =>
                      match findEvalField label pkgFields with
                      | some defField =>
                          -- The found def lives in `pkgFields`; its body's refs resolve with
                          -- `pkgFields` at depth 0 over the package binding's outer scope.
                          let nextEnv : Env := (0, pkgFields) :: frameEnv.drop (baseId.depth + 1)
                          followAliasDefBody? fuel nextEnv pkgFields (Field.value defField)
                      | none => none
                  | _ => none
  | .refId id =>
      match fuel with
      | 0 => none
      | fuel + 1 =>
          match frameEnv.drop id.depth with
          | [] => none
          | frame :: outer =>
              match nthField id.index frame.snd with
              | none => none
              | some defField =>
                  -- The resolved def's body resolves with `frame` at depth 0 over `outer`.
                  followAliasDefBody? fuel (frame :: outer) frame.snd (Field.value defField)
  | body =>
      let isStructLike := match body with
        | .struct _ _ => true | .structTail _ _ => true | .structComp _ _ _ _ => true | _ => false
      let bodyEnv : Env := (0, []) :: (0, capturedFrame) :: frameEnv.drop 1
      if isStructLike && bodyNeedsDefer bodyEnv evalFuel body then
        some (capturedFrame, body)
      else
        none

/-- The producer gate for slice-3 closures. Given the selector `base.label` where `base` is
    the UNEVALUATED binding `id` resolves to in `env`, decide whether to defer instead of
    eagerly evaluating `base` and plucking `label`. Returns the def's UNEVALUATED body when
    ALL hold: (1) the binding is a `.struct` (an import/package or any struct base), (2) it
    has a field `label` that is a definition (`#`), (3) that def body has a sibling self-ref
    (`defBodyHasSiblingSelfRef`) — the only shape that collapses today, so deferring it
    regresses no currently-green fixture. `none` ⇒ take the existing eager path. The caller
    pairs the returned body with `pushFrame pkgFields env` as the captured env.

    The captured body is run through `normalizeDefinitionValueWithFuel` to close it as a
    definition body (`open_ := false`, recursively): an IMPORTED package's def bodies were not
    normalized at load time (`normalizeDefinitions` only normalizes the TOP value's own `#`
    fields, never the hidden import binding's), so without this a forced cross-package def
    would lose its closedness and wrongly admit use-site fields the def does not declare. -/
def importDefClosureBody? (env : Env) (id : BindingId) (label : String) :
    Option (List Field × Value) :=
  match env.drop id.depth with
  | [] => none
  | frame :: _ =>
      match nthField id.index frame.snd with
      | none => none
      | some baseField =>
          match Field.value baseField with
          | .struct pkgFields _ =>
              match findEvalField label pkgFields with
              | some defField =>
                  -- The def body's embeddings reference the package frame (`pkgFields`, pushed when
                  -- the body is forced) at depth-1, the body itself at depth-0. So resolve them
                  -- against a placeholder body-frame over the package frame over the binding scope.
                  let bodyEnv : Env := (0, []) :: (0, pkgFields) :: env.drop (id.depth + 1)
                  if defField.fieldClass.isDefinition
                      && bodyNeedsDefer bodyEnv evalFuel (Field.value defField) then
                    some (pkgFields,
                      normalizeDefinitionValueWithFuel normalizeFuel (Field.value defField))
                  else if defField.fieldClass.isDefinition then
                    -- The def body is NOT a directly-deferring struct — it may be an alias/import
                    -- selector (`#A: parts.#M`) that resolves THROUGH the package indirection to a
                    -- struct that does. Follow the chain to its terminal `(frame, body)` and defer
                    -- over THAT frame (the `parts` package, not `defs`), so the use-site splices
                    -- like a direct `parts.#M & {…}`. The body's refs resolve with `pkgFields` at
                    -- depth 0 over the binding's outer scope.
                    let frameEnv : Env := (0, pkgFields) :: env.drop (id.depth + 1)
                    match followAliasDefBody? evalFuel frameEnv pkgFields (Field.value defField) with
                    | some (capturedFrame, body) =>
                        some (capturedFrame, normalizeDefinitionValueWithFuel normalizeFuel body)
                    | none => none
                  else
                    none
              | none => none
          | _ => none

/-- Bare-reference companion to `importDefClosureBody?` (slice E). A same-file def referenced
    DIRECTLY (`#Outer`, a `.refId`, not a `base.label` selector) whose body has a sibling self-ref
    must defer to a `.closure`, so a use-site conjunction (`#Outer & {#oname: "o"}`, or an
    embedding `#Inner & {#name: …}`) splices the narrowing into the def frame BEFORE its self-ref
    (`oname: Self.#oname`) collapses. Two gaps `conjStructOperand?`'s lazy-merge leaves:

    1. A `.structComp` body (embed-bearing) — no `.structComp` arm in `conjStructOperand?` at ANY
       depth, so it always took the eager collapse.
    2. A `.struct`/`.structTail` body referenced from a NESTED frame (`id.depth > 0` — e.g. the
       inner def of an embed chain, one frame deeper than the embedding's host) —
       `conjStructOperand?` is depth-0-only (`id.depth != 0 ⇒ none`), so a nested self-ref def ref
       lost the lazy-merge and collapsed.

    A DEPTH-0 `.struct`/`.structTail` self-ref ref keeps the existing lazy-merge path (the common
    same-file `#M & {narrow}` case) — deferring it too would churn every currently-green fixture.
    A definition body is normalized (closed, recursively), mirroring the selector producer; a
    NON-definition `.structComp` body (regular field `M: {x:int, if x>0 {y:x}}`, site 2 of F2)
    defers too but is left UNCLOSED — its open closedness is preserved so the use-site `meet`
    admits siblings as CUE does. -/
def refDefClosureBody? (env : Env) (id : BindingId) : Option Value :=
  match env.drop id.depth with
  | [] => none
  | frame :: _ =>
      match nthField id.index frame.snd with
      | none => none
      | some defField =>
          let body := Field.value defField
          let isStructComp := match body with | .structComp _ _ _ _ => true | _ => false
          let isStructLike := match body with
            | .struct _ _ => true | .structTail _ _ => true | .structComp _ _ _ _ => true | _ => false
          let isDef := defField.fieldClass.isDefinition
          -- Fire on the lazy-merge gaps `conjStructOperand?` cannot reduce: an embed-/guard-bearing
          -- `.structComp` (any depth — definition OR regular field; the regular case is F2 site 2:
          -- a comprehension struct meet whose guard must fire AFTER the use-site narrowing), or a
          -- nested (`depth > 0`) self-ref `.struct`/`.structTail` definition. Depth-0 plain
          -- `.struct`/`.structTail` stays on the lazy-merge path.
          -- Embeddings inside `body` are written relative to `body`'s own (about-to-be-pushed)
          -- frame, so depth-0 is `body` itself and depth-1 reaches the binding's scope. Prepend a
          -- placeholder body-frame onto the binding's resolution env so `resolveEmbedDefBody?`
          -- resolves an embed's depth-1 ref to the right enclosing frame.
          let bodyEnv : Env := (0, []) :: env.drop id.depth
          if isStructLike && bodyNeedsDefer bodyEnv evalFuel body
              && (isStructComp || (isDef && id.depth > 0)) then
            if isDef then
              some (normalizeDefinitionValueWithFuel normalizeFuel body)
            else
              some body
          else
            none

/-- Produce the captured `.closure` for a conjunct that is a bare ref to a self-ref def the
    lazy-merge path cannot handle (`#Outer & {narrow}` or a nested embed `#Inner & {narrow}` —
    slice E). The `.conj` fold uses this to defer such an operand BEFORE eval so the multi-operand
    force-fold splices the use-site narrowing into the def frame (`oname: Self.#oname` /
    `iname: Self.#name` see the narrowed siblings). Mirrors the selector producer's role in the
    `.conj` path. `none` for any other operand (evaluated normally). -/
def conjDefClosure? (env : Env) : Value -> Option Value
  | .refId id =>
      match env.drop id.depth with
      | [] => none
      | frame :: outer =>
          match refDefClosureBody? env id with
          | some defBody => some (.closure (frame :: outer) defBody)
          | none => none
  | _ => none

/-- Same-file alias companion to `importSelectorDef?`. A def referenced DIRECTLY (`#B`, a
    `.refId`) whose body is an alias/import-selector indirection (`#B: #A` where `#A: parts.#M`,
    OR `#B: parts.#M` directly) resolves THROUGH the chain to a struct that needs deferral, but
    over a DIFFERENT captured frame than `#B`'s own scope — the terminal package frame. The
    direct `refDefClosureBody?`/`conjDefClosure?` capture `#B`'s scope, which is wrong here.
    Follows the chain and returns `(terminalFrame, terminalBody)` so the consumer `pushFrame`s
    the right frame. `none` for a non-alias body (left to `refDefClosureBody?`). Mirrors
    `importSelectorDef?`'s `(pkgFields, defBody)` shape so the `.conj` fold and the `.refId` arm
    consume it identically. -/
def refAliasDefClosure? (env : Env) (id : BindingId) : Option (List Field × Value) :=
  match env.drop id.depth with
  | [] => none
  | frame :: outer =>
      match nthField id.index frame.snd with
      | none => none
      | some defField =>
          if defField.fieldClass.isDefinition then
            -- The body's refs resolve with `frame` at depth 0 over `outer` (the binding's scope).
            match followAliasDefBody? evalFuel (frame :: outer) frame.snd (Field.value defField) with
            | some (capturedFrame, body) =>
                some (capturedFrame, normalizeDefinitionValueWithFuel normalizeFuel body)
            | none => none
          else
            none

/-- Is this conjunct a raw `pkg.#Def` import-selector whose body defers to a closure? The `.conj`
    fold uses this to keep the RAW selector unevaluated (so the producer arm's eventual standalone
    force does not collapse it) and instead build the closure in-monad via `pushFrame`. -/
def importSelectorDef? (env : Env) : Value -> Option (List Field × Value)
  | .selector (.refId id) label => importDefClosureBody? env id label
  | _ => none

/-- Conjunct-level alias producer: a bare ref (`#B`) whose body chains through an alias/import
    selector to a deferring struct. Mirrors `importSelectorDef?` for the `.refId` conjunct form,
    returning the terminal `(frame, body)` to `pushFrame`. `none` for non-ref conjuncts. -/
def refAliasSelectorDef? (env : Env) : Value -> Option (List Field × Value)
  | .refId id => refAliasDefClosure? env id
  | _ => none

/-- The UNEVALUATED disjunction arms of a conjunct that is (or refs) a disjunction whose
    default arm needs deferral — so the `.conj` fold can DISTRIBUTE the other (narrowing)
    conjuncts into each arm BEFORE the arms collapse (`(*_#A|_#B) & {narrow}` →
    `*(_#A & {narrow}) | (_#B & {narrow})`). Without distribution, the disjunction evaluates
    standalone, forcing its def arms with NO use-operands, so a default arm's sibling self-ref
    (`copy: #x`, the argocd `#OpaqueSecret` shape) collapses to its abstract value before the
    narrowing reaches it.

    Returns `none` UNLESS the disjunction has a deferral-needing arm (`bodyNeedsDefer` on the
    arm's resolved def body) — a plain scalar/struct disjunction (`*1 | 2`, `*{a:1} | {a:2}`)
    keeps the existing distribute-at-meet path (no regression, no over-defer). The arms are the
    RAW (unevaluated) values, resolving in the SAME frame as the disjunction ref itself (a
    `.disj`-bodied def's arm refs are depth-relative to the def's scope = the conjunct's scope). -/
def conjDisjArms? (env : Env) (fuel : Nat) : Value -> Option (List (Mark × Value))
  | .disj alternatives =>
      if alternatives.any (fun a => bodyNeedsDefer ((0, []) :: env) fuel a.snd
          || (match a.snd with
              | .refId id =>
                  match (env.drop id.depth) with
                  | [] => false
                  | frame :: _ =>
                      match nthField id.index frame.snd with
                      | some f => bodyNeedsDefer ((0, []) :: env.drop id.depth) fuel (Field.value f)
                      | none => false
              | _ => false)) then
        some alternatives
      else
        none
  | .refId id =>
      match fuel with
      | 0 => none
      | fuel + 1 =>
          match env.drop id.depth with
          | [] => none
          | frame :: _ =>
              match nthField id.index frame.snd with
              | some field => conjDisjArms? env fuel (Field.value field)
              | none => none
  | _ => none

/-- Split a conjunction's constraints into (a distributable disjunction's unevaluated arms,
    the remaining constraints) IF exactly the first distributable disjunction conjunct is found —
    a depth-0 (or literal) disjunction with a deferral-needing arm (`conjDisjArms?`). Returns
    `none` when no constraint distributes (the standard fold applies). The remaining constraints
    are meet into EACH arm by the caller. -/
def splitDisjConjunct (env : Env) :
    List Value -> Option (List (Mark × Value) × List Value)
  | [] => none
  | c :: rest =>
      let distributes :=
        (match c with | .disj _ => true | .refId id => id.depth == 0 | _ => false)
      match (if distributes then conjDisjArms? env evalFuel c else none) with
      | some arms => some (arms, rest)
      | none =>
          match splitDisjConjunct env rest with
          | some (arms, others) => some (arms, c :: others)
          | none => none

mutual
  def evalFieldRefsWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (field : Field) : EvalM Field := do
    let evaluated <- evalValueWithFuel fuel env visited (Field.value field)
    pure ⟨Field.label field, Field.fieldClass field, evaluated⟩
  termination_by (fuel, 2, 0)

  def evalFieldRefsListWithFuel
      (fuel : Nat)
      (env : Env)
      (indexed : List (Nat × Field)) : EvalM (List Field) := do
    match indexed with
    | [] => pure []
    | (index, field) :: rest =>
        let evaluated <- evalFieldRefsWithFuel fuel env [index] field
        let restEvaluated <- evalFieldRefsListWithFuel fuel env rest
        pure (evaluated :: restEvaluated)
  termination_by (fuel, 3, indexed.length)

  def evalValuesWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat) : List Value -> EvalM (List Value)
    | [] => pure []
    | value :: rest => do
        let evaluated <- evalValueWithFuel fuel env visited value
        let restEvaluated <- evalValuesWithFuel fuel env visited rest
        pure (evaluated :: restEvaluated)
  termination_by values => (fuel, 3, values.length)

  /-- Evaluate a list's items, FLATTENING comprehension items. A plain item contributes one
      element; a `.listComprehension` contributes the zero-or-more elements its clause chain
      yields. Concatenation preserves source order, so plain elements and comprehensions
      interleave (`[1, for x in xs {x}, 2]`). -/
  def evalListItemsWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat) : List Value -> EvalM (List Value)
    | [] => pure []
    | .listComprehension clauses body :: rest => do
        let head <- expandListClausesWithFuel fuel env clauses body
        let restEvaluated <- evalListItemsWithFuel fuel env visited rest
        pure (head ++ restEvaluated)
    | value :: rest => do
        let evaluated <- evalValueWithFuel fuel env visited value
        let restEvaluated <- evalListItemsWithFuel fuel env visited rest
        pure (evaluated :: restEvaluated)
  termination_by values => (fuel, 3, values.length)

  /-- Cached entry into the evaluator, with fuel-saturation caching.

      Lookup order: (1) the fuel-FREE `satCache` — a SATURATED result is fuel-insensitive, so a
      hit serves it at ANY remaining fuel and bumps NOTHING (a saturated value never touched the
      truncation counter, so the bracketing parent stays saturated). (2) the fuel-keyed `cache` —
      a hit of a `truncated` entry re-bumps `truncCount` so the bracketing parent still sees the
      truncation (cache-hit honesty); a `saturated` entry bumps nothing.

      On a miss, BRACKET the monotonic `truncCount`: snapshot before/after the core eval; the
      result is `saturated` iff the counter did not move (no `fuel = 0` base and no cycle `.top`
      anywhere in the transitive subtree). Store `(value, sat)` in the fuel-keyed `cache`; if
      saturated, ALSO store in the fuel-free `satCache` — the SINGLE insertion site, gated to the
      `saturated` arm, so a truncated value can never enter the fuel-free cache. -/
  def evalValueWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (value : Value) : EvalM Value := do
    let satKey : SatKey := ⟨env.ids, visited, value⟩
    match (<- get).satCache.get? satKey with
    | some cached => do
        modify (fun state => { state with cacheHits := state.cacheHits + 1 })
        pure cached
    | none =>
      let key : EvalKey := ⟨fuel, env.ids, visited, value⟩
      match (<- get).cache.get? key with
      | some (cached, sat) => do
          let bump := if sat == .truncated then 1 else 0
          modify (fun state => { state with cacheHits := state.cacheHits + 1, truncCount := state.truncCount + bump })
          pure cached
      | none =>
          let before := (<- get).truncCount
          modify (fun state => { state with evalCalls := state.evalCalls + 1 })
          let result <- evalValueCoreWithFuel fuel env visited value
          let after := (<- get).truncCount
          let sat : Saturation := if after == before then .saturated else .truncated
          modify (fun state => { state with cache := state.cache.insert key (result, sat) })
          match sat with
          | .saturated =>
              modify (fun state => { state with satCache := state.satCache.insert satKey result })
          | .truncated => pure ()
          pure result
  termination_by (fuel, 1, 0)

  def evalValueCoreWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (value : Value) : EvalM Value := do
    match fuel, value with
    | 0, value => do
        modify (fun state => { state with truncCount := state.truncCount + 1 })
        pure value
    | _ + 1, .ref label =>
        pure (.bottomWith [.unresolvedReference label])
    | fuel + 1, .refId id =>
        match env.drop id.depth with
        | [] => pure (.bottomWith [.unresolvedBinding id])
        | frame :: outer =>
            match nthField id.index frame.snd with
            | none => pure (.bottomWith [.unresolvedBinding id])
            | some field =>
                -- Producer (slice E): a bare ref to a self-ref def the lazy-merge can't handle
                -- (embed-bearing `.structComp`, or a nested `.struct`/`.structTail`) FORCES the def
                -- body against its own captured scope — forced HERE with no use-operands (a bare
                -- ref has no use-site to splice). When the ref sits inside a use-site conjunction
                -- (`#Outer & {#oname: "o"}`, or a nested embed `#Inner & {#name: …}`), the `.conj`
                -- fold re-produces the closure from the raw constraint (`conjDefClosure?`) and
                -- force-splices the narrowing — so the standalone force here is only ever the
                -- terminal value. The captured env is `frame :: outer` (the binding's scope): the
                -- body's depth-0 refs land on `frame`, its cross-pkg refs walk `outer`.
                match refDefClosureBody? env id with
                | some defBody => forceClosureWithConjunct fuel (frame :: outer) defBody []
                | none =>
                  -- Alias/import-selector indirection (`#B: parts.#M` / `#B: #A`, `#A: parts.#M`):
                  -- the body is not a directly-deferring struct, but follows the chain to one. Force
                  -- standalone over the TERMINAL package frame (the use-site splice, if any, comes
                  -- via the `.conj` fold re-producing through `refAliasSelectorDef?`).
                  match refAliasDefClosure? env id with
                  | some (capturedFrame, defBody) => do
                      let capturedEnv <- pushFrame capturedFrame env
                      forceClosureWithConjunct fuel capturedEnv defBody []
                  | none =>
                    if id.depth == 0 then
                      if slotVisited id.index visited then do
                        modify (fun state => { state with truncCount := state.truncCount + 1 })
                        pure .top
                      else
                        evalValueWithFuel fuel env (id.index :: visited) (Field.value field)
                    else
                      evalValueWithFuel fuel (frame :: outer) [id.index] (Field.value field)
    | fuel + 1, .conj constraints => do
        -- DISJUNCTION DISTRIBUTION (argocd-secret-data sub-slice 2). A conjunct that is (or refs,
        -- at depth 0) a disjunction with a deferral-needing default arm must DISTRIBUTE the other
        -- conjuncts into each arm at the UNEVALUATED level — `(*_#A|_#B) & {narrow}` becomes
        -- `*(_#A & {narrow}) | (_#B & {narrow})` — so each arm-meet re-enters this fold and the
        -- post-ss1 def-deferral force-splices the narrowing BEFORE the arm's sibling self-ref
        -- (`copy: #x`, the `#OpaqueSecret` shape) collapses. The arm refs are depth-0-relative to
        -- the def's scope = THIS conj's `env`, so they thread in unchanged. A plain scalar/struct
        -- disjunction yields `none` from `conjDisjArms?` and keeps the existing distribute-at-meet
        -- path (no regression). Restricted to a depth-0 (or literal) disjunction conjunct so arm
        -- depths need no rebasing; a deeper disjunction ref falls through to the standard path.
        match splitDisjConjunct env constraints with
        | some (arms, others) =>
            let distributed <- arms.mapM fun arm => do
              let armValue <- evalValueWithFuel fuel env visited (.conj (arm.snd :: others))
              pure (arm.fst, armValue)
            pure (normalizeEvaluatedDisj distributed)
        | none => evalConjStandard fuel env visited constraints
    | fuel + 1, .builtinCall name args => do
        let evaluated <- evalValuesWithFuel fuel env visited args
        pure (evalBuiltinCall name evaluated)
    | fuel + 1, .unary op value => do
        let evaluated <- evalValueWithFuel fuel env visited value
        pure (distributeUnary op evaluated)
    | fuel + 1, .binary op (.bottom) right =>
        if isPresenceTestOp op then do
          let evaluated <- evalValueWithFuel fuel env visited right
          pure (evalPresenceTest (op == .eq) evaluated)
        else do
          let rightEvaluated <- evalValueWithFuel fuel env visited right
          pure (evalBinary op .bottom rightEvaluated)
    | fuel + 1, .binary op left (.bottom) =>
        if isPresenceTestOp op then do
          let evaluated <- evalValueWithFuel fuel env visited left
          pure (evalPresenceTest (op == .eq) evaluated)
        else do
          let leftEvaluated <- evalValueWithFuel fuel env visited left
          pure (evalBinary op leftEvaluated .bottom)
    | fuel + 1, .binary op left right => do
        let leftEvaluated <- evalValueWithFuel fuel env visited left
        let rightEvaluated <- evalValueWithFuel fuel env visited right
        pure (distributeBinary op leftEvaluated rightEvaluated)
    | fuel + 1, .selector (.refId id) label =>
        match thisStructFieldIndex? env id label with
        | some labelId => evalValueWithFuel fuel env visited (.refId labelId)
        | none =>
            -- Producer (slice 3): selecting an imported definition whose body has a sibling
            -- self-reference defers to a `.closure` instead of eagerly evaluating the base —
            -- which would collapse the self-ref against the def's own frame before a use-site
            -- `meet` (slice 4) narrows it. Gated on `defBodyHasSiblingSelfRef`, the only shape
            -- that collapses today, so every currently-green selection stays on the eager path.
            match importDefClosureBody? env id label with
            | some (pkgFields, defBody) => do
                -- Force the deferred def body STANDALONE (no use-operands) — the terminal value of
                -- a `pkg.#Def` selected OUTSIDE a conjunction (`out: attr.#Ports`, or an embed
                -- `{attr.#Ports}` with no narrowing). When `pkg.#Def` instead sits inside a `.conj`
                -- (`pkg.#Def & {narrow}`), that fold re-produces the closure from the RAW selector
                -- constraint (`importSelectorDef?`) and force-splices the narrowing, so this
                -- standalone force is only ever the terminal value. Mirrors the `.refId` arm.
                let capturedEnv <- pushFrame pkgFields env
                forceClosureWithConjunct fuel capturedEnv defBody []
            | none => do
                let base <- evalValueWithFuel fuel env visited (.refId id)
                pure (selectEvaluatedField base label)
    | fuel + 1, .selector base label => do
        let baseEvaluated <- evalValueWithFuel fuel env visited base
        pure (selectEvaluatedField baseEvaluated label)
    | fuel + 1, .index base key => do
        let baseEvaluated <- evalValueWithFuel fuel env visited base
        let keyEvaluated <- evalValueWithFuel fuel env visited key
        pure (selectEvaluatedIndex baseEvaluated keyEvaluated)
    | fuel + 1, .disj alternatives => do
        let evaluated <- alternatives.mapM fun alternative => do
          let evaluatedValue <- evalValueWithFuel fuel env visited alternative.snd
          pure (alternative.fst, evaluatedValue)
        pure (normalizeEvaluatedDisj evaluated)
    | fuel + 1, .struct nestedFields open_ => do
        let nestedFields := canonicalizeFields nestedFields
        let nested <- pushFrame nestedFields env
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields nestedFields)
        match mergeEvaluatedFields evaluatedFields with
        | some nestedFields => pure (.struct nestedFields open_)
        | none => pure .bottom
    | fuel + 1, .structTail nestedFields tail => do
        let nestedFields := canonicalizeFields nestedFields
        let nested <- pushFrame nestedFields env
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields nestedFields)
        match mergeEvaluatedFields evaluatedFields with
        | some nestedFields =>
            let evaluatedTail <- evalValueWithFuel fuel nested [] tail
            pure (.structTail nestedFields evaluatedTail)
        | none => pure .bottom
    | fuel + 1, .structPattern nestedFields labelPattern constraint open_ => do
        let nestedFields := canonicalizeFields nestedFields
        let nested <- pushFrame nestedFields env
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields nestedFields)
        match mergeEvaluatedFields evaluatedFields with
        | some nestedFields =>
            let evaluatedLabel <- evalValueWithFuel fuel nested [] labelPattern
            let evaluatedConstraint <- evalValueWithFuel fuel nested [] constraint
            pure (applyEvaluatedStructPattern nestedFields evaluatedLabel evaluatedConstraint open_)
        | none => pure .bottom
    | fuel + 1, .structPatterns nestedFields patterns open_ => do
        let nestedFields := canonicalizeFields nestedFields
        let nested <- pushFrame nestedFields env
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields nestedFields)
        match mergeEvaluatedFields evaluatedFields with
        | some nestedFields =>
            let evaluatedPatterns <- patterns.mapM fun pattern => do
              let evaluatedLabel <- evalValueWithFuel fuel nested [] pattern.fst
              let evaluatedConstraint <- evalValueWithFuel fuel nested [] pattern.snd
              pure (evaluatedLabel, evaluatedConstraint)
            pure (applyEvaluatedStructPatterns nestedFields evaluatedPatterns open_)
        | none => pure .bottom
    | fuel + 1, .list items => do
        let evaluated <- evalListItemsWithFuel fuel env visited items
        pure (.list evaluated)
    | fuel + 1, .listTail items tail => do
        let evaluatedItems <- evalListItemsWithFuel fuel env visited items
        let evaluatedTail <- evalValueWithFuel fuel env visited tail
        pure (.listTail evaluatedItems evaluatedTail)
    | fuel + 1, .comprehension clauses body => do
        let expanded <- expandClausesWithFuel fuel env clauses body
        match mergeEvaluatedFields expanded with
        | some fields => pure (.struct fields true)
        | none => pure .bottom
    | fuel + 1, .structComp fields comprehensions open_ _ => do
        let fields := canonicalizeFields fields
        let embeddings := comprehensions.filter isEmbeddingValue
        -- Pass 1: evaluate the static fields and comprehensions against the static-only frame,
        -- then the embedding-contributed fields. A static field referencing `Self.<label>` where
        -- `<label>` is supplied by an EMBEDDING (`type: Self.#type` with `#type` from an embedded
        -- `(*_#Opaque | …)`) cannot resolve here — the frame holds only static labels.
        let nested <- pushFrame fields env
        let staticFields <- evalFieldRefsListWithFuel fuel nested (indexedFields fields)
        let expanded <- expandComprehensionsWithFuel fuel nested comprehensions
        match mergeEvaluatedFields (staticFields ++ expanded) with
        | none => pure .bottom
        | some merged =>
            let embeddingFields <- evalEmbeddingFieldsWithFuel fuel nested merged embeddings
            -- Pass 2 (only when embeddings exist AND they contribute a label no static field
            -- declares): re-push a frame augmented with the embedded labels and re-evaluate the
            -- static fields, so a `Self.<embedded-label>` selection resolves against the embedded
            -- value. Gated tightly — no embeddings, or embeddings adding only already-static
            -- labels, keeps the single-pass path byte-identical. The augment carries the embedded
            -- fields as ALREADY-EVALUATED resolved values (so re-evaluation is idempotent on them).
            let newEmbeddedFields := embeddingFields.filter fun ef =>
              (findEvalField (Field.label ef) fields).isNone
            let reEvalIndices := embeddedSelfPassFieldIndices fields (newEmbeddedFields.map Field.label)
            let staticFields <-
              if reEvalIndices.isEmpty then
                pure staticFields
              else do
                -- Pass 2 (audit PART B selective re-eval): re-evaluate ONLY the static fields that
                -- depend (directly or transitively via a sibling `Self.<L>` read) on an embedded
                -- label, against a frame augmented with the embedded labels — so a
                -- `Self.<embedded-label>` selection resolves. Every other field reuses its Pass-1
                -- value (`reEvalIndices` excludes it precisely because its value cannot change under
                -- the Pass-2 frame): byte-identical, AND its eval is SKIPPED (we only feed the
                -- selected `(index, field)` entries to `evalFieldRefsListWithFuel`, preserving each
                -- field's slot index so refs still resolve against the full augmented frame). The
                -- augment carries embeds as ALREADY-EVALUATED resolved values.
                let augmented := canonicalizeFields (fields ++ newEmbeddedFields)
                let nested2 <- pushFrame augmented env
                let selected := (indexedFields fields).filter (fun (i, _) => reEvalIndices.contains i)
                let reEvaluated <- evalFieldRefsListWithFuel fuel nested2 selected
                -- Splice each re-evaluated value back at its original index; reuse the Pass-1 value
                -- for every unselected slot.
                let bySlot := (selected.map Prod.fst).zip reEvaluated
                pure ((staticFields.zipIdx).map fun (p1, i) =>
                  match bySlot.find? (fun (j, _) => j == i) with
                  | some (_, v) => v
                  | none => p1)
            match mergeEvaluatedFields (staticFields ++ expanded) with
            | none => pure .bottom
            | some merged =>
                -- Meet the embeddings OPEN (each opened by `meetEmbeddingsWithFuel`) against an OPEN
                -- host, then re-close ONCE over `def ∪ embed` labels — an embedding widens the host's
                -- allowed set without imposing its own closedness (CUE rule). Closing the host
                -- BEFORE the meet would let a closed embed/host reject the other's regular fields.
                let met <- meetEmbeddingsWithFuel fuel nested (.struct merged true) embeddings
                pure (closeEmbeddedOver merged embeddingFields open_ met)
    | fuel + 1, .interpolation parts => do
        let evaluated <- evalValuesWithFuel fuel env visited parts
        pure (evalInterpolation evaluated)
    | fuel + 1, .dynamicField label _ value => do
        let evaluatedLabel <- evalValueWithFuel fuel env visited label
        match evaluatedLabel with
        | .prim (.string name) => do
            let evaluatedValue <- evalValueWithFuel fuel env visited value
            pure (.struct [⟨name, .regular, evaluatedValue⟩] true)
        | _ => pure .bottom
    -- closure: force the deferred body against the lexical scope it captured. The
    -- call-site `env`/`visited` are discarded — a closure resolves against its definition
    -- site, not its use site (lexical, not dynamic, scope). `capturedEnv` is defeq to `Env`
    -- and carries the full id-stack, so it threads in with no coercion; `visited` resets to
    -- `[]` because the call-site slot markers index call-site frames, not captured ones.
    -- No producer yet (slice 3) ⇒ dead code, but this is the semantic anchor slices 3-4 hit.
    | fuel + 1, .closure capturedEnv body =>
        evalValueWithFuel fuel capturedEnv [] body
    | _, value => pure value
  termination_by (fuel, 0, 0)

  /-- The standard `.conj` fold (extracted so the `.conj` arm can first try disjunction
      distribution and fall through here). Either the lazy same-scope struct merge
      (`lazyConjMergedFields`), or the deferral fold: a bare self-ref def / import-selector
      conjunct defers to its `.closure`, then every closure is force-spliced with the SHARED
      use-operand set so deferred defs' siblings narrow against the use-site at once. `fuel` is
      the predecessor of the `.conj` arm's `fuel + 1`, so calls to `evalValueWithFuel fuel`
      `(fuel,1,0)` and `forceClosureWithConjunct fuel` `(fuel,5,0)` decrease from `(fuel,6,0)`. -/
  def evalConjStandard
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (constraints : List Value) : EvalM Value := do
    match lazyConjMergedFields env constraints with
    | some (mergedFields, open_) =>
        let canonical := canonicalizeFields mergedFields
        let nested <- pushFrame canonical env
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields canonical)
        match mergeEvaluatedFields evaluatedFields with
        | some fields => pure (.struct fields open_)
        | none => pure .bottom
    | none => do
        -- A bare ref to an embed-bearing self-ref def (`#Outer`, a `.structComp`) is DEFERRED
        -- to its `.closure` here (`conjDefClosure?`) rather than evaluated — the `.refId` arm
        -- would otherwise force it STANDALONE (no use-operands), collapsing its self-ref before
        -- this fold can splice the narrowing. A `pkg.#Def` import-selector conjunct is likewise
        -- deferred from the RAW constraint (`importSelectorDef?` + in-monad `pushFrame`), so the
        -- selector arm's standalone force (which fires when `pkg.#Def` is selected OUTSIDE a
        -- conjunction) does not collapse it here before the fold splices the use-site.
        let evaluated <- constraints.mapM fun constraint => do
          match conjDefClosure? env constraint with
          | some closure => pure closure
          | none =>
              -- `importSelectorDef?`: a `pkg.#Def` selector conjunct (incl. one aliased to
              -- another selector via the alias-follow inside `importDefClosureBody?`).
              -- `refAliasSelectorDef?`: a bare ref conjunct (`#B`) whose body chains through
              -- an alias to a deferring struct — captured over the TERMINAL package frame.
              match importSelectorDef? env constraint with
              | some (pkgFields, defBody) => do
                  let capturedEnv <- pushFrame pkgFields env
                  pure (.closure capturedEnv defBody)
              | none =>
                match refAliasSelectorDef? env constraint with
                | some (capturedFrame, defBody) => do
                    let capturedEnv <- pushFrame capturedFrame env
                    pure (.closure capturedEnv defBody)
                | none => evalValueWithFuel fuel env visited constraint
        -- A `.closure` among the evaluated operands is a deferred imported def (slices 3-4).
        -- Instead of the inert `meet` (→ `.bottom`), force EVERY closure with the SHARED
        -- use-operand set spliced into its body (slice A — multi-operand fold). The use-site
        -- struct conjuncts narrow all the deferred defs' siblings at once (`#M & #N &
        -- {narrow}`); non-struct non-closure operands `meet` against the folded result,
        -- preserving honesty (still `.bottom` on a genuine conflict).
        match allClosures evaluated with
        | [] => pure (evaluated.foldl (fun current constraint => meet current constraint) .top)
        | closures =>
            let useOperands := (evaluated.filterMap spliceNarrowingOperand?).map stripLetBindings
            let others := nonClosureNonStructOperands evaluated
            let foldClosure := fun (acc : EvalM Value) (cl : Env × Value) => do
              let current <- acc
              let forced <- forceClosureWithConjunct fuel cl.fst cl.snd useOperands
              pure (meet current forced)
            let forced <- closures.foldl foldClosure (pure .top)
            pure (others.foldl (fun current v => meet current v) forced)
  termination_by (fuel, 6, 0)

  /-- The fields each embedding contributes, for computing a closed embed-def's allowed-label
      union (slice A): embedding `#Base = {kind}` into a closed `#Def` widens the allowed set by
      `{kind}`. Evaluates each embedding (forcing a `.closure` embed against `narrowing` — the
      host's hidden/definition fields) and concatenates the struct fields it yields; non-struct
      embeddings contribute nothing.

      `narrowing` is load-bearing: a `.closure` embed whose body has a CONDITIONAL comprehension
      (`if #port > 0 { ports: … }`) introduces `ports` ONLY when the guard fires, which depends on
      the host's narrowed `#port`. Forcing the embed WITHOUT the narrowing (the old behavior)
      dropped the conditional label from the allowed set, so the host's closedness then rejected
      the field the actual embed-meet produced → spurious `bottom`. So force the embed-closure WITH
      the host's hidden fields spliced (the same `useOperands` the value-producing `meet` uses). -/
  def evalEmbeddingFieldsWithFuel
      (fuel : Nat)
      (env : Env)
      (narrowing : List Field) : List Value -> EvalM (List Field)
    | [] => pure []
    | embedding :: rest =>
        match fuel with
        | 0 => do
            modify (fun state => { state with truncCount := state.truncCount + 1 })
            pure []
        | nextFuel + 1 => do
            let evaluated <-
              match conjDefClosure? env embedding with
              | some closure => pure closure
              | none =>
                  match importSelectorDef? env embedding with
                  | some (pkgFields, defBody) => do
                      let capturedEnv <- pushFrame pkgFields env
                      pure (.closure capturedEnv defBody)
                  | none => evalValueWithFuel (nextFuel + 1) env [] embedding
            -- A `.closure` embed (self-ref imported def) is forced WITH the host's hidden narrowing
            -- so a conditional comprehension's labels surface (forcing drops a fuel tier — it sits
            -- above this measure); a non-closure embed already evaluated against the host frame,
            -- which carries the narrowing.
            let resolved <-
              match evaluated with
              | .closure capturedEnv body =>
                  forceClosureWithConjunct nextFuel capturedEnv (openStructValue body)
                    [hiddenFieldsOnly (narrowing, true)]
              | _ => pure evaluated
            let head :=
              match evaluatedStructOperand? (resolveEmbeddedDisjDefault resolved) with
              | some (fields, _) => fields
              | none => []
            let tail <- evalEmbeddingFieldsWithFuel (nextFuel + 1) env narrowing rest
            pure (head ++ tail)
  termination_by embeddings => (fuel, 3, embeddings.length)

  /-- Meet a struct against each embedding in turn, evaluating each in the nested frame. An
      embedding that evaluates to a `.closure` (a self-referential imported def embedded in a
      struct body, e.g. `parts.#Metadata`) is FORCED with the current struct's fields spliced in
      as the use-operand (slice A, facet c), so its self-references resolve against the
      surrounding narrowing instead of collapsing to a plain `meet → .bottom`. -/
  def meetEmbeddingsWithFuel
      (fuel : Nat)
      (env : Env)
      (current : Value) : List Value -> EvalM Value
    | [] => pure current
    | embedding :: rest =>
        match fuel with
        | 0 => do
            modify (fun state => { state with truncCount := state.truncCount + 1 })
            pure current
        | nextFuel + 1 => do
            -- An embedded DEFAULT DISJUNCTION whose arms need deferral (`(*_#A|_#B)` with `_#A`'s
            -- body referencing a sibling the host narrows — the argocd `#OpaqueSecret` shape) is
            -- DISTRIBUTED: the host's narrowing is folded into EVERY arm (each re-entering this
            -- fold so the post-ss1 def-deferral force-splices the narrowing before the arm's
            -- self-ref collapses), bottoms are PRUNED (`normalizeDisj` via `liveAlternatives`), and
            -- the survivor resolves. Committing to the default arm first (the old `resolveDisjDefault?`
            -- collapse) bottomed when the narrowing KILLED the default arm with no fall-through to a
            -- surviving arm (`#S & {v:"s"}` over `*_#A{v:int} | _#B{v:string}` → cue `{kind:"b",v:"s"}`,
            -- kue bottom). This mirrors the `.conj` fold's `splitDisjConjunct` arm-distribution.
            -- A plain scalar/struct disjunction yields `none` from `conjDisjArms?` and keeps the
            -- collapse-then-meet path below (no over-distribute). The per-arm fold drops a fuel tier
            -- (a single-embedding sub-fold of the host against the arm) to stay below this measure.
            match conjDisjArms? env evalFuel embedding with
            | some arms => do
                let distributed <- arms.mapM fun arm => do
                  let armResult <- meetEmbeddingsWithFuel nextFuel env current [arm.snd]
                  pure (arm.fst, armResult)
                meetEmbeddingsWithFuel (nextFuel + 1) env (normalizeDisj distributed) rest
            | none => do
              -- A bare ref to a self-ref def the lazy-merge can't handle is DEFERRED to its
              -- `.closure` here (not evaluated through `.refId`, which would force it STANDALONE with
              -- no use-operands), so the `.closure` branch below force-splices the HOST's current
              -- fields — the embedding analogue of the `.conj` fold's `conjDefClosure?`.
              let evaluated <-
                match conjDefClosure? env embedding with
                | some closure => pure closure
                | none =>
                    match importSelectorDef? env embedding with
                    | some (pkgFields, defBody) => do
                        let capturedEnv <- pushFrame pkgFields env
                        pure (.closure capturedEnv defBody)
                    | none => evalValueWithFuel (nextFuel + 1) env [] embedding
              match evaluated with
              | .closure capturedEnv body => do
                  -- An embedded self-referential imported def (`parts.#Metadata`) evaluates to a
                  -- `.closure`. A plain `meet` collapses it to `.bottom`; instead FORCE it with the
                  -- host's current fields spliced in as the use-operand, so the embed's self-refs
                  -- (`kind: #kind`) resolve against the host's use-site narrowing (slice A, facet c).
                  -- The embed's body is OPENED so the splice does not reject the host's sibling
                  -- fields (`#Def`'s `#x`/`spec` are not declared by `parts.#Metadata`); the embed's
                  -- labels fold into the union closedness the structComp arm applies afterwards.
                  -- Forcing is a deferred sub-evaluation, so it drops fuel (force sits at a higher
                  -- measure tier and must consume fuel to re-enter here).
                  -- Splice ONLY the host's hidden/definition fields (`#name`, …) into the embed:
                  -- those are the SHARED bindings the embed self-references (`pname: Self.#name`).
                  -- The host's regular output fields (`apiVersion`, `kind`) are NOT the embed's — they
                  -- unify at the outer `meet current forced`, not via the splice (splicing them makes
                  -- the embed re-evaluate and conflict on them). `hiddenFieldsOnly` also drops the
                  -- host's `Self=`/`let` aliases (the embed has its own).
                  let useOperands := (evaluatedStructOperand? current).toList.map hiddenFieldsOnly
                  let forced <-
                    forceClosureWithConjunct nextFuel capturedEnv (openStructValue body) useOperands
                  meetEmbeddingsWithFuel (nextFuel + 1) env (meet current (openStructValue forced)) rest
              | .disj alternatives =>
                  -- An embedded DEFAULT DISJUNCTION whose arms are already EVALUATED (no deferral
                  -- needed — `conjDisjArms?` returned `none`) must DISTRIBUTE the host's narrowing
                  -- into EVERY arm and PRUNE bottoms, not collapse to the default arm first. Picking
                  -- the default arm (the old `resolveEmbeddedDisjDefault`) bottomed when the narrowing
                  -- KILLED the default arm with no fall-through: `(*_#A{v:int} | _#B{v:string})` met
                  -- with `{v:"s"}` → cue `{kind:"b",v:"s"}`, kue bottom. Each arm meets the OPENED
                  -- host (an embedding widens, never imposes its own closedness); `normalizeDisj`
                  -- prunes the dead default (`liveAlternatives`) so the survivor wins. The plain
                  -- scalar/struct disjunctions that have a unique default surviving still resolve to
                  -- it (cue-exact). Closedness over the union is re-applied by the caller.
                  let distributed := alternatives.map fun alternative =>
                    (alternative.fst, meet current (openStructValue alternative.snd))
                  meetEmbeddingsWithFuel (nextFuel + 1) env (normalizeDisj distributed) rest
              | _ =>
                  -- Scalar-embedding collapse (`{5}`→`5`), done HERE where the host struct is KNOWN
                  -- to be EMBEDDING a scalar — not reconstructed at meet time, where an empty struct
                  -- `{}` is indistinguishable from `{5}`'s residual `.struct []` and would wrongly
                  -- absorb any scalar an empty/decl-free struct meets (`{} & 5` must be a conflict,
                  -- not `5`). Collapse only when LOSSLESS — the host has no output field and no
                  -- non-output decl to drop (`collapsesToScalarEmbed`) — and the embedding resolved
                  -- to a TERMINAL scalar. List comprehensions rely on this (`[{x} for…]`'s body is a
                  -- struct embedding a scalar that must collapse to the element). The fold continues
                  -- with the scalar as `current`, so a second equal embedding (`{5,5}`) unifies via
                  -- the plain `meet` below and a distinct one (`{5,6}`) conflicts.
                  match current with
                  | .struct fields _ =>
                      if collapsesToScalarEmbed fields evaluated then
                        meetEmbeddingsWithFuel (nextFuel + 1) env evaluated rest
                      else
                        -- A non-closure embedding (a plain struct, a same-package def ref) is OPENED
                        -- before the meet: an embedding UNIONS its labels into the host's allowed set
                        -- but never imposes its OWN closedness on the host (CUE rule, see
                        -- `openStructValue`). Without this, embedding a closed struct `{pval}` into a
                        -- host carrying `x` makes the closed embed reject `x` → `.bottom`. The host's
                        -- closedness over `def ∪ embed` labels is re-applied by the caller
                        -- (`meetEmbeddingsClosingOver`).
                        meetEmbeddingsWithFuel (nextFuel + 1) env
                          (meet current (openStructValue evaluated)) rest
                  | _ =>
                      meetEmbeddingsWithFuel (nextFuel + 1) env
                        (meet current (openStructValue evaluated)) rest
  termination_by embeddings => (fuel, 3, embeddings.length)

  /-- Force a closure (slice 4 — the closure-meet unlock) by splicing the use-site struct
      conjuncts INTO the deferred def body before evaluating, so a body field referencing a
      sibling the use-site narrows (`out: #name` with use-site `#name: "keel"`) sees the
      narrowed value instead of collapsing against the def's own `#name: string`.

      `capturedEnv` is the def's lexical scope (the package frame stack the producer captured);
      `body` is the def's UNEVALUATED struct; `useOperands` are the OTHER conjuncts' EVALUATED
      `(fields, open)` (struct-shaped). When `body` is a struct, def fields + use operands are
      merged into one frame via the same `mergeConjOperands` machinery same-package conjunction
      uses, pushed onto `capturedEnv`, and evaluated once — so the def's own depth>0 cross-pkg
      refs still resolve against `capturedEnv` while its depth-0 siblings see the spliced
      narrowing. Evaluated use operands carry no depth-0 frame refs (eval already resolved their
      siblings), so rebasing them is a no-op and the splice cannot leak use-site scope into the
      def frame. `visited := []` is sound: a forced closure is a fresh eval entry, so the
      ordinary `slotVisited` machinery on the pushed frame catches a self-referential captured
      binding and terminates (→ `.top`) rather than looping. A non-struct def body is forced
      under its scope, then `meet`-ed against the use structs (no frame to splice into). -/
  def forceClosureWithConjunct
      (fuel : Nat)
      (capturedEnv : Env)
      (body : Value)
      (useOperands : List (List Field × Bool)) : EvalM Value := do
    -- Force-memo: a `pkg.#Def` selected/referenced N times re-forces the same body N times
    -- (this path bypasses the `EvalKey` cache). Keyed on `(fuel, capturedEnv.ids, body,
    -- useOperands)` — the full pure-function input — the force runs once. Sound by the same
    -- proxy argument as `EvalKey` (see `ForceKey`); the id stack is canonical via frame sharing.
    let forceKey : ForceKey := ⟨fuel, capturedEnv.ids, body, useOperands⟩
    match (<- get).forceCache.get? forceKey with
    | some (cached, sat) => do
        -- Cache-hit honesty: a truncated force re-bumps `truncCount` so the bracketing
        -- `evalValueWithFuel` parent (this force is always reached from a core arm) still
        -- classifies itself truncated. A saturated force bumps nothing. Mirrors `cache`.
        let bump := if sat == .truncated then 1 else 0
        modify (fun state => { state with cacheHits := state.cacheHits + 1, truncCount := state.truncCount + bump })
        pure cached
    | none => do
      let before := (<- get).truncCount
      let result <- forceClosureWithConjunctCore fuel capturedEnv body useOperands
      let after := (<- get).truncCount
      let sat : Saturation := if after == before then .saturated else .truncated
      modify (fun state => { state with forceCache := state.forceCache.insert forceKey (result, sat) })
      pure result
  termination_by (fuel, 5, 0)

  def forceClosureWithConjunctCore
      (fuel : Nat)
      (capturedEnv : Env)
      (body : Value)
      (useOperands : List (List Field × Bool)) : EvalM Value := do
    match body with
    | .struct defFields defOpen =>
        let (mergedFields, open_) := mergeConjOperands ((defFields, defOpen) :: useOperands)
        let canonical := canonicalizeFields mergedFields
        let nested <- pushFrame canonical capturedEnv
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields canonical)
        match mergeEvaluatedFields evaluatedFields with
        | some fields => pure (.struct fields open_)
        | none => pure .bottom
    | .structTail defFields defTail =>
        -- Open def body (`...`): splice the use fields into the def's frame (as a struct
        -- conjunct), keep the open tail. The tail's own depth-0 sibling refs are rebased onto
        -- the merged layout — the same rebase the struct fields get — so it still resolves
        -- against the widened frame.
        let (mergedFields, _) := mergeConjOperands ((defFields, true) :: useOperands)
        let canonical := canonicalizeFields mergedFields
        let mergedMap := labelIndexMap canonical
        let rebasedTail := remapConjRefs remapFuel 0 defFields mergedMap defTail
        let nested <- pushFrame canonical capturedEnv
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields canonical)
        match mergeEvaluatedFields evaluatedFields with
        | some fields =>
            let evaluatedTail <- evalValueWithFuel fuel nested [] rebasedTail
            pure (.structTail fields evaluatedTail)
        | none => pure .bottom
    | .structComp defFields comprehensions defOpen _ =>
        -- Embed-bearing def body (`#Def: { parts.#Metadata; #x; spec: #x }` — slice A). Splice
        -- the use operands into the static fields (so `spec: #x` sees the narrowed `#x`), eval
        -- them under `capturedEnv`, then meet-fold the embeddings in the same nested frame —
        -- mirroring the `.structComp` eval arm. An embedding that resolves to a `.closure` (a
        -- self-ref cross-package embed) is force-spliced by `meetEmbeddingsWithFuel` against the
        -- partial struct, so it resolves under the surrounding narrowing rather than collapsing.
        --
        -- Closedness UNIONS embed labels with the def's own (CUE: embedding `#Base` widens the
        -- closed set by `#Base`'s labels). So merge/meet OPEN, then — if the def was closed —
        -- close ONCE over `def static labels ∪ each embedding's evaluated labels`. Pre-closing
        -- the static frame would wrongly reject both the embed's fields and the def's own.
        let (mergedFields, _) := mergeConjOperands ((defFields, true) :: useOperands)
        let canonical := canonicalizeFields mergedFields
        let embeddings := comprehensions.filter isEmbeddingValue
        let nested <- pushFrame canonical capturedEnv
        let staticFields <- evalFieldRefsListWithFuel fuel nested (indexedFields canonical)
        -- Expand the conditional/`for` comprehensions against the post-splice frame, so an
        -- `if #x > 0 { y: #x }` guard fires AFTER the use-site narrowing landed in `#x` —
        -- mirroring the eager `.structComp` arm (`staticFields ++ expanded`). Without this the
        -- force arm silently dropped every `if`/`for` member (the F2 cert-manager `attr.#Ports`
        -- collapse). Embeddings (`isEmbeddingValue`) expand to `[]` here and flow to the
        -- embed-meet below unchanged.
        let expanded <- expandComprehensionsWithFuel fuel nested comprehensions
        match mergeEvaluatedFields (staticFields ++ expanded) with
        | none => pure .bottom
        | some merged =>
            let embeddingFields <- evalEmbeddingFieldsWithFuel fuel nested merged embeddings
            -- Pass 2 (mirrors the eager `.structComp` arm): a static field referencing
            -- `Self.<label>` where `<label>` is supplied by an EMBEDDING (`type: Self.#type`,
            -- `#type` from an embedded `(*_#Opaque | …)`) cannot resolve against the static-only
            -- frame. Re-push a frame augmented with the embedded labels not already declared
            -- static, and re-evaluate the static fields so the selection resolves. Gated to fire
            -- only when an embedding adds a NEW label — byte-identical otherwise.
            let newEmbeddedFields := embeddingFields.filter fun ef =>
              (findEvalField (Field.label ef) canonical).isNone
            let reEvalIndices := embeddedSelfPassFieldIndices canonical (newEmbeddedFields.map Field.label)
            let staticFields <-
              if reEvalIndices.isEmpty then
                pure staticFields
              else do
                -- Pass 2 (audit PART B selective re-eval, mirrors the eager arm): re-evaluate ONLY
                -- the static fields that depend on an embedded label (feed just their `(index,
                -- field)` entries, so unselected fields are not recomputed); reuse Pass-1 values for
                -- the rest (byte-identical, no fresh-frame-id cache miss).
                let augmented := canonicalizeFields (canonical ++ newEmbeddedFields)
                let nested2 <- pushFrame augmented capturedEnv
                let selected := (indexedFields canonical).filter (fun (i, _) => reEvalIndices.contains i)
                let reEvaluated <- evalFieldRefsListWithFuel fuel nested2 selected
                let bySlot := (selected.map Prod.fst).zip reEvaluated
                pure ((staticFields.zipIdx).map fun (p1, i) =>
                  match bySlot.find? (fun (j, _) => j == i) with
                  | some (_, v) => v
                  | none => p1)
            match mergeEvaluatedFields (staticFields ++ expanded) with
            | none => pure .bottom
            | some merged =>
                -- A comprehension-introduced field (`y` from `if #x>0 {y:#x}`) is part of the def's
                -- own declared shape, so it must widen the closed allow-set alongside the static and
                -- embedding labels — otherwise re-closing rejects it as undeclared. `defFields` does
                -- NOT contain `y` (it lives only in the comprehension), so fold `expanded` in too.
                let met <- meetEmbeddingsWithFuel fuel nested (.struct merged true) embeddings
                pure (closeEmbeddedOver (defFields ++ expanded) embeddingFields defOpen met)
    | _ => do
        let forced <- evalValueWithFuel fuel capturedEnv [] body
        pure (useOperands.foldl (fun current op => meet current (.struct op.fst op.snd)) forced)
  termination_by (fuel, 4, 0)

  /-- Expand each embedded comprehension/dynamic field and concatenate the contributed fields. -/
  def expandComprehensionsWithFuel
      (fuel : Nat)
      (env : Env) : List Value -> EvalM (List Field)
    | [] => pure []
    | comprehension :: rest => do
        let head <- expandComprehensionWithFuel fuel env comprehension
        let tail <- expandComprehensionsWithFuel fuel env rest
        pure (head ++ tail)
  termination_by comprehensions => (fuel, 3, comprehensions.length)

  /-- Expand one embedded comprehension/dynamic field into the fields it contributes. -/
  def expandComprehensionWithFuel
      (fuel : Nat)
      (env : Env)
      (value : Value) : EvalM (List Field) := do
    match fuel, value with
    | 0, _ => do
        modify (fun state => { state with truncCount := state.truncCount + 1 })
        pure []
    | fuel + 1, .comprehension clauses body => expandClausesWithFuel fuel env clauses body
    | fuel + 1, .dynamicField label fieldClass value => do
        let evaluatedLabel <- evalValueWithFuel fuel env [] label
        match evaluatedLabel with
        | .prim (.string name) => do
            let evaluatedValue <- evalValueWithFuel fuel env [] value
            pure [⟨name, fieldClass, evaluatedValue⟩]
        | _ => pure []
    | _, _ => pure []
  termination_by (fuel, 0, 0)

  /--
  Walk a comprehension's clause chain, evaluating each clause's source/condition in
  the current env. Each `for` iteration pushes a fresh loop-variable frame; each `if`
  guard either admits or drops its remaining expansion. With no clauses left, the body
  struct is evaluated and its fields are emitted for merging.
  -/
  def expandClausesWithFuel
      (fuel : Nat)
      (env : Env)
      (clauses : List (Clause Value))
      (body : Value) : EvalM (List Field) := do
    match fuel with
    | 0 => do
        modify (fun state => { state with truncCount := state.truncCount + 1 })
        pure []
    | fuel + 1 =>
        match clauses with
        | [] => do
            let evaluatedBody <- evalValueWithFuel fuel env [] body
            match evaluatedBody with
            | .struct fields _ => pure fields
            | _ => pure []
        | .guard condition :: rest => do
            let evaluatedCondition <- evalValueWithFuel fuel env [] condition
            -- A guard condition is a concrete-context use: a marked-default disjunction
            -- (`bool | *false`) collapses to its default before the boolean test, matching
            -- manifestation. A non-default disjunction does not collapse and the guard
            -- stays unsatisfied. `resolveDisjDefault?` leaves non-`.disj` values untouched.
            let testCondition :=
              match evaluatedCondition with
              | .disj alternatives => (resolveDisjDefault? alternatives).getD evaluatedCondition
              | _ => evaluatedCondition
            match testCondition with
            | .prim (.bool true) => expandClausesWithFuel fuel env rest body
            | _ => pure []
        | .forIn key value source :: rest => do
            let evaluatedSource <- evalValueWithFuel fuel env [] source
            match comprehensionPairs evaluatedSource with
            | none => pure []
            | some pairs => expandForPairsWithFuel fuel env key value rest body pairs
  termination_by (fuel, 0, 0)

  /-- Expand the remaining clause chain once per iteration pair, concatenating results. -/
  def expandForPairsWithFuel
      (fuel : Nat)
      (env : Env)
      (key : Option String)
      (value : String)
      (rest : List (Clause Value))
      (body : Value) : List (Value × Value) -> EvalM (List Field)
    | [] => pure []
    | pair :: pairs => do
        let nested <- pushFrame (loopFrame key pair.fst value pair.snd) env
        let head <- expandClausesWithFuel fuel nested rest body
        let tail <- expandForPairsWithFuel fuel env key value rest body pairs
        pure (head ++ tail)
  termination_by pairs => (fuel, 3, pairs.length)

  /-- Walk a LIST comprehension's clause chain. Mirrors `expandClausesWithFuel`, but with the
      clauses exhausted it evaluates the brace-block `body` to a single ELEMENT (`[evaluated]`)
      rather than emitting the body struct's fields. Guards drop their remaining expansion to
      `[]` (zero elements); `for` iterates. The `fuel=0` base BUMPS `truncCount` so a
      fuel-exhausted truncation is COUNTED (audit #6 saturation invariant — an uncounted
      truncation source corrupts results via the fuel-saturation cache). -/
  def expandListClausesWithFuel
      (fuel : Nat)
      (env : Env)
      (clauses : List (Clause Value))
      (body : Value) : EvalM (List Value) := do
    match fuel with
    | 0 => do
        modify (fun state => { state with truncCount := state.truncCount + 1 })
        pure []
    | fuel + 1 =>
        match clauses with
        | [] => do
            let evaluatedBody <- evalValueWithFuel fuel env [] body
            pure [evaluatedBody]
        | .guard condition :: rest => do
            let evaluatedCondition <- evalValueWithFuel fuel env [] condition
            -- Match `expandClausesWithFuel`: a marked-default disjunction collapses to its
            -- default before the boolean test; a non-default disjunction stays unsatisfied.
            let testCondition :=
              match evaluatedCondition with
              | .disj alternatives => (resolveDisjDefault? alternatives).getD evaluatedCondition
              | _ => evaluatedCondition
            match testCondition with
            | .prim (.bool true) => expandListClausesWithFuel fuel env rest body
            | _ => pure []
        | .forIn key value source :: rest => do
            let evaluatedSource <- evalValueWithFuel fuel env [] source
            match comprehensionPairs evaluatedSource with
            | none => pure []
            | some pairs => expandListForPairsWithFuel fuel env key value rest body pairs
  termination_by (fuel, 0, 0)

  /-- Per-iteration expansion for a list comprehension `for` clause; concatenates the elements
      each iteration's remaining chain yields, preserving iteration order. -/
  def expandListForPairsWithFuel
      (fuel : Nat)
      (env : Env)
      (key : Option String)
      (value : String)
      (rest : List (Clause Value))
      (body : Value) : List (Value × Value) -> EvalM (List Value)
    | [] => pure []
    | pair :: pairs => do
        let nested <- pushFrame (loopFrame key pair.fst value pair.snd) env
        let head <- expandListClausesWithFuel fuel nested rest body
        let tail <- expandListForPairsWithFuel fuel env key value rest body pairs
        pure (head ++ tail)
  termination_by pairs => (fuel, 3, pairs.length)
end

/-- Run an evaluation action with a fresh cache, discarding the cache. The cache shares
    computed-once results within one top-level evaluation; it never escapes. -/
def runEval (action : EvalM α) : α :=
  (action.run { cache := ∅, nextFrameId := 0 }).fst

/-- Run an evaluation action and return `(result, evalCalls, cacheHits)`. The counts are a
    deterministic, build-checkable proxy for evaluation work: `evalCalls` is the number of
    core (cache-miss) evaluations, `cacheHits` the number of memo hits. On the synthetic
    `{a: prev, b: prev}` deep-sharing shape this witnesses exponential→linear without relying
    on wall-clock — used by the perf pins, not by any production path. -/
def runEvalStats (action : EvalM α) : α × Nat × Nat :=
  let (result, state) := action.run { cache := ∅, nextFrameId := 0 }
  (result, state.evalCalls, state.cacheHits)

def evalTopFieldsM (fields : List Field) : EvalM (Option (List Field)) := do
  let top <- pushFrame fields []
  let evaluated <- evalFieldRefsListWithFuel evalFuel top (indexedFields fields)
  pure (mergeEvaluatedFields evaluated)

def evalStructRefsM (value : Value) : EvalM Value := do
  match normalizeDefinitions value with
  | .struct fields open_ =>
      let fields := canonicalizeFields fields
      match (<- evalTopFieldsM fields) with
      | some fields => pure (.struct fields open_)
      | none => pure .bottom
  | .structTail fields tail =>
      let fields := canonicalizeFields fields
      match (<- evalTopFieldsM fields) with
      | some merged =>
          let top <- pushFrame fields []
          let evaluatedTail <- evalValueWithFuel evalFuel top [] tail
          pure (.structTail merged evaluatedTail)
      | none => pure .bottom
  | .structPattern fields labelPattern constraint open_ =>
      let fields := canonicalizeFields fields
      match (<- evalTopFieldsM fields) with
      | some merged =>
          let top <- pushFrame fields []
          let evaluatedLabel <- evalValueWithFuel evalFuel top [] labelPattern
          let evaluatedConstraint <- evalValueWithFuel evalFuel top [] constraint
          pure (applyEvaluatedStructPattern merged evaluatedLabel evaluatedConstraint open_)
      | none => pure .bottom
  | .structPatterns fields patterns open_ =>
      let fields := canonicalizeFields fields
      match (<- evalTopFieldsM fields) with
      | some merged =>
          let top <- pushFrame fields []
          let evaluatedPatterns <- patterns.mapM fun pattern => do
            let evaluatedLabel <- evalValueWithFuel evalFuel top [] pattern.fst
            let evaluatedConstraint <- evalValueWithFuel evalFuel top [] pattern.snd
            pure (evaluatedLabel, evaluatedConstraint)
          pure (applyEvaluatedStructPatterns merged evaluatedPatterns open_)
      | none => pure .bottom
  | normalized@(.structComp _ _ _ _) => evalValueWithFuel evalFuel [] [] normalized
  | value => pure value

def evalStructRefs (value : Value) : Value :=
  runEval (evalStructRefsM value)

/-- `evalCalls` for `evalStructRefs value` — the core-eval count for the perf pins. A
    deterministic proxy for evaluation work that witnesses exponential→linear on the
    deep-sharing shape without wall-clock. -/
def evalStructRefsCalls (value : Value) : Nat :=
  (runEvalStats (evalStructRefsM value)).snd.fst

end Kue
