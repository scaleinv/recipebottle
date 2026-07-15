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
# BUTCBX - BURX exchange test cases for BUK self-test
#
# Verifies that bud_dispatch.sh produces well-formed burx.env via
# dual-write during dispatch.  These cases inspect the current dispatch's
# own output — the dispatch IS the integration test for buf_write_fact_single.
# All tests are pure local — no GCP, no containers, no network.

set -euo pipefail

######################################################################
# Test cases — direct assertions inside zbute_tcase subshell

butcbx_burx_dual_write_tcase() {
  buto_trace "BURX: burx.env exists in both output and temp dirs (dual-write)"

  test -f "${BURD_TEMP_DIR}/${BUF_burx_env}"  || buto_fatal "Missing temp dir copy"
  test -f "${BURD_OUTPUT_DIR}/${BUF_burx_env}" || buto_fatal "Missing output dir copy"

  local -r z_tmp_content=$(<"${BURD_TEMP_DIR}/${BUF_burx_env}")
  local -r z_out_content=$(<"${BURD_OUTPUT_DIR}/${BUF_burx_env}")
  test "${z_tmp_content}" = "${z_out_content}" \
    || buto_fatal "Dual-write mismatch between output and temp dirs"
}

butcbx_burx_fields_tcase() {
  buto_trace "BURX: burx.env is sourceable and has all initial fields"

  local -r z_burx="${BURD_TEMP_DIR}/${BUF_burx_env}"

  # Verify sourceable in a subshell
  local z_status=0
  ( source "${z_burx}" ) || z_status=$?
  test "${z_status}" -eq 0 || buto_fatal "burx.env is not sourceable (status ${z_status})"

  # Source and check all initial fields
  source "${z_burx}"

  test -n "${BURX_PID:-}"        || buto_fatal "BURX_PID missing or empty"
  test -n "${BURX_BEGAN_AT:-}"   || buto_fatal "BURX_BEGAN_AT missing or empty"
  test -n "${BURX_TABTARGET:-}"  || buto_fatal "BURX_TABTARGET missing or empty"
  test -n "${BURX_TEMP_DIR:-}"   || buto_fatal "BURX_TEMP_DIR missing or empty"
  test -n "${BURX_TRANSCRIPT:-}" || buto_fatal "BURX_TRANSCRIPT missing or empty"
  test -n "${BURX_LOG_HIST:-}"   || buto_fatal "BURX_LOG_HIST missing or empty"

  # BURX_LABEL may be empty — verify it is declared (not missing)
  local -r z_label_check="${BURX_LABEL+declared}"
  test "${z_label_check}" = "declared" || buto_fatal "BURX_LABEL not declared in burx.env"
}

butcbx_burx_preexist_tcase() {
  buto_trace "BURX: buf_write_fact_single rejects preexisting file"

  local -r z_stderr="${BUT_TEMP_DIR}/preexist_stderr.txt"

  # burx.env already exists from this dispatch's initial write
  local z_status=0
  buf_write_fact_single "${BUF_burx_env}" "duplicate-write" 2>"${z_stderr}" || z_status=$?
  test "${z_status}" -ne 0 \
    || buto_fatal "buf_write_fact_single should have failed on preexisting burx.env"
}

butcbx_burx_timestamp_format_tcase() {
  buto_trace "BURX: BURX_BEGAN_AT matches nanosecond timestamp format"

  source "${BURD_TEMP_DIR}/${BUF_burx_env}"

  # Format: YYYYMMDD-HHMMSS.NNNNNNNNN
  local -r z_pattern='^[0-9]{8}-[0-9]{6}\.[0-9]{9}$'
  [[ "${BURX_BEGAN_AT}" =~ ${z_pattern} ]] \
    || buto_fatal "BURX_BEGAN_AT format invalid: '${BURX_BEGAN_AT}' (expected YYYYMMDD-HHMMSS.NNNNNNNNN)"
}

butcbx_multi_dual_write_tcase() {
  buto_trace "BUF multi: dual-writes <root>.<ext> to output and temp dirs with matching content"

  local -r z_root="butcbx_multi_a"
  local -r z_ext="probe"
  local -r z_filename="${z_root}.${z_ext}"
  buf_write_fact_multi "${z_root}" "${z_ext}" "alpha"

  test -f "${BURD_TEMP_DIR}/${z_filename}"   || buto_fatal "Missing temp dir copy: ${z_filename}"
  test -f "${BURD_OUTPUT_DIR}/${z_filename}" || buto_fatal "Missing output dir copy: ${z_filename}"

  local -r z_tmp_content=$(<"${BURD_TEMP_DIR}/${z_filename}")
  local -r z_out_content=$(<"${BURD_OUTPUT_DIR}/${z_filename}")
  test "${z_tmp_content}" = "${z_out_content}" \
    || buto_fatal "Dual-write mismatch for multi: ${z_filename}"
  test "${z_tmp_content}" = "alpha" \
    || buto_fatal "Multi content mismatch: got '${z_tmp_content}' expected 'alpha'"
}

butcbx_multi_preexist_tcase() {
  buto_trace "BUF multi: rejects preexisting file on second write"

  local -r z_root="butcbx_multi_b"
  local -r z_ext="probe"
  local -r z_stderr="${BUT_TEMP_DIR}/multi_preexist_stderr.txt"

  buf_write_fact_multi "${z_root}" "${z_ext}" "first"

  local z_status=0
  buf_write_fact_multi "${z_root}" "${z_ext}" "second" 2>"${z_stderr}" || z_status=$?
  test "${z_status}" -ne 0 \
    || buto_fatal "buf_write_fact_multi should have failed on preexisting file"
}

butcbx_multi_empty_content_tcase() {
  buto_trace "BUF multi: accepts empty content (presence is the fact) and uses registry ext"

  local -r z_root="butcbx_multi_c"
  local -r z_ext="${BUF_EXT_ALIAS}"
  local -r z_filename="${z_root}.${z_ext}"
  buf_write_fact_multi "${z_root}" "${z_ext}" ""

  test -f "${BURD_TEMP_DIR}/${z_filename}"   || buto_fatal "Missing temp dir copy: ${z_filename}"
  test -f "${BURD_OUTPUT_DIR}/${z_filename}" || buto_fatal "Missing output dir copy: ${z_filename}"
}

# eof
