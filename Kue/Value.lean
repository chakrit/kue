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

inductive Value where
  | top
  | bottom
  | prim (value : Prim)
  | kind (kind : Kind)
  | disj (alternatives : List (Mark × Value))
deriving Repr, BEq

end Kue
