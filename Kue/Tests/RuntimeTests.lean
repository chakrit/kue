import Kue.Runtime

namespace Kue

def evalSourcesOutputMatches (sources : List String) (expected : String) : Bool :=
  match evalSourcesToString sources with
  | .ok output => output == expected
  | .error _ => false

def evalSourcesFails (sources : List String) : Bool :=
  match evalSourcesToString sources with
  | .ok _ => false
  | .error _ => true

theorem eval_sources_merges_package_files :
    evalSourcesOutputMatches
        [
          "package demo\na: int\n",
          "package demo\na: 1\nb: a\n"
        ]
        "a: 1\nb: 1" = true := by
  native_decide

theorem eval_sources_merges_named_and_package_less_files :
    evalSourcesOutputMatches
        [
          "package demo\na: 1\n",
          "b: a\n"
        ]
        "a: 1\nb: 1" = true := by
  native_decide

theorem eval_sources_rejects_mismatched_packages :
    evalSourcesFails
        [
          "package one\na: 1\n",
          "package two\nb: 2\n"
        ] = true := by
  native_decide



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @eval_sources_rejects_mismatched_packages

end Kue
