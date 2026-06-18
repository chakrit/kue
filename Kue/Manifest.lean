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
deriving Repr, BEq

def manifestFuel : Nat :=
  100

mutual
  def manifestFieldsWithFuel : Nat -> List Field -> Except ManifestError (List (String × ManifestValue))
    | 0, _ => .error (.incomplete .top)
    | _ + 1, [] => .ok []
    | fuel + 1, field :: fields =>
        match Field.fieldClass field with
        | .field false false .regular =>
            match manifestWithFuel fuel (Field.value field), manifestFieldsWithFuel fuel fields with
            | .ok value, .ok rest => .ok ((Field.label field, value) :: rest)
            | .error error, _ => .error error
            | _, .error error => .error error
        | .field _ _ .required => .error (.incomplete (Field.value field))
        | .field _ _ .regular => manifestFieldsWithFuel fuel fields
        | .field _ _ .optional => manifestFieldsWithFuel fuel fields
        | .letBinding => manifestFieldsWithFuel fuel fields

  def manifestItemsWithFuel : Nat -> List Value -> Except ManifestError (List ManifestValue)
    | 0, _ => .error (.incomplete .top)
    | _ + 1, [] => .ok []
    | fuel + 1, item :: items =>
        match manifestWithFuel fuel item, manifestItemsWithFuel fuel items with
        | .ok value, .ok rest => .ok (value :: rest)
        | .error error, _ => .error error
        | _, .error error => .error error

  def manifestWithFuel : Nat -> Value -> Except ManifestError ManifestValue
    | 0, value => .error (.incomplete value)
    | _ + 1, .prim prim => .ok (.prim prim)
    | _ + 1, .bottom => .error .contradiction
    | _ + 1, .bottomWith _ => .error .contradiction
    | _ + 1, .top => .error (.incomplete .top)
    | _ + 1, .kind kind => .error (.incomplete (.kind kind))
    | _ + 1, .notPrim prim => .error (.incomplete (.notPrim prim))
    | _ + 1, .stringRegex pattern => .error (.incomplete (.stringRegex pattern))
    | _ + 1, .boundConstraint bound kind domain => .error (.incomplete (.boundConstraint bound kind domain))
    | _ + 1, .conj constraints => .error (.incomplete (.conj constraints))
    | _ + 1, .builtinCall name args => .error (.incomplete (.builtinCall name args))
    | _ + 1, .unary op value => .error (.incomplete (.unary op value))
    | _ + 1, .binary op left right => .error (.incomplete (.binary op left right))
    | _ + 1, .ref label => .error (.incomplete (.ref label))
    | _ + 1, .refId id => .error (.incomplete (.refId id))
    | _ + 1, .thisStruct => .error (.incomplete .thisStruct)
    | _ + 1, .selector base label => .error (.incomplete (.selector base label))
    | _ + 1, .index base key => .error (.incomplete (.index base key))
    | fuel + 1, .struct fields _ =>
        match manifestFieldsWithFuel fuel fields with
        | .ok fields => .ok (.struct fields)
        | .error error => .error error
    | fuel + 1, .structTail fields _ =>
        match manifestFieldsWithFuel fuel fields with
        | .ok fields => .ok (.struct fields)
        | .error error => .error error
    | fuel + 1, .structPattern fields _ _ _ =>
        match manifestFieldsWithFuel fuel fields with
        | .ok fields => .ok (.struct fields)
        | .error error => .error error
    | fuel + 1, .structPatterns fields _ _ =>
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
    | _ + 1, .comprehension clauses body => .error (.incomplete (.comprehension clauses body))
    | _ + 1, .structComp fields comprehensions open_ =>
        .error (.incomplete (.structComp fields comprehensions open_))
    | _ + 1, .interpolation parts => .error (.incomplete (.interpolation parts))
    | _ + 1, .dynamicField label fieldClass value =>
        .error (.incomplete (.dynamicField label fieldClass value))
    | _ + 1, .closure capturedEnv body =>
        -- an unforced closure is non-concrete; forcing it is the eval layer's job (slice
        -- 2+). Unreachable until a producer exists.
        .error (.incomplete (.closure capturedEnv body))
    | fuel + 1, .disj alternatives =>
        match resolveDisjDefault? alternatives with
        | some value => manifestWithFuel fuel value
        | none => .error (.ambiguous (liveAlternatives alternatives))
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
