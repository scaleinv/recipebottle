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
# Recipe Bottle Foundry Ledger - feoff cluster (guard-free, sourced by rbfl0_):
# elect one conjure base anchor — resolve a bole Lode touchmark express-or-chain,
# decode-and-gate its kind to bole, then rewrite RBRV_IMAGE_n_ANCHOR in one
# vessel's rbrv.env. Extracted out of conjure (rbfd_build) so conjure reads no
# fact. Operator-committed, never self-committing (RBr_a52).

set -euo pipefail

######################################################################
# Feoff (rbfl_*)

rbfl_feoff() {
  zrbfl_sentinel

  local -r z_vessel="${BUZ_FOLIO:-}"
  local -r z_express="${1:-}"

  buc_doc_brief "Feoff a conjure vessel — elect its base anchor from a bole Lode touchmark (express-or-chain), rewriting RBRV_IMAGE_n_ANCHOR in the vessel's rbrv.env"
  buc_doc_param "vessel"    "Vessel sigil or path to vessel directory"
  buc_doc_param "touchmark" "Bole Lode touchmark (e.g., b260327172456); optional — absent, falls back to the bole touchmark an ensconce chained forward"
  buc_doc_shown || return 0

  # Relay-then-read (RBr_3e7): forward the chain baton before any read or failure point.
  buf_relay || buc_die "Failed to relay chained facts"

  test -n "${z_vessel}" || buc_die "Vessel required (param1)"

  # Resolve the vessel directory (sigil or path). feoff rewrites the rbrv.env
  # text directly — like the election it replaces, it never loads the vessel
  # (loading makes RBRV_* readonly, and feoff only touches one ANCHOR line).
  zrbfc_resolve_vessel "${z_vessel}"
  local -r z_vessel_dir=$(<"${ZRBFC_VESSEL_RESOLVED_DIR_FILE}")
  test -n "${z_vessel_dir}" || buc_die "Empty resolved vessel path"
  local -r z_rbrv_file="${z_vessel_dir%/}/${RBCC_rbrv_file}"
  test -f "${z_rbrv_file}" || buc_die "Vessel regime file not found: ${z_rbrv_file}"
  local z_sigil="${z_vessel_dir%/}"
  z_sigil="${z_sigil##*/}"

  # Resolve the bole touchmark express-or-chain: an express argument wins; absent,
  # fall back to the touchmark an ensconce handed forward through the depth-1
  # chain. No clean-tree gate here (RBr_a52).
  local z_touchmark=""
  z_touchmark=$(buf_elect_fact_capture "${z_express}" "${RBF_FACT_LODE_TOUCHMARK}") \
    || buc_reject "${BUBC_band_chain}" "No bole touchmark — pass one (param2) or run a bole ensconce immediately before feoff"
  local z_source="chain"
  test -z "${z_express}" || z_source="express"

  # Assert the touchmark is a bole kind up front by decoding its kind-letter prefix
  # — the single home for touchmark kind decode, shared with yoke. A non-bole
  # capture (an underpin or conclave chained ahead of this election) hands its own
  # touchmark forward but carries no base image to elect: reject up front rather
  # than fail late. This prefix decode is the sole kind channel — the chain carries
  # no separate kind-brand fact.
  local z_kind=""
  z_kind=$(zrbld_decode_touchmark_kind_capture "${z_touchmark}") \
    || buc_reject "${BUBC_band_chain}" "Touchmark '${z_touchmark}' has no recognizable Lode kind prefix"
  test "${z_kind}" = "${RBGC_LODE_KIND_BOLE}" \
    || buc_reject "${BUBC_band_chain}" "Touchmark '${z_touchmark}' is kind '${z_kind}', not a bole — feoff elects a base anchor, which only a bole capture carries"

  local -r z_locator="${RBGL_LODES_ROOT}/${z_touchmark}:${RBGC_LODE_TAG_BOLE}"

  # Find the single populated base ORIGIN slot (an ensconce captures exactly one).
  # Unlike the no-op-friendly election it replaces, feoff is a deliberate gate:
  # zero or several populated slots is an operator misconfiguration (the touchmark
  # cannot say which slot it belongs to) — a hard die, a failure class distinct
  # from the chain-band rejections above.
  local z_line=""
  local z_slot=""
  local z_count=0
  while IFS= read -r z_line || test -n "${z_line}"; do
    case "${z_line}" in
      RBRV_IMAGE_1_ORIGIN=?*) z_slot="1"; z_count=$((z_count + 1)) ;;
      RBRV_IMAGE_2_ORIGIN=?*) z_slot="2"; z_count=$((z_count + 1)) ;;
      RBRV_IMAGE_3_ORIGIN=?*) z_slot="3"; z_count=$((z_count + 1)) ;;
    esac
  done < "${z_rbrv_file}"
  case "${z_count}" in
    1) ;;
    0) buc_die "Vessel '${z_sigil}' has no populated RBRV_IMAGE_n_ORIGIN slot — nothing to feoff (feoff elects the anchor for a conjure base origin)" ;;
    *) buc_die "Vessel '${z_sigil}' has ${z_count} populated RBRV_IMAGE_n_ORIGIN slots — the touchmark cannot disambiguate which to anchor; pin the anchor manually" ;;
  esac

  buc_step "Electing base ANCHOR for ${z_sigil} (slot ${z_slot}, source ${z_source})"

  # Replace-or-append the chosen slot's ANCHOR line.
  local -r z_anchor_var="RBRV_IMAGE_${z_slot}_ANCHOR"
  local -r z_anchor_line="${z_anchor_var}=${z_locator}"
  local -r z_tmp_file="${BURD_TEMP_DIR}/rbfl_feoff_${z_sigil}_${RBCC_rbrv_file}.new"
  local z_found=false
  while IFS= read -r z_line || test -n "${z_line}"; do
    if [[ "${z_line}" == ${z_anchor_var}=* ]]; then
      printf '%s\n' "${z_anchor_line}"; z_found=true
    else
      printf '%s\n' "${z_line}"
    fi
  done < "${z_rbrv_file}" > "${z_tmp_file}" \
    || buc_die "Failed to rewrite ${z_rbrv_file} for ${z_anchor_var}"
  if [[ "${z_found}" != "true" ]]; then
    printf '%s\n' "${z_anchor_line}" >> "${z_tmp_file}" || buc_die "Failed to append ${z_anchor_var}"
  fi
  mv "${z_tmp_file}" "${z_rbrv_file}" || buc_die "Failed to finalize ${z_rbrv_file}"

  # Loud on success: the elected anchor and its source named prominently, so a
  # wrong election shows at the moment of action rather than only in the git diff.
  buc_success "Feoffed ${z_sigil}: ${z_anchor_var}=${z_locator} (source: ${z_source})"
  buc_info "Commit the rbrv.env change with your usual git workflow, then conjure builds FROM this committed anchor."
}

# eof
