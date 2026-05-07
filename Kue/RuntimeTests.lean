import Kue.Runtime

namespace Kue

def evalSourcesOutputMatches (sources : List String) (expected : String) : Bool :=
  match evalSourcesToString sources with
  | .ok output => output == expected
  | .error _ => false

theorem eval_sources_merges_package_files :
    evalSourcesOutputMatches
        [
          "package demo\na: int\n",
          "package demo\na: 1\nb: a\n"
        ]
        "a: 1\nb: 1" = true := by
  native_decide

end Kue
