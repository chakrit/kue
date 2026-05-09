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

inductive BinaryOp where
  | add
  | sub
  | mul
  | div
  | eq
  | ne
  | lt
  | le
  | gt
  | ge
deriving Repr, BEq, DecidableEq

inductive FieldClass where
  | regular
  | optional
  | required
  | hidden
  | definition
  | letBinding
deriving Repr, BEq, DecidableEq

namespace FieldClass

def ignoresClosedness : FieldClass -> Bool
  | .hidden => true
  | .definition => true
  | .letBinding => true
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
  | invalidIndex (index : Int)
  | indexOutOfRange (index : Int) (length : Nat)
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
  | binary (op : BinaryOp) (left right : Value)
  | ref (label : String)
  | refId (id : BindingId)
  | selector (base : Value) (label : String)
  | index (base key : Value)
  | disj (alternatives : List (Mark × Value))
  | struct (fields : List (String × FieldClass × Value)) (open_ : Bool)
  | structTail (fields : List (String × FieldClass × Value)) (tail : Value)
  | structPattern
      (fields : List (String × FieldClass × Value))
      (labelPattern constraint : Value)
      (open_ : Bool)
  | structPatterns
      (fields : List (String × FieldClass × Value))
      (patterns : List (Value × Value))
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

def regexDigitRanges : List (Char × Char) :=
  [('0', '9')]

def regexWordRanges : List (Char × Char) :=
  [('0', '9'), ('A', 'Z'), ('_', '_'), ('a', 'z')]

def regexSpaceRanges : List (Char × Char) :=
  [(' ', ' '), ('\t', '\t'), ('\n', '\n'), ('\r', '\r')]

def regexDigitValue? (value : Char) : Option Nat :=
  if charInRegexRange '0' '9' value then
    some (value.toNat - '0'.toNat)
  else
    none

def parseRegexNatDigits : List Char -> Nat -> Bool -> Option (Nat × List Char)
  | [], _, _ => none
  | value :: rest, count, seen =>
      match regexDigitValue? value with
      | some digit => parseRegexNatDigits rest (count * 10 + digit) true
      | none => if seen then some (count, value :: rest) else none

def parseRegexRepeat : List Char -> Option (Nat × Nat × List Char)
  | '{' :: rest =>
      match parseRegexNatDigits rest 0 false with
      | some (minimum, '}' :: rest) => some (minimum, minimum, rest)
      | some (minimum, ',' :: rest) =>
          match parseRegexNatDigits rest 0 false with
          | some (maximum, '}' :: rest) =>
              if minimum <= maximum then some (minimum, maximum, rest) else none
          | _ => none
      | _ => none
  | _ => none

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
  | '\\' :: 'd' :: rest => some (.charClass regexDigitRanges false, rest)
  | '\\' :: 'D' :: rest => some (.charClass regexDigitRanges true, rest)
  | '\\' :: 'w' :: rest => some (.charClass regexWordRanges false, rest)
  | '\\' :: 'W' :: rest => some (.charClass regexWordRanges true, rest)
  | '\\' :: 's' :: rest => some (.charClass regexSpaceRanges false, rest)
  | '\\' :: 'S' :: rest => some (.charClass regexSpaceRanges true, rest)
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
        | some (atom, '?' :: rest) =>
            regexMatchHereWithFuel fuel anchoredEnd rest value
              || match value with
                 | [] => false
                 | current :: remaining =>
                     atom.matchesChar current
                       && regexMatchHereWithFuel fuel anchoredEnd rest remaining
        | some (atom, '+' :: rest) =>
            match value with
            | [] => false
            | current :: remaining =>
                atom.matchesChar current
                  && regexMatchStarWithFuel fuel anchoredEnd atom rest remaining
        | some (atom, rest) =>
            match parseRegexRepeat rest with
            | some (minimum, maximum, rest) =>
                regexMatchRepeatRangeWithFuel fuel anchoredEnd atom minimum maximum rest value
            | none =>
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

  def regexMatchAtMostWithFuel : Nat -> Bool -> RegexAtom -> Nat -> List Char -> List Char -> Bool
    | 0, _, _, _, _, _ => false
    | fuel + 1, anchoredEnd, _, 0, rest, value =>
        regexMatchHereWithFuel fuel anchoredEnd rest value
    | fuel + 1, anchoredEnd, atom, count + 1, rest, value =>
        regexMatchHereWithFuel fuel anchoredEnd rest value
          || match value with
             | [] => false
             | current :: remaining =>
                 atom.matchesChar current
                   && regexMatchAtMostWithFuel fuel anchoredEnd atom count rest remaining

  def regexMatchRepeatRangeWithFuel : Nat -> Bool -> RegexAtom -> Nat -> Nat -> List Char -> List Char -> Bool
    | 0, _, _, _, _, _, _ => false
    | fuel + 1, anchoredEnd, atom, 0, maximum, rest, value =>
        regexMatchAtMostWithFuel fuel anchoredEnd atom maximum rest value
    | fuel + 1, anchoredEnd, atom, minimum + 1, maximum + 1, rest, value =>
        match value with
        | [] => false
        | current :: remaining =>
            atom.matchesChar current
              && regexMatchRepeatRangeWithFuel fuel anchoredEnd atom minimum maximum rest remaining
    | _, _, _, _ + 1, 0, _, _ => false

  def regexMatchAnywhereWithFuel : Nat -> Bool -> List Char -> List Char -> Bool
    | 0, _, _, _ => false
    | fuel + 1, anchoredEnd, pattern, value =>
        regexMatchHereWithFuel fuel anchoredEnd pattern value
          || match value with
             | [] => false
             | _ :: remaining => regexMatchAnywhereWithFuel fuel anchoredEnd pattern remaining
end

def splitRegexAlternativesWithState :
    List Char -> Bool -> List Char -> List (List Char) -> List (List Char)
  | [], _, current, alternatives => (current.reverse :: alternatives).reverse
  | '\\' :: value :: rest, inClass, current, alternatives =>
      splitRegexAlternativesWithState rest inClass (value :: '\\' :: current) alternatives
  | ['\\'], inClass, current, alternatives =>
      splitRegexAlternativesWithState [] inClass ('\\' :: current) alternatives
  | '[' :: rest, false, current, alternatives =>
      splitRegexAlternativesWithState rest true ('[' :: current) alternatives
  | ']' :: rest, true, current, alternatives =>
      splitRegexAlternativesWithState rest false (']' :: current) alternatives
  | '|' :: rest, false, current, alternatives =>
      splitRegexAlternativesWithState rest false [] (current.reverse :: alternatives)
  | value :: rest, inClass, current, alternatives =>
      splitRegexAlternativesWithState rest inClass (value :: current) alternatives

def splitRegexAlternativeChars (pattern : List Char) : List (List Char) :=
  splitRegexAlternativesWithState pattern false [] []

def splitRegexAlternatives (pattern : String) : List String :=
  (splitRegexAlternativeChars pattern.toList).map String.ofList

def parseRegexGroupBodyWithState : List Char -> Bool -> List Char -> Option (List Char × List Char)
  | [], _, _ => none
  | '\\' :: value :: rest, inClass, current =>
      parseRegexGroupBodyWithState rest inClass (value :: '\\' :: current)
  | ['\\'], _, _ => none
  | '[' :: rest, false, current =>
      parseRegexGroupBodyWithState rest true ('[' :: current)
  | ']' :: rest, true, current =>
      parseRegexGroupBodyWithState rest false (']' :: current)
  | ')' :: rest, false, current => some (current.reverse, rest)
  | value :: rest, inClass, current =>
      parseRegexGroupBodyWithState rest inClass (value :: current)

def findFirstRegexGroupWithState :
    List Char -> Bool -> List Char -> Option (List Char × List Char × List Char)
  | [], _, _ => none
  | '\\' :: value :: rest, inClass, leading =>
      findFirstRegexGroupWithState rest inClass (value :: '\\' :: leading)
  | ['\\'], inClass, leading =>
      findFirstRegexGroupWithState [] inClass ('\\' :: leading)
  | '[' :: rest, false, leading =>
      findFirstRegexGroupWithState rest true ('[' :: leading)
  | ']' :: rest, true, leading =>
      findFirstRegexGroupWithState rest false (']' :: leading)
  | '(' :: rest, false, leading =>
      match parseRegexGroupBodyWithState rest false [] with
      | some (body, suffix) => some (leading.reverse, body, suffix)
      | none => findFirstRegexGroupWithState rest false ('(' :: leading)
  | value :: rest, inClass, leading =>
      findFirstRegexGroupWithState rest inClass (value :: leading)

def expandRegexGroupAlternatives : List Char -> List (List Char) -> List Char -> List String
  | _, [], _ => []
  | leading, alternative :: alternatives, suffix =>
      String.ofList (leading ++ alternative ++ suffix)
        :: expandRegexGroupAlternatives leading alternatives suffix

def expandFirstRegexGroup (pattern : String) : Option (List String) :=
  match findFirstRegexGroupWithState pattern.toList false [] with
  | none => none
  | some (leading, body, suffix) =>
      some (expandRegexGroupAlternatives leading (splitRegexAlternativeChars body) suffix)

def stringRegexAlternativeMatches (pattern value : String) : Bool :=
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

def stringRegexMatches (pattern value : String) : Bool :=
  let alternatives :=
    match expandFirstRegexGroup pattern with
    | some alternatives => alternatives
    | none => splitRegexAlternatives pattern
  alternatives.any fun alternative => stringRegexAlternativeMatches alternative value

end Kue
