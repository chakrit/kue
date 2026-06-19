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

/-- Positively witness that a source's JSON export BOTTOMS — the value parsed but manifesting
    it failed (the inner `.error` arm). Distinct from `exportJsonMatches … "" = false`, which a
    wrong NON-empty output also satisfies; this asserts the bottom itself, so a regression to a
    spurious concrete value fails the pin. A parse error (outer `.error`) is NOT a bottom and
    returns `false`. -/
def exportJsonBottoms (source : String) : Bool :=
  match exportSourcesToString .json [source] with
  | .ok (.error _) => true
  | _ => false

end Kue
