import Kue.Eval
import Kue.Format
import Kue.Lattice
import Kue.Parse
import Kue.Resolve

namespace Kue

def formatTopLevel : Value -> String
  | .struct fields _ => joinWith "\n" (formatStructFieldsWithFuel formatFuel fields)
  | value => formatValue value

def resolveAndEval (value : Value) : Value :=
  evalStructRefs (resolveStructRefs value)

def formatResolvedTopLevel (value : Value) : String :=
  formatTopLevel (resolveAndEval value)

def evalSourceToString (source : String) : Except ParseError String :=
  (parseSource source).map formatResolvedTopLevel

def parseSources : List String -> Except ParseError (List Value)
  | [] => .ok []
  | source :: sources => do
      let value ← parseSource source
      let values ← parseSources sources
      pure (value :: values)

def mergePackageNames (left right : Option String) : Except ParseError (Option String) :=
  match left, right with
  | none, packageName => pure packageName
  | packageName, none => pure packageName
  | some leftName, some rightName =>
      if leftName == rightName then
        pure (some leftName)
      else
        parseError [] "conflicting package names"

def checkSourcePackageNamesWith :
    Option String -> List String -> Except ParseError (Option String)
  | packageName, [] => pure packageName
  | packageName, source :: sources => do
      let sourceName ← sourcePackageName source
      let packageName ← mergePackageNames packageName sourceName
      checkSourcePackageNamesWith packageName sources

def checkSourcePackageNames (sources : List String) : Except ParseError (Option String) :=
  checkSourcePackageNamesWith none sources

def mergeSourceValues : List Value -> Value
  | [] => .struct [] true
  | value :: values => values.foldl meet value

def evalSourcesToString (sources : List String) : Except ParseError String := do
  let _ ← checkSourcePackageNames sources
  let values ← parseSources sources
  pure (formatResolvedTopLevel (mergeSourceValues values))

end Kue
