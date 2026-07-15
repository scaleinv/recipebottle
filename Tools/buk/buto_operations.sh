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
# BUK Test Operations - Assertions, invocations, dispatch, and evidence

set -euo pipefail

######################################################################
# Color codes

buto_color() {
  if test -n "${TERM:-}" && test "${TERM}" != "dumb"; then
    printf '\033[%sm' "${1}"
  else
    printf ''
  fi
}
ZBUTO_WHITE=$(  buto_color '1;37' )
ZBUTO_RED=$(    buto_color '1;31' )
ZBUTO_GREEN=$(  buto_color '1;32' )
ZBUTO_RESET=$(  buto_color '0'    )

######################################################################
# Generic renderer for aligned multi-line messages
# Usage: zbuto_render_lines PREFIX COLOR LINES...

zbuto_render_lines() {
  local z_label="${1}"; shift
  local z_color="${1}"; shift

  local z_prefix="${z_label}:"

  local z_visible_prefix="${z_prefix}"
  test -z "${z_color}" || z_prefix="${z_color}${z_prefix}${ZBUTO_RESET}"
  local z_indent=""
  printf -v z_indent '%*s' "${#z_visible_prefix}" ''

  local z_first=1
  local z_line=""
  for z_line in "$@"; do
    if test "${z_first}" -eq 1; then
      echo "${z_prefix} ${z_line}" >&2
      z_first=0
    else
      echo "${z_indent} ${z_line}" >&2
    fi
  done
}

######################################################################
# Output functions

buto_section() {
  test "${BUT_VERBOSE:-0}" -ge 1 || return 0
  zbuto_render_lines "info " "${ZBUTO_WHITE}" "$@"
}

buto_info() {
  zbuto_render_lines "info " "" "$@"
}

buto_trace() {
  test "${BUT_VERBOSE:-0}" -ge 2 || return 0
  zbuto_render_lines "trace" "" "$@"
}

buto_fatal() {
  zbuto_render_lines "ERROR" "${ZBUTO_RED}" "$@"
  exit 1
}

buto_fatal_on_error() {
  set -e
  local z_condition="${1}"; shift
  test "${z_condition}" -ne 0 || return 0
  buto_fatal "$@"
}

buto_fatal_on_success() {
  set -e
  local z_condition="${1}"; shift
  test "${z_condition}" -eq 0 || return 0
  buto_fatal "$@"
}

buto_success() {
  echo "${ZBUTO_GREEN}PASSED:${ZBUTO_RESET} $*" >&2
}

######################################################################
# BURV bridge support

# zbuto_next_invoke_capture() - Find next unused invoke number
# Scans BUTE_BURV_ROOT/invoke-NNNNN directories for next available slot
# Returns: next invoke number (starts at 10000)
zbuto_next_invoke_capture() {
  local z_burv_root="${BUTE_BURV_ROOT:-}"
  test -n "${z_burv_root}" || return 1

  local z_invoke_num=10000
  while test -d "${z_burv_root}/invoke-${z_invoke_num}"; do
    z_invoke_num=$((z_invoke_num + 1))
  done
  echo "${z_invoke_num}"
}

######################################################################
# Safely invoke a command under 'set -e', capturing stdout, stderr, and exit status
# Globals set:
#   ZBUTO_STDOUT       - command stdout
#   ZBUTO_STDERR       - command stderr
#   ZBUTO_STATUS       - command exit code
#   ZBUTO_BURV_OUTPUT      - BURV output root (empty if BURV not enabled)
#   ZBUTO_BURV_OUTPUT_DIR  - BURV output dir matching BURD_OUTPUT_DIR (empty if BURV not enabled)
# BURV bridge: If BUTE_BURV_ROOT is set, creates per-invocation BURV isolation

zbuto_invoke() {
  buto_trace "Invoking: $*"

  local z_tmp_stdout
  z_tmp_stdout=$(mktemp)
  local z_tmp_stderr
  z_tmp_stderr=$(mktemp)

  # BURV bridge setup if enabled
  local z_burv_output=""
  local z_burv_temp=""
  if test -n "${BUTE_BURV_ROOT:-}"; then
    local z_invoke_num
    z_invoke_num=$(zbuto_next_invoke_capture)
    local z_invoke_dir="${BUTE_BURV_ROOT}/invoke-${z_invoke_num}"
    z_burv_output="${z_invoke_dir}/output"
    z_burv_temp="${z_invoke_dir}/temp"
    mkdir -p "${z_burv_output}" "${z_burv_temp}"
  fi

  # The invoked argv gets its own nested subshell so a function that exits
  # (buc_die, buc_reject) lands there instead of killing the capture shell
  # before the status line is written — exit codes report faithfully rather
  # than masking to 127.
  ZBUTO_STATUS=$( (
      set +e
      if test -n "${z_burv_output}"; then
        ( export BURV_OUTPUT_ROOT_DIR="${z_burv_output}" BURV_TEMP_ROOT_DIR="${z_burv_temp}"
          "$@" >"${z_tmp_stdout}" 2>"${z_tmp_stderr}" )
      else
        ( "$@" >"${z_tmp_stdout}" 2>"${z_tmp_stderr}" )
      fi
      printf '%s' "$?"
      exit 0
    ) || printf '__subshell_failed__' )

  if test "${ZBUTO_STATUS}" = "__subshell_failed__" || test -z "${ZBUTO_STATUS}"; then
    ZBUTO_STATUS=127
    ZBUTO_STDOUT=""
    ZBUTO_STDERR="zbuto_invoke: command caused shell to exit before status could be captured"
  else
    ZBUTO_STDOUT=$(<"${z_tmp_stdout}")
    ZBUTO_STDERR=$(<"${z_tmp_stderr}")
  fi

  rm -f "${z_tmp_stdout}" "${z_tmp_stderr}"

  ZBUTO_BURV_OUTPUT="${z_burv_output}"
  ZBUTO_BURV_OUTPUT_DIR="${z_burv_output:+${z_burv_output}/current}"
}

######################################################################
# buto_unit_* - Raw command invocation via zbuto_invoke

buto_unit_expect_ok_stdout() {
  set -e

  local z_expected="${1}"; shift

  zbuto_invoke "$@"

  buto_fatal_on_error "${ZBUTO_STATUS}" "Command failed with status ${ZBUTO_STATUS}" \
                                        "Command: $*"                               \
                                        "STDERR: ${ZBUTO_STDERR}"

  test "${ZBUTO_STDOUT}" = "${z_expected}" || buto_fatal "Output mismatch"            \
                                                         "Command: $*"                \
                                                         "Expected: '${z_expected}'"  \
                                                         "Got:      '${ZBUTO_STDOUT}'"
}

buto_unit_expect_ok() {
  set -e

  zbuto_invoke "$@"

  buto_fatal_on_error "${ZBUTO_STATUS}" "Command failed with status ${ZBUTO_STATUS}" \
                                        "Command: $*"                               \
                                        "STDERR: ${ZBUTO_STDERR}"
}

buto_unit_expect_fatal() {
  set -e

  zbuto_invoke "$@"

  buto_fatal_on_success "${ZBUTO_STATUS}" "Expected failure but got success" \
                                          "Command: $*"                      \
                                          "STDOUT: ${ZBUTO_STDOUT}"          \
                                          "STDERR: ${ZBUTO_STDERR}"
}

# Assert the command exits with one specific code — closes the wrong-reason
# hole in expect_fatal, where any nonzero (harness breakage included) passes.
buto_unit_expect_code() {
  set -e

  local z_expected="${1:-}"
  test -n "${z_expected}" || buto_fatal "buto_unit_expect_code: expected code required"
  shift

  zbuto_invoke "$@"

  test "${ZBUTO_STATUS}" = "${z_expected}" || buto_fatal "Exit code mismatch"          \
                                                         "Command: $*"                 \
                                                         "Expected: ${z_expected}"     \
                                                         "Got:      ${ZBUTO_STATUS}"   \
                                                         "STDOUT: ${ZBUTO_STDOUT}"     \
                                                         "STDERR: ${ZBUTO_STDERR}"
}

######################################################################
# buto_tt_* - Tabtarget file invocation (requires tabtarget exists)
#
# Resolves colophon to tt/{colophon}.*.sh file, dies if missing.
# Extra args pass through to tabtarget script.

zbuto_resolve_tabtarget() {
  local z_colophon="${1:-}"
  test -n "${z_colophon}" || buto_fatal "zbuto_resolve_tabtarget: colophon required"

  local z_tt_dir="${BURC_TABTARGET_DIR:-}"
  test -n "${z_tt_dir}" || buto_fatal "BURC_TABTARGET_DIR not set -- buto_tt requires BUK environment"
  local z_matches=("${z_tt_dir}/${z_colophon}."*.sh)

  # Bash 3.2: no-match glob returns literal — check with test -e
  test -e "${z_matches[0]}" || buto_fatal "No tabtarget found for colophon '${z_colophon}' in ${z_tt_dir}/"

  test "${#z_matches[@]}" -eq 1 || buto_fatal "Multiple tabtargets found for colophon '${z_colophon}' in ${z_tt_dir}/"

  echo "${z_matches[0]}"
}

buto_tt_expect_ok() {
  set -e

  local z_colophon="${1:-}"
  test -n "${z_colophon}" || buto_fatal "buto_tt_expect_ok: colophon required"
  shift

  local z_tabtarget
  z_tabtarget=$(zbuto_resolve_tabtarget "${z_colophon}")

  zbuto_invoke "${z_tabtarget}" "$@"

  buto_fatal_on_error "${ZBUTO_STATUS}" "Tabtarget failed with status ${ZBUTO_STATUS}" \
                                        "Colophon: ${z_colophon}"                      \
                                        "Tabtarget: ${z_tabtarget}"                    \
                                        "STDERR: ${ZBUTO_STDERR}"
}

# Assert the tabtarget exits with one specific code through the full
# tabtarget/launcher/dispatch exec path — see buto_unit_expect_code.
buto_tt_expect_code() {
  set -e

  local z_expected="${1:-}"
  local z_colophon="${2:-}"
  test -n "${z_expected}" || buto_fatal "buto_tt_expect_code: expected code required"
  test -n "${z_colophon}" || buto_fatal "buto_tt_expect_code: colophon required"
  shift 2

  local z_tabtarget
  z_tabtarget=$(zbuto_resolve_tabtarget "${z_colophon}")

  zbuto_invoke "${z_tabtarget}" "$@"

  test "${ZBUTO_STATUS}" = "${z_expected}" || buto_fatal "Exit code mismatch"          \
                                                         "Colophon: ${z_colophon}"     \
                                                         "Tabtarget: ${z_tabtarget}"   \
                                                         "Expected: ${z_expected}"     \
                                                         "Got:      ${ZBUTO_STATUS}"   \
                                                         "STDOUT: ${ZBUTO_STDOUT}"     \
                                                         "STDERR: ${ZBUTO_STDERR}"
}

buto_tt_previous_output_capture() {
  test -n "${ZBUTO_BURV_OUTPUT_DIR:-}" || buto_fatal "No previous tabtarget output"
  echo "${ZBUTO_BURV_OUTPUT_DIR}"
}

buto_tt_expect_fatal() {
  set -e

  local z_colophon="${1:-}"
  test -n "${z_colophon}" || buto_fatal "buto_tt_expect_fatal: colophon required"
  shift

  local z_tabtarget
  z_tabtarget=$(zbuto_resolve_tabtarget "${z_colophon}")

  zbuto_invoke "${z_tabtarget}" "$@"

  buto_fatal_on_success "${ZBUTO_STATUS}" "Expected failure but got success"    \
                                          "Colophon: ${z_colophon}"             \
                                          "Tabtarget: ${z_tabtarget}"           \
                                          "STDOUT: ${ZBUTO_STDOUT}"             \
                                          "STDERR: ${ZBUTO_STDERR}"
}

######################################################################
# buto_launch_* - Workbench dispatch (no tabtarget file required)
#
# First arg is launcher (workbench), second is colophon, rest are args.
# Invokes launcher directly with colophon+args.

buto_launch_expect_ok() {
  set -e

  local z_launcher="${1:-}"
  local z_colophon="${2:-}"
  test -n "${z_launcher}" || buto_fatal "buto_launch_expect_ok: launcher required"
  test -n "${z_colophon}" || buto_fatal "buto_launch_expect_ok: colophon required"
  shift 2

  zbuto_invoke "${z_launcher}" "${z_colophon}" "$@"

  buto_fatal_on_error "${ZBUTO_STATUS}" "Launch failed with status ${ZBUTO_STATUS}" \
                                        "Launcher: ${z_launcher}"                   \
                                        "Colophon: ${z_colophon}"                   \
                                        "STDERR: ${ZBUTO_STDERR}"
}

buto_launch_expect_fatal() {
  set -e

  local z_launcher="${1:-}"
  local z_colophon="${2:-}"
  test -n "${z_launcher}" || buto_fatal "buto_launch_expect_fatal: launcher required"
  test -n "${z_colophon}" || buto_fatal "buto_launch_expect_fatal: colophon required"
  shift 2

  zbuto_invoke "${z_launcher}" "${z_colophon}" "$@"

  buto_fatal_on_success "${ZBUTO_STATUS}" "Expected failure but got success" \
                                          "Launcher: ${z_launcher}"          \
                                          "Colophon: ${z_colophon}"          \
                                          "STDOUT: ${ZBUTO_STDOUT}"          \
                                          "STDERR: ${ZBUTO_STDERR}"
}

# eof
