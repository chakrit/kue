import Kue.Runtime

namespace Kue

def evalSourceMatches (source expected : String) : Bool :=
  match evalSourceToString source with
  | .ok output => output == expected
  | .error _ => false

end Kue
