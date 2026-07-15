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
# BURD Regime - Bash Utility Regime Dispatch Module
#
# BURD is an ephemeral regime — variables are constructed by bud_dispatch.sh during
# tabtarget execution, not sourced from a file.

set -euo pipefail

# Multiple inclusion detection
test -z "${ZBURD_SOURCED:-}" || buc_die "Module burd multiply sourced - check sourcing hierarchy"
ZBURD_SOURCED=1

######################################################################
# Internal Functions (zburd_*)

zburd_kindle() {
  test -z "${ZBURD_KINDLED:-}" || buc_die "Module burd already kindled"

  # No defaults set — buv uses ${!varname:-} for safe indirect expansion under set -u.
  # Unset variables are detected distinctly from empty by zbuv_check_capture.

  # Enroll all BURD variables — single source of truth for validation and rendering

  buv_regime_enroll BURD

  buv_group_enroll "Launcher Configuration"
  buv_string_enroll  BURD_CONFIG_DIR            1  256  "Path to the ${BURD_MOORINGS_DIR}/ configuration directory"
  buv_string_enroll  BURD_MOORINGS_DIR          1  256  "Basename of the config directory (repo-root-relative, for operator-facing display)"
  buv_string_enroll  BURD_REGIME_FILE           1  256  "Path to the BURC regime configuration file"
  buv_string_enroll  BURD_STATION_FILE          1  256  "Path to the developer's BURS station file"
  buv_string_enroll  BURD_COORDINATOR_SCRIPT    1  256  "Path to the coordinator script for this tabtarget"
  buv_string_enroll  BURD_LAUNCHER              1  256  "Launcher basename (e.g. launcher.rbw_workbench.sh), set by the tabtarget"
  buv_string_enroll  BURD_TERM_COLS             1    8  "Terminal column width at dispatch time"

  buv_group_enroll "Directory Paths"
  buv_string_enroll  BURD_TOOLS_DIR             1  256  "Tools directory path (from BURC)"
  buv_string_enroll  BURD_BUK_DIR               1  256  "BUK directory path (derived)"
  buv_string_enroll  BURD_TABTARGET_DIR         1  256  "Tabtarget directory path (from BURC)"

  buv_group_enroll "Computed State"
  buv_string_enroll  BURD_NOW_STAMP             1   64  "Timestamp string computed at dispatch time"
  buv_string_enroll  BURD_NOW_EPOCH             1   16  "UTC epoch seconds from same date invocation as BURD_NOW_STAMP"
  buv_string_enroll  BURD_TEMP_DIR              1  256  "Temporary directory for this invocation"
  buv_string_enroll  BURD_OUTPUT_DIR            1  256  "Output directory for this invocation (current/)"
  buv_string_enroll  BURD_PREVIOUS_DIR          1  256  "Prior dispatch's output directory (previous/), promoted from current/ at dispatch start"
  buv_string_enroll  BURD_TRANSCRIPT            1  256  "Path to transcript file for this invocation"
  buv_string_enroll  BURD_GIT_CONTEXT           1  128  "Git context string at dispatch time"
  buv_string_enroll  BURD_OSTYPE                1   32  "Operating-system type at dispatch time (e.g. cygwin, linux-gnu, darwin) — lets native binaries learn the platform bash already knows"

  buv_group_enroll "Parsed Tabtarget"
  buv_string_enroll  BURD_TARGET                1  256  "Target parsed from tabtarget filename"
  buv_string_enroll  BURD_COMMAND               1   64  "Command parsed from tabtarget filename"
  buv_string_enroll  BURD_TOKEN_1               1   64  "First token parsed from tabtarget filename"
  buv_string_enroll  BURD_TOKEN_2               1  128  "Second token parsed from tabtarget filename"
  buv_string_enroll  BURD_TOKEN_3               0   64  "Third token (optional)"
  buv_string_enroll  BURD_TOKEN_4               0   64  "Fourth token (optional)"
  buv_string_enroll  BURD_TOKEN_5               0   64  "Fifth token (optional)"

  buv_group_enroll "Caller Options"
  buv_string_enroll  BURD_NO_LOG                0   16  "Disable logging when set"
  buv_string_enroll  BURD_INTERACTIVE           0   16  "Interactive mode flag when set"

  buv_group_enroll "Log Paths"
  buv_string_enroll  BURD_LOG_LAST              0  256  "Path to last-run log file"
  buv_string_enroll  BURD_LOG_SAME              0  256  "Path to same-command log file"
  buv_string_enroll  BURD_LOG_HIST              0  256  "Path to historical log file"

  # BURD_CLI_ARGS is an array — enroll as optional string for scope_sentinel awareness
  buv_string_enroll  BURD_CLI_ARGS              0 9999  "CLI arguments (array, validated separately)"

  # Guard against unexpected BURD_ variables not in enrollment
  buv_scope_sentinel BURD BURD_

  # Lock all enrolled BURD_ variables against mutation
  buv_lock BURD

  readonly ZBURD_KINDLED=1
}

zburd_sentinel() {
  test "${ZBURD_KINDLED:-}" = "1" || buc_die "Module burd not kindled - call zburd_kindle first"
}

# Enforce all BURD enrollment validations
zburd_enforce() {
  zburd_sentinel

  buv_vet BURD

  # Custom enforce: log paths must be set when logging is active
  if test -z "${BURD_NO_LOG:-}" && test -n "${BURD_LOG_LAST:-}"; then
    test -n "${BURD_LOG_SAME:-}" || buc_die "BURD_LOG_SAME required when logging is active"
    test -n "${BURD_LOG_HIST:-}" || buc_die "BURD_LOG_HIST required when logging is active"
  fi
}

# eof
