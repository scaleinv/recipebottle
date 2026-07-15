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
# RBOB CLI - Recipe Bottle Orchestration Bottle command-line interface
#
# Command roster: rbz_zipper.sh (rbw-c Crucible group).

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# CLI Commands

rbob_validate() {
  zrbob_sentinel

  buc_doc_brief "Validate that RBOB configuration is complete and runnable"
  buc_doc_shown || return 0

  buc_step "RBOB Validate: ${RBRN_MONIKER}"

  # All values computed at kindle - just verify they exist
  test -n "${ZRBOB_RUNTIME}" || buc_die "ZRBOB_RUNTIME not set"
  test -n "${ZRBOB_SENTRY}" || buc_die "ZRBOB_SENTRY not set"
  test -n "${ZRBOB_PENTACLE}" || buc_die "ZRBOB_PENTACLE not set"
  test -n "${ZRBOB_BOTTLE}" || buc_die "ZRBOB_BOTTLE not set"
  test -n "${ZRBOB_NETWORK}" || buc_die "ZRBOB_NETWORK not set"
  test -f "${ZRBOB_SENTRY_SCRIPT}" || buc_die "Sentry script not found: ${ZRBOB_SENTRY_SCRIPT}"
  test -f "${ZRBOB_PENTACLE_SCRIPT}" || buc_die "Pentacle script not found: ${ZRBOB_PENTACLE_SCRIPT}"
  test -f "${ZRBOB_COMPOSE_BASE}" || buc_die "Compose base not found: ${ZRBOB_COMPOSE_BASE}"

  buc_step "RBOB configuration valid"
  echo "Moniker:       ${RBRN_MONIKER}"
  echo "Runtime:       ${ZRBOB_RUNTIME}"
  echo "Sentry:        ${ZRBOB_SENTRY}"
  echo "Pentacle:        ${ZRBOB_PENTACLE}"
  echo "Bottle:        ${ZRBOB_BOTTLE}"
  echo "Network:       ${ZRBOB_NETWORK}"
  echo "Compose base:  ${ZRBOB_COMPOSE_BASE}"
  echo "Compose frag:  ${ZRBOB_COMPOSE_FRAGMENT} ($(test -f "${ZRBOB_COMPOSE_FRAGMENT}" && echo 'exists' || echo 'not found'))"
}

rbob_info() {
  zrbob_sentinel

  buc_doc_brief "Show container names, network, and runtime for kindled nameplate"
  buc_doc_shown || return 0

  buc_step "RBOB Info: ${RBRN_MONIKER}"
  echo "Runtime:   ${ZRBOB_RUNTIME}"
  echo "Sentry:    ${ZRBOB_SENTRY}"
  echo "Pentacle:    ${ZRBOB_PENTACLE}"
  echo "Bottle:    ${ZRBOB_BOTTLE}"
  echo "Network:   ${ZRBOB_NETWORK}"
  echo "Sentry IP: ${RBRN_ENCLAVE_SENTRY_IP}"
  echo "Bottle IP: ${RBRN_ENCLAVE_BOTTLE_IP}"
}

rbob_scry() {
  zrbob_sentinel

  buc_doc_brief "Observe network traffic on Crucible containers"
  buc_doc_oparm "duration" "bounded capture window for scripted use (e.g. 10, 30s, 1m); omit for interactive run-until-Ctrl+C"
  buc_doc_oparm "filter"   "tcpdump filter expression scoping every leg (e.g. 'host 10.242.0.2')"
  buc_doc_shown || return 0

  # Kindle observe module and delegate
  zrboo_kindle
  rboo_observe "$@"
}

rbob_charged() {
  zrbob_sentinel

  buc_doc_brief "Check whether the Crucible is charged (compose project has running containers)"
  buc_doc_shown || return 0

  rbob_charged_predicate
}

######################################################################
# Furnish and Main

zrbob_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env "BUZ_FOLIO             " "Nameplate moniker (e.g., tadmor)"
  buc_doc_env_done || return 0

  local z_command="${1:-}"

  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${z_rbk_kit_dir}/rbrn_regime.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbrr_regime.sh"
  source "${z_rbk_kit_dir}/rbrd_regime.sh"
  source "${z_rbk_kit_dir}/rbrf_regime.sh"
  source "${z_rbk_kit_dir}/rbrw_regime.sh"
  source "${z_rbk_kit_dir}/rbdc_derived.sh"
  source "${RBCC_rbrr_file}"
  source "${RBCC_rbrd_file}"
  rbcc_source_active_rbrf
  source "${RBCC_rbrw_file}"
  source "${z_rbk_kit_dir}/rbgc_constants.sh"
  source "${z_rbk_kit_dir}/rbgl_layout.sh"
  source "${z_rbk_kit_dir}/rbgd_depot.sh"
  source "${z_rbk_kit_dir}/rbgo_oauth.sh"
  source "${z_rbk_kit_dir}/rba_auth.sh"
  source "${z_rbk_kit_dir}/rbob_bottle.sh"
  source "${z_rbk_kit_dir}/rbrn_drive.sh"
  source "${BURD_BUK_DIR}/buf_fact.sh"
  source "${BURD_BUK_DIR}/bug_git.sh"
  source "${z_rbk_kit_dir}/rbfh_hygiene.sh"
  source "${z_rbk_kit_dir}/rbfk_kludge.sh"
  source "${z_rbk_kit_dir}/rbfb_beckon.sh"
  source "${z_rbk_kit_dir}/rboo_observe.sh"
  source "${BURD_BUK_DIR}/buz_zipper.sh"
  source "${z_rbk_kit_dir}/rbz_zipper.sh"

  zbuv_kindle
  zburd_kindle
  zrbcc_kindle

  local z_folio="${BUZ_FOLIO:-}"
  if test -z "${z_folio}"; then
    local z_monikers
    z_monikers=$(rbrn_list_capture) || buc_die "No nameplates found"
    buc_step "Available nameplates:"
    local z_moniker=""
    for z_moniker in ${z_monikers}; do
      buc_bare "        ${z_moniker}"
    done
    buc_die "Nameplate moniker required (pass as argument)"
  fi
  local z_nameplate_file="${RBCC_moorings_dir}/${z_folio}/${RBCC_rbrn_file}"
  test -f "${z_nameplate_file}" || buc_die "Nameplate not found: ${z_nameplate_file}"
  source "${z_nameplate_file}" || buc_die "Failed to source nameplate: ${z_nameplate_file}"
  zrbrn_kindle

  # Differential enforce: nameplate-keyed kludge commands write
  # RBRN_*_HALLMARK, so zrbrn_enforce would self-veto on marshal-zero
  # state where those fields are blank by design (rblm zeroes them;
  # rbtdrp_lifecycle treats them as RBTDRP_RBRN_BLANK_FIELDS). Strict
  # validation lives in rbw-rnv (rbrn_cli.sh). Mirrors the yoke/RBRV
  # split (rbfl_cli vs rbrv_cli).
  case "${z_command}" in
    rbob_kludge_bottle|rbob_kludge_sentry)
      ;;
    *)
      zrbrn_enforce
      ;;
  esac

  zrbrr_kindle
  zrbrd_kindle
  zrbrf_kindle
  zrbrw_kindle
  zrbrr_enforce
  zrbrd_enforce
  zrbrf_enforce
  zrbrw_enforce
  zrbdc_kindle
  zrbgc_kindle
  zrbgl_kindle
  zrbgd_kindle
  zrbgo_kindle
  zrba_kindle
  zrbob_kindle

  # rbfh kindle (Dockerfile hygiene) — load-bearing for both kludge and ordain
  # since both wired callsites invoke rbfh_dockerfile_check.
  zrbfh_kindle

  # Kludge commands need the uncredentialed foundry-kludge module.
  case "${z_command}" in
    rbob_kludge_bottle|rbob_kludge_sentry)
      zrbfk_kindle
      ;;
  esac

  zbuz_kindle
  zrbz_kindle
}

buc_execute rbob_ "Recipe Bottle Orchestration" zrbob_furnish "$@"

# eof
