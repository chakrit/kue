# Correctness Over Performance (but usable for basic cases)

- **Date:** 2026-06-18
- **PR:** manual
- **Status:** accepted

## Decision

When correctness and performance conflict, Kue chooses **correctness, every time**. Kue
never ships a performance optimization that can return a wrong value — a fast-but-wrong
evaluator defeats the entire reason Kue exists (correct CUE v0.15 semantics; see
[the compatibility target](2026-06-14-cue-compatibility-target.md)).

This is a hard rule, not a lean. A perf change is admissible only when it is **proven
behavior-preserving**: byte-identical fixture output plus a written soundness argument.
A perf slice that cannot guarantee soundness **stops and reports** rather than shipping —
it does not "probably-fine" its way past the gate.

The counterweight: Kue must still be **usable for basic cases**. "Correct but unusably
slow" on an ordinary config is a bug to fix — just never by trading away soundness. The
fix for slowness is always a *sound* optimization, or a clearer cost model the user can
work with, never a shortcut that risks the result.

## Rationale

Kue's fuel-bounded, total-function evaluator is chosen for soundness and guaranteed
termination, not speed. `fuel` is load-bearing: it distinguishes genuine values from
cycle-truncated ones (measured: 263 cases where the same `(envIds, visited, value)`
yields different results at different fuel). So the tempting perf shortcuts — dropping
`fuel` from the memo key, caching across fuel levels without tracking saturation — are
*provably unsound*, and were rejected on exactly that basis.

The history that motivates the rule: the frame-id-sharing perf slice landed only the
parts with a clean soundness argument (byte-identical fixtures, explicit no-false-share
key), and **deliberately did not ship** the fuel-axis fix because its soundness bit could
not yet be guaranteed by construction. That stop-and-report is the behavior this decision
codifies, not an exception to it.

But a sound engine nobody can run is also a failure. Real targets (e.g. prod9 infra apps)
must evaluate correctly *and* within a usable time. So performance is a tracked,
first-class concern — pursued through sound optimization and an honest cost model, never
through correctness debt.

## Consequences

- **Perf slices are gated.** Every optimization needs byte-identical fixtures + a soundness
  argument recorded in `plan.md`. No soundness guarantee → stop and report, file the design
  and the hole as a future slice.
- **A maintained performance guide.** [`guides/kue-performance.md`](../guides/kue-performance.md)
  records which CUE patterns are expensive in Kue and how to write Kue-friendly CUE. It is
  a living doc, kept current on every docs/spec pass and whenever a slice changes eval
  cost or surfaces a slow/fast pattern.
- **Audits check perf-guide currency.** The Phase B audit verifies the guide reflects
  current reality (new slow patterns, mitigations landed).
- **Slowness is a bug, not a non-issue.** A basic case that is unusably slow is tracked and
  fixed — via sound optimization only.

## Alternatives considered

- **Performance parity with `cue` as a hard goal** — rejected: it would pressure unsound
  shortcuts (the fuel-axis memo) that corrupt values. Speed is pursued, but never above
  correctness.
- **Ignore performance entirely** — rejected: an evaluator too slow to run on ordinary
  configs is unusable, which defeats adoption as a `cue` replacement.
