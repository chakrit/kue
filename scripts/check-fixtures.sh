#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

repo_root="$(cd "${script_dir}/.." && pwd)"
readonly repo_root

# Route bare `lake` through the repo ./lake wrapper (CPU cap + nice); see ./lake.
export PATH="${repo_root}:${PATH}"

readonly fixture_dir="${repo_root}/testdata/cue"
readonly export_dir="${repo_root}/testdata/export"
readonly module_dir="${repo_root}/testdata/modules"
readonly wild_dir="${repo_root}/testdata/wild"
readonly ocifetch_dir="${repo_root}/testdata/ocifetch"
readonly zip_dir="${repo_root}/testdata/zip"
generated_dir=

cleanup() {
  if [[ -n "${generated_dir}" ]]; then
    rm -rf -- "${generated_dir}"
  fi
}

generate_lean_fixtures() {
  local generated_dir=$1

  if ! lake build Kue.Tests.FixturePorts >/dev/null; then
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

  if [[ -d "${module_dir}" ]] && ! cue fmt --check --files "${module_dir}"; then
    printf 'module fixtures are not parseable or formatted; run cue fmt --files testdata/modules\n' >&2
    return 1
  fi
}

check_lean_fixture_ports() {
  local generated_dir=$1
  local status=0
  local expected_file
  local generated_file

  while IFS= read -r expected_file; do
    generated_file="${generated_dir}/${expected_file#"${fixture_dir}/"}"

    if [[ ! -f "${generated_file}" ]]; then
      printf 'missing Lean fixture port for %s\n' "${expected_file}" >&2
      status=1
    elif ! diff -u "${expected_file}" "${generated_file}"; then
      status=1
    fi
  done < <(find "${fixture_dir}" -name '*.expected' -type f | sort)

  while IFS= read -r generated_file; do
    expected_file="${fixture_dir}/${generated_file#"${generated_dir}/"}"

    if [[ ! -f "${expected_file}" ]]; then
      printf 'missing expected file for Lean fixture port %s\n' "${generated_file}" >&2
      status=1
    fi
  done < <(find "${generated_dir}" -name '*.expected' -type f | sort)

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

  while IFS= read -r expected_file; do
    stem="${expected_file%.expected}"
    if [[ "${stem}" == *.manifest ]]; then
      continue
    fi

    cue_file="${stem}.cue"
    output_file="${cli_dir}/${expected_file#"${fixture_dir}/"}"
    mkdir -p -- "$(dirname -- "${output_file}")"

    if ! "${kue_exe}" eval <"${cue_file}" >"${output_file}"; then
      printf 'failed to evaluate CLI fixture %s\n' "${cue_file}" >&2
      status=1
    elif ! diff -u "${expected_file}" "${output_file}"; then
      status=1
    fi
  done < <(find "${fixture_dir}" -name '*.expected' -type f | sort)

  return "${status}"
}

# Drive the `kue export` CLI mode over every `testdata/export/*.cue` for each committed
# `<stem>.yaml` / `<stem>.json` expected output (byte-for-byte matching `cue export`),
# wholly separate from the internal-format CLI path above so it never perturbs it.
#
# A fixture stem may carry a sidecar `<stem>.args` file (one extra `kue export` argument
# per line) — e.g. an `-e` field-path selector. Its args are passed before `--out` and the
# source file, so the committed `<stem>.json`/`<stem>.yaml` must be the
# `cue export <args> --out <fmt> <file>` oracle output. Stems without `.args` run unchanged.
check_export_fixtures() {
  local kue_exe="${repo_root}/.lake/build/bin/kue"
  local status=0
  local expected_file
  local stem
  local cue_file
  local out_format
  local args_file
  local extra_args
  local arg

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

    extra_args=()
    args_file="${stem}.args"
    if [[ -f "${args_file}" ]]; then
      while IFS= read -r arg; do
        [[ -z "${arg}" ]] && continue
        extra_args+=("${arg}")
      done <"${args_file}"
    fi

    if ! diff -u "${expected_file}" \
      <("${kue_exe}" export ${extra_args[@]+"${extra_args[@]}"} --out "${out_format}" "${cue_file}"); then
      status=1
    fi
  done

  return "${status}"
}

# Drive `kue export --out json` over each wild-caught regression under
# testdata/wild/<slug>/. Every fixture DIRECTORY is enumerated and must ship a `<slug>.cue`
# repro plus exactly one expectation: `<slug>.expected` (spec-adjudicated JSON the export must
# match on exit 0) or `<slug>.expected.err` (a substring the failing export's stderr must
# contain, exit non-zero — pinning a spec-correct BOTTOM). A dir missing either half, or
# shipping both expectation forms, FAILS the gate loudly — a typo'd/absent expected file can
# never silently drop a fixture from the suite.
#
# A `<slug>/.known-red` marker QUARANTINES a captured-but-unfixed case: its repro is committed
# (so the next slice has its red seed) but it does not yet pass, so it is reported and SKIPPED
# from the green gate rather than failing the whole suite. The shape requirement (cue file +
# expectation present) still applies to quarantined dirs. Deleting the marker (when the fix
# lands) re-arms it as a permanent guard.
check_wild_fixtures() {
  local kue_exe="${repo_root}/.lake/build/bin/kue"
  local status=0
  local dir
  local slug
  local cue_file
  local expected_file
  local err_file
  local output_file
  local stderr_output

  if [[ ! -d "${wild_dir}" ]]; then
    return 0
  fi

  for dir in "${wild_dir}"/*/; do
    slug="$(basename -- "${dir}")"
    cue_file="${dir}${slug}.cue"
    expected_file="${dir}${slug}.expected"
    err_file="${dir}${slug}.expected.err"

    if [[ ! -f "${cue_file}" ]]; then
      printf 'wild fixture %s has no %s.cue\n' "${dir#"${repo_root}/"}" "${slug}" >&2
      status=1
      continue
    fi

    if [[ -f "${expected_file}" && -f "${err_file}" ]]; then
      printf 'wild fixture %s has both %s.expected and %s.expected.err; pick one\n' \
        "${dir#"${repo_root}/"}" "${slug}" "${slug}" >&2
      status=1
      continue
    fi

    if [[ ! -f "${expected_file}" && ! -f "${err_file}" ]]; then
      printf 'wild fixture %s has neither %s.expected nor %s.expected.err\n' \
        "${dir#"${repo_root}/"}" "${slug}" "${slug}" >&2
      status=1
      continue
    fi

    # A quarantined (.known-red) fixture is EXPECTED to fail: while it still fails it is
    # reported and skipped. But if it now PASSES (the bug got fixed en passant), the gate
    # HARD-FAILS — the seed must graduate in the slice that fixed it, not linger quarantined.
    local known_red=0
    if [[ -f "${dir}.known-red" ]]; then
      known_red=1
    fi

    local passed=1
    if [[ -f "${expected_file}" ]]; then
      output_file="$(mktemp)"
      if ! "${kue_exe}" export --out json "${cue_file}" >"${output_file}"; then
        passed=0
        if [[ "${known_red}" -eq 0 ]]; then
          printf 'wild fixture %s: kue export exited non-zero\n' "${cue_file#"${repo_root}/"}" >&2
        fi
      elif ! diff -u "${expected_file}" "${output_file}" >/dev/null; then
        passed=0
        if [[ "${known_red}" -eq 0 ]]; then
          diff -u "${expected_file}" "${output_file}" || true
        fi
      fi
      rm -f -- "${output_file}"
    else
      if stderr_output="$("${kue_exe}" export --out json "${cue_file}" 2>&1 >/dev/null)"; then
        passed=0
        if [[ "${known_red}" -eq 0 ]]; then
          printf 'wild fixture %s expected an error but succeeded\n' "${cue_file#"${repo_root}/"}" >&2
        fi
      elif [[ "${stderr_output}" != *"$(cat "${err_file}")"* ]]; then
        passed=0
        if [[ "${known_red}" -eq 0 ]]; then
          printf 'wild fixture %s error mismatch: got %q\n' \
            "${cue_file#"${repo_root}/"}" "${stderr_output}" >&2
        fi
      fi
    fi

    if [[ "${known_red}" -eq 1 ]]; then
      if [[ "${passed}" -eq 1 ]]; then
        printf 'known-red %s now passes — remove .known-red to enforce it\n' "${slug}" >&2
        status=1
      else
        printf 'wild fixture %s is QUARANTINED (.known-red) — captured, not yet fixed; skipping gate\n' \
          "${cue_file#"${repo_root}/"}" >&2
      fi
    elif [[ "${passed}" -eq 0 ]]; then
      status=1
    fi
  done

  return "${status}"
}

# Diff `kue export --out json <subpath>` (run from inside `dir`, so the path arg is
# relative and the module-root walk must climb from the file's directory) against the
# committed oracle output `expected.<sanitized-subpath>`, where the subpath's `/` become
# `-` and the `.cue` suffix is dropped (`sub/main.cue` -> `expected.sub-main`). Pins the
# cue.mod discovery from a sub-directory path arg. Prints any diff; returns non-zero on
# mismatch.
#
# A `<dir>/.known-red` marker QUARANTINES the fixture's subpath diffs (mirroring the wild
# gate): a still-failing subpath is reported and SKIPPED from the green gate; a subpath that
# now PASSES hard-fails, so a red seed must graduate in the slice that fixes it, not linger.
check_module_subpaths() {
  local dir=$1
  local status=0
  local subpath
  local sanitized
  local expected_file
  local known_red=0
  local passed

  if [[ -f "${dir}.known-red" ]]; then
    known_red=1
  fi

  while IFS= read -r subpath; do
    [[ -z "${subpath}" ]] && continue
    sanitized="${subpath%.cue}"
    sanitized="${sanitized//\//-}"
    expected_file="${dir}expected.${sanitized}"

    if [[ ! -f "${expected_file}" ]]; then
      printf 'module subpath fixture %s missing %s\n' "${dir}" "${expected_file}" >&2
      status=1
      continue
    fi

    passed=1
    if ! diff -u "${expected_file}" \
      <(cd "${dir}" && "${kue_exe}" export --out json "${subpath}") >/dev/null 2>&1; then
      passed=0
    fi

    if [[ "${known_red}" -eq 1 ]]; then
      if [[ "${passed}" -eq 1 ]]; then
        printf 'known-red module fixture %s subpath %s now passes — remove .known-red to enforce it\n' \
          "${dir#"${repo_root}/"}" "${subpath}" >&2
        status=1
      else
        printf 'module fixture %s subpath %s is QUARANTINED (.known-red) — captured, not yet fixed; skipping gate\n' \
          "${dir#"${repo_root}/"}" "${subpath}" >&2
      fi
    elif [[ "${passed}" -eq 0 ]]; then
      diff -u "${expected_file}" \
        <(cd "${dir}" && "${kue_exe}" export --out json "${subpath}") || true
      status=1
    fi
  done <"${dir}subpaths"

  return "${status}"
}

# Drive the import-aware loader over each multi-file module fixture under
# testdata/modules/<name>/. A success fixture ships an `expected` file holding the
# `cue export`-matching JSON for `kue export --out json <dir>/main.cue`; an error fixture
# ships `expected.err` holding a substring the failing run's stderr must contain (loader
# errors — cycles, missing dirs, unknown/absent dependency, package-name conflicts).
#
# A fixture that ships a `subpaths` file (one relative path per line) is a sub-directory
# path-arg fixture instead: each subpath is exported from inside the fixture dir and diffed
# against its `expected.<sanitized>` oracle output (see `check_module_subpaths`). Such a
# fixture has no root `main.cue`. A `.known-red` marker there quarantines its subpath diffs.
#
# A cross-module fixture may carry a self-contained `_cache/` directory holding the
# extracted dependency modules in the cue cache layout (mod/extract/<modpath>@<ver>/). When
# present it is pointed at via CUE_CACHE_DIR so resolution is deterministic and never reads
# the user's real cache — for both kue and the oracle. Additive: leaves the single-file and
# export stages untouched.
check_module_fixtures() {
  local kue_exe="${repo_root}/.lake/build/bin/kue"
  local status=0
  local dir
  local main_file
  local stderr_output

  if [[ ! -d "${module_dir}" ]]; then
    return 0
  fi

  for dir in "${module_dir}"/*/; do
    if [[ -f "${dir}subpaths" ]]; then
      if ! check_module_subpaths "${dir}"; then
        status=1
      fi
      continue
    fi

    main_file="${dir}main.cue"
    if [[ ! -f "${main_file}" ]]; then
      printf 'module fixture %s has no main.cue\n' "${dir}" >&2
      status=1
      continue
    fi

    # A fixture's committed `_cache/` overrides the cue cache so resolution stays
    # self-contained; absent it, run unchanged with the ambient environment.
    run_kue() {
      local cache_dir
      if [[ -d "${dir}_cache" ]]; then
        cache_dir="$(cd "${dir}_cache" && pwd)"
        CUE_CACHE_DIR="${cache_dir}" "${kue_exe}" "$@"
      else
        "${kue_exe}" "$@"
      fi
    }

    if [[ -f "${dir}expected" ]]; then
      if ! diff -u "${dir}expected" <(run_kue export --out json "${main_file}"); then
        status=1
      fi
    elif [[ -f "${dir}expected.err" ]]; then
      if stderr_output="$(run_kue "${main_file}" 2>&1 >/dev/null)"; then
        printf 'module fixture %s expected an error but succeeded\n' "${dir}" >&2
        status=1
      elif [[ "${stderr_output}" != *"$(cat "${dir}expected.err")"* ]]; then
        printf 'module fixture %s error mismatch: got %q\n' "${dir}" "${stderr_output}" >&2
        status=1
      fi
    else
      printf 'module fixture %s has neither expected nor expected.err\n' "${dir}" >&2
      status=1
    fi
  done

  return "${status}"
}

# Exercise the subcommand/help/version CLI surface added alongside the eval/export paths.
# Purely additive: asserts exit codes and key output substrings without touching the
# byte-exact fixture stages above. `version` must print the `Kue.version` constant; the
# error cases (unknown flag, bad --out value) must exit with the usage code and write to
# stderr.
check_cli_behavior() {
  local kue_exe="${repo_root}/.lake/build/bin/kue"
  local status=0
  local output

  # `kue --help` and `kue help` exit 0 and list the subcommands.
  if ! output="$("${kue_exe}" --help)"; then
    printf 'kue --help exited non-zero\n' >&2
    status=1
  elif [[ "${output}" != *"eval"* || "${output}" != *"export"* || "${output}" != *"version"* ]]; then
    printf 'kue --help is missing a subcommand in its listing\n' >&2
    status=1
  fi

  # Bare `kue` with no arguments prints the top-level help on exit 0 — it must NOT hang on
  # stdin (the regression guard against the original interactive-freeze bug) nor dump the
  # old smoke demo. Closed stdin proves it never blocks reading input.
  if ! output="$("${kue_exe}" </dev/null)"; then
    printf 'bare kue (no args) exited non-zero\n' >&2
    status=1
  elif [[ "${output}" != *"Commands:"* ]]; then
    printf 'bare kue (no args) did not print the help Commands listing\n' >&2
    status=1
  fi

  # `kue eval` on empty stdin evaluates the empty struct (matching `cue eval -`): no output,
  # exit 0 — and specifically NOT the removed smoke demo.
  if ! output="$("${kue_exe}" eval </dev/null)"; then
    printf 'kue eval on empty stdin exited non-zero\n' >&2
    status=1
  elif [[ -n "${output}" ]]; then
    printf 'kue eval on empty stdin printed output (expected empty): %q\n' "${output}" >&2
    status=1
  fi

  # `kue version` and `kue --version` print the version constant on exit 0.
  if ! output="$("${kue_exe}" version)"; then
    printf 'kue version exited non-zero\n' >&2
    status=1
  elif [[ -z "${output}" ]]; then
    printf 'kue version printed nothing\n' >&2
    status=1
  fi
  if [[ "$("${kue_exe}" --version)" != "${output}" ]]; then
    printf 'kue --version and kue version disagree\n' >&2
    status=1
  fi

  # The bare `kue <file>` shorthand must agree byte-for-byte with the explicit
  # `kue eval <file>` subcommand on a representative fixture (the internal-format default).
  # Both take the file as a positional arg, so the no-args→help change leaves them intact.
  local sample_cue
  sample_cue="${fixture_dir}/numeric/additive_expressions.cue"
  if [[ ! -f "${sample_cue}" ]]; then
    printf 'CLI behavior sample fixture %s is missing\n' "${sample_cue}" >&2
    status=1
  elif ! diff -u <("${kue_exe}" "${sample_cue}") <("${kue_exe}" eval "${sample_cue}"); then
    printf 'kue <file> shorthand disagrees with kue eval <file> on %s\n' "${sample_cue}" >&2
    status=1
  fi

  # Unknown top-level flag → usage error (exit 2) with a stderr diagnostic.
  if "${kue_exe}" --bogus >/dev/null 2>&1; then
    printf 'kue --bogus unexpectedly succeeded\n' >&2
    status=1
  elif [[ "$("${kue_exe}" --bogus 2>&1 1>/dev/null)" != *"unknown flag"* ]]; then
    printf 'kue --bogus did not report an unknown flag on stderr\n' >&2
    status=1
  fi

  # Bad `--out` value → usage error with a stderr diagnostic.
  if "${kue_exe}" export --out bogus >/dev/null 2>&1; then
    printf 'kue export --out bogus unexpectedly succeeded\n' >&2
    status=1
  elif [[ "$("${kue_exe}" export --out bogus 2>&1 1>/dev/null)" != *"unsupported --out format"* ]]; then
    printf 'kue export --out bogus did not report a format error on stderr\n' >&2
    status=1
  fi

  # `-e` selecting a missing field → eval error (exit 1) with a "not found" diagnostic.
  local select_fixture="${export_dir}/select_common.cue"
  if [[ -f "${select_fixture}" ]]; then
    if "${kue_exe}" export -e nope_missing "${select_fixture}" >/dev/null 2>&1; then
      printf 'kue export -e nope_missing unexpectedly succeeded\n' >&2
      status=1
    elif [[ "$("${kue_exe}" export -e nope_missing "${select_fixture}" 2>&1 1>/dev/null)" != *"not found"* ]]; then
      printf 'kue export -e nope_missing did not report a not-found error on stderr\n' >&2
      status=1
    fi
  fi

  return "${status}"
}

# Drive the B3d-4 OCI-fetch curl seam against `file://` fixtures (testdata/ocifetch/),
# OFFLINE. Proves the whole composition — curl subprocess, raw-byte capture, SHA-256 digest
# verification — works without a network or a real registry, and that the digest-integrity
# gate rejects a tampered blob. The live HTTPS fetch from registry.cue.works is human-gated
# (see .afk.log); this covers everything reproducible offline.
check_ocifetch_seam() {
  if [[ ! -d "${ocifetch_dir}" ]]; then
    return 0
  fi

  if ! lake build Kue.OciFetch >/dev/null; then
    printf 'failed to build Kue.OciFetch\n' >&2
    return 1
  fi

  if ! lake env lean --run "${repo_root}/scripts/check-ocifetch.lean" "${ocifetch_dir}"; then
    printf 'OCI-fetch file:// seam check failed\n' >&2
    return 1
  fi
}

# Drive the B3d-5z pure-Lean ZIP reader (Kue.Zip.readZip: container parse + RFC 1951 inflate +
# CRC-32 verification) over a REAL cached cue module zip (testdata/zip/module.zip, all-DEFLATE),
# OFFLINE. Cross-checks the extracted content against the independently-produced ground truth
# testdata/zip/module.zip.sha256 (one `<sha256>  <name>` line per file via `unzip -p | shasum`).
check_zip_golden() {
  if [[ ! -d "${zip_dir}" ]]; then
    return 0
  fi

  if ! lake build Kue.Zip >/dev/null; then
    printf 'failed to build Kue.Zip\n' >&2
    return 1
  fi

  if ! lake env lean --run "${repo_root}/scripts/check-zip.lean" "${zip_dir}"; then
    printf 'ZIP reader golden check failed\n' >&2
    return 1
  fi
}

# Drive the B3d-5 fetch->extract->cache-write->read-path wiring (Kue.fetchAndCacheModule) over
# the committed testdata/ocifetch/pipeline/ fixtures, OFFLINE. The fetch step reads the local
# fixture zip (no network, no real registry); CUE_CACHE_DIR points at a fresh repo-local temp dir
# so the cache-write path is exercised WITHOUT touching the real ~/Library/Caches/cue. Asserts the
# module installs + is located, the integrity gate (cue.sum h1:) accepts/rejects, and the B3d-5a
# unified cache-path authority. The live HTTPS fetch from registry.cue.works is human-gated
# (see .afk.log).
check_fetch_pipeline() {
  local pipeline_dir="${ocifetch_dir}/pipeline"
  if [[ ! -d "${pipeline_dir}" ]]; then
    return 0
  fi

  if ! lake build Kue.Module >/dev/null; then
    printf 'failed to build Kue.Module\n' >&2
    return 1
  fi

  local cache_dir
  cache_dir="$(mktemp -d "${pipeline_dir}/.cache-XXXXXX")"

  local rc=0
  if ! CUE_CACHE_DIR="${cache_dir}" \
    lake env lean --run "${repo_root}/scripts/check-fetch-pipeline.lean" "${pipeline_dir}"; then
    printf 'fetch pipeline check failed\n' >&2
    rc=1
  fi

  rm -rf -- "${cache_dir}"
  return "${rc}"
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

  while IFS= read -r cue_file; do
    stem="${cue_file%.cue}"
    if [[ ! -f "${stem}.expected" && ! -f "${stem}.manifest.expected" ]]; then
      printf 'missing expected file for %s\n' "${cue_file}" >&2
      status=1
    fi
  done < <(find "${fixture_dir}" -name '*.cue' -type f | sort)

  while IFS= read -r expected_file; do
    stem="${expected_file%.expected}"
    if [[ "${stem}" == *.manifest ]]; then
      stem="${stem%.manifest}"
    fi

    source_file="${stem}.cue"
    if [[ ! -f "${source_file}" ]]; then
      printf 'missing source fixture for %s\n' "${expected_file}" >&2
      status=1
    fi
  done < <(find "${fixture_dir}" -name '*.expected' -type f | sort)

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

  if ! check_module_fixtures; then
    status=1
  fi

  if ! check_wild_fixtures; then
    status=1
  fi

  if ! check_cli_behavior; then
    status=1
  fi

  if ! check_ocifetch_seam; then
    status=1
  fi

  if ! check_fetch_pipeline; then
    status=1
  fi

  if ! check_zip_golden; then
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
