#!/bin/bash
#
# Copyright 2026 Scale Invariant, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: Brad Hyslop <bhyslop@scaleinvariant.org>
#
# BUK Test Dispatch - fixture boundary runner, suite dispatch, and reporting

set -euo pipefail

# Source test engine
ZBUTD_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
source "${ZBUTD_SCRIPT_DIR}/bute_engine.sh"

# Multiple inclusion guard
test -z "${ZBUTD_INCLUDED:-}" || buto_fatal "butd_dispatch multiply sourced"
ZBUTD_INCLUDED=1

######################################################################
# Fixture boundary — fixture isolation and execution

# butd_run_fixture() - Run registered fixture with init/setup/case layers
# Args: fixture_name [case_fn1 case_fn2 ...]
# If case functions specified, runs only those cases; otherwise runs all cases in fixture
butd_run_fixture() {
  local -r z_fixture="${1:-}"
  shift || true

  if test -z "${z_fixture}"; then
    buto_info "Available fixtures:"
    local z_fixture_list
    z_fixture_list=$(mktemp)
    butr_fixtures_recite > "${z_fixture_list}"
    while IFS= read -r z_fixture_name || test -n "${z_fixture_name}"; do
      test -n "${z_fixture_name}" || continue
      local z_case_count=0
      while IFS= read -r _; do
        z_case_count=$((z_case_count + 1))
      done < <(butr_cases_recite "${z_fixture_name}")

      local z_plural=""
      test "${z_case_count}" -eq 1 || z_plural="s"
      printf "  %-30s %2d case%s\n" "${z_fixture_name}" "${z_case_count}" "${z_plural}" >&2
    done < "${z_fixture_list}"
    rm -f "${z_fixture_list}"
    return 0
  fi

  local z_litmus
  z_litmus=$(butr_litmus_recite "${z_fixture}") || buto_fatal "butd_run_fixture: failed to get litmus for '${z_fixture}'"
  local z_baste
  z_baste=$(butr_baste_recite "${z_fixture}") || buto_fatal "butd_run_fixture: failed to get baste for '${z_fixture}'"

  buto_section "Fixture: ${z_fixture}"

  # Run litmus predicate if specified (status capture pattern)
  if test -n "${z_litmus}"; then
    buto_trace "Running litmus: ${z_litmus}"
    declare -F "${z_litmus}" >/dev/null || buto_fatal "Litmus function not found: ${z_litmus}"
    local z_status=0
    "${z_litmus}" || z_status=$?
    if test "${z_status}" -ne 0; then
      buc_warn "Fixture '${z_fixture}' skipped (litmus: ${z_litmus})"
      return 2
    fi
  fi

  # Fixture subshell boundary: isolates fixture state (baste kindles, module guards) from other fixtures.
  # Litmus runs above in parent so it can skip via return.
  (
    set -e

    # Run baste function if specified
    if test -n "${z_baste}"; then
      buto_trace "Running baste: ${z_baste}"
      declare -F "${z_baste}" >/dev/null || buto_fatal "Baste function not found: ${z_baste}"
      "${z_baste}"
    fi

    # Create per-fixture temp dir
    local -r z_fixture_dir="${ZBUTE_ROOT_TEMP_DIR}/${z_fixture}"
    mkdir -p "${z_fixture_dir}"

    # Load case list: from args if provided, otherwise all cases for fixture
    local z_cases=()
    if test $# -gt 0; then
      z_cases=("$@")
    else
      local z_cases_temp
      z_cases_temp=$(mktemp)
      butr_cases_recite "${z_fixture}" > "${z_cases_temp}" || buto_fatal "Failed to get cases for fixture '${z_fixture}'"
      local z_case_fn=""
      while IFS= read -r z_case_fn || test -n "${z_case_fn}"; do
        z_cases+=("${z_case_fn}")
      done < "${z_cases_temp}"
      rm -f "${z_cases_temp}"
    fi

    local z_case_count=0
    local z_ci
    for z_ci in "${!z_cases[@]}"; do
      test -n "${z_cases[$z_ci]}" || continue
      zbute_tcase "${z_cases[$z_ci]}"
      z_case_count=$((z_case_count + 1))
    done

    test "${z_case_count}" -gt 0 || buto_fatal "No test cases found for fixture '${z_fixture}'"

    echo "${ZBUTO_GREEN}Fixture passed: ${z_fixture} (${z_case_count} case$(test "${z_case_count}" -eq 1 || echo 's'))${ZBUTO_RESET}" >&2
  )
  local -r z_sub_status=$?
  return "${z_sub_status}"
}

# butd_run_one() - Run single _tcase with its parent fixture setup
# Args: function_name
butd_run_one() {
  local -r z_func="${1:-}"
  if test -z "${z_func}"; then
    buto_info "Available test functions:"
    local z_fixtures_list
    z_fixtures_list=$(mktemp)
    butr_fixtures_recite > "${z_fixtures_list}"
    while IFS= read -r z_fixture_name || test -n "${z_fixture_name}"; do
      test -n "${z_fixture_name}" || continue
      buto_info "  ${z_fixture_name}:"
      local z_cases_list
      z_cases_list=$(mktemp)
      butr_cases_recite "${z_fixture_name}" > "${z_cases_list}"
      while IFS= read -r z_case_fn || test -n "${z_case_fn}"; do
        test -n "${z_case_fn}" || continue
        buto_info "    ${z_case_fn}"
      done < "${z_cases_list}"
      rm -f "${z_cases_list}"
    done < "${z_fixtures_list}"
    rm -f "${z_fixtures_list}"
    return 0
  fi

  local z_fixture
  z_fixture=$(butr_fixture_for_case_recite "${z_func}") || buto_fatal "butd_run_one: no fixture matches function '${z_func}'"

  local z_litmus
  z_litmus=$(butr_litmus_recite "${z_fixture}") || buto_fatal "butd_run_one: failed to get litmus for '${z_fixture}'"
  local z_baste
  z_baste=$(butr_baste_recite "${z_fixture}") || buto_fatal "butd_run_one: failed to get baste for '${z_fixture}'"

  buto_section "Fixture: ${z_fixture} (single case: ${z_func})"

  # Run litmus predicate if specified (status capture pattern)
  if test -n "${z_litmus}"; then
    buto_trace "Running litmus: ${z_litmus}"
    declare -F "${z_litmus}" >/dev/null || buto_fatal "Litmus function not found: ${z_litmus}"
    local z_status=0
    "${z_litmus}" || z_status=$?
    if test "${z_status}" -ne 0; then
      buto_fatal "Fixture '${z_fixture}' not ready (litmus: ${z_litmus})"
    fi
  fi

  # Fixture subshell boundary — same isolation pattern as butd_run_fixture
  (
    set -e

    # Run baste function if specified
    if test -n "${z_baste}"; then
      buto_trace "Running baste: ${z_baste}"
      declare -F "${z_baste}" >/dev/null || buto_fatal "Baste function not found: ${z_baste}"
      "${z_baste}"
    fi

    # Create per-fixture temp dir
    local -r z_fixture_dir="${ZBUTE_ROOT_TEMP_DIR}/${z_fixture}"
    mkdir -p "${z_fixture_dir}"

    # Run the single case
    zbute_tcase "${z_func}"

    echo "${ZBUTO_GREEN}Test passed: ${z_func}${ZBUTO_RESET}" >&2
  )
  local -r z_sub_status=$?
  return "${z_sub_status}"
}

# butd_run_all() - Run all registered fixtures
# Args: none
butd_run_all() {
  local z_total_fixtures=0
  local z_total_skipped=0
  local z_total_failed=0
  local z_fixture=""
  local z_fixtures_temp
  z_fixtures_temp=$(mktemp)

  # Load fixture list into array before execution (BCG: load-then-iterate)
  # Prevents stdin consumption by fixture test commands
  local z_fixtures=()
  butr_fixtures_recite > "${z_fixtures_temp}" || buto_fatal "Failed to get fixtures"
  while IFS= read -r z_fixture || test -n "${z_fixture}"; do
    z_fixtures+=("${z_fixture}")
  done < "${z_fixtures_temp}"
  rm -f "${z_fixtures_temp}"

  local z_si
  for z_si in "${!z_fixtures[@]}"; do
    z_fixture="${z_fixtures[$z_si]}"
    test -n "${z_fixture}" || continue

    local z_fixture_status=0
    butd_run_fixture "${z_fixture}" || z_fixture_status=$?

    if test "${z_fixture_status}" -eq 0; then
      z_total_fixtures=$((z_total_fixtures + 1))
    elif test "${z_fixture_status}" -eq 2; then
      z_total_skipped=$((z_total_skipped + 1))
    else
      z_total_failed=$((z_total_failed + 1))
      buc_warn "Fixture '${z_fixture}' failed with status ${z_fixture_status}"
    fi
  done

  local -r z_total_ran=$((z_total_fixtures + z_total_failed))
  test "${z_total_ran}" -gt 0 || buto_fatal "No fixtures ran (${z_total_skipped} skipped)"

  if test "${z_total_failed}" -gt 0; then
    echo "${ZBUTO_RED}Some fixtures failed: ${z_total_fixtures} passed, ${z_total_failed} failed, ${z_total_skipped} skipped${ZBUTO_RESET}" >&2
    exit 1
  fi

  local z_skip_note=""
  test "${z_total_skipped}" -eq 0 || z_skip_note=", ${z_total_skipped} skipped"

  echo "${ZBUTO_GREEN}All fixtures passed (${z_total_fixtures} fixture$(test "${z_total_fixtures}" -eq 1 || echo 's')${z_skip_note})${ZBUTO_RESET}" >&2
}

######################################################################
# Suite dispatch — cross-cutting suite runner

# butd_run_suite() - Run all cases in a suite, grouped by owning fixture
# Args: suite_name
butd_run_suite() {
  local -r z_suite="${1:-}"

  if test -z "${z_suite}"; then
    buto_info "Available suites:"
    local z_suites_temp
    z_suites_temp=$(mktemp)
    butr_suites_recite > "${z_suites_temp}"
    while IFS= read -r z_suite_name || test -n "${z_suite_name}"; do
      test -n "${z_suite_name}" || continue
      local z_case_count=0
      while IFS= read -r _; do
        z_case_count=$((z_case_count + 1))
      done < <(butr_suite_cases_recite "${z_suite_name}")

      local z_plural=""
      test "${z_case_count}" -eq 1 || z_plural="s"
      printf "  %-20s %3d case%s\n" "${z_suite_name}" "${z_case_count}" "${z_plural}" >&2
    done < "${z_suites_temp}"
    rm -f "${z_suites_temp}"
    return 0
  fi

  buto_section "Suite: ${z_suite}"

  # Load all cases in this suite (BCG: load-then-iterate)
  local z_all_cases=()
  local z_cases_temp
  z_cases_temp=$(mktemp)
  butr_suite_cases_recite "${z_suite}" > "${z_cases_temp}"
  local z_line
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    z_all_cases+=("${z_line}")
  done < "${z_cases_temp}"
  rm -f "${z_cases_temp}"

  test "${#z_all_cases[@]}" -gt 0 || buto_fatal "No cases in suite '${z_suite}'"

  # Build ordered unique fixture list
  local z_fixtures=()
  local z_ci
  for z_ci in "${!z_all_cases[@]}"; do
    local z_fn="${z_all_cases[$z_ci]}"
    local z_fix
    z_fix=$(butr_fixture_for_case_recite "${z_fn}") || buto_fatal "No fixture for case '${z_fn}'"
    local z_found=0
    local z_fi
    for z_fi in "${!z_fixtures[@]}"; do
      if test "${z_fixtures[$z_fi]}" = "${z_fix}"; then
        z_found=1
        break
      fi
    done
    test "${z_found}" -eq 1 || z_fixtures+=("${z_fix}")
  done

  # Run each fixture with its filtered cases
  local z_total_fixtures=0
  local z_total_skipped=0
  local z_total_failed=0

  for z_fi in "${!z_fixtures[@]}"; do
    local z_fix_name="${z_fixtures[$z_fi]}"
    # Collect cases for this fixture from the suite
    local z_fix_cases=()
    for z_ci in "${!z_all_cases[@]}"; do
      local z_case_fn="${z_all_cases[$z_ci]}"
      local z_case_fix
      z_case_fix=$(butr_fixture_for_case_recite "${z_case_fn}") || continue
      test "${z_case_fix}" = "${z_fix_name}" || continue
      z_fix_cases+=("${z_case_fn}")
    done

    local z_status=0
    butd_run_fixture "${z_fix_name}" "${z_fix_cases[@]}" || z_status=$?

    if test "${z_status}" -eq 0; then
      z_total_fixtures=$((z_total_fixtures + 1))
    elif test "${z_status}" -eq 2; then
      z_total_skipped=$((z_total_skipped + 1))
    else
      z_total_failed=$((z_total_failed + 1))
      buc_warn "Fixture '${z_fix_name}' failed in suite with status ${z_status}"
    fi
  done

  local -r z_total_ran=$((z_total_fixtures + z_total_failed))
  test "${z_total_ran}" -gt 0 || buto_fatal "No fixtures ran in suite '${z_suite}' (${z_total_skipped} skipped)"

  if test "${z_total_failed}" -gt 0; then
    echo "${ZBUTO_RED}Suite '${z_suite}' failed: ${z_total_fixtures} passed, ${z_total_failed} failed, ${z_total_skipped} skipped${ZBUTO_RESET}" >&2
    exit 1
  fi

  local z_skip_note=""
  test "${z_total_skipped}" -eq 0 || z_skip_note=", ${z_total_skipped} skipped"

  local -r z_case_count="${#z_all_cases[@]}"
  echo "${ZBUTO_GREEN}Suite '${z_suite}' passed (${z_total_fixtures} fixture$(test "${z_total_fixtures}" -eq 1 || echo 's'), ${z_case_count} case$(test "${z_case_count}" -eq 1 || echo 's')${z_skip_note})${ZBUTO_RESET}" >&2
}

# eof
