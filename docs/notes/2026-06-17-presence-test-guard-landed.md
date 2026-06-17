# `!= _|_` / `== _|_` presence test landed — and it exposed the NEXT layer

**Slice:** plan item 2b — the `if Self.#field != _|_` presence-test *comparison*, named as
the #1 real-file blocker behind `kue export apps/argocd.cue` → `⊥`.

## The exact CUE semantics (oracle `cue` v0.16.1, measured — not assumed)

`e == _|_` / `e != _|_` is a **definedness test, not value equality.** Evaluate the
non-`_|_` operand, classify three-way:

| operand state          | example                  | `!= _|_` | `== _|_` |
|------------------------|--------------------------|----------|----------|
| **defined** (resolved) | `1`, `"a"`, `{x:1}`, `[1,2]`, `true` | true | false |
| **error** (bottom)     | missing field, `1&2`, `_|_` | false | true |
| **incomplete**         | `int`, `>5`, `1\|2`, `_`, unresolved ref | *incomplete — propagates, never a bool* | same |

Evidence: `a:1; b:a!=_|_` → `true`; `a:1; b:a==_|_` → `false`; `_|_==_|_` → `true`;
`a:int; b:a!=_|_` → `incomplete value int` (NOT true); `a:_; b:_!=_|_` → `requires concrete
value`. Critical contrast: `(1/0)==2` **propagates the division error** (NOT `false`), so
the test is keyed on the *literal* `_|_`, not on "an operand happens to be bottom".

## The bug + the fix

`evalEq` blanket-propagated bottom (`.bottom,_ => .bottom`), so `concrete != _|_` gave `⊥`
not `true`, and the present-field guard never fired. Fix: intercept `.eq`/`.ne` against the
**syntactic `_|_` literal** (parses to bare `.bottom`) at the `.binary` dispatch in
`evalValueWithFuel`, before generic operand eval — the only point where the literal is
distinguishable from an evaluated bottom, so genuine error-propagation (`(1/0)==2`) stays
intact. New `inductive Definedness`, `classifyDefinedness`, `evalPresenceTest` in
`Eval.lean`.

Verified observably === `cue`: concrete `!=`→true/`==`→false; same-scope present guard
fires (`if f != _|_ {seen:f}` → `seen:3`); absent-field guard drops.

## Tightening flagged, DEFERRED (incomplete/bottom conflation)

kue models a missing-field selection on a *concrete closed struct* as residual `.selector`
(→ incomplete), where `cue` makes it a definite *bottom* (`x.absent == _|_` → true in
`cue`). Guard behavior AGREES (both drop `if x.absent != _|_`); only a bare `x.absent ==
_|_` outside a guard differs. Tightening missing-field-on-closed-struct → bottom is the
principled fix but has broad blast radius across every selection path and does NOT unblock
argocd — deferred. NOT a `cue` divergence (cue is right; kue agrees observably), so no
`cue-divergences.md` entry; recorded in compat-assumptions instead.

## Tests / verify

`presence_test_guard` fixture (+ FixturePorts entry); 12 `PresenceTests` `native_decide`
theorems. Theorem count **663 → 675**. Verify gate green: `lake build`,
`scripts/check-fixtures.sh` ⇒ `fixture pairs ok`, `shellcheck` clean.

## Next blocker — read-only check

`apps/argocd.cue` is NOT on this host (external prod9 tree; remote-fs split). The isolated
real-shape repro still fails and pinpoints the next layer:

`#D: {#x?: string, out: {if Self.#x != _|_ {val: Self.#x}}}; y: #D & {#x:"hi"}` → kue
`out:{}`/`y:⊥`, `cue` `out.val:"hi"`.

This is **NOT the comparison** (now fixed) — it is **lazy field resolution through
definition-meet** (plan **slice 2c**, the live argocd gate): kue eagerly evaluates a
definition's comprehension body + field refs against the definition's own *pre-meet* scope
(`#x: string`), instead of deferring until the meet supplies `#x: "hi"`. Confirmed
orthogonal with no comparison at all — `#D: {#x?: string, out: {if true {val: #x}}}; y: #D
& {#x:"hi"}` → kue `out.val: string`, `cue` `out.val: "hi"`. **Point next at slice 2c.**

## Orchestrator note — AUDIT DUE

This is the **3rd slice since the Phase A/B audit** (memoization → `[...]` embedding →
this). A **two-phase `/ace-audit`** over the recent batch is due next — fold findings into
the plan as fix-slices before pushing further forward.

## Carry forward (re-ranked list + standing constraints)

- Re-ranked next-work: **2c lazy-meet-resolution (HIGH, argocd gate)** → 3 collapse
  `intGe/Gt/Le/Lt → boundConstraint+kind` → 4 base64-out-of-`Json` → 5 test/`testdata`
  reorg → 6 `Field`→`structure` → 7 Linux `cacheRoot` default.
- Alpha cadence: ~1 datestamped alpha/day via `scripts/release.sh` on chakrit's command. NO
  CI / no `.github`; do NOT touch `scripts/release.sh` / `packaging/` / release files.
- External repos (prod9 tree + cue cache) are READ-ONLY reference.
