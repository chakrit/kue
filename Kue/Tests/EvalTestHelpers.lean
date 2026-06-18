import Kue.Runtime

namespace Kue

def evalSourceMatches (source expected : String) : Bool :=
  match evalSourceToString source with
  | .ok output => output == expected
  | .error _ => false

/-- Match the JSON `export` of a single source against `expected`. Unlike
    `evalSourceMatches` (CUE-syntax eval output, which keeps structural decoration like
    `...` and `[string]: T`), this manifests to concrete JSON — the B2-stable observable
    for struct-shape meets, where the internal constructor may change but the exported
    value may not. -/
def exportJsonMatches (source expected : String) : Bool :=
  match exportSourcesToString .json [source] with
  | .ok (.ok output) => output == expected
  | _ => false

end Kue
