# GDA-FLOAT-RENDER — landed 2026-07-05

## What

Floats render through CUE's canonical General-Decimal-Arithmetic `to-scientific-string`
instead of verbatim source `text`. Byte-identical to `cue` v0.16.1 across JSON, YAML, and
cue-native export on the full matrix + edges.

- `Value.lean`: `floatApdForm` (text → apd `(negative, coefficient, exponent)`),
  `renderFloatApd` (GDA to-scientific-string), `renderFloatText style text` (entrypoint),
  `FloatRenderStyle` + `jsonFloatStyle`/`yamlFloatStyle`/`cueFloatStyle`.
- Wired: `Format.formatPrim` (cue-native), `Json.manifestPrimToJson`, `Yaml.yamlScalarPrim`.

## The false premise (why this matters for the next float slice)

The plan said "render GDA on the exact `DecimalValue`". FALSE — a normalized `DecimalValue`
(non-negative `scale`) multiplies a positive exponent into the coefficient, so `1e2` and
`1.00e2` share `{100,0}` yet must render `1E+2` vs `100`, and `1e40` would render PLAIN not
`1E+40`. Rendering derives the apd form from the retained `text` (0e's round-trip anchor) —
the ONLY faithful source. Any future float-render work builds on `text`, not `DecimalValue`.

## Per-surface rules (all mirror cue — spec-silent → cue-compat)

| surface     | exp letter | whole float |
|-------------|------------|-------------|
| JSON        | `E`        | bare (`100`)   |
| YAML        | `E`        | `.` (`100.`)   |
| cue-native  | `e`        | `.0` (`100.0`) |

Small-exp expansion (`1e-2`→`0.01`), plain/scientific boundary at adjusted-exp `≥ −6`
(`1e-6`→`0.000001`, `1e-7`→`1E-7`), collapse (`1.00e2`→`100`/`100.0`), `-0.0`→`0.0`.

## Negative zero

Normalized to `0.0` on render (lattice-consistency: `-0.0 == 0.0`). Matches cue on literal
`-0.0`; DIVERGES from cue's arithmetic `0.0 * -1`→`-0.0` (cue does NOT uniformly normalize
export zeros — the plan's premise was wrong). Recorded in `cue-divergences.md`.

## Verify

`./scripts/check.sh` GREEN; cert-manager canary byte-identical (no float literal in it hits
the changed rendering). 4 GDA `native_decide` theorems in `FloatTests.lean`; fixtures
`testdata/export/float_render_gda.*` + `testdata/cue/numeric/float_gda_render.expected`.
Spec gap recorded (FLOAT OUTPUT FORM, `cue-spec-gaps.md`).

## Next

Backlog per plan.md ranked OPEN: BYTES-SLICE-MISSING, BYTE-INTERPOLATION,
BUILTIN-IMPORT-LENIENCY, B3d-6b (network-gated). Two-phase audit window: last audit was
batch-5 (ARCH-QUOTED-STRIP + PRIM-FLOAT-PARSED); this is 1 slice past it (GDA-FLOAT-RENDER) —
audit DUE after 1–2 more slices.
