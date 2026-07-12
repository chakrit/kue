# def-flatten-closedness-disj-open-arm

- **Source:** DEF-FLATTEN-CLOSEDNESS-DISJ over-close guard (2026-07-13).
- **Role:** pins the second direction of the fix — a disjunction arm with an explicit
  `...` tail must STAY OPEN through the distribute-and-close. Closing each arm to its own
  declared fields UNION the arm's openness leaves a `...`-arm open (admits extras) while a
  bare (no-`...`) arm closes. Prevents a future over-close regression that would reject a
  legitimately-open arm.
- **cue:** v0.16.1 ⇒ `{y: {a:1, b:2, d:4}}`. kue after fix ⇒ same.
