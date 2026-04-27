import Kue.Value

namespace Kue

def formatKind : Kind -> String
  | .null => "null"
  | .bool => "bool"
  | .int => "int"
  | .string => "string"

def formatPrim : Prim -> String
  | .null => "null"
  | .bool true => "true"
  | .bool false => "false"
  | .int value => toString value
  | .string value => s!"\"{value}\""

def formatValue : Value -> String
  | .top => "_"
  | .bottom => "_|_"
  | .prim prim => formatPrim prim
  | .kind kind => formatKind kind

end Kue
