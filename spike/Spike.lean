import Kue

/-- Spike entry: calls Kue's REAL pure evaluator. `@[export]` makes a C symbol
    `kue_spike_eval`. The arg is an OWNED `String` (NOT `@&`): `evalSourceToString`
    consumes its argument, so the export must own and pass it through. A borrowed
    `@&` arg here is a double-free trap — the export forwards the borrowed handle
    into a consuming callee, and the C caller decs it again. The return is an
    OWNED Lean String. Exercises the full runtime: parse → resolve → eval
    (Decimal/GMP bignum) → format. -/
@[export kue_spike_eval]
def kueSpikeEval (input : String) : String :=
  match Kue.evalSourceToString input with
  | .ok s => s
  | .error e => s!"parse error {e.line}:{e.column}: {e.message}"
