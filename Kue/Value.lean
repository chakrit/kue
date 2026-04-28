namespace Kue

inductive Kind where
  | null
  | bool
  | int
  | string
deriving Repr, BEq, DecidableEq

inductive Prim where
  | null
  | bool (value : Bool)
  | int (value : Int)
  | string (value : String)
deriving Repr, BEq, DecidableEq

namespace Prim

def kind : Prim -> Kind
  | .null => .null
  | .bool _ => .bool
  | .int _ => .int
  | .string _ => .string

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

inductive BottomReason where
  | primitiveConflict (left right : Prim)
  | kindConflict (left right : Kind)
  | fieldConflict (label : String)
  | fieldNotAllowed (label : String)
  | fieldConstraint (label : String)
deriving Repr, BEq, DecidableEq

inductive Value where
  | top
  | bottom
  | bottomWith (reasons : List BottomReason)
  | prim (value : Prim)
  | kind (kind : Kind)
  | disj (alternatives : List (Mark × Value))
  | struct (fields : List (String × FieldClass × Value)) (open_ : Bool)
  | structTail (fields : List (String × FieldClass × Value)) (tail : Value)
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

end Kue
