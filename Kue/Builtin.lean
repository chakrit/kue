import Kue.Lattice

namespace Kue

def closeValue : Value -> Value
  | .struct fields _ => .struct fields false
  | value => value

def countRegularFields : List Field -> Nat
  | [] => 0
  | field :: fields =>
      let rest := countRegularFields fields
      if Field.fieldClass field == .regular then
        rest + 1
      else
        rest

def lenValue : Value -> Value
  | .prim (.string value) => .prim (.int (Int.ofNat value.utf8ByteSize))
  | .prim (.bytes value) => .prim (.int (Int.ofNat value.utf8ByteSize))
  | .kind .string => .kind .int
  | .kind .bytes => .kind .int
  | .list items => .prim (.int (Int.ofNat items.length))
  | .listTail items _ => .prim (.int (Int.ofNat items.length))
  | .struct fields _ => .prim (.int (Int.ofNat (countRegularFields fields)))
  | .structTail fields _ => .prim (.int (Int.ofNat (countRegularFields fields)))
  | .structPattern fields _ _ => .prim (.int (Int.ofNat (countRegularFields fields)))
  | _ => .bottom

def andValues (values : List Value) : Value :=
  values.foldl (fun current value => meet current value) .top

def orValues : List Value -> Value
  | [] => .bottom
  | value :: values => values.foldl (fun current next => join current next) value

end Kue
