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
# RBRV CLI - Command line interface for RBRV vessel regime operations

set -euo pipefail

# Source dependencies
source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# Command Functions

# Command: validate - enrollment-based validation report
rbrv_validate() {
  buc_doc_brief "Validate RBRV vessel regime configuration via enrollment report"
  buc_doc_shown || return 0

  if test -z "${BUZ_FOLIO:-}"; then
    rbrv_list
    buc_die "Vessel sigil required"
  fi
  buc_step "Validating RBRV vessel regime"
  buv_report RBRV "Vessel Regime"
  buc_step "RBRV vessel valid"
}

# Command: render - diagnostic display
rbrv_render() {
  buc_doc_brief "Display diagnostic view of RBRV vessel regime configuration"
  buc_doc_shown || return 0

  if test -z "${BUZ_FOLIO:-}"; then
    rbrv_list
    buc_die "Vessel sigil required"
  fi
  local z_vessel_file="${RBRR_VESSEL_DIR}/${BUZ_FOLIO}/${RBCC_rbrv_file}"
  buv_render RBRV "RBRV - Recipe Bottle Regime Vessel" "${z_vessel_file}"
}

# Command: list - show available vessel sigils
rbrv_list() {
  buc_doc_brief "List available vessel sigils"
  buc_doc_shown || return 0

  local z_sigils
  z_sigils=$(rbrv_list_capture) || buc_die "No vessels found"
  buc_step "Available vessels:"
  local z_sigil=""
  for z_sigil in ${z_sigils}; do
    buc_bare "        ${z_sigil}"
  done
}

######################################################################
# Furnish and Main

zrbrv_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env "BUZ_FOLIO             " "Vessel sigil (e.g., tadmor-sentry); empty for list"
  buc_doc_env_done || return 0

  # Sources (always)
  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/bupr_regime.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbgc_constants.sh"
  source "${z_rbk_kit_dir}/rbrr_regime.sh"
  source "${z_rbk_kit_dir}/rbrd_regime.sh"
  source "${z_rbk_kit_dir}/rbdc_derived.sh"
  source "${z_rbk_kit_dir}/rbrv_regime.sh"

  # Kindles (always)
  zbuv_kindle
  zburd_kindle
  zburd_enforce
  zbupr_kindle
  zrbcc_kindle

  # Load and kindle repo regime (needed for RBRR_VESSEL_DIR)
  source "${RBCC_rbrr_file}"
  source "${RBCC_rbrd_file}"
  zrbrr_kindle
  zrbrd_kindle
  zrbrr_enforce
  zrbrd_enforce
  zrbdc_kindle

  # If BUZ_FOLIO is set, load and kindle the specified vessel
  if test -n "${BUZ_FOLIO:-}"; then
    local z_vessel_file="${RBRR_VESSEL_DIR}/${BUZ_FOLIO}/${RBCC_rbrv_file}"
    test -f "${z_vessel_file}" || buc_die "Vessel not found: ${z_vessel_file}"
    source "${z_vessel_file}"  || buc_die "Failed to source vessel: ${z_vessel_file}"
    zrbrv_kindle
    zrbrv_enforce
  fi
}

buc_execute rbrv_ "Recipe Bottle Vessel Regime" zrbrv_furnish "$@"

# eof
