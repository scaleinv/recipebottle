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
# Recipe Bottle Lode - reliquary body (guard-free cluster, sourced by rbld0_lode):
#   conclave — convene the build-tool cohort into a Lode (Director credentials)
# The reliquary rides the capture-assembly spine (rblds_): this body owns only the
# kind-specific data — the conclave recipe (gcrane cohort capture + vouch-push)
# and the substitutions blob — and composes them through
# zrbld_spine_dispatch / zrbld_spine_extract_single. No build-submission or
# step-composition machinery lives here.
#
# Conclave captures the build-tool cohort:
# one rbi_ld package holding N member tags (:rbi_<tool>) plus the :rbi_vouch envelope. Both
# steps ride the floating gcrane builder (ZRBLD_GCRANE_BUILDER): the tools captured
# here ARE the reliquary, so capture cannot bootstrap from one — conclave is the
# generation phase the pinning rule permits to run unpinned (RBS0 rbsk_pinning_boundary).

set -euo pipefail

# Conclave is capture-pure: it writes no consumer config. It hands the captured
# touchmark to a later explicit yoke election through one bare single-form
# chaining fact (RBF_FACT_LODE_TOUCHMARK) via the depth-1 cross-tabtarget chain;
# yoke decodes the reliquary kind from the touchmark prefix. The provenance
# envelope lives only in GAR (:rbi_vouch tag, pushed cloud-side by rbgjl02),
# never host-side.

######################################################################
# Internal Helpers (zrbld_*)

# Internal: compose the conclave capture recipe (gcrane cohort capture + vouch-push)
# and its substitutions blob, then ride the capture spine to submit
# and poll. The spine owns the capture-domain build knobs (mason SA, TETHER pool,
# regime timeout); this body chooses only the recipe, the substitutions, and the
# heavy capture poll ceiling (the cohort copy needs the larger budget).
# Args: token stamp
zrbld_conclave_submit() {
  zrbld_sentinel

  local -r z_token="${1:?Token required}"
  local -r z_stamp="${2:?Stamp required}"

  buc_step "Constructing conclave capture recipe"
  local -r z_gar_host="${RBGD_GAR_LOCATION}${RBGC_GAR_HOST_SUFFIX}"
  local -r z_gar_path="${RBGD_GAR_PROJECT_ID}/${RBDC_GAR_REPOSITORY}"

  # Recipe rows: script_path|builder_image|id|entrypoint, pre-resolved for the
  # spine. Both steps ride the floating gcrane builder (busybox entrypoint —
  # gcrane:debug's only shell) — no reliquary bootstrap (conclave IS what captures
  # the reliquary tools; generation-tier, the one phase allowed unpinned).
  local -r z_recipe=(
    "${ZRBLD_RBGJL_STEPS_DIR}/rbgjl03-conclave-capture.sh|${ZRBLD_GCRANE_BUILDER}|conclave-capture|busybox"
    "${ZRBLD_RBGJL_STEPS_DIR}/rbgjl02-assemble-push-vouch.sh|${ZRBLD_GCRANE_BUILDER}|assemble-push-vouch|busybox"
  )

  buc_log_args "Composing conclave substitutions blob"
  local -r z_subs_file="${ZRBLD_CONCLAVE_PREFIX}subs.json"
  jq -n \
    --arg zjq_gar_host     "${z_gar_host}" \
    --arg zjq_gar_path     "${z_gar_path}" \
    --arg zjq_lodes_root   "${RBGL_LODES_ROOT}" \
    --arg zjq_tag_sprue    "${RBGC_LODE_TAG_SPRUE}" \
    --arg zjq_tag_vouch    "${RBGC_LODE_TAG_VOUCH}" \
    --arg zjq_trust_grade  "${RBGC_LODE_TRUST_VERIFIED}" \
    --arg zjq_vouch_schema "${RBGC_LODE_VOUCH_SCHEMA}" \
    --arg zjq_acquired_by  "${RBGD_MASON_EMAIL}" \
    --arg zjq_stamp        "${z_stamp}" \
    '{
      _RBGL_GAR_HOST:     $zjq_gar_host,
      _RBGL_GAR_PATH:     $zjq_gar_path,
      _RBGL_LODES_ROOT:   $zjq_lodes_root,
      _RBGL_TAG_SPRUE:    $zjq_tag_sprue,
      _RBGL_TAG_VOUCH:    $zjq_tag_vouch,
      _RBGL_TRUST_GRADE:  $zjq_trust_grade,
      _RBGL_VOUCH_SCHEMA: $zjq_vouch_schema,
      _RBGL_ACQUIRED_BY:  $zjq_acquired_by,
      _RBGL_LODE_STAMP:   $zjq_stamp
    }' > "${z_subs_file}" \
    || buc_die "Failed to compose conclave substitutions blob"

  zrbld_spine_dispatch \
    "${z_token}" "${RBGD_MASON_EMAIL}" "Conclave" "${ZRBFC_BUILD_POLL_CEILING_CAPTURE_HEAVY}" \
    "${z_subs_file}" "${ZRBLD_CONCLAVE_PREFIX}" \
    "${z_recipe[@]}"
}

######################################################################
# External Functions (rbld_*)

rbld_conclave() {
  zrbld_sentinel

  buc_doc_brief "Convene the build-tool cohort into one Lode (reliquary kind, rbi_ld capture)"
  buc_doc_shown || return 0

  # Dirty-tree guard — capture composes its cloud step bodies from the working
  # tree; the Lode's provenance envelope must be the product of committed code.
  bug_require_clean_tree_creed "${RBCC_creed_clean_capture}"

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  # Mint the Lode stamp on the host: <kind-letter><YYMMDDHHMMSS>. The host owns
  # the stamp so the touchmark is known before the build for the capture-file.
  local -r z_stamp="${RBGC_LODE_KIND_RELIQUARY}${BURD_NOW_STAMP:2:6}${BURD_NOW_STAMP:9:6}"

  buc_info "Lode: ${RBGL_LODES_ROOT}/${z_stamp}"

  zrbld_conclave_submit "${z_token}" "${z_stamp}"
  # Shared single-slot extract (rblds_): the capture step (step 0) authors the
  # output; the vouch-push step writes none.
  zrbld_spine_extract_single "${ZRBLD_CONCLAVE_PREFIX}" "${RBGC_LODE_BRAND_RELIQUARY}" "Conclave"

  buc_success "Conclave complete: build-tool cohort -> ${RBGL_LODES_ROOT}/${z_stamp}"
}

# eof
