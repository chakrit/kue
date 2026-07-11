# wide-struct-large  (manifest — proves the fix is not a cliff-move)

- **Source:** the anti-workaround guard for `wide-struct-export` (2026-07-11 audit HIGH). The
  naive "fix" for the field-count cliff is to bump `manifestFuel` (100 → larger). That is a
  workaround: it moves the cliff, it does not remove it (a 500-field struct would still fail
  at whatever the new constant minus two is). This 500-field fixture would fail under ANY
  plausible constant bump but passes under the real fix, which decouples the fuel budget from
  field count entirely (fuel bounds nesting DEPTH only, not sibling breadth).
- **CUE construct at fault:** a 500-field flat struct `{ r0: 0, …, r499: 499 }`.
- **Direction: UNDER-ACCEPT.**
- **Root cause (kue):** same as `wide-struct-export` — per-sibling fuel decrement in
  `manifestFieldsWithFuel`, fixed by threading fuel undecremented across siblings.
- **Spec basis:** byte-identical to `cue export --out json` v0.16.1. (5000-field and
  arbitrary counts also pass — the mechanism is now field-count-independent; 500 is committed
  as a representative large guard.)
