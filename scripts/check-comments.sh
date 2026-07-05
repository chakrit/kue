#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

repo_root="$(cd "${script_dir}/.." && pwd)"
readonly repo_root

readonly src_dir="${repo_root}/Kue"

# "Comments are timeless" (CLAUDE.md § Recurring misalignments): a comment narrates what the
# code IS and why, never the code's own history. History — "the old X", "before/after the fix",
# what the code "formerly" did — belongs in commits and the implementation log, not the source.
#
# Enforced idiom set is deliberately NARROW: these three phrases are essentially always history
# narration in this codebase, so the grep is zero-false-positive. Broader idioms are intentionally
# NOT gated — they collide with timeless English: "used to" == "utilized to" ("Used to decide the
# fallback"), "no longer" states facts ("lengths 55/56 straddle where the length no longer fits"),
# "previously" appears in "previously-computed". A cheap grep cannot separate those from history, so
# the rule there stays reviewer-enforced. Reword a flagged comment to state the CORRECT behavior and,
# where a wrong alternative aids understanding, phrase it as a hypothetical ("a catch-all `_` arm
# would defer") — not as something the code once did.
readonly history_idioms='formerly|before the fix|after the fix|\bthe old\b'

check_no_history_narration() {
  local status=0
  local file
  local hits

  while IFS= read -r file; do
    if hits="$(grep -niE "${history_idioms}" "${file}")"; then
      printf 'timeless-comment violation in %s (history narration — reword to a timeless statement):\n%s\n' \
        "${file#"${repo_root}/"}" "${hits}" >&2
      status=1
    fi
  done < <(find "${src_dir}" -name '*.lean' -type f | sort)

  return "${status}"
}

main() {
  local status=0

  if ! check_no_history_narration; then
    status=1
  fi

  if [[ "${status}" -eq 0 ]]; then
    printf 'comment health ok\n'
  fi

  return "${status}"
}

main "$@"
