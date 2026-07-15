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
# BURS CLI - Command line interface for BURS regime operations

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# Command Functions

burs_validate() {
  buc_doc_brief "Validate BURS station regime configuration via enrollment report"
  buc_doc_shown || return 0

  buc_step "Validating BURS station regime: ${BURD_STATION_FILE}"
  buv_report BURS "Station Regime"
  buc_step "BURS station regime valid"
}

burs_render() {
  buc_doc_brief "Display diagnostic view of BURS station regime configuration"
  buc_doc_shown || return 0

  buv_render BURS "BURS - Bash Utility Station Regime" "${BURD_STATION_FILE}"
}

######################################################################
# Furnish and Main

zburs_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env_done || return 0

  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/burs_regime.sh"
  source "${BURD_BUK_DIR}/bupr_regime.sh"

  zbuv_kindle
  zburd_kindle
  zburd_enforce

  source "${BURD_STATION_FILE}" || buc_die "Failed to source BURS: ${BURD_STATION_FILE}"

  zburs_kindle
  zburs_enforce

  zbupr_kindle
}

buc_execute burs_ "Bash Utility Station Regime" zburs_furnish "$@"

# eof
