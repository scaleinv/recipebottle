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
# Recipe Bottle Handbook Payor Ceremonies - Command Line Interface
#
# Full furnish: payor-only ceremonies require the complete regime +
# OAuth + IAM dependency stack.

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"

zrbhp_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env "BURD_TEMP_DIR         " "Temporary directory for intermediate files"
  buc_doc_env "BURD_OUTPUT_DIR       " "Directory for command outputs"
  buc_doc_env_done || return 0

  local -r z_rbk_kit_dir="${BASH_SOURCE[0]%/*}/.."
  local -r z_rbh0_dir="${z_rbk_kit_dir}/rbh0"

  source "${BURD_BUK_DIR}/burd_regime.sh"                  || buc_die "Failed to source burd_regime.sh"
  source "${BURD_BUK_DIR}/buv_validation.sh"               || buc_die "Failed to source buv_validation.sh"
  source "${BURD_BUK_DIR}/buym_yelp.sh"                    || buc_die "Failed to source buym_yelp.sh"
  source "${BURD_BUK_DIR}/buh_handbook.sh"                 || buc_die "Failed to source buh_handbook.sh"
  source "${z_rbk_kit_dir}/rbgc_constants.sh"              || buc_die "Failed to source rbgc_constants.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"              || buc_die "Failed to source rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbrr_regime.sh"                 || buc_die "Failed to source rbrr_regime.sh"
  source "${z_rbk_kit_dir}/rbrd_regime.sh"                 || buc_die "Failed to source rbrd_regime.sh"
  source "${z_rbk_kit_dir}/rbdc_derived.sh"       || buc_die "Failed to source rbdc_derived.sh"
  source "${RBCC_rbrr_file}"                               || buc_die "Failed to source ${RBCC_rbrr_file}"
  source "${RBCC_rbrd_file}" || buc_die "Failed to source RBRD: ${RBCC_rbrd_file}"
  source "${z_rbk_kit_dir}/rbrp_regime.sh"                 || buc_die "Failed to source rbrp_regime.sh"
  source "${z_rbk_kit_dir}/rbgo_oauth.sh"                  || buc_die "Failed to source rbgo_oauth.sh"
  source "${z_rbk_kit_dir}/rbuh_http.sh"                   || buc_die "Failed to source rbuh_http.sh"
  source "${z_rbk_kit_dir}/rbge_rest.sh"                   || buc_die "Failed to source rbge_rest.sh"
  source "${z_rbk_kit_dir}/rba_auth.sh"                    || buc_die "Failed to source rba_auth.sh"
  source "${z_rbk_kit_dir}/rbgi_iam.sh"                    || buc_die "Failed to source rbgi_iam.sh"
  source "${z_rbh0_dir}/rbhp0_payor.sh"       || buc_die "Failed to source rbhp0_payor.sh"
  source "${z_rbh0_dir}/rbhpe_establish.sh"   || buc_die "Failed to source rbhpe_establish.sh"
  source "${z_rbh0_dir}/rbhpq_quota_build.sh" || buc_die "Failed to source rbhpq_quota_build.sh"
  source "${z_rbh0_dir}/rbhpf_entra.sh"       || buc_die "Failed to source rbhpf_entra.sh"
  source "${BURD_BUK_DIR}/buz_zipper.sh"                   || buc_die "Failed to source buz_zipper.sh"
  source "${z_rbk_kit_dir}/rbz_zipper.sh"                  || buc_die "Failed to source rbz_zipper.sh"

  zbuv_kindle
  zburd_kindle
  zrbcc_kindle

  zrbrr_kindle
  zrbrd_kindle
  zrbrr_enforce
  zrbrd_enforce
  zrbdc_kindle

  zrbgc_kindle

  source "${RBCC_rbrp_file}" || buc_die "Failed to source RBRP: ${RBCC_rbrp_file}"
  zrbrp_kindle
  zrbrp_enforce

  zrbgo_kindle
  zrbuh_kindle
  zrbge_kindle
  zrba_kindle
  zrbgi_kindle
  zrbhp_kindle
  zrbhp_enforce

  zbuz_kindle
  zrbz_kindle
}

buc_execute rbhp_ "Payor Ceremonies" zrbhp_furnish "$@"

# eof
