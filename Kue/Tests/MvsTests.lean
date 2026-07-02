import Kue.Semver
import Kue.Mvs

--
-- # Semver comparison + MVS solver tests (B3d-6a)
--
-- `native_decide`/`#guard` pins for `Kue.Semver` (Go `x/mod/semver` ordering) and `Kue.Mvs`
-- (Russ Cox MVS). Expected values come from the authoritative sources, not from `cue` output:
-- - semver: `~/go/pkg/mod/golang.org/x/mod@v0.15.0/semver/semver.go` (`Compare` + the doc-comment
-- precedence chain `1.0.0-alpha < … < 1.0.0-rc.1 < 1.0.0`).
-- - MVS: cue v0.16.1 `internal/mod/mvs/{mvs.go,graph.go}` and the diamond worked example from
-- <https://research.swtch.com/vgo-mvs>.
--

namespace Kue
namespace Mvs

open Kue.Registry (ModuleVersion)

-- ## Semver: numeric major/minor/patch ordering

-- Numeric, not lexical: 10 > 2 even though "10" < "2" as strings (compareInt length rule).
theorem semver_minor_numeric : (Semver.compare "v1.2.0" "v1.10.0" < 0) = true := by native_decide
theorem semver_major_numeric : (Semver.compare "v2.0.0" "v10.0.0" < 0) = true := by native_decide
theorem semver_patch_numeric : (Semver.compare "v1.0.2" "v1.0.10" < 0) = true := by native_decide
theorem semver_equal : (Semver.compare "v1.2.3" "v1.2.3" == 0) = true := by native_decide
-- Shorthands: vMAJOR and vMAJOR.MINOR fill in .0 / .0.0.
theorem semver_shorthand_major : (Semver.compare "v1" "v1.0.0" == 0) = true := by native_decide
theorem semver_shorthand_minor : (Semver.compare "v1.2" "v1.2.0" == 0) = true := by native_decide

-- ## Semver: prerelease ordering

-- A prerelease sorts BEFORE the same version without one.
theorem semver_prerelease_before_release :
    (Semver.compare "v1.2.3-rc.1" "v1.2.3" < 0) = true := by native_decide
-- Alphabetic identifier ordering.
theorem semver_prerelease_alpha_beta :
    (Semver.compare "v1.2.3-alpha" "v1.2.3-beta" < 0) = true := by native_decide
-- The full doc-comment precedence chain, pairwise.
theorem semver_chain_alpha_alpha1 :
    (Semver.compare "v1.0.0-alpha" "v1.0.0-alpha.1" < 0) = true := by native_decide
theorem semver_chain_alpha1_alphabeta :
    (Semver.compare "v1.0.0-alpha.1" "v1.0.0-alpha.beta" < 0) = true := by native_decide
theorem semver_chain_alphabeta_beta :
    (Semver.compare "v1.0.0-alpha.beta" "v1.0.0-beta" < 0) = true := by native_decide
theorem semver_chain_beta_beta2 :
    (Semver.compare "v1.0.0-beta" "v1.0.0-beta.2" < 0) = true := by native_decide
-- Numeric identifiers compared numerically, not lexically: beta.2 < beta.11.
theorem semver_chain_beta2_beta11 :
    (Semver.compare "v1.0.0-beta.2" "v1.0.0-beta.11" < 0) = true := by native_decide
theorem semver_chain_beta11_rc1 :
    (Semver.compare "v1.0.0-beta.11" "v1.0.0-rc.1" < 0) = true := by native_decide
theorem semver_chain_rc1_release :
    (Semver.compare "v1.0.0-rc.1" "v1.0.0" < 0) = true := by native_decide
-- Numeric identifier < non-numeric identifier at the same position.
theorem semver_numeric_lt_alpha :
    (Semver.compare "v1.0.0-1" "v1.0.0-alpha" < 0) = true := by native_decide
-- A longer prerelease set (equal prefix) has higher precedence.
theorem semver_longer_prerelease_wins :
    (Semver.compare "v1.0.0-alpha" "v1.0.0-alpha.0" < 0) = true := by native_decide

-- ## Semver: build metadata ignored, validity

-- Build metadata is parsed but does NOT affect precedence.
theorem semver_build_ignored :
    (Semver.compare "v1.2.3+build.1" "v1.2.3+other" == 0) = true := by native_decide
theorem semver_build_vs_none :
    (Semver.compare "v1.2.3+build" "v1.2.3" == 0) = true := by native_decide
-- Invalid < valid; two invalids equal.
theorem semver_invalid_lt_valid :
    (Semver.compare "garbage" "v1.0.0" < 0) = true := by native_decide
theorem semver_two_invalids_equal :
    (Semver.compare "x" "y" == 0) = true := by native_decide
-- Leading-zero major/patch is invalid.
#guard !Semver.isValid "v01.0.0"
#guard !Semver.isValid "v1.0.0-01"
#guard Semver.isValid "v1.0.0-0"
#guard Semver.isValid "v1.2.3-rc.1+build.5"
#guard Semver.isValid "v2"
#guard !Semver.isValid "1.0.0"      -- missing the 'v'
-- Empty prerelease/build segment after its marker is malformed (Go rejects `start == i`).
#guard !Semver.isValid "v1.2.3-"        -- empty prerelease
#guard !Semver.isValid "v1.2.3+"        -- empty build
#guard !Semver.isValid "v1.2.3-alpha+"  -- prerelease then empty build
#guard !Semver.isValid "v1.2.3-a+b+c"   -- two '+' ⇒ malformed build
#guard Semver.isValid "v1.2.3+a-b"      -- build identifier may contain '-'
#guard Semver.isValid "v1.0.0+meta-pre" -- '-' in build is not a prerelease marker
-- maxVersion folds to the greater.
#guard Semver.maxVersion "v1.2.0" "v1.10.0" == "v1.10.0"
#guard Semver.maxVersion "v1.3.0" "v1.2.0" == "v1.3.0"

-- ## MVS: helpers and node constructor

private def mv (path version : String) : ModuleVersion := ⟨path, version⟩

-- ## MVS: the diamond (research.swtch.com/vgo-mvs)
--
-- main → A v1.0.0, B v1.0.0;  A v1.0.0 → C v1.2.0;  B v1.0.0 → C v1.3.0.
-- Max of the two minimums on C ⇒ select C v1.3.0. Build list = main, then A,B,C sorted.

private def diamondGraph : RequirementGraph :=
  [ (mv "main" "v1.0.0", [mv "A" "v1.0.0", mv "B" "v1.0.0"]),
    (mv "A" "v1.0.0", [mv "C" "v1.2.0"]),
    (mv "B" "v1.0.0", [mv "C" "v1.3.0"]) ]

theorem mvs_diamond_selects_max :
    (solve (mv "main" "v1.0.0") diamondGraph
      == [mv "main" "v1.0.0", mv "A" "v1.0.0", mv "B" "v1.0.0", mv "C" "v1.3.0"]) = true := by
  native_decide

-- ## MVS: same module, two minimums of the same major → take the higher

private def twoMinGraph : RequirementGraph :=
  [ (mv "main" "v1.0.0", [mv "X" "v1.1.0", mv "Y" "v1.0.0"]),
    (mv "Y" "v1.0.0", [mv "X" "v1.4.0"]) ]

theorem mvs_two_min_takes_higher :
    (solve (mv "main" "v1.0.0") twoMinGraph
      == [mv "main" "v1.0.0", mv "X" "v1.4.0", mv "Y" "v1.0.0"]) = true := by
  native_decide

-- ## MVS: an "upgrade" — requiring a higher min pulls the selection up

-- main now requires C v1.4.0 directly; it dominates both A's v1.2.0 and B's v1.3.0.
private def upgradeGraph : RequirementGraph :=
  [ (mv "main" "v1.0.0", [mv "A" "v1.0.0", mv "B" "v1.0.0", mv "C" "v1.4.0"]),
    (mv "A" "v1.0.0", [mv "C" "v1.2.0"]),
    (mv "B" "v1.0.0", [mv "C" "v1.3.0"]) ]

theorem mvs_upgrade_dominates :
    (solve (mv "main" "v1.0.0") upgradeGraph
      == [mv "main" "v1.0.0", mv "A" "v1.0.0", mv "B" "v1.0.0", mv "C" "v1.4.0"]) = true := by
  native_decide

-- ## MVS: "downgrade by not requiring" — dropping an edge lowers the selection
--
-- Same modules as the diamond, but B no longer requires C v1.3.0 (its requirement is removed);
-- only A's v1.2.0 remains, so C downgrades to v1.2.0 — no explicit downgrade needed.

private def downgradeGraph : RequirementGraph :=
  [ (mv "main" "v1.0.0", [mv "A" "v1.0.0", mv "B" "v1.0.0"]),
    (mv "A" "v1.0.0", [mv "C" "v1.2.0"]),
    (mv "B" "v1.0.0", []) ]

theorem mvs_downgrade_by_not_requiring :
    (solve (mv "main" "v1.0.0") downgradeGraph
      == [mv "main" "v1.0.0", mv "A" "v1.0.0", mv "B" "v1.0.0", mv "C" "v1.2.0"]) = true := by
  native_decide

-- ## MVS: distinct majors are distinct paths and coexist

-- `m` and `m/v2` are different paths ⇒ both appear, each at its own selected version.
private def majorsGraph : RequirementGraph :=
  [ (mv "main" "v1.0.0", [mv "m" "v1.5.0", mv "m/v2" "v2.1.0"]) ]

theorem mvs_distinct_majors_coexist :
    (solve (mv "main" "v1.0.0") majorsGraph
      == [mv "main" "v1.0.0", mv "m" "v1.5.0", mv "m/v2" "v2.1.0"]) = true := by
  native_decide

-- ## MVS: a cycle in the requirement graph terminates

-- A ⇄ B mutual requirement (legal in MVS); reachability must halt and select both.
private def cycleGraph : RequirementGraph :=
  [ (mv "main" "v1.0.0", [mv "A" "v1.0.0"]),
    (mv "A" "v1.0.0", [mv "B" "v1.0.0"]),
    (mv "B" "v1.0.0", [mv "A" "v1.0.0"]) ]

theorem mvs_cycle_terminates :
    (solve (mv "main" "v1.0.0") cycleGraph
      == [mv "main" "v1.0.0", mv "A" "v1.0.0", mv "B" "v1.0.0"]) = true := by
  native_decide

-- ## MVS: an unreachable module is excluded

-- Z is in the graph as a key but nothing reachable from main requires it ⇒ excluded.
private def unreachableGraph : RequirementGraph :=
  [ (mv "main" "v1.0.0", [mv "A" "v1.0.0"]),
    (mv "A" "v1.0.0", []),
    (mv "Z" "v9.9.9", [mv "A" "v2.0.0"]) ]

theorem mvs_unreachable_excluded :
    (solve (mv "main" "v1.0.0") unreachableGraph
      == [mv "main" "v1.0.0", mv "A" "v1.0.0"]) = true := by
  native_decide

-- ## MVS: empty requirements → just the main module

theorem mvs_empty_just_main :
    (solve (mv "main" "v1.0.0") []
      == [mv "main" "v1.0.0"]) = true := by
  native_decide

-- main pinned even when the graph mentions a higher version of main's own path: the target
-- always wins for its path (`reqs.Max(target, v) == target`).
private def mainPinGraph : RequirementGraph :=
  [ (mv "main" "v1.0.0", [mv "A" "v1.0.0"]),
    (mv "A" "v1.0.0", [mv "main" "v2.0.0"]) ]

theorem mvs_main_path_pinned :
    (solve (mv "main" "v1.0.0") mainPinGraph
      == [mv "main" "v1.0.0", mv "A" "v1.0.0"]) = true := by
  native_decide

-- ## MVS: build-list ordering is path-sorted after the root

-- Out-of-order requirements still produce a path-sorted remainder.
private def orderGraph : RequirementGraph :=
  [ (mv "main" "v1.0.0", [mv "zeta" "v1.0.0", mv "alpha" "v1.0.0", mv "mid" "v1.0.0"]) ]

theorem mvs_remainder_sorted_by_path :
    (solve (mv "main" "v1.0.0") orderGraph
      == [mv "main" "v1.0.0", mv "alpha" "v1.0.0", mv "mid" "v1.0.0", mv "zeta" "v1.0.0"]) = true := by
  native_decide

-- ## MVS: high fan-in / dense graph does NOT truncate (fuel soundness)
--
-- A near-complete graph re-enqueues each node once per parent, so the worklist length far
-- exceeds the distinct-node count. The first fuel bound (`|allNodes|+|targets|+1`) bounded only
-- distinct expansions, not total steps, and SILENTLY DROPPED nodes here. The build list must
-- contain every reachable path.

private def denseNodes : List String := ["A", "B", "C", "D", "E"]
private def denseReqs : List ModuleVersion := denseNodes.map (fun n => mv n "v1.0.0")
private def denseGraph : RequirementGraph :=
  (mv "main" "v1.0.0", denseReqs) :: denseNodes.map (fun n => (mv n "v1.0.0", denseReqs))

theorem mvs_dense_no_truncation :
    (solve (mv "main" "v1.0.0") denseGraph
      == [mv "main" "v1.0.0", mv "A" "v1.0.0", mv "B" "v1.0.0", mv "C" "v1.0.0",
          mv "D" "v1.0.0", mv "E" "v1.0.0"]) = true := by
  native_decide

-- ## Totality pins: only the standard classical axioms, no `sorryAx`/`partial`/custom axiom.

-- `#print axioms` emits to stdout; a regression to `sorryAx` would show here in the build log.
#print axioms Kue.Semver.compare
#print axioms Kue.Mvs.solve


-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @semver_shorthand_minor           -- Semver: numeric major/minor/patch ordering
#check @semver_longer_prerelease_wins    -- Semver: prerelease ordering
#check @semver_two_invalids_equal        -- Semver: build metadata ignored, validity
#check @mvs_diamond_selects_max          -- MVS: the diamond (research.swtch.com/vgo-mvs)
#check @mvs_two_min_takes_higher         -- MVS: same module, two minimums of the same major...
#check @mvs_upgrade_dominates            -- MVS: an "upgrade" — requiring a higher min pulls...
#check @mvs_downgrade_by_not_requiring   -- MVS: "downgrade by not requiring" — dropping an e...
#check @mvs_distinct_majors_coexist      -- MVS: distinct majors are distinct paths and coexist
#check @mvs_cycle_terminates             -- MVS: a cycle in the requirement graph terminates
#check @mvs_unreachable_excluded         -- MVS: an unreachable module is excluded
#check @mvs_main_path_pinned             -- MVS: empty requirements → just the main module
#check @mvs_remainder_sorted_by_path     -- MVS: build-list ordering is path-sorted after the...
#check @mvs_dense_no_truncation          -- MVS: high fan-in / dense graph does NOT truncate...

end Mvs

end Kue
