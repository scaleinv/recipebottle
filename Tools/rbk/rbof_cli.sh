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
# Recipe Bottle Foedus - test-bed cardinality verbs CLI (descry / instate / canvass)

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"

zrbof_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env "BURD_TEMP_DIR         " "Bash Dispatch Utility provided temporary directory, empty at start of command"
  buc_doc_env "BURD_OUTPUT_DIR       " "Bash Dispatch Utility provided output directory (fact files)"
  buc_doc_env_done || return 0

  local -r z_command="${1:-}"

  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"

  # Light core — sufficient for instate (a pure rbrr.env single-field rewrite)
  # and the foedus-resolution shared by both verbs.
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/buf_fact.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbof_foedus.sh"

  zbuv_kindle
  zburd_kindle
  zrbcc_kindle
  zrbof_kindle

  case "${z_command}" in
    rbof_descry|rbof_canvass)
      # descry and canvass read the org-level workforce-pool surface from the
      # Manor — the same payor-OAuth credential and IAM-REST stack affiance/jilt
      # use. instate needs none of this, so it is sourced/kindled only here.
      source "${z_rbk_kit_dir}/rbgc_constants.sh"
      source "${z_rbk_kit_dir}/rbrr_regime.sh"
      source "${z_rbk_kit_dir}/rbrd_regime.sh"
      source "${z_rbk_kit_dir}/rbdc_derived.sh"
      source "${z_rbk_kit_dir}/rbrp_regime.sh"
      source "${z_rbk_kit_dir}/rbgo_oauth.sh"
      source "${z_rbk_kit_dir}/rbuh_http.sh"
      source "${z_rbk_kit_dir}/rbge_rest.sh"
      source "${z_rbk_kit_dir}/rbgi_iam.sh"
      source "${z_rbk_kit_dir}/rba_auth.sh"
      source "${z_rbk_kit_dir}/rbgp_payor.sh"
      source "${RBCC_rbrr_file}" || buc_die "Failed to source RBRR: ${RBCC_rbrr_file}"
      source "${RBCC_rbrd_file}" || buc_die "Failed to source RBRD: ${RBCC_rbrd_file}"
      source "${RBCC_rbrp_file}" || buc_die "Failed to source RBRP: ${RBCC_rbrp_file}"

      # RBDC derives the RBRO/RBRA credential paths from BOTH the repo regime
      # (secrets dir) and the depot regime (cloud prefix), so RBRD must be
      # kindled before RBDC even though descry reads no depot resource.
      zrbgc_kindle
      zrbrr_kindle
      zrbrr_enforce
      zrbrd_kindle
      zrbrd_enforce
      zrbdc_kindle
      zrbrp_kindle
      zrbrp_enforce
      zrbgo_kindle
      zrbuh_kindle
      zrbge_kindle
      zrbgi_kindle
      zrba_kindle
      zrbgp_kindle
      ;;
    rbof_instate)
      : # the light core (rbcc + burd + rbof) is all instate needs
      ;;
    *)
      buc_die "rbof: unknown command '${z_command}'"
      ;;
  esac
}

buc_execute rbof_ "Recipe Bottle Foedus" zrbof_furnish "$@"

# eof
