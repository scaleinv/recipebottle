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
# RBFH CLI - Recipe Bottle Foundry Hygiene command-line interface
#
# Surfaces the Dockerfile FROM-line constraint enforced by the rbfh
# library module so that theurge fixtures (and operators) can drive
# the contract from outside the kludge/conjure code paths.
#
# Commands:
#   check         Check a Dockerfile path for FROM-line hygiene
#   check_vessel  Check a vessel's RBRV_CONJURE_DOCKERFILE for hygiene

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# CLI Commands

rbfh_check() {
  zrbfh_sentinel

  buc_doc_brief "Check a Dockerfile against the FROM-line hygiene contract"
  buc_doc_param "dockerfile" "Path to the Dockerfile to check"
  buc_doc_shown || return 0

  local -r z_path="${BUZ_FOLIO:-}"
  test -n "${z_path}" || buc_die "Dockerfile path required (free-form path argument)"

  buc_step "RBFH Check: ${z_path}"
  rbfh_dockerfile_check "${z_path}"
  buc_success "Dockerfile passes hygiene contract: ${z_path}"
}

rbfh_check_vessel() {
  zrbfh_sentinel
  zrbfc_sentinel

  buc_doc_brief "Check a vessel's conjure Dockerfile against the FROM-line hygiene contract"
  buc_doc_param "vessel" "Vessel sigil or path to vessel directory"
  buc_doc_shown || return 0

  # Resolve vessel argument (sigil or path) — lists-and-dies on missing/invalid
  zrbfc_resolve_vessel "${BUZ_FOLIO:-}"
  local -r z_vessel_dir=$(<"${ZRBFC_VESSEL_RESOLVED_DIR_FILE}")
  test -n "${z_vessel_dir}" || buc_die "Empty resolved vessel path"

  # Source the vessel's rbrv.env to pick up RBRV_VESSEL_MODE and RBRV_CONJURE_DOCKERFILE
  source "${z_vessel_dir}/${RBCC_rbrv_file}" || buc_die "Failed to source vessel rbrv.env: ${z_vessel_dir}/${RBCC_rbrv_file}"

  # Hygiene is a property of the FROM line; non-conjure vessels have no
  # local Dockerfile, so the contract is vacuously satisfied. Exit silently
  # so callers iterating the whole fleet need not pre-filter by mode.
  if test "${RBRV_VESSEL_MODE:-}" != "rbnve_conjure"; then
    buc_info "Vessel '${RBRV_SIGIL:-${z_vessel_dir}}' is mode '${RBRV_VESSEL_MODE:-<unset>}' — no Dockerfile to check"
    return 0
  fi

  test -n "${RBRV_CONJURE_DOCKERFILE:-}" \
    || buc_die "Vessel '${RBRV_SIGIL:-${z_vessel_dir}}' has no RBRV_CONJURE_DOCKERFILE"

  buc_step "RBFH Check Vessel: ${RBRV_SIGIL:-${z_vessel_dir}} → ${RBRV_CONJURE_DOCKERFILE}"
  rbfh_dockerfile_check "${RBRV_CONJURE_DOCKERFILE}"
  buc_success "Vessel Dockerfile passes hygiene contract: ${RBRV_CONJURE_DOCKERFILE}"
}

######################################################################
# Furnish and Main

zrbfh_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env "BURD_TEMP_DIR         " "Bash Dispatch Utility provided temporary directory, empty at start of command"
  buc_doc_env "BUZ_FOLIO             " "Dockerfile path (rbfh_check) or vessel sigil/path (rbfh_check_vessel)"
  buc_doc_env_done || return 0

  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"
  source "${BURD_BUK_DIR}/buf_fact.sh"
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbgc_constants.sh"
  source "${z_rbk_kit_dir}/rbgl_layout.sh"
  source "${z_rbk_kit_dir}/rbgd_depot.sh"
  source "${z_rbk_kit_dir}/rbrr_regime.sh"
  source "${z_rbk_kit_dir}/rbrd_regime.sh"
  source "${z_rbk_kit_dir}/rbrv_regime.sh"
  source "${z_rbk_kit_dir}/rbdc_derived.sh"
  source "${RBCC_rbrr_file}"
  source "${RBCC_rbrd_file}"
  source "${z_rbk_kit_dir}/rbgo_oauth.sh"
  source "${z_rbk_kit_dir}/rbfc0_core.sh"
  source "${z_rbk_kit_dir}/rbfh_hygiene.sh"
  source "${BURD_BUK_DIR}/buz_zipper.sh"
  source "${z_rbk_kit_dir}/rbz_zipper.sh"

  zbuv_kindle
  zburd_kindle
  zrbcc_kindle

  zrbrr_kindle
  zrbrd_kindle
  zrbrr_enforce
  zrbrd_enforce
  zrbdc_kindle

  zrbgc_kindle
  zrbgl_kindle
  zrbgd_kindle
  zrbgo_kindle
  zrbfc_kindle
  zrbfh_kindle

  zbuz_kindle
  zrbz_kindle
}

buc_execute rbfh_ "Recipe Bottle Foundry Hygiene" zrbfh_furnish "$@"

# eof
