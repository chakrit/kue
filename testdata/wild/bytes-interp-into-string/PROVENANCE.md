# bytes-interp-into-string

- **Source:** STRING-BYTES-PROBE (2026-07-13 differential probe of the bytes/string
  value family vs cue v0.16.1). The single wrong-value defect the probe surfaced.
- **Defect:** `classifyInterpolationPart` (`Kue/EvalBase.lean`) classified every
  `.prim (.bytes …)` operand as `.incomplete`, so a bytes value interpolated into a
  string literal (`"\(b)"` with `b: 'ab'`) deferred the whole interpolation as an
  unresolved residual; `kue export` then errored "incomplete value" instead of
  rendering.
- **Spec basis:** CUE § Interpolation restricts operands to `bool|string|bytes|number`;
  `bytes` is interpolatable. The enclosing literal kind (double-quoted string) fixes the
  result type and the bytes operand is coerced to its string form (Go `string(bytes)`).
  For valid-UTF-8 byte content the decode is exact.
- **cue:** v0.16.1 — `x: "ab"`, `inline: "p=yz-q"`, `multi: "ab"`.
- **Fix:** `classifyInterpolationPart`'s bytes arm decodes `String.fromUTF8?`; valid
  UTF-8 → `.text`; invalid UTF-8 (unrepresentable as a Lean `String`) still defers —
  cue lossily replaces invalid runes with U+FFFD on JSON export, an obscure edge left
  as a spec-gap (`cue-spec-gaps.md`, `bytes-interp-invalid-utf8`).
