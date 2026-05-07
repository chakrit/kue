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

def liveAlternatives (alternatives : List (Mark × Value)) : List (Mark × Value) :=
  (flattenAlternatives alternatives).filter fun alternative => !containsBottom alternative.snd

def defaultAlternatives (alternatives : List (Mark × Value)) : List (Mark × Value) :=
  alternatives.filter fun alternative => alternative.fst == .default

def manifestFuel : Nat :=
  100

mutual
  def manifestFieldsWithFuel : Nat -> List Field -> Except ManifestError (List (String × ManifestValue))
    | 0, _ => .error (.incomplete .top)
    | _ + 1, [] => .ok []
    | fuel + 1, field :: fields =>
        match Field.fieldClass field with
        | .regular =>
            match manifestWithFuel fuel (Field.value field), manifestFieldsWithFuel fuel fields with
            | .ok value, .ok rest => .ok ((Field.label field, value) :: rest)
            | .error error, _ => .error error
            | _, .error error => .error error
        | .required => .error (.incomplete (Field.value field))
        | .optional => manifestFieldsWithFuel fuel fields
        | .hidden => manifestFieldsWithFuel fuel fields
        | .definition => manifestFieldsWithFuel fuel fields
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
    | _ + 1, .intGe minimum => .error (.incomplete (.intGe minimum))
    | _ + 1, .intGt minimum => .error (.incomplete (.intGt minimum))
    | _ + 1, .intLe maximum => .error (.incomplete (.intLe maximum))
    | _ + 1, .intLt maximum => .error (.incomplete (.intLt maximum))
    | _ + 1, .conj constraints => .error (.incomplete (.conj constraints))
    | _ + 1, .builtinCall name args => .error (.incomplete (.builtinCall name args))
    | _ + 1, .ref label => .error (.incomplete (.ref label))
    | _ + 1, .refId id => .error (.incomplete (.refId id))
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
    | _ + 1, .listTail items tail => .error (.incomplete (.listTail items tail))
    | fuel + 1, .disj alternatives =>
        let live := liveAlternatives alternatives
        let defaults := defaultAlternatives live
        match defaults with
        | [(_, value)] => manifestWithFuel fuel value
        | [] =>
            match live with
            | [(.regular, value)] => manifestWithFuel fuel value
            | alternatives => .error (.ambiguous alternatives)
        | alternatives => .error (.ambiguous alternatives)
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
