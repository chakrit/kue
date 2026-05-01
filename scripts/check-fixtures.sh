#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

repo_root="$(cd "${script_dir}/.." && pwd)"
readonly repo_root

readonly fixture_dir="${repo_root}/testdata/cue"

check_cue_format() {
  if ! command -v cue >/dev/null 2>&1; then
    printf 'cue command not found; cannot validate CUE fixture syntax\n' >&2
    return 1
  fi

  if ! cue fmt --check --files "${fixture_dir}"; then
    printf 'CUE fixtures are not parseable or formatted; run cue fmt --files testdata/cue\n' >&2
    return 1
  fi
}

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

  if ! check_cue_format; then
    status=1
  fi

  if [[ "${status}" -eq 0 ]]; then
    printf 'fixture pairs ok\n'
  fi

  return "${status}"
}

main "$@"
