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
  | structPattern (fields : List (String × FieldClass × Value)) (labelPattern constraint : Value)
  | list (items : List Value)
  | listTail (items : List Value) (tail : Value)
deriving Repr, BEq

abbrev Field := String × FieldClass × Value

namespace Field

def label (field : Field) : String :=
  field.fst

def fieldClass (field : Field) : FieldClass :=
  field.snd.fst

def value (field : Field) : Value :=
  field.snd.snd

def regular (label : String) (value : Value) : Field :=
  (label, .regular, value)

end Field

def stringRegexMatches (pattern value : String) : Bool :=
  if pattern.startsWith "^" && pattern.endsWith "$" then
    value == ((pattern.drop 1).dropEnd 1).copy
  else if pattern.startsWith "^" then
    (pattern.drop 1).copy |>.isPrefixOf value
  else if pattern.endsWith "$" then
    value.endsWith (pattern.dropEnd 1).copy
  else
    value.contains pattern

end Kue
