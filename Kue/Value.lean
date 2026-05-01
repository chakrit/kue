import Init.Data.String.Search

namespace Kue

inductive Kind where
  | null
  | bool
  | number
  | int
  | float
  | string
  | bytes
deriving Repr, BEq, DecidableEq

inductive Prim where
  | null
  | bool (value : Bool)
  | int (value : Int)
  | float (value : String)
  | string (value : String)
  | bytes (value : String)
deriving Repr, BEq, DecidableEq

namespace Prim

def kind : Prim -> Kind
  | .null => .null
  | .bool _ => .bool
  | .int _ => .int
  | .float _ => .float
  | .string _ => .string
  | .bytes _ => .bytes

end Prim

inductive Mark where
  | regular
  | default
deriving Repr, BEq, DecidableEq

inductive FieldClass where
  | regular
  | optional
  | required
  | hidden
  | definition
deriving Repr, BEq, DecidableEq

namespace FieldClass

def ignoresClosedness : FieldClass -> Bool
  | .hidden => true
  | .definition => true
  | _ => false

end FieldClass

structure BindingId where
  index : Nat
deriving Repr, BEq, DecidableEq

inductive BottomReason where
  | primitiveConflict (left right : Prim)
  | kindConflict (left right : Kind)
  | fieldConflict (label : String)
  | fieldNotAllowed (label : String)
  | fieldConstraint (label : String)
  | unresolvedReference (label : String)
  | unresolvedBinding (id : BindingId)
  | intBoundConflict
  | divisionByZero
  | excludedValue (value : Prim)
deriving Repr, BEq, DecidableEq

inductive Value where
  | top
  | bottom
  | bottomWith (reasons : List BottomReason)
  | prim (value : Prim)
  | kind (kind : Kind)
  | notPrim (value : Prim)
  | stringRegex (pattern : String)
  | intGe (minimum : Int)
  | intGt (minimum : Int)
  | intLe (maximum : Int)
  | intLt (maximum : Int)
  | conj (constraints : List Value)
  | builtinCall (name : String) (args : List Value)
  | ref (label : String)
  | refId (id : BindingId)
  | disj (alternatives : List (Mark × Value))
  | struct (fields : List (String × FieldClass × Value)) (open_ : Bool)
  | structTail (fields : List (String × FieldClass × Value)) (tail : Value)
  | structPattern
      (fields : List (String × FieldClass × Value))
      (labelPattern constraint : Value)
      (open_ : Bool)
  | list (items : List Value)
  | listTail (items : List Value) (tail : Value)
deriving Repr, BEq

abbrev Field := String × FieldClass × Value

namespace Field

def label (field : Field) : String :=
  field.fst

def fieldClass (field : Field) : FieldClass :=
  field.snd.fst

def ignoresClosedness (field : Field) : Bool :=
  FieldClass.ignoresClosedness (fieldClass field)

def value (field : Field) : Value :=
  field.snd.snd

def regular (label : String) (value : Value) : Field :=
  (label, .regular, value)

end Field

inductive RegexAtom where
  | literal (value : Char)
  | any
  | charClass (ranges : List (Char × Char)) (negated : Bool)
deriving Repr, BEq

def charInRegexRange (lower upper value : Char) : Bool :=
  lower.toNat <= value.toNat && value.toNat <= upper.toNat

def regexClassMatches (ranges : List (Char × Char)) (value : Char) : Bool :=
  ranges.any fun range => charInRegexRange range.fst range.snd value

namespace RegexAtom

def matchesChar : RegexAtom -> Char -> Bool
  | .literal expected, value => expected == value
  | .any, _ => true
  | .charClass ranges false, value => regexClassMatches ranges value
  | .charClass ranges true, value => !regexClassMatches ranges value

end RegexAtom

def parseRegexClassRanges : List Char -> List (Char × Char) -> Option (List (Char × Char) × List Char)
  | [], _ => none
  | ']' :: rest, ranges => some (ranges.reverse, rest)
  | lower :: '-' :: upper :: rest, ranges => parseRegexClassRanges rest ((lower, upper) :: ranges)
  | value :: rest, ranges => parseRegexClassRanges rest ((value, value) :: ranges)

def parseRegexAtom : List Char -> Option (RegexAtom × List Char)
  | [] => none
  | '\\' :: value :: rest => some (.literal value, rest)
  | ['\\'] => some (.literal '\\', [])
  | '[' :: '^' :: rest =>
      match parseRegexClassRanges rest [] with
      | some (ranges, rest) => some (.charClass ranges true, rest)
      | none => some (.literal '[', '^' :: rest)
  | '[' :: rest =>
      match parseRegexClassRanges rest [] with
      | some (ranges, rest) => some (.charClass ranges false, rest)
      | none => some (.literal '[', rest)
  | '.' :: rest => some (.any, rest)
  | value :: rest => some (.literal value, rest)

mutual
  def regexMatchHereWithFuel : Nat -> Bool -> List Char -> List Char -> Bool
    | 0, _, _, _ => false
    | fuel + 1, anchoredEnd, pattern, value =>
        match parseRegexAtom pattern with
        | none => !anchoredEnd || value.isEmpty
        | some (atom, '*' :: rest) => regexMatchStarWithFuel fuel anchoredEnd atom rest value
        | some (atom, '+' :: rest) =>
            match value with
            | [] => false
            | current :: remaining =>
                atom.matchesChar current
                  && regexMatchStarWithFuel fuel anchoredEnd atom rest remaining
        | some (atom, rest) =>
            match value with
            | [] => false
            | current :: remaining =>
                atom.matchesChar current
                  && regexMatchHereWithFuel fuel anchoredEnd rest remaining

  def regexMatchStarWithFuel : Nat -> Bool -> RegexAtom -> List Char -> List Char -> Bool
    | 0, _, _, _, _ => false
    | fuel + 1, anchoredEnd, atom, rest, value =>
        regexMatchHereWithFuel fuel anchoredEnd rest value
          || match value with
             | [] => false
             | current :: remaining =>
                 atom.matchesChar current
                   && regexMatchStarWithFuel fuel anchoredEnd atom rest remaining

  def regexMatchAnywhereWithFuel : Nat -> Bool -> List Char -> List Char -> Bool
    | 0, _, _, _ => false
    | fuel + 1, anchoredEnd, pattern, value =>
        regexMatchHereWithFuel fuel anchoredEnd pattern value
          || match value with
             | [] => false
             | _ :: remaining => regexMatchAnywhereWithFuel fuel anchoredEnd pattern remaining
end

def stringRegexMatches (pattern value : String) : Bool :=
  let anchoredStart := pattern.startsWith "^"
  let withoutStart := if anchoredStart then (pattern.drop 1).copy else pattern
  let anchoredEnd := withoutStart.endsWith "$"
  let body := if anchoredEnd then (withoutStart.dropEnd 1).copy else withoutStart
  let patternChars := body.toList
  let valueChars := value.toList
  let fuel := ((patternChars.length + 1) * (valueChars.length + 1) * 4) + 10
  if anchoredStart then
    regexMatchHereWithFuel fuel anchoredEnd patternChars valueChars
  else
    regexMatchAnywhereWithFuel fuel anchoredEnd patternChars valueChars

end Kue
