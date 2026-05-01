import Kue.Value

namespace Kue

def closeValue : Value -> Value
  | .struct fields _ => .struct fields false
  | value => value

end Kue
