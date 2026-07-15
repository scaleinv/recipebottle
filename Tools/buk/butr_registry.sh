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
# BUK Test Registry - fixture/case/suite enrollment following BCG enroll/recite patterns
#
# Fixtures: litmus/baste execution contexts (one per case)
# Suites: cross-cutting selection groups (N:M with cases)

set -euo pipefail

# Multiple inclusion guard
test -z "${ZBUTR_INCLUDED:-}" || buto_fatal "butr_registry multiply sourced"
ZBUTR_INCLUDED=1

######################################################################
# Internal kindle boilerplate

butr_kindle() {
  test -z "${ZBUTR_KINDLED:-}" || buto_fatal "butr already kindled"

  # Fixture rolls (parallel arrays)
  z_butr_name_roll=()
  z_butr_litmus_roll=()
  z_butr_baste_roll=()

  # Case rolls (parallel arrays with foreign key to fixture)
  z_butr_case_fn_roll=()
  z_butr_case_fixture_roll=()

  # Suite state
  z_butr_suite_context_set=0
  z_butr_current_suites=()
  z_butr_case_suites_roll=()
  z_butr_known_suites=()

  readonly ZBUTR_KINDLED=1
}

######################################################################
# Internal sentinel

zbutr_sentinel() {
  test "${ZBUTR_KINDLED:-}" = "1" || buto_fatal "Module butr not kindled - call butr_kindle first"
}

######################################################################
# Public fixture enrollment functions

# butr_fixture_enroll() - Register a fixture with litmus predicate and baste function
# Args: fixture_name, litmus_fn, baste_fn
#   fixture_name: unique name for the fixture
#   litmus_fn: predicate in parent shell, 0=proceed 1=skip ("" for always ready)
#   baste_fn: kindle/source/configure inside fixture subshell ("" for none)
butr_fixture_enroll() {
  zbutr_sentinel

  local -r z_name="${1:-}"
  local -r z_litmus="${2:-}"
  local -r z_baste="${3:-}"

  test -n "${z_name}" || buto_fatal "butr_fixture_enroll: fixture_name required"

  # Check for duplicate fixture names
  local z_i
  for z_i in "${!z_butr_name_roll[@]}"; do
    test "${z_butr_name_roll[$z_i]}" != "${z_name}" || buto_fatal "butr_fixture_enroll: duplicate fixture '${z_name}'"
  done

  # Validate litmus function if specified
  if test -n "${z_litmus}"; then
    declare -F "${z_litmus}" >/dev/null || buto_fatal "butr_fixture_enroll: litmus function not found: ${z_litmus}"
  fi

  # Validate baste function if specified
  if test -n "${z_baste}"; then
    declare -F "${z_baste}" >/dev/null || buto_fatal "butr_fixture_enroll: baste function not found: ${z_baste}"
  fi

  z_butr_name_roll+=("${z_name}")
  z_butr_litmus_roll+=("${z_litmus}")
  z_butr_baste_roll+=("${z_baste}")
}

######################################################################
# Public suite enrollment

# butr_suite_enroll() - Set current suite context for subsequent case enrollments
# Args: SUITE1 [SUITE2...]
# Replacement (not additive) — overwrites previous suite context
butr_suite_enroll() {
  zbutr_sentinel

  test $# -gt 0 || buto_fatal "butr_suite_enroll: at least one suite required"

  z_butr_current_suites=("$@")
  z_butr_suite_context_set=1

  # Track known suites
  local z_s
  for z_s in "$@"; do
    local z_found=0
    local z_k
    for z_k in "${!z_butr_known_suites[@]}"; do
      if test "${z_butr_known_suites[$z_k]}" = "${z_s}"; then
        z_found=1
        break
      fi
    done
    test "${z_found}" -eq 1 || z_butr_known_suites+=("${z_s}")
  done
}

######################################################################
# Public case enrollment

# butr_case_enroll() - Register a test case function for a fixture
# Inherits current suite context. Fatals if no suite context set.
# Args: fixture_name, case_function
butr_case_enroll() {
  zbutr_sentinel

  local -r z_fixture="${1:-}"
  local -r z_case="${2:-}"

  test -n "${z_fixture}" || buto_fatal "butr_case_enroll: fixture_name required"
  test -n "${z_case}" || buto_fatal "butr_case_enroll: case_function required"

  # Require suite context
  test "${z_butr_suite_context_set}" -eq 1 || buto_fatal "butr_case_enroll: no suite context — call butr_suite_enroll first"

  # Find fixture index
  local z_fixture_idx=""
  local z_i
  for z_i in "${!z_butr_name_roll[@]}"; do
    if test "${z_butr_name_roll[$z_i]}" = "${z_fixture}"; then
      z_fixture_idx="${z_i}"
      break
    fi
  done

  test -n "${z_fixture_idx}" || buto_fatal "butr_case_enroll: unknown fixture '${z_fixture}'"

  # Validate case function exists
  declare -F "${z_case}" >/dev/null || buto_fatal "butr_case_enroll: case function not found: ${z_case}"

  z_butr_case_fn_roll+=("${z_case}")
  z_butr_case_fixture_roll+=("${z_fixture_idx}")
  z_butr_case_suites_roll+=("${z_butr_current_suites[*]}")
}

######################################################################
# Public fixture recite functions

# butr_fixtures_recite() - List all fixture names
butr_fixtures_recite() {
  zbutr_sentinel
  local z_i
  for z_i in "${!z_butr_name_roll[@]}"; do
    echo "${z_butr_name_roll[$z_i]}" || return 1
  done
}

# butr_litmus_recite() - Get litmus predicate function for named fixture
# Args: fixture_name
# Returns: litmus function name (or empty string)
butr_litmus_recite() {
  zbutr_sentinel
  local -r z_name="${1:-}"
  test -n "${z_name}" || return 1
  local z_i
  for z_i in "${!z_butr_name_roll[@]}"; do
    if test "${z_butr_name_roll[$z_i]}" = "${z_name}"; then
      echo "${z_butr_litmus_roll[$z_i]}" || return 1
      return 0
    fi
  done
  return 1
}

# butr_baste_recite() - Get baste function for named fixture
# Args: fixture_name
# Returns: baste function name (or empty string)
butr_baste_recite() {
  zbutr_sentinel
  local -r z_name="${1:-}"
  test -n "${z_name}" || return 1
  local z_i
  for z_i in "${!z_butr_name_roll[@]}"; do
    if test "${z_butr_name_roll[$z_i]}" = "${z_name}"; then
      echo "${z_butr_baste_roll[$z_i]}" || return 1
      return 0
    fi
  done
  return 1
}

# butr_cases_recite() - List case function names for fixture
# Args: fixture_name
butr_cases_recite() {
  zbutr_sentinel
  local -r z_fixture="${1:-}"
  test -n "${z_fixture}" || return 1

  # Find fixture index
  local z_fixture_idx=""
  local z_i
  for z_i in "${!z_butr_name_roll[@]}"; do
    if test "${z_butr_name_roll[$z_i]}" = "${z_fixture}"; then
      z_fixture_idx="${z_i}"
      break
    fi
  done

  test -n "${z_fixture_idx}" || return 1

  # List all cases for this fixture
  for z_i in "${!z_butr_case_fn_roll[@]}"; do
    if test "${z_butr_case_fixture_roll[$z_i]}" = "${z_fixture_idx}"; then
      echo "${z_butr_case_fn_roll[$z_i]}" || return 1
    fi
  done
}

# butr_fixture_for_case_recite() - Find owning fixture name for a case function
# Args: case_function
butr_fixture_for_case_recite() {
  zbutr_sentinel
  local -r z_case="${1:-}"
  test -n "${z_case}" || return 1

  local z_i
  for z_i in "${!z_butr_case_fn_roll[@]}"; do
    if test "${z_butr_case_fn_roll[$z_i]}" = "${z_case}"; then
      local -r z_fixture_idx="${z_butr_case_fixture_roll[$z_i]}"
      echo "${z_butr_name_roll[$z_fixture_idx]}" || return 1
      return 0
    fi
  done
  return 1
}

######################################################################
# Public suite recite functions

# butr_suites_recite() - List all known suite names
butr_suites_recite() {
  zbutr_sentinel
  local z_i
  for z_i in "${!z_butr_known_suites[@]}"; do
    echo "${z_butr_known_suites[$z_i]}" || return 1
  done
}

# butr_suite_cases_recite() - List case function names enrolled in a suite
# Args: suite_name
butr_suite_cases_recite() {
  zbutr_sentinel
  local -r z_suite="${1:-}"
  test -n "${z_suite}" || return 1

  local z_i
  for z_i in "${!z_butr_case_fn_roll[@]}"; do
    local z_suites="${z_butr_case_suites_roll[$z_i]}"
    # Check if suite is in the space-separated list
    local z_s
    for z_s in ${z_suites}; do
      if test "${z_s}" = "${z_suite}"; then
        echo "${z_butr_case_fn_roll[$z_i]}" || return 1
        break
      fi
    done
  done
}

# eof
