#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

repo_root="$(cd "${script_dir}/.." && pwd)"
readonly repo_root

readonly tests_dir="${repo_root}/Kue/Tests"
readonly size_cap=1800

# FixturePorts.lean is machine-generated fixture DATA (write-fixture-ports.lean): no section
# headers, no theorems, and legitimately larger than the cap. Every other Kue/Tests/*.lean is
# a hand-authored test module the TEST-HEALTH CONVENTION governs.
readonly generated="FixturePorts.lean"

# Section headers and per-theorem notes must be `--` LINE comments — a block comment left
# unterminated swallows every following declaration until the next stray `-/`, silently
# dropping theorems while the build stays green. A line comment self-terminates at EOL and
# structurally cannot swallow the next declaration.
check_no_block_comments() {
  local status=0
  local file
  local base
  local hits

  while IFS= read -r file; do
    base="$(basename -- "${file}")"
    if [[ "${base}" == "${generated}" ]]; then
      continue
    fi
    if hits="$(grep -nE '^[[:space:]]*/-' "${file}")"; then
      printf 'block comment in %s (use -- line comments):\n%s\n' \
        "${file#"${repo_root}/"}" "${hits}" >&2
      status=1
    fi
  done < <(find "${tests_dir}" -name '*.lean' -type f | sort)

  return "${status}"
}

# Every module that declares named theorems carries an end-of-file coverage tripwire
# (`#check @<last-theorem-per-section>`): a section swallowed by an editing slip makes its
# anchor an unknown identifier, so `#check` fails to ELABORATE — a hard build error rather
# than a silent green build with dead theorems. Modules with only anonymous `example`s or no
# theorems cannot anchor a named `#check`, so the tripwire is required only where a name exists.
check_tripwires() {
  local status=0
  local file
  local base

  while IFS= read -r file; do
    base="$(basename -- "${file}")"
    if [[ "${base}" == "${generated}" ]]; then
      continue
    fi
    if grep -qE '^theorem ' "${file}" && ! grep -q '#check @' "${file}"; then
      # shellcheck disable=SC2016  # `#check @` is literal diagnostic text, not an expansion
      printf 'test module %s has named theorems but no `#check @` coverage tripwire\n' \
        "${file#"${repo_root}/"}" >&2
      status=1
    fi
  done < <(find "${tests_dir}" -name '*.lean' -type f | sort)

  return "${status}"
}

# A test module too large to eyeball hides a swallowed section; split it (the slice-loop
# test-org pass) before it grows past the cap.
check_size_cap() {
  local status=0
  local file
  local base
  local lines

  while IFS= read -r file; do
    base="$(basename -- "${file}")"
    if [[ "${base}" == "${generated}" ]]; then
      continue
    fi
    lines="$(wc -l <"${file}")"
    if (( lines > size_cap )); then
      printf 'test module %s is %s lines (cap %s); split it\n' \
        "${file#"${repo_root}/"}" "${lines}" "${size_cap}" >&2
      status=1
    fi
  done < <(find "${tests_dir}" -name '*.lean' -type f | sort)

  return "${status}"
}

main() {
  local status=0

  if ! check_no_block_comments; then
    status=1
  fi

  if ! check_tripwires; then
    status=1
  fi

  if ! check_size_cap; then
    status=1
  fi

  if [[ "${status}" -eq 0 ]]; then
    printf 'test health ok\n'
  fi

  return "${status}"
}

main "$@"
