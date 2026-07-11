import Kue.Runtime

namespace Kue

def evalSourceMatches (source expected : String) : Bool :=
  match evalSourceToString source with
  | .ok output => output == expected
  | .error _ => false

-- Whether a value manifests to a concrete result (`true`) or fails — a bottom, an
-- incompleteness, or an ambiguous disjunction (`false`). The disjunction-arm-survival witness:
-- an ambiguous 2-arm disjunction manifests `.error`, so a spurious fabrication that collapses it
-- to one concrete arm would flip this to `true`.
def manifestValueOk (value : Value) : Bool :=
  match manifest value with
  | .ok _ => true
  | .error _ => false

-- Match the JSON `export` of a single source against `expected`. Unlike
-- `evalSourceMatches` (CUE-syntax eval output, which keeps structural decoration like
-- `...` and `[string]: T`), this manifests to concrete JSON — the B2-stable observable
-- for struct-shape meets, where the internal constructor may change but the exported
-- value may not.
def exportJsonMatches (source expected : String) : Bool :=
  match exportSourcesToString .json [source] with
  | .ok (.ok output) => output == expected
  | _ => false

-- Positively witness that a source's JSON export BOTTOMS — the value parsed but manifesting
-- it failed (the inner `.error` arm). Distinct from `exportJsonMatches … "" = false`, which a
-- wrong NON-empty output also satisfies; this asserts the bottom itself, so a regression to a
-- spurious concrete value fails the pin. A parse error (outer `.error`) is NOT a bottom and
-- returns `false`.
def exportJsonBottoms (source : String) : Bool :=
  match exportSourcesToString .json [source] with
  | .ok (.error _) => true
  | _ => false

-- The rendered CLI error string of a failed single-source JSON export (`formatManifestError`
-- output, exactly what `kue: export error: <msg>` wraps). Empty string on parse failure or a
-- successful export — lets a pin assert the exact cue-shaped wording, not merely "some bottom".
def exportErrorMessage (source : String) : String :=
  match exportSourcesToString .json [source] with
  | .ok (.error message) => message
  | _ => ""

-- Does a resolved value carry a `.structuralCycle` bottom anywhere in its struct/disj/list
-- spine? Pins the REASON of a structural-cycle detection (D#2a), not merely "some bottom" — a
-- plain `exportJsonBottoms` is satisfied by an unrelated conflict, so it cannot witness that the
-- cycle lever fired and tagged correctly. Fuel-bounded over the shapes a cycle hides in (struct
-- fields + tail, disjunction arms, list items + tail); `fuel` from the AST so it cannot
-- under-run on a finitely-deep value.
def valueHasStructuralCycle : Nat -> Value -> Bool
  | 0, _ => false
  | _ + 1, .bottomWith reasons => reasons.contains .structuralCycle
  | fuel + 1, .struct fields _ tail _ _ =>
      fields.any (fun f => valueHasStructuralCycle fuel (Field.value f))
        || (match tail with | some t => valueHasStructuralCycle fuel t | none => false)
  | fuel + 1, .structComp fields comprehensions _ =>
      fields.any (fun f => valueHasStructuralCycle fuel (Field.value f))
        || comprehensions.any (valueHasStructuralCycle fuel)
  | fuel + 1, .disj alternatives =>
      alternatives.any (fun a => valueHasStructuralCycle fuel a.snd)
  | fuel + 1, .list items => items.any (valueHasStructuralCycle fuel)
  | fuel + 1, .listTail items tail =>
      items.any (valueHasStructuralCycle fuel) || valueHasStructuralCycle fuel tail
  | _ + 1, _ => false

-- Witness that evaluating `source` detects a structural cycle: the resolved value carries a
-- `.structuralCycle` bottom in its spine. The bound (200) comfortably exceeds any test AST.
def evalSourceDetectsStructuralCycle (source : String) : Bool :=
  match parseSource source with
  | .ok value => valueHasStructuralCycle 200 (resolveAndEval value)
  | .error _ => false

end Kue
