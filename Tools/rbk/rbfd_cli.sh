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

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

zrbfd_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env "BURD_TEMP_DIR         " "Bash Dispatch Utility provided temporary directory, empty at start of command"
  buc_doc_env "BURD_NOW_STAMP        " "Bash Dispatch Utility provided string unique between invocations"
  buc_doc_env_done || return 0

  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"
  source "${BURD_BUK_DIR}/buf_fact.sh"
  source "${BURD_BUK_DIR}/bug_git.sh"
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbgc_constants.sh"
  source "${z_rbk_kit_dir}/rbgl_layout.sh"
  source "${z_rbk_kit_dir}/rbgd_depot.sh"
  source "${z_rbk_kit_dir}/rbrr_regime.sh"
  source "${z_rbk_kit_dir}/rbrd_regime.sh"
  source "${z_rbk_kit_dir}/rbrf_regime.sh"
  source "${z_rbk_kit_dir}/rbrw_regime.sh"
  source "${z_rbk_kit_dir}/rbdc_derived.sh"
  source "${RBCC_rbrr_file}"
  source "${RBCC_rbrd_file}"
  rbcc_source_active_rbrf
  source "${RBCC_rbrw_file}"
  source "${z_rbk_kit_dir}/rbgo_oauth.sh"
  source "${z_rbk_kit_dir}/rbuh_http.sh"
  source "${z_rbk_kit_dir}/rbge_rest.sh"
  source "${z_rbk_kit_dir}/rba_auth.sh"
  source "${z_rbk_kit_dir}/rbfh_hygiene.sh"
  source "${z_rbk_kit_dir}/rbfd_director.sh"
  source "${z_rbk_kit_dir}/rbfb_beckon.sh"
  source "${z_rbk_kit_dir}/rbndb_base.sh"
  source "${BURD_BUK_DIR}/buz_zipper.sh"
  source "${z_rbk_kit_dir}/rbz_zipper.sh"

  zbuv_kindle

  buc_log_args 'Validate BUD environment'
  zburd_kindle

  buc_log_args 'Validate required tools'
  command -v git >/dev/null 2>&1 || buc_die "git not found - required for assuring controlled build context"

  buc_log_args 'Container runtime settings'
  RBG_RUNTIME="${RBG_RUNTIME:-podman}"
  RBG_RUNTIME_ARG="${RBG_RUNTIME_ARG:-}"

  zrbcc_kindle

  zrbrr_kindle
  zrbrd_kindle
  zrbrf_kindle
  zrbrw_kindle
  zrbrr_enforce
  zrbrd_enforce
  zrbrf_enforce
  zrbrw_enforce
  zrbdc_kindle

  source "${z_rbk_kit_dir}/rbrv_regime.sh"

  buc_log_args 'Kindle modules in dependency order'
  zrbgc_kindle
  zrbgl_kindle
  zrbgd_kindle
  zrbgo_kindle
  zrbuh_kindle
  zrbge_kindle
  zrba_kindle
  zrbfh_kindle
  zrbfd_kindle
  zrbndb_kindle

  zbuz_kindle
  zrbz_kindle
}

buc_execute rbfd_ "Recipe Bottle Foundry Director Build" zrbfd_furnish "$@"

# eof
