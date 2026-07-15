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
# Recipe Bottle Lode - bole body (guard-free cluster, sourced by rbld0_lode):
#   ensconce — capture an upstream base image into a Lode (Director credentials)
# The bole rides the capture-assembly spine (rblds_): this body owns only the
# kind-specific data — the ensconce recipe (gcrane capture + vouch-push),
# the substitutions blob, and the touchmark-fact extract — and composes them
# through zrbld_spine_dispatch / zrbld_spine_extract. No build-submission or
# step-composition machinery lives here.

set -euo pipefail

# Ensconce is capture-pure: it writes no consumer config. It hands the captured
# bole touchmark to feoff (the conjure ANCHOR election) through one bare
# single-form chaining fact (RBF_FACT_LODE_TOUCHMARK) via the depth-1
# cross-tabtarget chain; feoff decodes the bole kind from the touchmark prefix.
# The provenance envelope lives only in GAR (:rbi_vouch tag, pushed cloud-side by
# rbgjl02), never host-side.

######################################################################
# Internal Helpers (zrbld_*)

# Internal: compose the ensconce capture recipe (gcrane capture + vouch-push) and
# its substitutions blob, then ride the capture spine to submit and
# poll. The spine owns the capture-domain build knobs (mason SA, TETHER pool,
# regime timeout); this body chooses only the recipe, the substitutions, and the
# light capture poll ceiling (a single small image copy).
# Args: token origin stamp
zrbld_ensconce_submit() {
  zrbld_sentinel

  local -r z_token="${1:?Token required}"
  local -r z_origin="${2:?Origin required}"
  local -r z_stamp="${3:?Stamp required}"

  buc_step "Constructing ensconce capture recipe"
  local -r z_gar_host="${RBGD_GAR_LOCATION}${RBGC_GAR_HOST_SUFFIX}"
  local -r z_gar_path="${RBGD_GAR_PROJECT_ID}/${RBDC_GAR_REPOSITORY}"

  # Recipe rows: script_path|builder_image|id|entrypoint, pre-resolved for the
  # spine. The | delimiter is load-bearing — builder refs carry colons (tags).
  # bole is a sealed-reliquary consumer: BOTH steps ride the PINNED reliquary gcrane
  # (z_rbfc_tool_gcrane), never the floating bootstrap — zero unpinned aspects.
  local -r z_recipe=(
    "${ZRBLD_RBGJL_STEPS_DIR}/rbgjl01-ensconce-capture.sh|${z_rbfc_tool_gcrane}|ensconce-capture|busybox"
    "${ZRBLD_RBGJL_STEPS_DIR}/rbgjl02-assemble-push-vouch.sh|${z_rbfc_tool_gcrane}|assemble-push-vouch|busybox"
  )

  buc_log_args "Composing ensconce substitutions blob"
  local -r z_subs_file="${ZRBLD_ENSCONCE_PREFIX}subs.json"
  jq -n \
    --arg zjq_gar_host     "${z_gar_host}" \
    --arg zjq_gar_path     "${z_gar_path}" \
    --arg zjq_lodes_root   "${RBGL_LODES_ROOT}" \
    --arg zjq_tag_bole     "${RBGC_LODE_TAG_BOLE}" \
    --arg zjq_tag_vouch    "${RBGC_LODE_TAG_VOUCH}" \
    --arg zjq_tag_digest   "${RBGC_LODE_TAG_DIGEST_PREFIX}" \
    --arg zjq_trust_grade  "${RBGC_LODE_TRUST_VERIFIED}" \
    --arg zjq_vouch_schema "${RBGC_LODE_VOUCH_SCHEMA}" \
    --arg zjq_acquired_by  "${RBGD_MASON_EMAIL}" \
    --arg zjq_origin_1     "${z_origin}" \
    --arg zjq_stamp_1      "${z_stamp}" \
    '{
      _RBGL_GAR_HOST:          $zjq_gar_host,
      _RBGL_GAR_PATH:          $zjq_gar_path,
      _RBGL_LODES_ROOT:        $zjq_lodes_root,
      _RBGL_TAG_BOLE:          $zjq_tag_bole,
      _RBGL_TAG_VOUCH:         $zjq_tag_vouch,
      _RBGL_TAG_DIGEST_PREFIX: $zjq_tag_digest,
      _RBGL_TRUST_GRADE:       $zjq_trust_grade,
      _RBGL_VOUCH_SCHEMA:      $zjq_vouch_schema,
      _RBGL_ACQUIRED_BY:       $zjq_acquired_by,
      _RBGL_IMAGE_1_ORIGIN:    $zjq_origin_1,
      _RBGL_IMAGE_2_ORIGIN:    "",
      _RBGL_IMAGE_3_ORIGIN:    "",
      _RBGL_LODE_1_STAMP:      $zjq_stamp_1,
      _RBGL_LODE_2_STAMP:      "",
      _RBGL_LODE_3_STAMP:      ""
    }' > "${z_subs_file}" \
    || buc_die "Failed to compose ensconce substitutions blob"

  zrbld_spine_dispatch \
    "${z_token}" "${RBGD_MASON_EMAIL}" "Ensconce" "${ZRBFC_BUILD_POLL_CEILING_CAPTURE_LIGHT}" \
    "${z_subs_file}" "${ZRBLD_ENSCONCE_PREFIX}" \
    "${z_recipe[@]}"
}

# Internal: extract the captured touchmark from the completed ensconce build and
# emit the two bare single-form chaining facts (touchmark value + kind-brand
# enum). The gcrane capture step (step 0) authors the base64 JSON carrying the
# host-minted stamp per slot; the vouch-push step writes no output. Base-kind
# ensconce captures exactly one base, so exactly one slot is populated — the
# single-form facts are one-per-dispatch and buf_write_fact_single's no-clobber
# guard turns any second populated slot into a loud failure. The provenance
# envelope is NOT read host-side: it lives only in GAR (rbgjl02 pushed it under
# :rbi_vouch), so the host hands forward only the touchmark a consumer needs.
zrbld_ensconce_extract() {
  zrbld_sentinel

  buc_step "Extracting capture results from build step outputs"

  local -r z_output_file="${ZRBLD_ENSCONCE_PREFIX}output.json"
  zrbld_spine_extract 0 "${z_output_file}"

  buc_log_args "Ensconce output:"
  buc_log_pipe < "${z_output_file}"

  local z_n=""
  local z_slot_key=""
  local z_stamp_file=""
  local z_stamp=""
  for z_n in 1 2 3; do
    z_slot_key="rbls_slot_${z_n}"
    z_stamp_file="${ZRBLD_ENSCONCE_PREFIX}${z_n}_stamp.txt"
    jq -r ".${z_slot_key}.rbls_stamp // empty" "${z_output_file}" > "${z_stamp_file}" \
      || buc_die "Failed to read stamp for ${z_slot_key}"
    z_stamp=$(<"${z_stamp_file}")
    test -n "${z_stamp}" || continue

    buf_write_fact_single "${RBF_FACT_LODE_TOUCHMARK}" "${z_stamp}" \
      || buc_die "Failed to write touchmark fact for ${z_stamp}"
    buc_success "Ensconced Lode ${z_stamp} — touchmark fact emitted (${RBGC_LODE_BRAND_BOLE})"
  done
}

######################################################################
# External Functions (rbld_*)

rbld_ensconce() {
  zrbld_sentinel

  buc_doc_brief "Ensconce an upstream base image into a Lode (parallel rbi_ld capture)"
  buc_doc_param "vessel" "Vessel sigil or path to vessel directory declaring the base ORIGIN"
  buc_doc_shown || return 0

  # Dirty-tree guard — capture composes its cloud step bodies from the working
  # tree; the Lode's provenance envelope must be the product of committed code.
  bug_require_clean_tree_creed "${RBCC_creed_clean_capture}"

  # Resolve vessel argument (sigil or path) and load.
  zrbfc_resolve_vessel "${BUZ_FOLIO:-}"
  local -r z_vessel_dir=$(<"${ZRBFC_VESSEL_RESOLVED_DIR_FILE}")
  test -n "${z_vessel_dir}" || buc_die "Empty resolved vessel path"
  zrbfc_load_vessel "${z_vessel_dir}"

  # Resolve the single base ORIGIN. Base-kind ensconce captures one base per
  # Lode per invocation; multi-base vessels are dispatched per base. Every real
  # vessel declares exactly one base slot today.
  local z_origin=""
  local z_origin_count=0
  local z_n=""
  local z_origin_var=""
  local z_slot_origin=""
  for z_n in 1 2 3; do
    z_origin_var="RBRV_IMAGE_${z_n}_ORIGIN"
    z_slot_origin="${!z_origin_var:-}"
    test -n "${z_slot_origin}" || continue
    z_origin="${z_slot_origin}"
    z_origin_count=$((z_origin_count + 1))
  done

  test "${z_origin_count}" -ne 0 \
    || buc_die "Vessel '${RBRV_SIGIL}' declares no upstream base-image slot (RBRV_IMAGE_n_ORIGIN)"
  test "${z_origin_count}" -eq 1 \
    || buc_die "Vessel '${RBRV_SIGIL}' declares ${z_origin_count} base slots; base-kind ensconce captures one base per Lode — invoke per base"

  # Reject producer-vessel pins: an origin naming a local vessel directory is a
  # made-side hallmark-pin (bind/airgap), not an upstream base to capture.
  test ! -d "${RBRR_VESSEL_DIR}/${z_origin}" \
    || buc_die "Origin '${z_origin}' names a producer vessel — base-Lode capture is for upstream bases, not hallmark-pins"

  buc_info "Ensconce base: ${z_origin}"

  # Resolve tool images from the reliquary. bole is a sealed-reliquary consumer, so
  # BOTH steps ride the PINNED reliquary gcrane (z_rbfc_tool_gcrane) — zero unpinned
  # aspects (RBS0 rbsk_pinning_boundary). The vessel supplies RBRV_RELIQUARY; gcrane
  # auths GAR ambiently whether pulled from gcr.io or our AR.
  zrbfc_resolve_tool_images

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  # Mint the Lode stamp on the host: <kind-letter><YYMMDDHHMMSS>. The host owns
  # the stamp so the touchmark is known before the build for the capture-file.
  local z_stamp="${RBGC_LODE_KIND_BOLE}${BURD_NOW_STAMP:2:6}${BURD_NOW_STAMP:9:6}"

  # Tweak override: test infrastructure pins the stamp via the bure tweak channel
  # to drive two captures onto one touchmark (the collision-guard exercise) — the
  # time-based mint is seconds-grained, so two CLI ensconces never share a
  # touchmark and the cloud guard's idempotent/collision branches never fire
  # without a pin. The name carries the buo sprue (BURE enforces the shape).
  # Mirror: rbtdrc_crucible.rs RBTDRC_ENSCONCE_STAMP_TWEAK_NAME — same literal.
  local -r z_ensconce_stamp_tweak_name="buorb_ensconce_stamp"
  test "${BURE_TWEAK_NAME:-}" != "${z_ensconce_stamp_tweak_name}" || z_stamp="${BURE_TWEAK_VALUE}"

  buc_info "Lode: ${RBGL_LODES_ROOT}/${z_stamp}"

  zrbld_ensconce_submit "${z_token}" "${z_origin}" "${z_stamp}"
  zrbld_ensconce_extract

  buc_success "Ensconce complete: ${z_origin} -> ${RBGL_LODES_ROOT}/${z_stamp}"
}

# eof
