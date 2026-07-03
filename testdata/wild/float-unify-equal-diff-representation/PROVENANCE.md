# float-unify-equal-diff-representation  (numeric lattice — meet on floats)

- **Source:** found 2026-07-04 by the numeric/decimal conformance probe (bounded
  divergence hunt over numeric literals, formatting, arithmetic, and stdlib builtins).
  Not from a prod9 export — a directed probe of `Prim` unification. Landed as an ENFORCED
  fixture (green after the fix in the same slice), not quarantined.
- **CUE construct at fault:** unifying two float literals that denote the SAME value but
  are written differently — trailing zeros (`1.0 & 1.00`), scale (`0.10 & 0.1`), or
  scientific-vs-decimal (`100.0 & 1e2`).
- **Direction: SOUNDNESS / UNDER-ACCEPT** — kue reported a primitive conflict (bottom)
  where cue and the spec yield the value. Self-inconsistent: kue's `==` already returns
  `true` for `1.0 == 1.00`, so `&` bottoming on the same pair contradicted its own equality.
- **Root cause (kue):** `meetPrim` (`Kue/Lattice.lean`) compared the two `Prim`s
  structurally (`left = right`), so two `.float` carrying distinct strings were read as
  distinct values. Fix: `primsUnifyEqual` compares float-vs-float by exact base-10
  rational value (`parseDecimalText` + `decimalEqValues`), keeping the LEFT operand when
  equal (matching cue). All other prim kinds stay structural; int-vs-float stays a type
  conflict.
- **Spec basis:** meet is idempotent on the numeric lattice — unifying two equal values
  yields that value, never bottom. `cue` v0.16.1 renders each case as its left operand
  (`1.0`, `0.10`, `1.5`, `100.0`) and is correct (NOT a cue bug). The pinned `.expected`
  is kue's post-fix JSON, value-identical to cue.
