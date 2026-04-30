#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

repo_root="$(cd "${script_dir}/.." && pwd)"
readonly repo_root

readonly fixture_dir="${repo_root}/testdata/cue"

main() {
  local status=0
  local cue_file
  local expected_file
  local stem
  local source_file

  shopt -s nullglob

  for cue_file in "${fixture_dir}"/*.cue; do
    stem="${cue_file%.cue}"
    if [[ ! -f "${stem}.expected" && ! -f "${stem}.manifest.expected" ]]; then
      printf 'missing expected file for %s\n' "${cue_file}" >&2
      status=1
    fi
  done

  for expected_file in "${fixture_dir}"/*.expected; do
    stem="${expected_file%.expected}"
    if [[ "${stem}" == *.manifest ]]; then
      stem="${stem%.manifest}"
    fi

    source_file="${stem}.cue"
    if [[ ! -f "${source_file}" ]]; then
      printf 'missing source fixture for %s\n' "${expected_file}" >&2
      status=1
    fi
  done

  if [[ "${status}" -eq 0 ]]; then
    printf 'fixture pairs ok\n'
  fi

  return "${status}"
}

main "$@"
