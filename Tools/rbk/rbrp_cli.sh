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
# RBRP CLI - Command line interface for RBRP payor operations

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# Command Functions

rbrp_validate() {
  buc_doc_brief "Validate RBRP payor regime configuration via enrollment report"
  buc_doc_shown || return 0

  buc_step "Validating RBRP payor file: ${RBCC_rbrp_file}"
  buv_report RBRP "Payor Regime"
  buc_step "RBRP payor valid"
}

rbrp_render() {
  buc_doc_brief "Display diagnostic view of RBRP payor regime configuration"
  buc_doc_shown || return 0

  buv_render RBRP "RBRP - Recipe Bottle Regime Payor" "${RBCC_rbrp_file}"
}

######################################################################
# Furnish and Main

zrbrp_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env_done || return 0

  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/bupr_regime.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbgc_constants.sh"
  source "${z_rbk_kit_dir}/rbrp_regime.sh"

  zbuv_kindle
  zburd_kindle
  zburd_enforce
  zrbcc_kindle
  zrbgc_kindle

  source "${RBCC_rbrp_file}" || buc_die "Failed to source RBRP: ${RBCC_rbrp_file}"

  zrbrp_kindle
  zrbrp_enforce

  zbupr_kindle
}

buc_execute rbrp_ "Recipe Bottle Payor Regime" zrbrp_furnish "$@"

# eof
