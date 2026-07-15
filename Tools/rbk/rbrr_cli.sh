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
# RBRR CLI - Command line interface for RBRR repo regime operations

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# Command Functions

# Command: validate - enrollment-based validation report
rbrr_validate() {
  buc_doc_brief "Validate RBRR repo regime configuration via enrollment report"
  buc_doc_shown || return 0

  buc_step "Validating RBRR repo regime file: ${RBCC_rbrr_file}"
  buv_report RBRR "Repository Regime"
  buc_step "RBRR repo regime valid"
}

# Command: render - diagnostic display of all RBRR fields
rbrr_render() {
  buc_doc_brief "Display diagnostic view of RBRR repo regime configuration"
  buc_doc_shown || return 0

  buv_render RBRR "RBRR - Recipe Bottle Regime Repo" "${RBCC_rbrr_file}"
}

######################################################################
# Furnish and Main

zrbrr_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env_done || return 0

  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"

  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/bupr_regime.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbrr_regime.sh"
  source "${RBCC_rbrr_file}"

  zbuv_kindle
  zburd_kindle
  zburd_enforce
  zrbcc_kindle

  zrbrr_kindle
  zrbrr_enforce

  zbupr_kindle
}

buc_execute rbrr_ "Recipe Bottle Repository Regime" zrbrr_furnish "$@"

# eof
