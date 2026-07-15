#!/bin/bash
#
# Copyright 2025 Scale Invariant, Inc.
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
# BURC Regime - Bash Utility Regime Configuration Module

set -euo pipefail

# Multiple inclusion detection
test -z "${ZBURC_SOURCED:-}" || buc_die "Module burc multiply sourced - check sourcing hierarchy"
ZBURC_SOURCED=1

######################################################################
# Internal Functions (zburc_*)

zburc_kindle() {
  test -z "${ZBURC_KINDLED:-}" || buc_die "Module burc already kindled"

  # No defaults set — buv uses ${!varname:-} for safe indirect expansion under set -u.
  # Unset variables are detected distinctly from empty by zbuv_check_capture.
  # Exception: BURC_BUK_DIR is derived from BURC_TOOLS_DIR at kindle time (before vet).
  readonly BURC_BUK_DIR="${BURC_TOOLS_DIR:-}/buk"

  # Enroll all BURC variables — single source of truth for validation and rendering

  buv_regime_enroll BURC

  buv_group_enroll "Station Reference"
  buv_string_enroll  BURC_STATION_FILE          1  512  "Path to developer's BURS station file"

  buv_group_enroll "Tabtarget Infrastructure"
  buv_string_enroll  BURC_TABTARGET_DIR         1  128  "Project dir containing launcher scripts"
  buv_string_enroll  BURC_TABTARGET_DELIMITER   1    1  "Token separator in tabtarget filenames"

  buv_group_enroll "Project Structure"
  buv_string_enroll  BURC_TOOLS_DIR             1  128  "Project dir containing tool scripts"
  buv_string_enroll  BURC_PROJECT_ROOT          1  512  "Repo root, expressed relative to burc.env"
  buv_string_enroll  BURC_MANAGED_KITS          1  512  "Comma-separated kit list for vvx"

  buv_group_enroll "Build Output"
  buv_string_enroll  BURC_TEMP_ROOT_DIR         1  512  "Parent dir for per-dispatch scratch subdirs (temp-<stamp>)"
  buv_string_enroll  BURC_OUTPUT_ROOT_DIR       1  512  "Parent dir containing 'current/', cleared and recreated each dispatch"

  buv_group_enroll "Logging"
  buv_xname_enroll   BURC_LOG_LAST              1   64  "Filename stem for last-run log"
  buv_xname_enroll   BURC_LOG_EXT               1   16  "Log file extension (without dot)"
  buv_string_enroll  BURC_BUK_DIR               1  256  "Derived: BUK directory"

  # Guard against unexpected BURC_ variables not in enrollment
  buv_scope_sentinel BURC BURC_

  # Export and lock all enrolled BURC_ variables — committed config,
  # needed by coordinator child processes across exec boundary
  buv_export_and_lock BURC

  readonly ZBURC_KINDLED=1
}

zburc_sentinel() {
  test "${ZBURC_KINDLED:-}" = "1" || buc_die "Module burc not kindled - call zburc_kindle first"
}

# Enforce all BURC enrollment validations
zburc_enforce() {
  zburc_sentinel

  buv_vet BURC
}

# eof
