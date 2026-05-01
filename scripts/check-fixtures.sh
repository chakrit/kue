#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

repo_root="$(cd "${script_dir}/.." && pwd)"
readonly repo_root

readonly fixture_dir="${repo_root}/testdata/cue"
generated_dir=

cleanup() {
  if [[ -n "${generated_dir}" ]]; then
    rm -rf -- "${generated_dir}"
  fi
}

generate_lean_fixtures() {
  local generated_dir=$1

  if ! lake build Kue.FixturePorts >/dev/null; then
    printf 'failed to build Lean fixture ports\n' >&2
    return 1
  fi

  if ! lake env lean --run "${repo_root}/scripts/write-fixture-ports.lean" "${generated_dir}"; then
    printf 'failed to generate Lean fixture ports\n' >&2
    return 1
  fi
}

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

check_lean_fixture_ports() {
  local generated_dir=$1
  local status=0
  local expected_file
  local generated_file

  for expected_file in "${fixture_dir}"/*.expected; do
    generated_file="${generated_dir}/${expected_file##*/}"

    if [[ ! -f "${generated_file}" ]]; then
      printf 'missing Lean fixture port for %s\n' "${expected_file}" >&2
      status=1
    elif ! diff -u "${expected_file}" "${generated_file}"; then
      status=1
    fi
  done

  for generated_file in "${generated_dir}"/*.expected; do
    expected_file="${fixture_dir}/${generated_file##*/}"

    if [[ ! -f "${expected_file}" ]]; then
      printf 'missing expected file for Lean fixture port %s\n' "${generated_file}" >&2
      status=1
    fi
  done

  return "${status}"
}

main() {
  local status=0
  local cue_file
  local expected_file
  local stem
  local source_file

  shopt -s nullglob

  generated_dir="$(mktemp -d)"
  trap cleanup EXIT

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

  if ! generate_lean_fixtures "${generated_dir}"; then
    status=1
  elif ! check_lean_fixture_ports "${generated_dir}"; then
    status=1
  fi

  if ! check_cue_format; then
    status=1
  fi

  if [[ "${status}" -eq 0 ]]; then
    printf 'fixture pairs ok\n'
  fi

  return "${status}"
}

main "$@"
