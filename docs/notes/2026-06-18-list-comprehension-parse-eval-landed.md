# START HERE — list-comprehension-parse-eval LANDED (audit #9 finding 1 cleared)

Supersedes `2026-06-18-f1-default-mark-algebra-landed.md`. Build 86 jobs green, fixtures
byte-identical (+7 new pairs), shellcheck clean. Pushed to `main`.

## What landed — list comprehensions + scalar struct-embedding collapse

List comprehensions (`[for x in xs {…}]`, `[if cond {…}]`, `[for k, v in m {…}]`) were a HARD
PARSE ERROR (audit #9 finding 1, `9915d21` — HIGH basic-case gap). Now the full LIST surface works
cue v0.16.1-exact. Required a root prerequisite fix first: scalar struct-embedding collapse.

- **Scalar embedding collapse (`Lattice.lean`).** A list-comp body `{x}` is a struct embedding a
  scalar, which CUE collapses to the scalar (`{5}`→`5`, `[{5},{6}]`→`[5,6]`); kue gave `bottom`.
  Extended the two `.struct, …` `meet` arms: a struct with no output field + no decls met with a
  terminal value (`collapsesToScalarEmbed`: `prim`/`kind`/`notPrim`/`stringRegex`/`boundConstraint`)
  IS that value. Closures/conj stay inert. This ALSO fixes `{5}`, `[{5},{6}]` outside comprehensions.
- **AST (`Value.lean`).** New `listComprehension (clauses) (body)` node, stored as a list ITEM,
  REUSING the existing `Clause Value` chain (one clause representation, two body contexts). Body is
  the brace-block VALUE yielded as one element per innermost iteration.
- **Parser (`Parse.lean`).** `parseListItems` dispatches `for`/`if` head → `parseListComprehension`,
  reusing `parseClause`/`parseComprehensionClauses` (the struct form's machinery).
- **Resolve (`Resolve.lean`).** Added `.listComprehension` arm (mirrors `.comprehension`). THE
  load-bearing wiring — without it source/guard/body/loop-var refs were never resolved to `.refId`
  (catch-all silently passed `.ref` through) and eval bottomed. This was the bug that made the first
  build "compile but return bottom".
- **Eval (`Eval.lean`).** `.list`/`.listTail` flatten via `evalListItemsWithFuel`; each list-comp
  expands via `expandListClausesWithFuel` (collects body VALUES, not fields). New `fuel=0` base
  BUMPS `truncCount` (audit #6 saturation invariant — uncounted truncation corrupts via `satCache`).
- **Totality:** `.listComprehension` arms added to `Format`/`Manifest`/`meetCore`/`valueTag`.

### Tests
7 fixture pairs (`comprehensions/list_comprehension_{for,for_index,for_kv,guard_for,nested,mixed}`,
`structs/scalar_embedding_collapse`) + `FixturePorts`. 18 `native_decide` pins (11 list-comp
behavioral, 5 scalar-embedding, 2 fuel-truncation/saturation guards on the NEW path). Oracle: full
surface byte-matches `cue` in JSON+YAML (26/26 across 13 cases).

### Verify
86 jobs green, `fixture pairs ok` (zero drift, existing fixtures byte-unchanged), shellcheck clean.

## Real-app re-probe (honest)
- **cert-manager: NO regression.** Content-identical to cue (`jq -S`), modulo tracked field-order
  #3, ~28s single-pass drop-in. (My scalar-collapse fires only on no-output-field structs;
  cert-manager's structs have output fields, so it never triggers.)
- **argocd: blocker NOT moved.** Still bottoms (~92s) on the SAME link-2 STRUCT-comp narrowing
  (`for k,v in Self.#data` into an embedded default arm) — a struct form, orthogonal to this LIST
  slice. BUT: list comprehensions in transitive deps (stage9, rabbitmq, plane) now PARSE cleanly (a
  class of parse errors eliminated repo-wide), and the link-3 list-guard shape (`[if #a != _|_
  {name: #a}]` with use-site narrowing) is byte-exact in ISOLATION. Link 3's language capability is
  in place; it is just not independently reachable while argocd bottoms earlier on link 2.

## NEXT STEP — backlog (in order)

The argocd chain's live correctness link is unchanged: **link 2 (`argocd-secret-data`)** is the
next correctness slice. Narrowing must flow INTO an embedded default arm before its `for k,v in
Self.#data` STRUCT comprehension expands (repro `w3` in `2026-06-18-argocd-disjsel-chain-landed.md`).
This is the deep one that actually unblocks argocd (and would then make link 3 reachable).

Other parked items:
1. **`argocd-secret-data` (link 2, struct-comp narrowing into embedded default arm)** — DEEP, the
   live argocd blocker. Highest correctness value.
2. **`truncate-primitive` soundness hardening (F-B1)** — owed soundness item in `Eval.lean`.
3. **Regex extraction (R3) / EvalOps extraction (R1)** — parked cleanup, parallel-safe.
4. **Field-ordering parity #3 (DEEP)** — per-`Field` provenance through meet/manifest for byte-exact
   cue field order. The cert-manager/argocd raw-diff is THIS (content already matches via `jq -S`).
5. **Test/fixture-organization slice** — when Phase B flags it.

## Two-phase audit due
This is the 1st slice since audit #9 (the F1/argocd-1 Phase A + the closure/fuel Phase B). Two more
slices until the next 2–3-slice audit mark. A code-quality audit should check the scalar-embedding
collapse rule (does `collapsesToScalarEmbed`'s allow-list miss any terminal value cue collapses? is
the lossless-only restriction sound?) and the list-comp eval's fuel threading.
