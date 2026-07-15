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
# Recipe Bottle GCP Payor - Billing and Destructive Operations CLI

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"

zrbgp_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env_done || return 0

  local -r z_command="${1:-}"

  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/bug_git.sh"
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/buym_yelp.sh"
  source "${BURD_BUK_DIR}/buh_handbook.sh"
  source "${BURD_BUK_DIR}/buf_fact.sh"
  source "${z_rbk_kit_dir}/rbgc_constants.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbpc_constants.sh"
  source "${z_rbk_kit_dir}/rbrr_regime.sh"
  source "${z_rbk_kit_dir}/rbrd_regime.sh"
  source "${z_rbk_kit_dir}/rbrf_regime.sh"
  source "${z_rbk_kit_dir}/rbrw_regime.sh"
  source "${z_rbk_kit_dir}/rbdc_derived.sh"
  source "${z_rbk_kit_dir}/rbgd_depot.sh"
  source "${RBCC_rbrr_file}"
  source "${RBCC_rbrd_file}"
  # Federation regime file. affiance and jilt are folio-addressed (param1,
  # RBSMA/RBSMJ): each sources the NAMED foedus's rbrf.env, resolved from the
  # operator-supplied folio (an rbef_-sprued library subdirectory) exactly as
  # descry addresses its subject — never the active/pinned foedus, whose selector
  # (RBRR_ACTIVE_FOEDUS) is reserved for the credential accessor. Every other payor
  # verb reads the active foedus, resolved from RBRR_ACTIVE_FOEDUS. An unresolvable
  # folio is an arg-validation precondition (imprecise buc_die, BCG carve-out).
  case "${z_command}" in
    rbgp_manor_affiance|rbgp_manor_jilt)
      local z_folio="${BUZ_FOLIO:-}"
      [[ "${z_folio}" == rbef_* ]] \
        || buc_die "Foedus folio required (param1), an rbef_-sprued library name: got '${z_folio}'"
      local z_folio_rbrf=""
      z_folio_rbrf=$(rbcc_rbrf_file_capture "${z_folio}") \
        || buc_die "Failed to resolve the foedus regime path for folio '${z_folio}'"
      test -f "${z_folio_rbrf}" \
        || buc_die "No foedus '${z_folio}' in the foedera library: ${z_folio_rbrf}"
      source "${z_folio_rbrf}"
      ;;
    *)
      rbcc_source_active_rbrf
      ;;
  esac
  source "${RBCC_rbrw_file}"
  source "${z_rbk_kit_dir}/rbgl_layout.sh"
  source "${z_rbk_kit_dir}/rbgo_oauth.sh"
  source "${z_rbk_kit_dir}/rbuh_http.sh"
  source "${z_rbk_kit_dir}/rbge_rest.sh"
  source "${z_rbk_kit_dir}/rba_auth.sh"
  source "${z_rbk_kit_dir}/rbgi_iam.sh"
  source "${z_rbk_kit_dir}/rbgb_buckets.sh"
  source "${z_rbk_kit_dir}/rbgft_terrier.sh"
  source "${z_rbk_kit_dir}/rbgw_capabilities.sh"
  source "${z_rbk_kit_dir}/rbrp_regime.sh"
  source "${z_rbk_kit_dir}/rbgp_payor.sh"
  source "${z_rbk_kit_dir}/rbndb_base.sh"
  source "${BURD_BUK_DIR}/buz_zipper.sh"
  source "${z_rbk_kit_dir}/rbz_zipper.sh"

  buc_log_args 'Initialize modules'
  zbuv_kindle
  zburd_kindle
  zrbcc_kindle

  zrbrr_kindle
  zrbrd_kindle
  zrbrf_kindle
  zrbrw_kindle
  # Per-command regime enforcement. depot_list scans all depots and needs no one
  # depot/repo regime; manor_escheat likewise scans every polity slice in the
  # payor-project terrier (RBRP supplies the bucket, enforced unconditionally
  # below) and probes depot liveness by what it finds, never by a configured
  # depot. manor_affiance and manor_jilt are manor-level founding/
  # un-founding ops that work the federation trust independent of any one depot,
  # so they enforce the federation regimes (RBRW manor pool + RBRF provider)
  # instead of the depot/repo regimes. manor_raze (the pool-destroyer) touches
  # only the pool, so it enforces RBRW alone — it reads no provider field.
  # manor_instaurate (the manor-setup finisher) founds the pool AND the payor-project
  # terrier bucket, so it enforces RBRW (pool) + RBRD (the bucket's region rides
  # RBRD_GCP_REGION) — no provider, no repo; the depot-grain polity folder is
  # founded at depot levy, not here.
  # The polity admission verbs
  # (brevet/unseat/attaint/rehearse) work a specific depot AND don the governor
  # mantle, so they enforce the federation regimes (RBRW pool id + RBRF provider +
  # sitting machinery — the don's STS audience rides the provider) on top of the
  # depot/repo regimes. Gird (the payor-wielded founding first-governor admission)
  # drives the shared core with the payor credential, not a don, and the
  # pool-scoped admission core reads no provider (RBSTN), so gird enforces RBRW
  # without RBRF — an active foedus need not stand before the founding admission.
  # Every other command works a specific depot.
  case "${z_command}" in
    rbgp_depot_list|rbgp_manor_escheat)                 : ;;
    rbgp_manor_affiance|rbgp_manor_jilt)                zrbrw_enforce; zrbrf_enforce ;;
    rbgp_manor_raze)                                    zrbrw_enforce ;;
    rbgp_manor_instaurate)                              zrbrw_enforce; zrbrd_enforce ;;
    rbgp_gird)                                          zrbrw_enforce; zrbrr_enforce; zrbrd_enforce ;;
    rbgp_brevet|rbgp_unseat|rbgp_attaint|rbgp_rehearse) zrbrw_enforce; zrbrf_enforce; zrbrr_enforce; zrbrd_enforce ;;
    *)                                                  zrbrr_enforce; zrbrd_enforce ;;
  esac
  zrbdc_kindle

  zrbgc_kindle
  zrbgd_kindle
  zrbgl_kindle

  source "${RBCC_rbrp_file}" || buc_die "Failed to source RBRP: ${RBCC_rbrp_file}"
  zrbrp_kindle
  zrbrp_enforce

  zrbgo_kindle
  zrbuh_kindle
  zrbge_kindle
  zrba_kindle
  zrbgi_kindle
  zrbgb_kindle
  zrbgft_kindle
  zrbgw_kindle
  zrbgp_kindle
  zrbndb_kindle

  zbuz_kindle
  zrbz_kindle
}

buc_execute rbgp_ "Recipe Bottle Payor" zrbgp_furnish "$@"

# eof
