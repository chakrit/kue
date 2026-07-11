# rfc3339-offset-overrange  (time.Time — RFC3339 offset range-check)

- **Source:** found 2026-07-11 by the STDLIB-TIME Phase-A audit, probing `time.Time`'s
  RFC3339 offset validator against `cue` v0.16.1. kue ACCEPTED `+25:00` (exported the
  string) where cue rejects it. Landed as an ENFORCED fixture (green after the fix in the
  same slice), not quarantined.
- **CUE construct at fault:** an RFC3339 timestamp with an out-of-range numeric offset
  (`2020-01-01T00:00:00+25:00`). The offset hour `25` exceeds cue/Go's accepted maximum.
- **Direction: OVER-ACCEPT** — kue validated a timestamp the reference rejects.
- **Root cause (kue):** `validRFC3339Offset` (`Kue/Time.lean`) did STRUCTURAL-ONLY offset
  validation — any two digits passed the `HH:MM` shape check. cue/Go's `time.Parse` also
  RANGE-checks the offset: hour ≤ 24 and minute ≤ 60 (both inclusive — `+24:60` passes,
  `+25:00` and `+12:61` reject). Fix: bind the two offset fields and enforce
  `offHour ≤ 24 ∧ offMin ≤ 60`.
- **Spec basis:** the CUE spec is silent on the `time` stdlib package (a vendored slice of
  Go's `time`); the spec-silent-non-core tiebreak is cue-compat. The exact boundary was
  pinned against the `cue` v0.16.1 binary: `+24:00`/`+24:60` PASS, `+25:00`/`+24:61`/
  `+12:61`/`+00:61` FAIL. Recorded in `docs/spec/cue-spec-gaps.md` (STDLIB-TIME entry).
