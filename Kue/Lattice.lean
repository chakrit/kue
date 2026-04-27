import Kue.Value

namespace Kue

def meetPrim (left right : Prim) : Value :=
  if left = right then
    .prim left
  else
    .bottom

def meet (left right : Value) : Value :=
  match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .top, value => value
  | value, .top => value
  | .kind leftKind, .kind rightKind =>
      if leftKind = rightKind then
        .kind leftKind
      else
        .bottom
  | .kind kind, .prim prim =>
      if Prim.kind prim = kind then
        .prim prim
      else
        .bottom
  | .prim prim, .kind kind =>
      if Prim.kind prim = kind then
        .prim prim
      else
        .bottom
  | .prim leftPrim, .prim rightPrim => meetPrim leftPrim rightPrim

def joinPrim (left right : Prim) : Value :=
  if left = right then
    .prim left
  else if Prim.kind left = Prim.kind right then
    .kind (Prim.kind left)
  else
    .top

def join (left right : Value) : Value :=
  match left, right with
  | .top, _ => .top
  | _, .top => .top
  | .bottom, value => value
  | value, .bottom => value
  | .kind leftKind, .kind rightKind =>
      if leftKind = rightKind then
        .kind leftKind
      else
        .top
  | .kind kind, .prim prim =>
      if Prim.kind prim = kind then
        .kind kind
      else
        .top
  | .prim prim, .kind kind =>
      if Prim.kind prim = kind then
        .kind kind
      else
        .top
  | .prim leftPrim, .prim rightPrim => joinPrim leftPrim rightPrim

end Kue
