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
# Recipe Bottle Handbook Onboarding - Command Line Interface
#
# Thin furnish: onboarding walkthroughs need only display infrastructure
# (buh handbook, buz/rbz zippers, rbcc/rbgc constants) — no regime, no
# OAuth, no full GCP stack. All probes work on the filesystem directly.

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"

zrbho_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env "BURD_TEMP_DIR         " "Temporary directory for intermediate files"
  buc_doc_env "BURD_OUTPUT_DIR       " "Directory for command outputs"
  buc_doc_env_done || return 0

  local -r z_rbk_kit_dir="${BASH_SOURCE[0]%/*}/.."
  local -r z_rbh0_dir="${z_rbk_kit_dir}/rbh0"

  source "${BURD_BUK_DIR}/buh_handbook.sh"           || buc_die "Failed to source buh_handbook.sh"
  source "${BURD_BUK_DIR}/buym_yelp.sh"             || buc_die "Failed to source buym_yelp.sh"
  source "${BURD_BUK_DIR}/buv_validation.sh"         || buc_die "Failed to source buv_validation.sh"
  source "${BURD_BUK_DIR}/buz_zipper.sh"             || buc_die "Failed to source buz_zipper.sh"
  source "${BURD_BUK_DIR}/buwz_zipper.sh"            || buc_die "Failed to source buwz_zipper.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"        || buc_die "Failed to source rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbgc_constants.sh"        || buc_die "Failed to source rbgc_constants.sh"
  source "${z_rbk_kit_dir}/rbrr_regime.sh"           || buc_die "Failed to source rbrr_regime.sh"
  source "${z_rbk_kit_dir}/rbrd_regime.sh"           || buc_die "Failed to source rbrd_regime.sh"
  source "${RBCC_rbrr_file}"                         || buc_die "Failed to source ${RBCC_rbrr_file}"
  source "${RBCC_rbrd_file}"                         || buc_die "Failed to source ${RBCC_rbrd_file}"
  source "${z_rbk_kit_dir}/rbyc_common.sh"            || buc_die "Failed to source rbyc_common.sh"
  source "${z_rbk_kit_dir}/rbz_zipper.sh"            || buc_die "Failed to source rbz_zipper.sh"
  zbuv_kindle
  zrbgc_kindle
  zbuz_kindle
  zbuwz_kindle
  zrbz_kindle
  # RBRR kindle only — thin-deps concession: enforce would fail on fresh installs
  # (filesystem gates for vessel/secrets dirs), blocking onboarding entry.
  zrbrr_kindle
  zrbrd_kindle
  zrbyc_kindle
  source "${z_rbh0_dir}/rbho0_onboarding.sh"            || buc_die "Failed to source rbho0_onboarding.sh"
  source "${z_rbh0_dir}/rbho0_start_here.sh"            || buc_die "Failed to source rbho0_start_here.sh"
  source "${z_rbh0_dir}/rbhocc_crash_course.sh"         || buc_die "Failed to source rbhocc_crash_course.sh"
  source "${z_rbh0_dir}/rbhoct_crucible_trunk.sh"       || buc_die "Failed to source rbhoct_crucible_trunk.sh"
  source "${z_rbh0_dir}/rbhocq_crucible_quench.sh"      || buc_die "Failed to source rbhocq_crucible_quench.sh"
  source "${z_rbh0_dir}/rbhofc_first_crucible.sh"       || buc_die "Failed to source rbhofc_first_crucible.sh"
  source "${z_rbh0_dir}/rbhots_tadmor_security.sh"      || buc_die "Failed to source rbhots_tadmor_security.sh"
  source "${z_rbh0_dir}/rbhodf_director_first_build.sh" || buc_die "Failed to source rbhodf_director_first_build.sh"
  source "${z_rbh0_dir}/rbhoda_director_airgap.sh"      || buc_die "Failed to source rbhoda_director_airgap.sh"
  source "${z_rbh0_dir}/rbhodb_director_bind.sh"        || buc_die "Failed to source rbhodb_director_bind.sh"
  source "${z_rbh0_dir}/rbhodg_director_graft.sh"       || buc_die "Failed to source rbhodg_director_graft.sh"
  source "${z_rbh0_dir}/rbhopw_payor_wrapper.sh"        || buc_die "Failed to source rbhopw_payor_wrapper.sh"
  zrbho_kindle
}

buc_execute rbho_ "Onboarding Guides" zrbho_furnish "$@"

# eof
