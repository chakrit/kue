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
  | .kind .string => .builtinCall "len" [.kind .string]
  | .kind .bytes => .builtinCall "len" [.kind .bytes]
  | .list items => .prim (.int (Int.ofNat items.length))
  | .listTail items _ => .prim (.int (Int.ofNat items.length))
  | .struct fields _ => .prim (.int (Int.ofNat (countRegularFields fields)))
  | .structTail fields _ => .prim (.int (Int.ofNat (countRegularFields fields)))
  | .structPattern fields _ _ => .prim (.int (Int.ofNat (countRegularFields fields)))
  | value => .builtinCall "len" [value]

def andValues (values : List Value) : Value :=
  values.foldl (fun current value => meet current value) .top

def orValues : List Value -> Value
  | [] => .builtinCall "or" [.list []]
  | value :: values => values.foldl (fun current next => join current next) value

def intBinaryBuiltinValue (name : String) (op : Int -> Int -> Int) (left right : Value) : Value :=
  match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim (.int leftInt), .prim (.int rightInt) =>
      if rightInt == 0 then
        .bottomWith [.divisionByZero]
      else
        .prim (.int (op leftInt rightInt))
  | left, right =>
      let leftAsInt := meet (.kind .int) left
      let rightAsInt := meet (.kind .int) right
      if containsBottom leftAsInt then
        leftAsInt
      else if containsBottom rightAsInt then
        rightAsInt
      else
        .builtinCall name [left, right]

def divValue (left right : Value) : Value :=
  intBinaryBuiltinValue "div" Int.ediv left right

def modValue (left right : Value) : Value :=
  intBinaryBuiltinValue "mod" Int.emod left right

def quoValue (left right : Value) : Value :=
  intBinaryBuiltinValue "quo" Int.tdiv left right

def remValue (left right : Value) : Value :=
  intBinaryBuiltinValue "rem" Int.tmod left right

end Kue
