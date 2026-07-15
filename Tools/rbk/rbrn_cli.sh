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
# RBRN CLI - Command line interface for RBRN nameplate regime operations
#
# Differential furnish: light deps (validate, render) always loaded;
# heavy deps (survey, audit) loaded only when needed.

set -euo pipefail

# Source dependencies
source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# Internal Helpers

# Fleet info table — non-opinionated display of all nameplate configuration
# Requires: RBCC, RBGC, RBGD kindled + RBRR loaded (via differential furnish)
zrbrn_fleet_survey() {
  zrbcc_sentinel
  zrbgc_sentinel
  zrbgd_sentinel
  zrbrr_sentinel

  local z_gar_base="${RBGD_GAR_LOCATION}${RBGC_GAR_HOST_SUFFIX}/${RBGD_GAR_PROJECT_ID}/${RBDC_GAR_REPOSITORY}"
  local -r z_row_fmt="%-10s %-8s %6s %6s  %-17s %-14s %-14s  %3s %3s\n"
  echo ""
  printf "${z_row_fmt}" \
    "Moniker" "Entry" "WS" "Enc" "Subnet" "Sentry IP" "Bottle IP" "Snt" "Btl"
  printf "${z_row_fmt}" \
    "--------" "-----" "------" "------" "-----------------" "--------------" "--------------" "---" "---"

  local z_sv_files=("${RBCC_moorings_dir}/"*"/${RBCC_rbrn_file}")
  local z_sv_i=""
  for z_sv_i in "${!z_sv_files[@]}"; do
    test -f "${z_sv_files[$z_sv_i]}" || continue
    (
      source "${z_sv_files[$z_sv_i]}" || buc_die "Failed to source: ${z_sv_files[$z_sv_i]}"

      local z_sentry_img="${z_gar_base}/${RBGL_HALLMARKS_ROOT}/${RBRN_SENTRY_HALLMARK}/${RBGC_ARK_BASENAME_IMAGE}:${RBRN_SENTRY_HALLMARK}"
      local z_bottle_img="${z_gar_base}/${RBGL_HALLMARKS_ROOT}/${RBRN_BOTTLE_HALLMARK}/${RBGC_ARK_BASENAME_IMAGE}:${RBRN_BOTTLE_HALLMARK}"

      local z_sentry_local="--"
      local z_bottle_local="--"
      if command -v "${RBRN_RUNTIME}" >/dev/null 2>&1; then
        ${RBRN_RUNTIME} image inspect "${z_sentry_img}" >/dev/null 2>&1 && z_sentry_local="ok"
        ${RBRN_RUNTIME} image inspect "${z_bottle_img}" >/dev/null 2>&1 && z_bottle_local="ok"
      else
        z_sentry_local="??"
        z_bottle_local="??"
      fi

      local z_ws_port="${RBRN_ENTRY_PORT_WORKSTATION:-}"
      local z_enc_port="${RBRN_ENTRY_PORT_ENCLAVE:-}"
      if [[ "${RBRN_ENTRY_MODE}" != "rbnne_enabled" ]]; then
        z_ws_port="-"
        z_enc_port="-"
      fi

      printf "${z_row_fmt}" \
        "${RBRN_MONIKER}" "${RBRN_ENTRY_MODE}" "${z_ws_port}" "${z_enc_port}" \
        "${RBRN_ENCLAVE_BASE_IP}/${RBRN_ENCLAVE_NETMASK}" \
        "${RBRN_ENCLAVE_SENTRY_IP}" "${RBRN_ENCLAVE_BOTTLE_IP}" \
        "${z_sentry_local}" "${z_bottle_local}" || buc_die "Failed to printf survey row"
    ) || buc_die "Survey isolation failed for: ${z_sv_files[$z_sv_i]}"
  done
  echo ""
}

######################################################################
# Command Functions

# Command: validate - enrollment-based validation report
rbrn_validate() {
  buc_doc_brief "Validate RBRN nameplate regime configuration via enrollment report"
  buc_doc_shown || return 0

  if test -z "${BUZ_FOLIO:-}"; then
    rbrn_list
    buc_die "Nameplate moniker required"
  fi
  buc_step "Validating RBRN nameplate regime"
  buv_report RBRN "Nameplate Regime"
  buc_step "RBRN nameplate valid"
}

# Command: render - diagnostic display
rbrn_render() {
  buc_doc_brief "Display diagnostic view of RBRN nameplate regime configuration"
  buc_doc_shown || return 0

  if test -z "${BUZ_FOLIO:-}"; then
    rbrn_list
    buc_die "Nameplate moniker required"
  fi
  local z_nameplate_file="${RBCC_moorings_dir}/${BUZ_FOLIO}/${RBCC_rbrn_file}"
  buv_render RBRN "RBRN - Recipe Bottle Regime Nameplate" "${z_nameplate_file}"
}

# Command: survey - fleet info table across all nameplates
rbrn_survey() {
  buc_doc_brief "Survey nameplate status — display the configuration table for every nameplate"
  buc_doc_shown || return 0

  zrbrn_fleet_survey
}

# Command: audit - survey display then preflight validation
rbrn_audit() {
  buc_doc_brief "Validate all nameplates — survey every nameplate, then run cross-nameplate preflight validation"
  buc_doc_shown || return 0

  zrbrn_fleet_survey
  rbrn_preflight
  buc_step "Cross-nameplate audit passed"

  buc_step "Full audit passed (nameplates)"
}

# Command: list - show available nameplate monikers
rbrn_list() {
  buc_doc_brief "List available nameplate monikers"
  buc_doc_shown || return 0

  local z_monikers
  z_monikers=$(rbrn_list_capture) || buc_die "No nameplates found"
  buc_step "Available nameplates:"
  local z_moniker=""
  for z_moniker in ${z_monikers}; do
    buc_bare "        ${z_moniker}"
  done
}

######################################################################
# Furnish and Main

zrbrn_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env_done || return 0

  local z_command="${1:-}"

  # Light sources (always)
  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/bupr_regime.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbrn_regime.sh"

  # Heavy sources (survey/audit only)
  case "${z_command}" in
    rbrn_survey|rbrn_audit)
      source "${z_rbk_kit_dir}/rbrr_regime.sh"
      source "${z_rbk_kit_dir}/rbrd_regime.sh"
      source "${z_rbk_kit_dir}/rbdc_derived.sh"
      source "${z_rbk_kit_dir}/rbgc_constants.sh"
      source "${z_rbk_kit_dir}/rbgl_layout.sh"
      source "${z_rbk_kit_dir}/rbgd_depot.sh"
      source "${z_rbk_kit_dir}/rbgo_oauth.sh"
      ;;
    rbrn_drive)
      # Drive needs only the fact-name constants (rbgc) and the express-or-chain
      # footing (buf_fact) — not the google/GAR stack survey/audit pulls.
      source "${z_rbk_kit_dir}/rbgc_constants.sh"
      source "${BURD_BUK_DIR}/buf_fact.sh"
      source "${z_rbk_kit_dir}/rbrn_drive.sh"
      ;;
  esac

  # Light kindles (always)
  zbuv_kindle
  zburd_kindle
  zburd_enforce
  zbupr_kindle
  zrbcc_kindle
  test "${z_rbk_kit_dir}" = "${RBCC_KIT_DIR}" || buc_die "z_rbk_kit_dir mismatch: ${z_rbk_kit_dir} != ${RBCC_KIT_DIR}"

  # Heavy kindles (survey/audit only)
  case "${z_command}" in
    rbrn_survey|rbrn_audit)
      source "${RBCC_rbrr_file}"
      source "${RBCC_rbrd_file}"
      zrbgc_kindle
      zrbgl_kindle
      zrbrr_kindle
      zrbrd_kindle
      zrbrr_enforce
      zrbrd_enforce
      zrbdc_kindle
      zrbgo_kindle
      zrbgd_kindle
      ;;
    rbrn_drive)
      # rbgc holds RBF_FACT_HALLMARK; it is standalone (pure readonly constants).
      zrbgc_kindle
      ;;
  esac

  # If BUZ_FOLIO is set, load and kindle the specified nameplate — EXCEPT for
  # rbrn_drive, which addresses a target nameplate by moniker and rewrites one
  # RBRN_*_HALLMARK line WITHOUT loading it (loading enforces the regime, which
  # would reject a nameplate whose hallmark field is still blank — the very state
  # the drive fills; mirrors feoff, which never loads the vessel it rewrites).
  if test -n "${BUZ_FOLIO:-}" && test "${z_command}" != "rbrn_drive"; then
    local z_nameplate_file="${RBCC_moorings_dir}/${BUZ_FOLIO}/${RBCC_rbrn_file}"
    test -f "${z_nameplate_file}" || buc_die "Nameplate not found: ${z_nameplate_file}"
    source "${z_nameplate_file}" || buc_die "Failed to source nameplate: ${z_nameplate_file}"
    zrbrn_kindle
    zrbrn_enforce
  fi
}

buc_execute rbrn_ "Recipe Bottle Nameplate Regime" zrbrn_furnish "$@"

# eof
