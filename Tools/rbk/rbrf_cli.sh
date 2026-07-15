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
# RBRF CLI - Command line interface for RBRF federation regime operations

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# Command Functions

# Command: validate - enrollment-based validation report
rbrf_validate() {
  buc_doc_brief "Validate RBRF federation regime configuration via enrollment report"
  buc_doc_shown || return 0

  local z_rbrf
  z_rbrf=$(rbcc_rbrf_file_capture) || buc_die "No active foedus resolved — RBRR_ACTIVE_FOEDUS unset or blank"
  buc_step "Validating RBRF federation regime file: ${z_rbrf}"
  buv_report RBRF "Federation Regime"
  buc_step "RBRF federation regime valid"
}

# Command: render - diagnostic display of all RBRF fields
rbrf_render() {
  buc_doc_brief "Display diagnostic view of RBRF federation regime configuration"
  buc_doc_shown || return 0

  local z_rbrf
  z_rbrf=$(rbcc_rbrf_file_capture) || buc_die "No active foedus resolved — RBRR_ACTIVE_FOEDUS unset or blank"
  buv_render RBRF "RBRF - Recipe Bottle Regime Federation" "${z_rbrf}"
}

######################################################################
# Furnish and Main

zrbrf_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env_done || return 0

  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"

  source "${BURD_BUK_DIR}/bug_git.sh"
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/bupr_regime.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbrf_regime.sh"
  # The federation regime file is the ACTIVE foedus's rbrf.env, resolved from
  # RBRR_ACTIVE_FOEDUS — so this validator sources the repo regime first for the
  # selector, then the active rbrf. It reads the selector only; it does not
  # enforce RBRR (federation-scoped, like rbgv's depot-agnostic probes).
  source "${RBCC_rbrr_file}" || buc_die "Failed to source RBRR: ${RBCC_rbrr_file}"
  rbcc_source_active_rbrf

  zbuv_kindle
  zburd_kindle
  zburd_enforce
  zrbcc_kindle

  zrbrf_kindle
  zrbrf_enforce

  zbupr_kindle
}

buc_execute rbrf_ "Recipe Bottle Federation Regime" zrbrf_furnish "$@"

# eof
