# Breadcrumb — let/alias no-shadow validation, FORWARD direction landed (2026-07-04)

## Where things stand

The `let`/alias no-shadow load validation is now enforced in the FORWARD direction. The wild
seed `testdata/wild/let-alias-shadow-not-rejected` is GRADUATED (kue rejects it with cue's
message). `./scripts/check.sh` GREEN; cert-manager canary EMPTY (no over-rejection).

## What landed

- `Kue/Parse.lean`: `parsedFieldsValue` now returns `Except ParseError Value`. At every struct
  scope it runs `checkLetFieldShadow` = `collidableLabels` (quoted-accurate bare/hidden field
  names, parse-time) ∩ `collectLetNames` (struct-member `let`/alias names in the subtree;
  comprehension `let` clauses and `for` vars excluded). Rejects with
  `cannot have both alias and field with name "x" in same scope`. Threaded through all four
  `parsedFieldsValue` call sites.
- `Kue/Tests/ParseTests.lean`: `parseFailsWith` helper + 16 `noshadow_*` probe theorems
  (9 reject, 7 accept-guard). The accept-guards (quoted / definition / dynamic / for-var /
  comprehension-let / siblings / let-over-let) are the over-rejection tripwires.
- Seed graduated; 3 reverse-direction red seeds committed (quarantined).

## cue's exact rule (pinned against v0.16.1)

`let`/alias name `n` collides with a bare/hidden identifier field `n` iff their declaration
scopes are COMPARABLE in the PER-FILE lexical tree (ancestor-or-equal either way). Cousins
never collide; cross-file never collides. Field-side exempt: quoted / `#def` / dynamic /
pattern labels. Binder-side exempt: `for` vars and comprehension `let` CLAUSES. Full probe
matrix in the implementation-log (slice "let/alias no-shadow validation — FORWARD direction").

## Plan-hygiene pass (2026-07-04)

`docs/spec/plan.md` distilled 936 → 490 lines and ground-truthed to current reality (L1–L5
campaign COMPLETE; A1–A8 applied; file-scoped imports + let/alias forward done; both
2026-07-03 audit phases CLEAN; toolchain v4.31.0). The ranked OPEN backlog is now accurate:
(1) let/alias REVERSE (below), (2) B3d-6b, (3) B2-A1, (4) scalar-embed pins + a LOW tail.
`www/index.html` refreshed to match. Next-step pointer UNCHANGED — still the reverse direction.

## Next step (the open fork)

REVERSE direction is an OPEN under-rejection: a `let` in an ENCLOSING scope shadowed by a field
in a NESTED scope is not rejected (red seeds `let-shadowed-by-nested-field`,
`…-by-descendant-field-in-struct`, `…-by-field-in-def-body`; `cue-spec-gaps.md`). To land it
soundly, the descendant field's quoted-accurate name must be checked against ancestor `let`s.
Two routes, both bigger than this slice:
- thread ancestor-`let` names down through the expression parser to each `parsedFieldsValue`, or
- preserve the `quoted` bit on `Value.Field` (1932 construction/match sites) so a post-parse
  Value-tree walk can be quoted-accurate.
Over-rejection is the cardinal danger (cert-manager), so do NOT ship a broad Value-tree walk
that ignores quoted — it fails the `noshadow_quoted_label_accepts` guard.
