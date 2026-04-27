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

def joinWith (separator : String) : List String -> String
  | [] => ""
  | [value] => value
  | value :: values => value ++ separator ++ joinWith separator values

mutual
  def formatAlternative : Mark × Value -> String
    | (.regular, value) => formatValue value
    | (.default, value) => "*" ++ formatValue value

  def formatValue : Value -> String
    | .top => "_"
    | .bottom => "_|_"
    | .prim prim => formatPrim prim
    | .kind kind => formatKind kind
    | .disj alternatives => joinWith " | " (alternatives.map formatAlternative)
end

end Kue
