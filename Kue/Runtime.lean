import Kue.Eval
import Kue.Format
import Kue.Parse
import Kue.Resolve

namespace Kue

def formatTopLevel : Value -> String
  | .struct fields _ => joinWith "\n" (fields.map (formatStructFieldWithFuel formatFuel))
  | value => formatValue value

def resolveAndEval (value : Value) : Value :=
  evalStructRefs (resolveStructRefs value)

def formatResolvedTopLevel (value : Value) : String :=
  formatTopLevel (resolveAndEval value)

def evalSourceToString (source : String) : Except ParseError String :=
  (parseSource source).map formatResolvedTopLevel

end Kue
