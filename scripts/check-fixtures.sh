#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

repo_root="$(cd "${script_dir}/.." && pwd)"
readonly repo_root

readonly fixture_dir="${repo_root}/testdata/cue"
readonly export_dir="${repo_root}/testdata/export"
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

  if [[ -d "${export_dir}" ]] && ! cue fmt --check --files "${export_dir}"; then
    printf 'export fixtures are not parseable or formatted; run cue fmt --files testdata/export\n' >&2
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

check_cli_fixture_outputs() {
  local generated_dir=$1
  local cli_dir="${generated_dir}/cli"
  local kue_exe="${repo_root}/.lake/build/bin/kue"
  local status=0
  local cue_file
  local expected_file
  local output_file
  local stem

  mkdir -p -- "${cli_dir}"

  if ! lake build kue:exe >/dev/null; then
    printf 'failed to build kue executable\n' >&2
    return 1
  fi

  for expected_file in "${fixture_dir}"/*.expected; do
    stem="${expected_file%.expected}"
    if [[ "${stem}" == *.manifest ]]; then
      continue
    fi

    cue_file="${stem}.cue"
    output_file="${cli_dir}/${expected_file##*/}"

    if ! "${kue_exe}" <"${cue_file}" >"${output_file}"; then
      printf 'failed to evaluate CLI fixture %s\n' "${cue_file}" >&2
      status=1
    elif ! diff -u "${expected_file}" "${output_file}"; then
      status=1
    fi
  done

  return "${status}"
}

# Drive the `kue export` CLI mode over every `testdata/export/*.cue` for each committed
# `<stem>.yaml` / `<stem>.json` expected output (byte-for-byte matching `cue export`),
# wholly separate from the internal-format CLI path above so it never perturbs it.
check_export_fixtures() {
  local kue_exe="${repo_root}/.lake/build/bin/kue"
  local status=0
  local expected_file
  local stem
  local cue_file
  local out_format

  if [[ ! -d "${export_dir}" ]]; then
    return 0
  fi

  for expected_file in "${export_dir}"/*.yaml "${export_dir}"/*.json; do
    case "${expected_file}" in
      *.yaml) out_format=yaml; stem="${expected_file%.yaml}" ;;
      *.json) out_format=json; stem="${expected_file%.json}" ;;
      *) continue ;;
    esac

    cue_file="${stem}.cue"
    if [[ ! -f "${cue_file}" ]]; then
      printf 'missing source for export fixture %s\n' "${expected_file}" >&2
      status=1
      continue
    fi

    if ! diff -u "${expected_file}" <("${kue_exe}" export --out "${out_format}" "${cue_file}"); then
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

  if ! check_cli_fixture_outputs "${generated_dir}"; then
    status=1
  fi

  if ! check_export_fixtures; then
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
