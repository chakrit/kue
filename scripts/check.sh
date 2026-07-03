#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

repo_root="$(cd "${script_dir}/.." && pwd)"
readonly repo_root

# Route bare `lake` through the repo ./lake wrapper (CPU cap + nice); see ./lake.
export PATH="${repo_root}:${PATH}"

# The single repo-local verify entrypoint: `lake build`, then every `scripts/check-*.sh`
# gate (glob-discovered so a new gate needs zero wiring here), then `shellcheck scripts/*.sh`.
# Collects all failures instead of stopping at the first, and prints a PASS/FAIL summary.
# Strictly repo-local and clone-portable — no absolute paths, no external repos. The
# cert-manager canary is deliberately NOT part of this aggregator.
main() {
  local status=0
  local failures=()
  local gate
  local name

  cd "${repo_root}"

  if ! lake build; then
    printf 'lake build failed\n' >&2
    status=1
    failures+=("lake build")
  fi

  # `check.sh` has no hyphen, so `check-*.sh` never matches this aggregator itself.
  shopt -s nullglob
  for gate in "${script_dir}"/check-*.sh; do
    name="$(basename -- "${gate}")"
    printf '=== %s ===\n' "${name}"
    if ! bash "${gate}"; then
      printf '%s failed\n' "${name}" >&2
      status=1
      failures+=("${name}")
    fi
  done

  # Shellcheck the gate scripts AND the repo-root ./lake and ./lean build wrappers — the
  # wrappers carry the CPU cap and are shell too, so they rot the same way; the glob can't
  # reach them (no `.sh` extension), so name them.
  printf '=== shellcheck scripts/*.sh + ./lake ./lean ===\n'
  if ! shellcheck "${script_dir}"/*.sh "${repo_root}/lake" "${repo_root}/lean"; then
    printf 'shellcheck failed\n' >&2
    status=1
    failures+=("shellcheck scripts/*.sh ./lake ./lean")
  fi

  if [[ "${status}" -eq 0 ]]; then
    printf 'PASS: all checks green\n'
  else
    printf 'FAIL: %d check(s) failed:\n' "${#failures[@]}" >&2
    for name in "${failures[@]}"; do
      printf '  - %s\n' "${name}" >&2
    done
  fi

  return "${status}"
}

main "$@"
