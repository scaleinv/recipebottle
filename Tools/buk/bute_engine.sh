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
# BUK Test Engine - _tcase boundary runner

set -euo pipefail

# Source test-case API
ZBUTE_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
source "${ZBUTE_SCRIPT_DIR}/buto_operations.sh"

######################################################################
# _tcase boundary — case isolation subshell

# _tcase boundary runner: execute case function in isolation subshell
zbute_tcase() {
  set -e

  local z_case_name="${1}"
  declare -F "${z_case_name}" >/dev/null || buto_fatal "Test function not found: ${z_case_name}"

  buto_section "START: ${z_case_name}"

  local z_case_temp_dir="${ZBUTE_ROOT_TEMP_DIR}/${z_case_name}"
  mkdir -p "${z_case_temp_dir}" || buto_fatal "Failed to create test temp dir: ${z_case_temp_dir}"

  local z_status=0
  (
    set -e
    export BUT_TEMP_DIR="${z_case_temp_dir}"
    export BUTE_BURV_ROOT="${z_case_temp_dir}/burv"
    "${z_case_name}"
  ) || z_status=$?

  buto_trace "Ran: ${z_case_name} and got status:${z_status}"
  buto_fatal_on_error "${z_status}" "Test failed: ${z_case_name}"

  buto_trace "Finished: ${z_case_name} with status: ${z_status}"
  echo "${ZBUTO_GREEN}PASSED:${ZBUTO_RESET} ${z_case_name}" >&2
}

# eof
