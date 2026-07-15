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
# Recipe Bottle Foundry Ledger - anoint cluster (guard-free, sourced by rbfl0_):
# read the previous dispatch's build facts and rewrite RBRV_GRAFT_IMAGE in one
# graft vessel's rbrv.env. Operator-committed, never self-committing.

set -euo pipefail

######################################################################
# Anoint (rbfl_*)

rbfl_anoint() {
  zrbfl_sentinel

  local -r z_vessel="${BUZ_FOLIO:-}"

  buc_doc_brief "Anoint a graft vessel with the previous build's hallmark — read the chained build facts and rewrite RBRV_GRAFT_IMAGE in the vessel's rbrv.env"
  buc_doc_param "vessel" "Vessel sigil or path to vessel directory"
  buc_doc_shown || return 0

  # Relay-then-read (RBr_3e7): forward the chain baton before any read or failure point.
  buf_relay || buc_die "Failed to relay chained facts"

  test -n "${z_vessel}" || buc_die "Vessel required (param1)"

  # Resolve and load the vessel; anoint addresses graft-mode vessels only.
  zrbfc_resolve_vessel "${z_vessel}"
  local -r z_vessel_dir=$(<"${ZRBFC_VESSEL_RESOLVED_DIR_FILE}")
  test -n "${z_vessel_dir}" || buc_die "Empty resolved vessel path"
  zrbfc_load_vessel "${z_vessel_dir}"
  test "${RBRV_VESSEL_MODE:-}" = "rbnve_graft" \
    || buc_die "Vessel '${RBRV_SIGIL}' is not a graft vessel (mode: ${RBRV_VESSEL_MODE:-unset})"

  # Read the chained build facts through the shared express-or-chain resolver —
  # anoint carries no express path, so an empty express makes each resolve a pure
  # chain read through the same footing every other fact consumer uses. The
  # previous dispatch must be a build (kludge or ordain).
  buc_step "Reading chained build facts"
  local z_hallmark=""
  z_hallmark=$(buf_elect_fact_capture "" "${RBF_FACT_HALLMARK}") \
    || buc_reject "${BUBC_band_chain}" "No hallmark fact from the previous dispatch — run a build (kludge or ordain) immediately before anoint"
  local z_gar_root=""
  z_gar_root=$(buf_elect_fact_capture "" "${RBF_FACT_GAR_ROOT}") \
    || buc_reject "${BUBC_band_chain}" "No gar_root fact from the previous dispatch"
  local z_ark_stem=""
  z_ark_stem=$(buf_elect_fact_capture "" "${RBF_FACT_ARK_STEM}") \
    || buc_reject "${BUBC_band_chain}" "No ark_stem fact from the previous dispatch"

  local -r z_image_ref="${z_gar_root}/${z_ark_stem}/${RBGC_ARK_BASENAME_IMAGE}:${z_hallmark}"
  buc_info "Hallmark: ${z_hallmark}"
  buc_info "Image:    ${z_image_ref}"

  # Graft pushes from the local docker cache; a cloud-built hallmark is not
  # local, so flag the gap now rather than letting graft refuse later.
  docker image inspect "${z_image_ref}" > /dev/null 2>&1 \
    || buc_warn "Image not in the local docker cache — graft will refuse until it is present locally"

  buc_step "Anointing ${RBRV_SIGIL}"

  local -r z_rbrv_file="${z_vessel_dir%/}/${RBCC_rbrv_file}"
  test -f "${z_rbrv_file}" || buc_die "Vessel regime file not found: ${z_rbrv_file}"

  local z_rbrv_lines=()
  local z_rbrv_line=""
  while IFS= read -r z_rbrv_line || test -n "${z_rbrv_line}"; do
    z_rbrv_lines+=("${z_rbrv_line}")
  done < "${z_rbrv_file}"

  local -r z_tmp_file="${BURD_TEMP_DIR}/rbfl_anoint_${RBRV_SIGIL}_${RBCC_rbrv_file}.new"
  : > "${z_tmp_file}" || buc_die "Failed to create ${z_tmp_file}"

  local z_wrote=0
  local z_j=""
  for z_j in "${!z_rbrv_lines[@]}"; do
    case "${z_rbrv_lines[$z_j]}" in
      RBRV_GRAFT_IMAGE=*)
        printf 'RBRV_GRAFT_IMAGE=%s\n' "${z_image_ref}" >> "${z_tmp_file}" \
          || buc_die "Failed to write RBRV_GRAFT_IMAGE for ${RBRV_SIGIL}"
        z_wrote=1
        ;;
      *)
        printf '%s\n' "${z_rbrv_lines[$z_j]}" >> "${z_tmp_file}" \
          || buc_die "Failed to write line for ${RBRV_SIGIL}"
        ;;
    esac
  done

  case "${z_wrote}" in
    1) ;;
    *) printf '\n# Grafting Configuration\nRBRV_GRAFT_IMAGE=%s\n' "${z_image_ref}" >> "${z_tmp_file}" \
         || buc_die "Failed to append RBRV_GRAFT_IMAGE for ${RBRV_SIGIL}" ;;
  esac

  mv "${z_tmp_file}" "${z_rbrv_file}" \
    || buc_die "Failed to finalize ${z_rbrv_file}"

  # Loud on success: name the written value and its source so a wrong anoint shows
  # at the moment of action, not only in the eventual git diff. Anoint reads the
  # build facts from the chain (no express path), so the source is always chain.
  buc_success "Anointed ${RBRV_SIGIL}: RBRV_GRAFT_IMAGE=${z_image_ref} (source: chain)"
  buc_info "Commit the rbrv.env change with your usual git workflow."
}

# eof
