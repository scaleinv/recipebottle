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
# Recipe Bottle Foundry Ledger - yoke cluster (guard-free, sourced by rbflk_):
# validate a reliquary touchmark against GAR, then rewrite RBRV_RELIQUARY across every
# vessel's rbrv.env (Director credentials).

set -euo pipefail

######################################################################
# Yoke (rbfl_*)

rbfl_yoke() {
  zrbfl_sentinel

  local -r z_express="${BUZ_FOLIO:-}"

  buc_doc_brief "Yoke a reliquary touchmark into every vessel's rbrv.env — pre-validate the conclave Lode once against GAR, then rewrite RBRV_RELIQUARY across all vessels under \${RBRR_VESSEL_DIR}"
  buc_doc_param "touchmark" "Reliquary Lode touchmark (e.g., r260327172456); optional — absent, falls back to the reliquary touchmark a conclave chained forward"
  buc_doc_shown || return 0

  # Relay-then-read (RBr_3e7): forward the chain baton before any read or failure point.
  buf_relay || buc_die "Failed to relay chained facts"

  # Resolve the reliquary touchmark express-or-chain: an express argument wins;
  # absent, fall back to the touchmark a conclave handed forward through the
  # depth-1 chain.
  local z_stamp=""
  z_stamp=$(buf_elect_fact_capture "${z_express}" "${RBF_FACT_LODE_TOUCHMARK}") \
    || buc_reject "${BUBC_band_chain}" "No reliquary touchmark — pass one (param1) or run a reliquary conclave immediately before yoke"

  # Assert the touchmark is a reliquary kind up front by decoding its kind-letter
  # prefix. yoke validates existence against GAR below but never asserted KIND, so
  # a non-reliquary touchmark would otherwise fail late at cohort validation. This
  # is the express-path kind gate (a bare touchmark), distinct from the chaining
  # channel's own brand fact that the conjure election reads.
  local z_kind=""
  z_kind=$(zrbld_decode_touchmark_kind_capture "${z_stamp}") \
    || buc_reject "${BUBC_band_chain}" "Touchmark '${z_stamp}' has no recognizable Lode kind prefix"
  test "${z_kind}" = "${RBGC_LODE_KIND_RELIQUARY}" \
    || buc_reject "${BUBC_band_chain}" "Touchmark '${z_stamp}' is kind '${z_kind}', not a reliquary — yoke requires a reliquary Lode (run a reliquary conclave)"

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  buc_step "Validating reliquary Lode: ${z_stamp}"
  local -r z_pkg="${RBGL_LODES_ROOT}/${z_stamp}"
  local -r z_pkg_encoded="${z_pkg//\//%2F}"
  local -r z_tags_url="${ZRBFC_GAR_API_BASE}/${ZRBFC_GAR_PACKAGE_BASE}/packages/${z_pkg_encoded}/tags?pageSize=1000"
  local -r z_list_infix="rbfl_yoke_list"

  rbuh_json "GET" "${z_tags_url}" "${z_token}" "${z_list_infix}"
  rbuh_require_ok "List conclave Lode tags" "${z_list_infix}"

  local -r z_resp_file="${ZRBUH_PREFIX}${z_list_infix}${ZRBUH_POSTFIX_JSON}"
  local -r z_present_file="${BURD_TEMP_DIR}/rbfl_yoke_present.txt"

  jq -r '.tags[]?.name | sub(".*/tags/"; "")' "${z_resp_file}" > "${z_present_file}" \
    || buc_die "Failed to extract conclave Lode member tags"

  local z_present=()
  local z_line=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    z_present+=("${z_line}")
  done < "${z_present_file}"

  # Expected cohort members as SPRUED tags (:rbi_<tool>) — compose RBGC_LODE_TAG_SPRUE
  # onto each bare tool seed, matching the conclave member-tag scheme (rbgjl03). The
  # seeds stay inputs; the membership check is always against the sprued member tag.
  local -r z_expected=(
    "${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_GCLOUD}"
    "${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_DOCKER}"
    "${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_ALPINE}"
    "${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_SYFT}"
    "${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_BINFMT}"
    "${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_GCRANE}"
  )

  local z_missing=""
  local z_tool=""
  for z_tool in "${z_expected[@]}"; do
    local z_found=0
    local z_i=""
    for z_i in "${!z_present[@]}"; do
      test "${z_present[$z_i]}" = "${z_tool}" || continue
      z_found=1
      break
    done
    case "${z_found}" in
      1) ;;
      *) z_missing="${z_missing}${z_missing:+, }${z_tool}" ;;
    esac
  done

  # Derive count and roster from the expected array so a cohort change (a tool
  # added or evicted) keeps these messages accurate without a hand-edit.
  local z_roster=""
  local z_r=""
  for z_r in "${z_expected[@]}"; do z_roster="${z_roster}${z_roster:+, }${z_r}"; done

  # Render the conclave-tabtarget hint from its colophon home (RBZ_CONCLAVE_RELIQUARY)
  # via the tt yawp — never a hardcoded tt/<colophon>.<frontispiece>.sh literal, which
  # rots on rename. buc_die resolves the diastema-wrapped yelp through buyf_format_yawp.
  buyy_tt_yawp "${RBZ_CONCLAVE_RELIQUARY}"; local -r z_conclave_tt="${z_buym_yelp}"
  test -z "${z_missing}" || buc_die "Reliquary Lode '${z_stamp}' incomplete in Depot — expected ${#z_expected[@]} tool member tags on ${z_pkg}; missing: ${z_missing}. Re-run ${z_conclave_tt} to capture a fresh reliquary Lode, or verify the touchmark spelling."
  buc_info "Reliquary Lode valid — all ${#z_expected[@]} tool member tags present (${z_roster})"

  buc_step "Yoking ${z_stamp} into all vessels under ${RBRR_VESSEL_DIR}"

  local z_written=()
  local z_vessel_dir=""
  local z_rbrv_file=""
  local z_sigil=""
  local z_tmp_file=""
  local z_rbrv_lines=()
  local z_rbrv_line=""
  local z_wrote=0
  local z_j=""

  for z_vessel_dir in "${RBRR_VESSEL_DIR}"/*/; do
    test -d "${z_vessel_dir}" || continue
    z_rbrv_file="${z_vessel_dir%/}/${RBCC_rbrv_file}"
    test -f "${z_rbrv_file}" || continue
    z_sigil="${z_vessel_dir%/}"
    z_sigil="${z_sigil##*/}"

    z_rbrv_lines=()
    while IFS= read -r z_rbrv_line || test -n "${z_rbrv_line}"; do
      z_rbrv_lines+=("${z_rbrv_line}")
    done < "${z_rbrv_file}"

    z_tmp_file="${BURD_TEMP_DIR}/rbfl_yoke_${z_sigil}_${RBCC_rbrv_file}.new"
    : > "${z_tmp_file}" \
      || buc_die "Failed to create ${z_tmp_file} (yoking ${z_sigil}; already wrote: ${z_written[*]:-(none)})"

    z_wrote=0
    for z_j in "${!z_rbrv_lines[@]}"; do
      case "${z_rbrv_lines[$z_j]}" in
        RBRV_RELIQUARY=*)
          printf 'RBRV_RELIQUARY=%s\n' "${z_stamp}" >> "${z_tmp_file}" \
            || buc_die "Failed to write RBRV_RELIQUARY for ${z_sigil} (already wrote: ${z_written[*]:-(none)})"
          z_wrote=1
          ;;
        *)
          printf '%s\n' "${z_rbrv_lines[$z_j]}" >> "${z_tmp_file}" \
            || buc_die "Failed to write line for ${z_sigil} (already wrote: ${z_written[*]:-(none)})"
          ;;
      esac
    done

    case "${z_wrote}" in
      1) ;;
      *) printf '\n# Tool Image Reliquary\nRBRV_RELIQUARY=%s\n' "${z_stamp}" >> "${z_tmp_file}" \
           || buc_die "Failed to append RBRV_RELIQUARY for ${z_sigil} (already wrote: ${z_written[*]:-(none)})" ;;
    esac

    mv "${z_tmp_file}" "${z_rbrv_file}" \
      || buc_die "Failed to finalize ${z_rbrv_file} (yoking ${z_sigil}; already wrote: ${z_written[*]:-(none)})"

    z_written+=("${z_sigil}")
    buc_log_args "Yoked ${z_sigil}"
  done

  test "${#z_written[@]}" -gt 0 \
    || buc_die "No vessels found under ${RBRR_VESSEL_DIR} — nothing yoked"

  buc_success "Yoked ${#z_written[@]} vessel(s) to reliquary ${z_stamp}"
  buc_info "Vessels: ${z_written[*]}"
  buc_info "Commit the rbrv.env changes with your usual git workflow."
  buc_info "Reminder: the reliquary tool images are now linked, but vessel images must be rebuilt (ordain) to pick up the new tool versions."
}

# eof
