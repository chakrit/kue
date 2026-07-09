# Guides

**Task-oriented usage docs** — how-to guides and getting-started walkthroughs
for whoever (human or agent) *uses* what this repo produces. Answers "how do I
accomplish X?"

A guide is goal-driven: it walks one real task start to finish. Third-party
facts you keep looking up (a framework, an external CLI) are `../vendor/`.
Explaining how our system fits together, or enumerating our own surface, is
`../spec/`.

## Format

One file per task: `<slug>.md` (no date prefix — a guide describes a task, not a
moment). Keep each guide to one job; link to `../spec/` or `../vendor/` for
exhaustive detail rather than inlining it. Update in place.
