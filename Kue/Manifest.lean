import Kue.Format
import Kue.Lattice

namespace Kue

inductive ManifestValue where
  | prim (value : Prim)
  | struct (fields : List (String × ManifestValue))
  | list (items : List ManifestValue)
deriving Repr, BEq

inductive ManifestError where
  | contradiction
  | incomplete (value : Value)
  | ambiguous (alternatives : List (Mark × Value))
  /-- A whole-file build failure: one or more imports declared but never referenced. Carries the
      offending imports as `(path, optional alias)` pairs so the CLI renders cue's per-import
      `imported and not used: "<path>"` message instead of the generic contradiction. -/
  | importedNotUsed (imports : List (String × Option String))
  /-- A concrete call to a builtin kue recognizes but has not yet implemented
      (`strconv.Quote`, `strconv.FormatFloat`, …), deferred to `.bottomWith [.unsupportedBuiltin …]`.
      Carries the qualified function name so the CLI names the unimplemented function instead of the
      generic contradiction. -/
  | unsupportedBuiltinFunction (name : String)
deriving Repr, BEq

/-- `Except` carries no stdlib `BEq`, so `manifest`/`formatManifestField` results cannot be
    compared with `==` for `native_decide` pins. This total structural instance closes that
    gap (both component types derive `BEq`). -/
instance [BEq ε] [BEq α] : BEq (Except ε α) where
  beq
    | .ok a, .ok b => a == b
    | .error a, .error b => a == b
    | _, _ => false

def manifestFuel : Nat :=
  100

/-- Collect the `imported and not used` reasons out of a bottom's reason list. A non-empty result
    marks a top-level import-gate bottom (`resolveImports` produces these standalone), routing the
    manifest error to the cue-shaped per-import message rather than the generic contradiction. -/
def unusedImportReasons (reasons : List BottomReason) : List (String × Option String) :=
  reasons.filterMap fun
    | .importedNotUsed path alias => some (path, alias)
    | _ => none

/-- The first `unsupportedBuiltin` name in a bottom's reason list, if any. A concrete call to a
    deferred-but-recognized builtin (`strconv.Quote`) tags its bottom this way; surfacing the name
    lets the manifest error name the unimplemented function rather than collapse to a generic
    contradiction. -/
def unsupportedBuiltinName? (reasons : List BottomReason) : Option String :=
  reasons.findSome? fun
    | .unsupportedBuiltin name => some name
    | _ => none

/-- Finalize a disjunction arm's retained length / uniqueness residual at manifestation. An arm
    shaped `.conj [value, lengthConstraint …]` or `.conj [value, uniqueItems]` (an undecided bound
    deferred at meet for cross-conjunct accretion, or a uniqueness check held until the list is
    concrete) reaches finalization with NO further conjunct to accrete: `finalizeLengthConj`
    adjudicates it — a violated bound collapses the arm to `.bottomWith`, which
    `liveAlternatives`/`resolveDisjDefault?` then PRUNE, exactly as an in-isolation manifest would.
    This runs ONLY here (manifest = the genuinely-final point); doing it at meet-time `normalizeDisj`
    would prematurely prune an arm a later conjunct could still rescue. A non-conj arm, or a conj
    that is not this validator shape, passes through unchanged. -/
def finalizeDisjArm : Mark × Value -> Mark × Value
  | (mark, .conj constraints) =>
      match finalizeLengthConj constraints with
      | some resolved => (mark, resolved)
      | none => (mark, .conj constraints)
  | arm => arm

mutual
  -- Fuel bounds nesting DEPTH, not sibling breadth: the sibling/tail recursion threads `fuel`
  -- UNCHANGED (only descending INTO a value via `manifestWithFuel`'s own `fuel + 1` match spends
  -- a unit). Peeling one fuel per sibling coupled the budget to field COUNT — a struct with
  -- `manifestFuel - 2` top-level fields ran the last field out of fuel (`incomplete value`),
  -- regardless of how shallow. Mirrors `evalFieldRefsListWithFuel`, which likewise passes fuel
  -- undecremented across siblings. Termination comes from the list length (see `termination_by`).
  def manifestFieldsWithFuel : Nat -> List Field -> Except ManifestError (List (String × ManifestValue))
    | _, [] => .ok []
    | fuel, field :: fields =>
        match Field.fieldClass field with
        | .field false false .regular =>
            match manifestWithFuel fuel (Field.value field), manifestFieldsWithFuel fuel fields with
            | .ok value, .ok rest => .ok ((Field.label field, value) :: rest)
            | .error error, _ => .error error
            | _, .error error => .error error
        | .field _ _ .required => .error (.incomplete (Field.value field))
        | .field _ _ .regular =>
            -- A real in-file HIDDEN/definition present field (`#u: v`, `_u: v`) — REACHED, since
            -- it is in the manifested struct (import-package bindings are `.importBinding`, handled
            -- below and kept lazy). cue ENFORCES a bottom reached anywhere in such a field, even
            -- DEEP (`{#u: {x: _|_}}` → explicit error, oracle-confirmed v0.16.1). So recurse the
            -- value's manifest output spine and surface a DEEP `.contradiction`. A non-contradiction
            -- error (incomplete — `{#u: {x: string}}`) stays skipped: hidden/def fields are
            -- non-output, and an unreached incomplete is tolerated (cue exports clean).
            match manifestWithFuel fuel (Field.value field) with
            | .error .contradiction => .error .contradiction
            | _ => manifestFieldsWithFuel fuel fields
        | .field _ _ .optional => manifestFieldsWithFuel fuel fields
        | .letBinding => manifestFieldsWithFuel fuel fields
        -- A bound imported package: its unreferenced content stays cue-LAZY (output-reachability
        -- laziness — cue never manifests unreferenced imported content). SHALLOW `isBottom` only;
        -- a deep recurse here would re-bottom cert-manager/argocd (the reverted-A2 trap). The
        -- marker makes that laziness LOCAL: an `importBinding` IS the unreferenced-import case by
        -- construction, so the deep recurse above NEVER runs on a bound package.
        | .importBinding =>
            if isBottom (Field.value field) then .error .contradiction
            else manifestFieldsWithFuel fuel fields
  termination_by n fields => (n, 2, fields.length)

  -- Fuel threads UNCHANGED across list elements (breadth is free); only `manifestWithFuel`'s
  -- descent into an item spends fuel (depth). Same breadth/depth decoupling as the field walk.
  def manifestItemsWithFuel : Nat -> List Value -> Except ManifestError (List ManifestValue)
    | _, [] => .ok []
    | fuel, item :: items =>
        match manifestWithFuel fuel item, manifestItemsWithFuel fuel items with
        | .ok value, .ok rest => .ok (value :: rest)
        | .error error, _ => .error error
        | _, .error error => .error error
  termination_by n items => (n, 2, items.length)

  def manifestWithFuel : Nat -> Value -> Except ManifestError ManifestValue
    | 0, value => .error (.incomplete value)
    | _ + 1, .prim prim => .ok (.prim prim)
    | _ + 1, .bottom => .error .contradiction
    | _ + 1, .bottomWith reasons =>
      match unusedImportReasons reasons, unsupportedBuiltinName? reasons with
      | [], some name => .error (.unsupportedBuiltinFunction name)
      | [], none => .error .contradiction
      | imports, _ => .error (.importedNotUsed imports)
    | _ + 1, .top => .error (.incomplete .top)
    | _ + 1, .kind kind => .error (.incomplete (.kind kind))
    | _ + 1, .notPrim prim => .error (.incomplete (.notPrim prim))
    | _ + 1, .stringRegex pattern => .error (.incomplete (.stringRegex pattern))
    | _ + 1, .boundConstraint bound kind domain => .error (.incomplete (.boundConstraint bound kind domain))
    | _ + 1, .lengthConstraint kind bound limit => .error (.incomplete (.lengthConstraint kind bound limit))
    | _ + 1, .uniqueItems => .error (.incomplete .uniqueItems)
    | _ + 1, .stringFormat fmt => .error (.incomplete (.stringFormat fmt))
    -- A value guarded by retained length / uniqueness validators (`{a:1} & struct.MinFields(2)`,
    -- `[1] & list.MinItems(2)`, `[x] & list.UniqueItems`) is adjudicated HERE, at finalization:
    -- satisfied ⇒ manifest the value, violated ⇒ contradiction. Any other `.conj` is a genuine
    -- incomplete residual.
    | fuel + 1, .conj constraints =>
        match finalizeLengthConj constraints with
        | some resolved => manifestWithFuel fuel resolved
        | none => .error (.incomplete (.conj constraints))
    | _ + 1, .builtinCall name args => .error (.incomplete (.builtinCall name args))
    | _ + 1, .unary op value => .error (.incomplete (.unary op value))
    | _ + 1, .binary op left right => .error (.incomplete (.binary op left right))
    | _ + 1, .ref label => .error (.incomplete (.ref label))
    | _ + 1, .refId id => .error (.incomplete (.refId id))
    | _ + 1, .patternLabel name => .error (.incomplete (.patternLabel name))
    | _ + 1, .thisStruct => .error (.incomplete .thisStruct)
    | _ + 1, .selector base label => .error (.incomplete (.selector base label))
    | _ + 1, .index base key => .error (.incomplete (.index base key))
    -- Manifest the named fields; tail/patterns/openness do not appear in output.
    | fuel + 1, .struct fields _ _ _ _ =>
        match manifestFieldsWithFuel fuel fields with
        | .ok fields => .ok (.struct fields)
        | .error error => .error error
    | fuel + 1, .list items =>
        match manifestItemsWithFuel fuel items with
        | .ok items => .ok (.list items)
        | .error error => .error error
    | fuel + 1, .listTail items _ =>
        -- an open list manifests as its concrete prefix; the open/typed tail is dropped
        -- on export, matching `cue` (`[1, ...]` -> `[1]`, `[...]` -> `[]`). A non-concrete
        -- prefix element still surfaces as incomplete via the recursion below.
        match manifestItemsWithFuel fuel items with
        | .ok items => .ok (.list items)
        | .error error => .error error
    | fuel + 1, .embeddedList items _ _ =>
        -- a struct-embedded list manifests as its (concrete) items; the open tail and
        -- the non-output decls do not appear in output.
        match manifestItemsWithFuel fuel items with
        | .ok items => .ok (.list items)
        | .error error => .error error
    | fuel + 1, .embeddedScalar scalar _ =>
        -- a struct-embedded scalar manifests as that scalar; the non-output decls do not
        -- appear in output (the scalar analog of the `.embeddedList` arm above).
        manifestWithFuel fuel scalar
    | _ + 1, .comprehension clauses body => .error (.incomplete (.comprehension clauses body))
    | _ + 1, .listComprehension clauses body => .error (.incomplete (.listComprehension clauses body))
    | _ + 1, .structComp fields comprehensions openness =>
        -- A held `.structComp` residual is incomplete (the deferred comprehension cannot manifest),
        -- BUT its resolved `fields` can carry a held `.bottomWith` field conflict (the inline-`_|_`
        -- convention: `{x:1,for…} & {x:2}` ⇒ `.structComp [x:_|_] …`, NOT a top-level `.bottom`).
        -- That conflict is TERMINAL — surface it as a `.contradiction`, mirroring the `.struct` arm
        -- (cue: `conflicting values`, not `incomplete value`). Detection descends; the VALUE keeps
        -- its inline bottom (RESID-MASK-1's consuming-layer convention). Same predicate that prunes
        -- a dead disjunction arm (`containsBottomFields`, which skips unset-optional bottoms).
        if containsBottomFields fields then .error .contradiction
        else .error (.incomplete (.structComp fields comprehensions openness))
    | _ + 1, .interpolation parts => .error (.incomplete (.interpolation parts))
    | _ + 1, .dynamicField label fieldClass value =>
        .error (.incomplete (.dynamicField label fieldClass value))
    | _ + 1, .closure capturedEnv body =>
        -- an unforced closure is non-concrete; forcing it is the eval layer's job (slice
        -- 2+). Unreachable until a producer exists.
        .error (.incomplete (.closure capturedEnv body))
    | fuel + 1, .disj alternatives =>
        let finalized := alternatives.map finalizeDisjArm
        match resolveDisjDefault? finalized with
        | some value => manifestWithFuel fuel value
        | none => .error (.ambiguous (liveAlternatives finalized))
  termination_by n _ => (n, 1, 0)
end

def manifest (value : Value) : Except ManifestError ManifestValue :=
  manifestWithFuel manifestFuel value

mutual
  def formatManifestFieldWithFuel : Nat -> String × ManifestValue -> String
    | 0, _ => "..."
    | fuel + 1, field => s!"{field.fst}: {formatManifestValueWithFuel fuel field.snd}"

  def formatManifestValueWithFuel : Nat -> ManifestValue -> String
    | 0, _ => "..."
    | _, .prim prim => formatPrim prim
    | fuel + 1, .struct fields =>
        "{" ++ joinWith ", " (fields.map (formatManifestFieldWithFuel fuel)) ++ "}"
    | fuel + 1, .list items =>
        "[" ++ joinWith ", " (items.map (formatManifestValueWithFuel fuel)) ++ "]"
end

def formatManifestValue (value : ManifestValue) : String :=
  formatManifestValueWithFuel formatFuel value

end Kue
