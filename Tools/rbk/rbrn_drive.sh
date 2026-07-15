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
# Recipe Bottle Nameplate - drive cluster (guard-free): resolve a hallmark
# express-or-chain and write it into one target nameplate's RBRN_BOTTLE_HALLMARK
# or RBRN_SENTRY_HALLMARK line. The durable-config LINK for the nameplate/hallmark
# chain — sibling of feoff/anoint/yoke on the rbch_enchase surface, but writing
# the rbrn_regime family rather than rbrv_regime. Sourced by rbrn_cli (the cloud
# operator verb) and by rbob (the local kludge composes it). Operator-committed,
# never self-committing.

set -euo pipefail

######################################################################
# Drive (rbrn_*)

rbrn_drive() {
  local -r z_nameplate="${BUZ_FOLIO:-}"
  local -r z_field="${1:-}"
  local -r z_express="${2:-}"

  buc_doc_brief "Drive a freshly-built hallmark into a nameplate — resolve the hallmark express-or-chain and rewrite RBRN_BOTTLE_HALLMARK or RBRN_SENTRY_HALLMARK in the nameplate's rbrn.env"
  buc_doc_param "nameplate" "Target nameplate moniker"
  buc_doc_param "field"     "Which hallmark to drive: 'bottle' or 'sentry'"
  buc_doc_param "hallmark"  "Hallmark tag (e.g., k260327172456); optional — absent, falls back to the hallmark a build handed forward through the depth-1 chain"
  buc_doc_shown || return 0

  # Relay-then-read (RBr_3e7): forward the chain baton before any read or failure point.
  buf_relay || buc_die "Failed to relay chained facts"

  test -n "${z_nameplate}" || buc_die "Nameplate required (param1)"

  # Map the operator-facing field selector to the RBRN variable. A two-value
  # ashlar selector (bottle|sentry), never the raw variable name.
  local z_var_name=""
  case "${z_field}" in
    bottle) z_var_name="RBRN_BOTTLE_HALLMARK" ;;
    sentry) z_var_name="RBRN_SENTRY_HALLMARK" ;;
    "")     buc_die "Field required (param2): 'bottle' or 'sentry'" ;;
    *)      buc_die "Unknown field '${z_field}' — expected 'bottle' or 'sentry'" ;;
  esac

  # Resolve the target nameplate's rbrn.env by moniker WITHOUT loading it. The
  # drive rewrites one line; loading the regime would enforce the field's
  # min-length and reject a still-blank hallmark — the very state the drive fills.
  # Mirrors feoff, which never loads the vessel whose rbrv.env it rewrites.
  local -r z_rbrn_file="${RBCC_moorings_dir}/${z_nameplate}/${RBCC_rbrn_file}"
  test -f "${z_rbrn_file}" || buc_die "Nameplate regime file not found: ${z_rbrn_file}"

  # Resolve the hallmark express-or-chain: an express argument wins; absent, the
  # value a build (kludge or ordain) handed forward through the depth-1 chain.
  # No clean-tree gate here (RBr_a52).
  local z_hallmark=""
  z_hallmark=$(buf_elect_fact_capture "${z_express}" "${RBF_FACT_HALLMARK}") \
    || buc_reject "${BUBC_band_chain}" "No hallmark — pass one (param3) or run a build (kludge or ordain) immediately before drive"
  local z_source="chain"
  test -z "${z_express}" || z_source="express"

  buc_step "Driving ${z_var_name} into ${z_nameplate} (source ${z_source})"

  # Replace-or-die the chosen field's line. RBRN_{BOTTLE,SENTRY}_HALLMARK is a
  # required enrolled field always present in a well-formed nameplate — a missing
  # line is schema drift, a hard die (the find-or-err schema-drift catch), never a
  # silent append (contrast anoint, whose RBRV_GRAFT_IMAGE may legitimately be
  # absent and is appended).
  local -r z_tmp_file="${BURD_TEMP_DIR}/rbrn_drive_${z_nameplate}_${RBCC_rbrn_file}.new"
  local z_line=""
  local z_found=false
  while IFS= read -r z_line || test -n "${z_line}"; do
    if [[ "${z_line}" == ${z_var_name}=* ]]; then
      printf '%s\n' "${z_var_name}=${z_hallmark}"; z_found=true
    else
      printf '%s\n' "${z_line}"
    fi
  done < "${z_rbrn_file}" > "${z_tmp_file}" \
    || buc_die "Failed to rewrite ${z_rbrn_file} for ${z_var_name}"
  test "${z_found}" = "true" \
    || buc_die "Field ${z_var_name} not found in ${z_rbrn_file} — nameplate schema drift"
  mv "${z_tmp_file}" "${z_rbrn_file}" || buc_die "Failed to finalize ${z_rbrn_file}"

  # Loud on success: the driven field, value, and source named prominently, so a
  # wrong drive shows at the moment of action rather than only in the git diff.
  buc_success "Drove ${z_nameplate}: ${z_var_name}=${z_hallmark} (source: ${z_source})"
  buc_info "Commit the rbrn.env change with your usual git workflow."
}

# eof
