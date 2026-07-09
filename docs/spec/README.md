# Spec & architecture

**Current-understanding durable artifacts** — the design of the project and how
it actually fits together: design specs, RFCs, interface contracts, and
architecture / "how it works" overviews. Prose you read to *understand the
system*. Updated in place as understanding evolves; always reflects present
design, not history.

If it's a ruling on a question, that's a decision — `../decisions/`. If it's
third-party lookup detail (their flags, their API), that's `../vendor/`. If it's
research, exploration, or a draft, `../scratch/`.

## Format

One file per subject: `<slug>.md` (no date prefix — describes a thing, not the
moment it was written). Add a status header (`draft`, `accepted`, `superseded`,
`implemented`) so readers can tell whether it still describes current design.
