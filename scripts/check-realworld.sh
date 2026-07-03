#!/usr/bin/env bash
set -euo pipefail

# Drive `kue export --out json` over each self-contained, sanitized real-world fixture under
# testdata/realworld/<name>/. Every fixture DIRECTORY ships a `<name>.cue` (no external
# imports, no registry, no private dependency) paired with a committed `<name>.expected`
# holding the spec-adjudicated JSON the export must match byte-for-byte. A dir missing either
# half FAILS the gate loudly so a fixture can never silently drop from the suite.
#
# The `.expected` is regenerated from the SANITIZED source via the kue binary (spec is
# authority — where kue and `cue` disagree only on non-mandated field ORDER, kue's
# declaration-order rendering is the ratified reference; see cue-spec-gaps.md). Auto-discovered
# by the top-level check glob; repo-local only, no external paths.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

repo_root="$(cd "${script_dir}/.." && pwd)"
readonly repo_root

# Route bare `lake` through the repo ./lake wrapper (CPU cap + nice); see ./lake.
export PATH="${repo_root}:${PATH}"

readonly realworld_dir="${repo_root}/testdata/realworld"
readonly kue_exe="${repo_root}/.lake/build/bin/kue"

main() {
  local status=0
  local dir
  local name
  local cue_file
  local expected_file
  local output_file

  if [[ ! -d "${realworld_dir}" ]]; then
    return 0
  fi

  if [[ ! -x "${kue_exe}" ]]; then
    if ! lake build kue:exe >/dev/null; then
      printf 'failed to build kue executable\n' >&2
      return 1
    fi
  fi

  shopt -s nullglob

  for dir in "${realworld_dir}"/*/; do
    name="$(basename -- "${dir}")"
    cue_file="${dir}${name}.cue"
    expected_file="${dir}${name}.expected"

    if [[ ! -f "${cue_file}" ]]; then
      printf 'realworld fixture %s has no %s.cue\n' "${dir#"${repo_root}/"}" "${name}" >&2
      status=1
      continue
    fi

    if [[ ! -f "${expected_file}" ]]; then
      printf 'realworld fixture %s has no %s.expected\n' "${dir#"${repo_root}/"}" "${name}" >&2
      status=1
      continue
    fi

    output_file="$(mktemp)"
    if ! "${kue_exe}" export --out json "${cue_file}" >"${output_file}"; then
      printf 'realworld fixture %s: kue export exited non-zero\n' "${cue_file#"${repo_root}/"}" >&2
      status=1
    elif ! diff -u "${expected_file}" "${output_file}"; then
      status=1
    fi
    rm -f -- "${output_file}"
  done

  if [[ "${status}" -eq 0 ]]; then
    printf 'realworld fixtures ok\n'
  fi

  return "${status}"
}

main "$@"
