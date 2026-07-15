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
# RBRD CLI - Command line interface for RBRD depot regime operations

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# Command Functions

# Command: validate - enrollment-based validation report
rbrd_validate() {
  buc_doc_brief "Validate RBRD depot regime configuration via enrollment report"
  buc_doc_shown || return 0

  buc_step "Validating RBRD depot regime file: ${RBCC_rbrd_file}"
  buv_report RBRD "Depot Regime"
  buc_step "RBRD depot regime valid"
}

# Command: render - diagnostic display of all RBRD fields
rbrd_render() {
  buc_doc_brief "Display diagnostic view of RBRD depot regime configuration"
  buc_doc_shown || return 0

  buv_render RBRD "RBRD - Recipe Bottle Regime Depot" "${RBCC_rbrd_file}"
}

######################################################################
# Furnish and Main

# Furnish receives the dispatched command name as $1 (per buc_execute's
# contract), enabling per-command differential setup: validate/render
# stay lightweight (just RBRD enrollment); check/inscribe need the full
# GAR-coordinate machinery (RBRR + RBDC + RBGC + RBGL) plus the rbndb
# bespoke module for the tripwire image FQN.
zrbrd_furnish() {
  local -r z_command="${1:-}"

  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env_done || return 0

  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"

  source "${BURD_BUK_DIR}/bug_git.sh"
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/bupr_regime.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbrd_regime.sh"
  source "${RBCC_rbrd_file}"

  zbuv_kindle
  zburd_kindle
  zburd_enforce
  zrbcc_kindle

  zrbrd_kindle
  zrbrd_enforce

  zbupr_kindle

  case "${z_command}" in
    rbrd_check|rbrd_inscribe)
      source "${z_rbk_kit_dir}/rbrr_regime.sh"
      source "${RBCC_rbrr_file}"
      source "${z_rbk_kit_dir}/rbgc_constants.sh"
      source "${z_rbk_kit_dir}/rbgl_layout.sh"
      source "${z_rbk_kit_dir}/rbdc_derived.sh"
      source "${z_rbk_kit_dir}/rbndb_base.sh"

      zrbrr_kindle
      zrbrr_enforce
      zrbgc_kindle
      zrbgl_kindle
      zrbdc_kindle
      zrbndb_kindle
      ;;
  esac
}

buc_execute rbrd_ "Recipe Bottle Depot Regime" zrbrd_furnish "$@"

# eof
