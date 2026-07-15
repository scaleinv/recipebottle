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
# Recipe Bottle Foundry Verify - about, vouch, and batch_vouch operations (director credentials)

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBFV_SOURCED:-}" || buc_die "Module rbfv multiply sourced - check sourcing hierarchy"
ZRBFV_SOURCED=1

# Source shared Foundry Core module
source "${BASH_SOURCE[0]%/*}/rbfc0_core.sh"

######################################################################
# Internal Functions (zrbfv_*)

zrbfv_kindle() {
  test -z "${ZRBFV_KINDLED:-}" || buc_die "Module rbfv already kindled"

  buc_log_args 'Validate Foundry Core is kindled'
  zrbfc_sentinel

  buc_log_args 'Define vouch operation file prefix'
  readonly ZRBFV_VOUCH_PREFIX="${BURD_TEMP_DIR}/rbfv_vouch_"

  buc_log_args 'Define about operation file prefix'
  readonly ZRBFV_ABOUT_PREFIX="${BURD_TEMP_DIR}/rbfv_about_"

  buc_log_args 'Define graft metadata operation file prefix'
  readonly ZRBFV_GRAFT_META_PREFIX="${BURD_TEMP_DIR}/rbfv_graft_meta_"

  readonly ZRBFV_KINDLED=1
}

zrbfv_sentinel() {
  zrbfc_sentinel
  test "${ZRBFV_KINDLED:-}" = "1" || buc_die "Module rbfv not kindled - call zrbfv_kindle first"
}

######################################################################
# Public Functions (rbfv_*)

rbfv_vouch_gate() {
  zrbfv_sentinel

  local -r z_vessel="${1:-}"
  local -r z_hallmark="${2:-}"

  test -n "${z_vessel}"       || buc_die "rbfv_vouch_gate: vessel required"
  test -n "${z_hallmark}" || buc_die "rbfv_vouch_gate: hallmark required"

  # Vouch package = rbi_hm/<H>/vouch, tag = <H> (hallmark-as-tag).
  local -r z_vouch_tag="${z_hallmark}"
  buc_step "Vouch gate: checking ${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_VOUCH}:${z_vouch_tag}"

  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "rbfv_vouch_gate: failed to get Director OAuth token"

  local z_vouch_http_code
  local z_curl_status=0
  curl --head -s \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
    --max-time "${RBCC_CURL_MAX_TIME_SEC}" \
    -H "Authorization: Bearer ${z_token}" \
    -o /dev/null \
    -w "%{http_code}" \
    "${ZRBFC_REGISTRY_API_BASE}/${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_VOUCH}/manifests/${z_vouch_tag}" \
    > "${ZRBFC_SCRATCH_FILE}" \
    || z_curl_status=$?
  test "${z_curl_status}" -eq 0 \
    || buc_die "rbfv_vouch_gate: HEAD request failed for ${z_vessel}:${z_vouch_tag} (curl exit ${z_curl_status})"
  z_vouch_http_code=$(<"${ZRBFC_SCRATCH_FILE}")

  if test "${z_vouch_http_code}" != "200"; then
    buc_die "Hallmark not vouched: ${z_hallmark} (HTTP ${z_vouch_http_code} — refusing to use unvouched image)"
  fi

  buc_info "Vouch verified: ${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_VOUCH}:${z_vouch_tag}"
}

rbfv_about() {
  zrbfv_sentinel

  # No dirty-tree guard — about constructs metadata for an image already in
  # GAR, not an image. The commit it stamps cannot be made to match the
  # image's build-time tree by gating (standalone re-about is approximate by
  # construction); the ordain paths produce about inside their gated builds.

  local -r z_hallmark="${2:-}"
  local -r z_conjure_build_id="${3:-}"  # Optional: conjure BUILD_ID for provenance

  buc_doc_brief "Assemble about metadata artifact for an existing hallmark image"
  buc_doc_param "vessel" "Vessel sigil or path to vessel directory"
  buc_doc_param "hallmark" "Full hallmark (e.g., c260305133650-r260305160530)"
  buc_doc_param "conjure_build_id" "(Optional) Cloud Build job ID from conjure"
  buc_doc_shown || return 0

  # Resolve vessel argument (sigil or path) and load
  zrbfc_resolve_vessel "${1:-}"
  local -r z_vessel_dir=$(<"${ZRBFC_VESSEL_RESOLVED_DIR_FILE}")
  test -n "${z_vessel_dir}" || buc_die "Empty resolved vessel path"
  zrbfc_load_vessel "${z_vessel_dir}"
  test -n "${z_hallmark}" || buc_die "Hallmark parameter required"

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  # Gate: require image exists. Image package = rbi_hm/<H>/image, tag = <H>.
  buc_step "Gating on image artifact existence"
  local -r z_hallmark_subtree="${RBGL_HALLMARKS_ROOT}/${z_hallmark}"
  local -r z_image_gate_status="${ZRBFV_ABOUT_PREFIX}image_status.txt"
  local -r z_image_gate_response="${ZRBFV_ABOUT_PREFIX}image_response.json"
  local -r z_image_gate_stderr="${ZRBFV_ABOUT_PREFIX}image_stderr.txt"

  local z_curl_status=0
  curl --head -s \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
    --max-time "${RBCC_CURL_MAX_TIME_SEC}" \
    -H "Authorization: Bearer ${z_token}" \
    -H "Accept: ${ZRBFC_ACCEPT_MANIFEST_MTYPES}" \
    -w "%{http_code}" \
    -o "${z_image_gate_response}" \
    "${ZRBFC_REGISTRY_API_BASE}/${z_hallmark_subtree}/${RBGC_ARK_BASENAME_IMAGE}/manifests/${z_hallmark}" \
    > "${z_image_gate_status}" 2>"${z_image_gate_stderr}" \
    || z_curl_status=$?
  test "${z_curl_status}" -eq 0 \
    || buc_die "HEAD request failed for image artifact (curl exit ${z_curl_status}) — see ${z_image_gate_stderr}"

  local -r z_image_http_code=$(<"${z_image_gate_status}")
  test -n "${z_image_http_code}" || buc_die "HTTP status code is empty for image"
  test "${z_image_http_code}" = "200" \
    || buc_die "Image artifact not found (HTTP ${z_image_http_code}) — image must exist before about"

  buc_info "Image artifact confirmed: ${z_hallmark_subtree}/${RBGC_ARK_BASENAME_IMAGE}:${z_hallmark}"

  # Gate: warn if about already exists (re-about is idempotent overwrite)
  local -r z_about_gate_status="${ZRBFV_ABOUT_PREFIX}about_status.txt"
  local -r z_about_gate_response="${ZRBFV_ABOUT_PREFIX}about_response.json"
  local -r z_about_gate_stderr="${ZRBFV_ABOUT_PREFIX}about_stderr.txt"

  curl --head -s \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
    --max-time "${RBCC_CURL_MAX_TIME_SEC}" \
    -H "Authorization: Bearer ${z_token}" \
    -H "Accept: ${ZRBFC_ACCEPT_MANIFEST_MTYPES}" \
    -w "%{http_code}" \
    -o "${z_about_gate_response}" \
    "${ZRBFC_REGISTRY_API_BASE}/${z_hallmark_subtree}/${RBGC_ARK_BASENAME_ABOUT}/manifests/${z_hallmark}" \
    > "${z_about_gate_status}" 2>"${z_about_gate_stderr}" \
    || z_curl_status=$?
  # RBr_c17
  test "${z_curl_status}" -eq 0 \
    || buc_die "HEAD request failed for about artifact (curl exit ${z_curl_status}) — see ${z_about_gate_stderr}"

  local -r z_about_http_code=$(<"${z_about_gate_status}")
  test -n "${z_about_http_code}" || buc_die "HTTP status code is empty for about"
  if test "${z_about_http_code}" = "200"; then
    buc_warn "Re-about in progress: ${z_hallmark_subtree}/${RBGC_ARK_BASENAME_ABOUT}:${z_hallmark} already exists"
  fi

  # Submit about Cloud Build
  zrbfv_about_submit "${z_hallmark}" "${z_token}" "${z_conjure_build_id}"

  buc_success "About complete: ${z_hallmark}"
  buc_info "About artifact: ${z_hallmark_subtree}/${RBGC_ARK_BASENAME_ABOUT}:${z_hallmark}"
}

# Internal: submit combined about+vouch Cloud Build job for graft mode.
# Eliminates the orphan gap between standalone about and vouch by running
# both step sets in a single GCB submission.
# Args: vessel_dir hallmark
zrbfv_graft_metadata_submit() {
  zrbfv_sentinel

  local -r z_vessel_dir="$1"
  local -r z_hallmark="$2"

  # Load vessel (follows reload pattern used by rbfv_about/rbfv_vouch)
  zrbfc_load_vessel "${z_vessel_dir}"
  test -n "${z_hallmark}" || buc_die "Hallmark parameter required"

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  buc_step "Constructing combined about+vouch Cloud Build resource"
  local -r z_gar_host="${RBGD_GAR_LOCATION}${RBGC_GAR_HOST_SUFFIX}"
  local -r z_gar_path="${RBGD_GAR_PROJECT_ID}/${RBDC_GAR_REPOSITORY}"
  local -r z_mason_sa="projects/${RBDC_DEPOT_PROJECT_ID}/serviceAccounts/${RBGD_MASON_EMAIL}"

  # Gate: require image exists (graft push must have completed)
  buc_step "Gating on image artifact existence"
  local -r z_hallmark_subtree="${RBGL_HALLMARKS_ROOT}/${z_hallmark}"
  local -r z_image_gate_status="${ZRBFV_GRAFT_META_PREFIX}image_status.txt"
  local -r z_image_gate_response="${ZRBFV_GRAFT_META_PREFIX}image_response.json"
  local -r z_image_gate_stderr="${ZRBFV_GRAFT_META_PREFIX}image_stderr.txt"

  local z_curl_status=0
  curl --head -s \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
    --max-time "${RBCC_CURL_MAX_TIME_SEC}" \
    -H "Authorization: Bearer ${z_token}" \
    -H "Accept: ${ZRBFC_ACCEPT_MANIFEST_MTYPES}" \
    -w "%{http_code}" \
    -o "${z_image_gate_response}" \
    "${ZRBFC_REGISTRY_API_BASE}/${z_hallmark_subtree}/${RBGC_ARK_BASENAME_IMAGE}/manifests/${z_hallmark}" \
    > "${z_image_gate_status}" 2>"${z_image_gate_stderr}" \
    || z_curl_status=$?
  test "${z_curl_status}" -eq 0 \
    || buc_die "HEAD request failed for image artifact (curl exit ${z_curl_status}) — see ${z_image_gate_stderr}"

  local -r z_image_http_code=$(<"${z_image_gate_status}")
  test -n "${z_image_http_code}" || buc_die "HTTP status code is empty for image"
  test "${z_image_http_code}" = "200" \
    || buc_die "Image artifact not found (HTTP ${z_image_http_code}) — graft push must complete before about+vouch"

  buc_info "Image artifact confirmed: ${z_hallmark_subtree}/${RBGC_ARK_BASENAME_IMAGE}:${z_hallmark}"

  # Git metadata (shared temp files, idempotent)
  zrbfc_ensure_git_metadata
  local z_git_commit=""
  z_git_commit=$(<"${ZRBFC_GIT_COMMIT_FILE}")
  local z_git_branch=""
  z_git_branch=$(<"${ZRBFC_GIT_BRANCH_FILE}")
  local z_git_repo=""
  z_git_repo=$(<"${ZRBFC_GIT_REPO_FILE}")

  # Graft-specific about substitution values
  local -r z_graft_source="${RBRV_GRAFT_IMAGE:-}"
  local z_dockerfile_content=""
  local -r z_dockerfile_max_bytes=4000
  if test -n "${RBRV_GRAFT_OPTIONAL_DOCKERFILE:-}" && test -f "${RBRV_GRAFT_OPTIONAL_DOCKERFILE}"; then
    z_dockerfile_content=$(<"${RBRV_GRAFT_OPTIONAL_DOCKERFILE}")
    if test "${#z_dockerfile_content}" -gt "${z_dockerfile_max_bytes}"; then
      buc_warn "Dockerfile exceeds 4KB substitution limit (${#z_dockerfile_content} bytes) — recipe.txt omitted"
      z_dockerfile_content=""
    fi
  fi

  # === Assemble about steps ===
  local -r z_about_steps_file="${ZRBFV_GRAFT_META_PREFIX}about_steps.json"
  zrbfc_assemble_about_steps "${z_about_steps_file}" "${ZRBFV_GRAFT_META_PREFIX}about_"

  # === Resolve base image provenance (for vouch summary) ===
  # ANCHOR carries a locator (package-path:tag); cloud prefix applied at use-site.
  local -r z_vi_gar_repo_base="${z_gar_host}/${z_gar_path}"
  local z_vi_ref_1="" z_vi_ref_2="" z_vi_ref_3=""
  local z_vi_prov_1="" z_vi_prov_2="" z_vi_prov_3=""
  local z_vi_n="" z_vi_origin_var="" z_vi_anchor_var="" z_vi_origin="" z_vi_anchor=""
  local z_vi_pkg_path=""
  local z_vi_tag=""
  for z_vi_n in 1 2 3; do
    z_vi_origin_var="RBRV_IMAGE_${z_vi_n}_ORIGIN"
    z_vi_anchor_var="RBRV_IMAGE_${z_vi_n}_ANCHOR"
    z_vi_origin="${!z_vi_origin_var:-}"
    z_vi_anchor="${!z_vi_anchor_var:-}"
    test -n "${z_vi_origin}" || continue
    local z_vi_ref="" z_vi_prov=""
    if test -n "${z_vi_anchor}"; then
      case "${z_vi_anchor}" in
        *:*) : ;;
        *)   buc_die "Invalid ${z_vi_anchor_var} locator format (expected package-path:tag): ${z_vi_anchor}" ;;
      esac
      z_vi_pkg_path="${z_vi_anchor%:*}"
      z_vi_tag="${z_vi_anchor##*:}"
      test -n "${z_vi_pkg_path}" || buc_die "Package path is empty in ${z_vi_anchor_var}: ${z_vi_anchor}"
      test -n "${z_vi_tag}"      || buc_die "Tag is empty in ${z_vi_anchor_var}: ${z_vi_anchor}"
      z_vi_ref="${z_vi_gar_repo_base}/${z_vi_pkg_path}:${z_vi_tag}"
      z_vi_prov="anchored"
    else
      z_vi_ref="${z_vi_origin}"
      z_vi_prov="pass-through"
    fi
    case "${z_vi_n}" in
      1) z_vi_ref_1="${z_vi_ref}"; z_vi_prov_1="${z_vi_prov}" ;;
      2) z_vi_ref_2="${z_vi_ref}"; z_vi_prov_2="${z_vi_prov}" ;;
      3) z_vi_ref_3="${z_vi_ref}"; z_vi_prov_3="${z_vi_prov}" ;;
    esac
  done

  # === Assemble vouch steps ===
  local -r z_vouch_steps_file="${ZRBFV_GRAFT_META_PREFIX}vouch_steps.json"
  zrbfc_assemble_vouch_steps "${z_vouch_steps_file}" "${ZRBFV_GRAFT_META_PREFIX}vouch_"

  # === Step 0: in-pool reliquary preflight (defense-in-depth) ===
  local -r z_preflight_step_file="${ZRBFV_GRAFT_META_PREFIX}preflight_step.json"
  zrbfc_assemble_preflight_step "${z_preflight_step_file}" "${ZRBFV_GRAFT_META_PREFIX}"

  # === Combine: preflight + about steps + vouch steps ===
  local -r z_combined_steps="${ZRBFV_GRAFT_META_PREFIX}combined_steps.json"
  jq -s '.[0] + .[1] + .[2]' "${z_preflight_step_file}" "${z_about_steps_file}" "${z_vouch_steps_file}" \
    > "${z_combined_steps}" || buc_die "Failed to combine preflight, about, and vouch steps"

  # Compose Build resource JSON with both _RBGA_ and _RBGV_ substitutions
  buc_log_args "Composing combined about+vouch Build resource JSON"
  local -r z_build_file="${ZRBFV_GRAFT_META_PREFIX}build.json"

  jq -n \
    --slurpfile zjq_steps       "${z_combined_steps}" \
    --arg zjq_sa                "${z_mason_sa}" \
    --arg zjq_gar_host          "${z_gar_host}" \
    --arg zjq_gar_path          "${z_gar_path}" \
    --arg zjq_hallmarks_root    "${RBGL_HALLMARKS_ROOT}" \
    --arg zjq_hallmark          "${z_hallmark}" \
    --arg zjq_vessel            "${RBRV_SIGIL}" \
    --arg zjq_git_commit        "${z_git_commit}" \
    --arg zjq_git_branch        "${z_git_branch}" \
    --arg zjq_git_repo          "${z_git_repo}" \
    --arg zjq_graft_source      "${z_graft_source}" \
    --arg zjq_dockerfile        "${z_dockerfile_content}" \
    --arg zjq_vi_ref_1          "${z_vi_ref_1}" \
    --arg zjq_vi_prov_1         "${z_vi_prov_1}" \
    --arg zjq_vi_ref_2          "${z_vi_ref_2}" \
    --arg zjq_vi_prov_2         "${z_vi_prov_2}" \
    --arg zjq_vi_ref_3          "${z_vi_ref_3}" \
    --arg zjq_vi_prov_3         "${z_vi_prov_3}" \
    --arg zjq_pool              "${RBDC_POOL_AIRGAP}" \
    --arg zjq_timeout           "${RBRR_GCB_TIMEOUT}" \
    --arg zjq_basename_image    "${RBGC_ARK_BASENAME_IMAGE}" \
    --arg zjq_basename_about    "${RBGC_ARK_BASENAME_ABOUT}" \
    --arg zjq_basename_vouch    "${RBGC_ARK_BASENAME_VOUCH}" \
    --arg zjq_basename_attest   "${RBGC_ARK_BASENAME_ATTEST}" \
    --arg zjq_basename_diags    "${RBGC_ARK_BASENAME_DIAGS}" \
    --arg zjq_lodes_root        "${RBGL_LODES_ROOT}" \
    --arg zjq_tag_sprue         "${RBGC_LODE_TAG_SPRUE}" \
    --arg zjq_reliquary         "${RBRV_RELIQUARY}" \
    '{
      steps: $zjq_steps[0],
      substitutions: {
        _RBGA_GAR_HOST:              $zjq_gar_host,
        _RBGA_GAR_PATH:              $zjq_gar_path,
        _RBGA_HALLMARKS_ROOT:        $zjq_hallmarks_root,
        _RBGA_HALLMARK:              $zjq_hallmark,
        _RBGA_VESSEL:                $zjq_vessel,
        _RBGA_VESSEL_MODE:           "rbnve_graft",
        _RBGA_GIT_COMMIT:            $zjq_git_commit,
        _RBGA_GIT_BRANCH:            $zjq_git_branch,
        _RBGA_GIT_REPO:              $zjq_git_repo,
        _RBGA_BUILD_ID:              "",
        _RBGA_INSCRIBE_TIMESTAMP:    "",
        _RBGA_BIND_SOURCE:           "",
        _RBGA_GRAFT_SOURCE:          $zjq_graft_source,
        _RBGA_DOCKERFILE_CONTENT:    $zjq_dockerfile,
        _RBGA_ARK_BASENAME_IMAGE:    $zjq_basename_image,
        _RBGA_ARK_BASENAME_ABOUT:    $zjq_basename_about,
        _RBGA_ARK_BASENAME_DIAGS:    $zjq_basename_diags,
        _RBGV_GAR_HOST:              $zjq_gar_host,
        _RBGV_GAR_PATH:              $zjq_gar_path,
        _RBGV_HALLMARKS_ROOT:        $zjq_hallmarks_root,
        _RBGV_HALLMARK:              $zjq_hallmark,
        _RBGV_VESSEL:                $zjq_vessel,
        _RBGV_VESSEL_MODE:           "rbnve_graft",
        _RBGV_BIND_SOURCE:           "",
        _RBGV_GRAFT_SOURCE:          $zjq_graft_source,
        _RBGV_IMAGE_1:               $zjq_vi_ref_1,
        _RBGV_IMAGE_1_PROVENANCE:    $zjq_vi_prov_1,
        _RBGV_IMAGE_2:               $zjq_vi_ref_2,
        _RBGV_IMAGE_2_PROVENANCE:    $zjq_vi_prov_2,
        _RBGV_IMAGE_3:               $zjq_vi_ref_3,
        _RBGV_IMAGE_3_PROVENANCE:    $zjq_vi_prov_3,
        _RBGV_ARK_BASENAME_IMAGE:    $zjq_basename_image,
        _RBGV_ARK_BASENAME_VOUCH:    $zjq_basename_vouch,
        _RBGV_ARK_BASENAME_ATTEST:   $zjq_basename_attest,
        _RBGR_GAR_HOST:              $zjq_gar_host,
        _RBGR_GAR_PATH:              $zjq_gar_path,
        _RBGR_LODES_ROOT:            $zjq_lodes_root,
        _RBGR_TAG_SPRUE:             $zjq_tag_sprue,
        _RBGR_RELIQUARY:             $zjq_reliquary,
        _RBGR_BASE_LOCATOR_1:    "",
        _RBGR_BASE_LOCATOR_2:    "",
        _RBGR_BASE_LOCATOR_3:    ""
      },
      serviceAccount: $zjq_sa,
      options: {
        automapSubstitutions: true,
        logging: "CLOUD_LOGGING_ONLY",
        pool: { name: $zjq_pool }
      },
      timeout: $zjq_timeout
    }' > "${z_build_file}" \
    || buc_die "Failed to compose combined about+vouch build JSON"

  buc_log_args "Combined about+vouch build JSON: ${z_build_file}"

  rbrd_check "${z_token}"

  buc_step "Submitting combined about+vouch Cloud Build"
  rbuh_json "POST" "${ZRBFC_GCB_PROJECT_BUILDS_URL}" "${z_token}" \
    "graft_meta_build_create" "${z_build_file}"
  rbuh_require_ok "Combined about+vouch build submission" "graft_meta_build_create"

  local z_build_id=""
  z_build_id=$(rbuh_json_field_capture "graft_meta_build_create" '.metadata.build.id') || z_build_id=""
  test -n "${z_build_id}" || buc_die "Build ID not found in builds.create response"
  echo "${z_build_id}" > "${ZRBFC_BUILD_ID_FILE}" || buc_die "Failed to persist build ID"

  local -r z_console_url="${ZRBFC_CLOUD_QUERY_BASE};region=${RBGD_GCB_REGION}/${z_build_id}?project=${RBGD_GCB_PROJECT_ID}"
  buc_info "Combined about+vouch build submitted: ${z_build_id}"
  buc_link "Click to " "Open build in Cloud Console" "${z_console_url}"

  zrbfc_wait_build_completion "${ZRBFC_BUILD_POLL_CEILING_ABOUT_VOUCH}" "About+Vouch"

  buc_success "About+Vouch complete: ${z_hallmark}"
  buc_info "About artifact: ${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_ABOUT}:${z_hallmark}"
  buc_info "Vouch artifact: ${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_VOUCH}:${z_hallmark}"
}

# Internal: submit about Cloud Build job and wait for completion
zrbfv_about_submit() {
  zrbfv_sentinel

  local -r z_hallmark="$1"
  local -r z_token="$2"
  local -r z_conjure_build_id="${3:-}"

  buc_step "Constructing about Cloud Build resource"
  local -r z_gar_host="${RBGD_GAR_LOCATION}${RBGC_GAR_HOST_SUFFIX}"
  local -r z_gar_path="${RBGD_GAR_PROJECT_ID}/${RBDC_GAR_REPOSITORY}"
  local -r z_mason_sa="projects/${RBDC_DEPOT_PROJECT_ID}/serviceAccounts/${RBGD_MASON_EMAIL}"

  # Determine mode-specific substitution values
  local z_vessel_mode="${RBRV_VESSEL_MODE}"
  local z_bind_source=""
  local z_graft_source=""
  local z_inscribe_ts=""
  local z_dockerfile_content=""
  # Cloud Build substitution values are limited to 4096 bytes. We use 4000 as a
  # conservative guard to account for encoding overhead and avoid edge-case failures.
  local -r z_dockerfile_max_bytes=4000

  case "${z_vessel_mode}" in
    rbnve_conjure)
      # Extract inscribe timestamp from hallmark (e.g., c260305133650 from c260305133650-r260305160530)
      z_inscribe_ts="${z_hallmark%%-r*}"
      # Read Dockerfile content for recipe.txt
      if test -f "${RBRV_CONJURE_DOCKERFILE:-}"; then
        z_dockerfile_content=$(<"${RBRV_CONJURE_DOCKERFILE}")
        if test "${#z_dockerfile_content}" -gt "${z_dockerfile_max_bytes}"; then
          buc_warn "Dockerfile exceeds 4KB substitution limit (${#z_dockerfile_content} bytes) — recipe.txt omitted"
          z_dockerfile_content=""
        fi
      fi
      ;;
    rbnve_bind)
      z_bind_source="${RBRV_BIND_IMAGE:-}"
      if test -n "${RBRV_BIND_OPTIONAL_DOCKERFILE:-}" && test -f "${RBRV_BIND_OPTIONAL_DOCKERFILE}"; then
        z_dockerfile_content=$(<"${RBRV_BIND_OPTIONAL_DOCKERFILE}")
        if test "${#z_dockerfile_content}" -gt "${z_dockerfile_max_bytes}"; then
          buc_warn "Dockerfile exceeds 4KB substitution limit (${#z_dockerfile_content} bytes) — recipe.txt omitted"
          z_dockerfile_content=""
        fi
      fi
      ;;
    rbnve_graft)
      z_graft_source="${RBRV_GRAFT_IMAGE:-}"
      if test -n "${RBRV_GRAFT_OPTIONAL_DOCKERFILE:-}" && test -f "${RBRV_GRAFT_OPTIONAL_DOCKERFILE}"; then
        z_dockerfile_content=$(<"${RBRV_GRAFT_OPTIONAL_DOCKERFILE}")
        if test "${#z_dockerfile_content}" -gt "${z_dockerfile_max_bytes}"; then
          buc_warn "Dockerfile exceeds 4KB substitution limit (${#z_dockerfile_content} bytes) — recipe.txt omitted"
          z_dockerfile_content=""
        fi
      fi
      ;;
    *)
      buc_die "Unknown vessel mode: ${z_vessel_mode}"
      ;;
  esac

  # Git metadata (shared temp files, idempotent)
  zrbfc_ensure_git_metadata
  local z_git_commit=""
  z_git_commit=$(<"${ZRBFC_GIT_COMMIT_FILE}")
  local z_git_branch=""
  z_git_branch=$(<"${ZRBFC_GIT_BRANCH_FILE}")
  local z_git_repo=""
  z_git_repo=$(<"${ZRBFC_GIT_REPO_FILE}")

  # Assemble about steps via shared helper
  local -r z_about_steps_accumulator="${ZRBFV_ABOUT_PREFIX}steps.json"
  zrbfc_assemble_about_steps "${z_about_steps_accumulator}" "${ZRBFV_ABOUT_PREFIX}"

  buc_log_args "Composing about Build resource JSON"
  local -r z_about_build_file="${ZRBFV_ABOUT_PREFIX}build.json"

  jq -n \
    --slurpfile zjq_steps    "${z_about_steps_accumulator}" \
    --arg zjq_sa             "${z_mason_sa}" \
    --arg zjq_gar_host       "${z_gar_host}" \
    --arg zjq_gar_path       "${z_gar_path}" \
    --arg zjq_hallmarks_root "${RBGL_HALLMARKS_ROOT}" \
    --arg zjq_hallmark       "${z_hallmark}" \
    --arg zjq_vessel         "${RBRV_SIGIL}" \
    --arg zjq_vessel_mode    "${z_vessel_mode}" \
    --arg zjq_git_commit     "${z_git_commit}" \
    --arg zjq_git_branch     "${z_git_branch}" \
    --arg zjq_git_repo       "${z_git_repo}" \
    --arg zjq_build_id       "${z_conjure_build_id}" \
    --arg zjq_inscribe_ts    "${z_inscribe_ts}" \
    --arg zjq_bind_source    "${z_bind_source}" \
    --arg zjq_graft_source   "${z_graft_source}" \
    --arg zjq_dockerfile     "${z_dockerfile_content}" \
    --arg zjq_pool           "${RBDC_POOL_AIRGAP}" \
    --arg zjq_timeout        "${RBRR_GCB_TIMEOUT}" \
    '{
      steps: $zjq_steps[0],
      substitutions: {
        _RBGA_GAR_HOST:              $zjq_gar_host,
        _RBGA_GAR_PATH:              $zjq_gar_path,
        _RBGA_HALLMARKS_ROOT:        $zjq_hallmarks_root,
        _RBGA_HALLMARK:              $zjq_hallmark,
        _RBGA_VESSEL:                $zjq_vessel,
        _RBGA_VESSEL_MODE:           $zjq_vessel_mode,
        _RBGA_GIT_COMMIT:            $zjq_git_commit,
        _RBGA_GIT_BRANCH:            $zjq_git_branch,
        _RBGA_GIT_REPO:              $zjq_git_repo,
        _RBGA_BUILD_ID:              $zjq_build_id,
        _RBGA_INSCRIBE_TIMESTAMP:    $zjq_inscribe_ts,
        _RBGA_BIND_SOURCE:           $zjq_bind_source,
        _RBGA_GRAFT_SOURCE:          $zjq_graft_source,
        _RBGA_DOCKERFILE_CONTENT:    $zjq_dockerfile
      },
      serviceAccount: $zjq_sa,
      options: {
        automapSubstitutions: true,
        logging: "CLOUD_LOGGING_ONLY",
        pool: { name: $zjq_pool }
      },
      timeout: $zjq_timeout
    }' > "${z_about_build_file}" \
    || buc_die "Failed to compose about build JSON"

  buc_log_args "About build JSON: ${z_about_build_file}"

  rbrd_check "${z_token}"

  buc_step "Submitting about Cloud Build"
  rbuh_json "POST" "${ZRBFC_GCB_PROJECT_BUILDS_URL}" "${z_token}" \
    "about_build_create" "${z_about_build_file}"
  rbuh_require_ok "About build submission" "about_build_create"

  local z_build_id=""
  z_build_id=$(rbuh_json_field_capture "about_build_create" '.metadata.build.id') || z_build_id=""
  test -n "${z_build_id}" || buc_die "Build ID not found in builds.create response"
  echo "${z_build_id}" > "${ZRBFC_BUILD_ID_FILE}" || buc_die "Failed to persist build ID"

  local -r z_console_url="${ZRBFC_CLOUD_QUERY_BASE};region=${RBGD_GCB_REGION}/${z_build_id}?project=${RBGD_GCB_PROJECT_ID}"
  buc_info "About build submitted: ${z_build_id}"
  buc_link "Click to " "Open build in Cloud Console" "${z_console_url}"

  zrbfc_wait_build_completion "${ZRBFC_BUILD_POLL_CEILING_ABOUT}" "About"
}

######################################################################
# Vouch

rbfv_vouch() {
  zrbfv_sentinel

  local -r z_vessel_dir="${1:-}"
  local -r z_hallmark="${2:-}"

  buc_doc_brief "Vouch for an ark by mode-aware verification in Cloud Build"
  buc_doc_param "vessel_dir" "Path to vessel directory containing rbrv.env"
  buc_doc_param "hallmark" "Full hallmark (e.g., c260305133650-r260305160530)"
  buc_doc_shown || return 0

  if test -z "${z_vessel_dir}"; then
    local z_sigils
    z_sigils=$(rbrv_list_capture) || buc_die "No vessels found"
    buc_step "Available vessels:"
    local z_sigil=""
    for z_sigil in ${z_sigils}; do
      buc_bare "        ${RBRR_VESSEL_DIR}/${z_sigil}"
    done
    buc_die "Vessel directory required"
  fi

  zrbfc_load_vessel "${z_vessel_dir}"
  test -n "${z_hallmark}" || buc_die "Hallmark parameter required"

  # Resolve tool images from reliquary (vouch steps use tool images)
  zrbfc_resolve_tool_images

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  # Gate: require about exists (about must complete before vouch)
  buc_step "Gating on about artifact existence"
  local -r z_hallmark_subtree="${RBGL_HALLMARKS_ROOT}/${z_hallmark}"
  local -r z_about_gate_status="${ZRBFV_VOUCH_PREFIX}about_status.txt"
  local -r z_about_gate_response="${ZRBFV_VOUCH_PREFIX}about_response.json"
  local -r z_about_gate_stderr="${ZRBFV_VOUCH_PREFIX}about_stderr.txt"

  local z_curl_status=0
  curl --head -s \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
    --max-time "${RBCC_CURL_MAX_TIME_SEC}" \
    -H "Authorization: Bearer ${z_token}" \
    -H "Accept: ${ZRBFC_ACCEPT_MANIFEST_MTYPES}" \
    -w "%{http_code}" \
    -o "${z_about_gate_response}" \
    "${ZRBFC_REGISTRY_API_BASE}/${z_hallmark_subtree}/${RBGC_ARK_BASENAME_ABOUT}/manifests/${z_hallmark}" \
    > "${z_about_gate_status}" 2>"${z_about_gate_stderr}" \
    || z_curl_status=$?
  # RBr_c17
  test "${z_curl_status}" -eq 0 \
    || buc_die "HEAD request failed for about artifact (curl exit ${z_curl_status}) — see ${z_about_gate_stderr}"

  local -r z_about_http_code=$(<"${z_about_gate_status}")
  test -n "${z_about_http_code}" || buc_die "HTTP status code is empty for about"
  test "${z_about_http_code}" = "200" \
    || buc_die "About artifact not found (HTTP ${z_about_http_code}) — about must complete before vouch"

  buc_info "About artifact confirmed: ${z_hallmark_subtree}/${RBGC_ARK_BASENAME_ABOUT}:${z_hallmark}"

  # Gate: warn if vouch already exists (re-vouch)
  local -r z_vouch_gate_status="${ZRBFV_VOUCH_PREFIX}vouch_status.txt"
  local -r z_vouch_gate_response="${ZRBFV_VOUCH_PREFIX}vouch_response.json"
  local -r z_vouch_gate_stderr="${ZRBFV_VOUCH_PREFIX}vouch_stderr.txt"

  curl --head -s \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
    --max-time "${RBCC_CURL_MAX_TIME_SEC}" \
    -H "Authorization: Bearer ${z_token}" \
    -H "Accept: ${ZRBFC_ACCEPT_MANIFEST_MTYPES}" \
    -w "%{http_code}" \
    -o "${z_vouch_gate_response}" \
    "${ZRBFC_REGISTRY_API_BASE}/${z_hallmark_subtree}/${RBGC_ARK_BASENAME_VOUCH}/manifests/${z_hallmark}" \
    > "${z_vouch_gate_status}" 2>"${z_vouch_gate_stderr}" \
    || z_curl_status=$?
  test "${z_curl_status}" -eq 0 \
    || buc_die "HEAD request failed for vouch artifact (curl exit ${z_curl_status}) — see ${z_vouch_gate_stderr}"

  local -r z_vouch_http_code=$(<"${z_vouch_gate_status}")
  test -n "${z_vouch_http_code}" || buc_die "HTTP status code is empty for vouch"
  if test "${z_vouch_http_code}" = "200"; then
    buc_warn "Re-vouch in progress: ${z_hallmark_subtree}/${RBGC_ARK_BASENAME_VOUCH}:${z_hallmark} already exists"
  fi

  # All modes use Cloud Build for vouch (mode-aware verification inside the build)
  zrbfv_vouch_submit "${z_hallmark}" "${z_token}"

  buc_success "Vouch complete: ${z_hallmark}"
  buc_info "Vouch artifact: ${z_hallmark_subtree}/${RBGC_ARK_BASENAME_VOUCH}:${z_hallmark}"
}

# Internal: Submit vouch Cloud Build job (mode-aware verification)
# All vessel modes use Cloud Build. The build scripts branch on _RBGV_VESSEL_MODE:
#   conjure: DSSE envelope signature verification (Python 3 + openssl)
#   bind: digest-pin comparison against upstream reference
#   graft: GRAFTED stamp (no verification)
zrbfv_vouch_submit() {
  zrbfv_sentinel

  local -r z_hallmark="$1"
  local -r z_token="$2"

  buc_step "Constructing vouch Cloud Build resource"
  local -r z_gar_host="${RBGD_GAR_LOCATION}${RBGC_GAR_HOST_SUFFIX}"
  local -r z_gar_path="${RBGD_GAR_PROJECT_ID}/${RBDC_GAR_REPOSITORY}"
  local -r z_mason_sa="projects/${RBDC_DEPOT_PROJECT_ID}/serviceAccounts/${RBGD_MASON_EMAIL}"

  # Mode-specific substitution values (empty strings for non-applicable modes)
  local z_bind_source=""
  local z_graft_source=""

  case "${RBRV_VESSEL_MODE}" in
    rbnve_conjure) : ;;  # DSSE verification uses embedded keys, no extra substitutions
    rbnve_bind)    z_bind_source="${RBRV_BIND_IMAGE:-}" ;;
    rbnve_graft)   z_graft_source="${RBRV_GRAFT_IMAGE:-}" ;;
    *)             buc_die "Unknown vessel mode: ${RBRV_VESSEL_MODE}" ;;
  esac

  # Resolve base image provenance (for vouch summary recording)
  # ANCHOR carries a locator (package-path:tag); cloud prefix applied at use-site.
  local -r z_vi_gar_repo_base="${z_gar_host}/${z_gar_path}"
  local z_vi_ref_1="" z_vi_ref_2="" z_vi_ref_3=""
  local z_vi_prov_1="" z_vi_prov_2="" z_vi_prov_3=""
  local z_vi_n="" z_vi_origin_var="" z_vi_anchor_var="" z_vi_origin="" z_vi_anchor=""
  local z_vi_pkg_path=""
  local z_vi_tag=""
  for z_vi_n in 1 2 3; do
    z_vi_origin_var="RBRV_IMAGE_${z_vi_n}_ORIGIN"
    z_vi_anchor_var="RBRV_IMAGE_${z_vi_n}_ANCHOR"
    z_vi_origin="${!z_vi_origin_var:-}"
    z_vi_anchor="${!z_vi_anchor_var:-}"
    test -n "${z_vi_origin}" || continue
    local z_vi_ref="" z_vi_prov=""
    if test -n "${z_vi_anchor}"; then
      case "${z_vi_anchor}" in
        *:*) : ;;
        *)   buc_die "Invalid ${z_vi_anchor_var} locator format (expected package-path:tag): ${z_vi_anchor}" ;;
      esac
      z_vi_pkg_path="${z_vi_anchor%:*}"
      z_vi_tag="${z_vi_anchor##*:}"
      test -n "${z_vi_pkg_path}" || buc_die "Package path is empty in ${z_vi_anchor_var}: ${z_vi_anchor}"
      test -n "${z_vi_tag}"      || buc_die "Tag is empty in ${z_vi_anchor_var}: ${z_vi_anchor}"
      z_vi_ref="${z_vi_gar_repo_base}/${z_vi_pkg_path}:${z_vi_tag}"
      z_vi_prov="anchored"
    else
      z_vi_ref="${z_vi_origin}"
      z_vi_prov="pass-through"
    fi
    case "${z_vi_n}" in
      1) z_vi_ref_1="${z_vi_ref}"; z_vi_prov_1="${z_vi_prov}" ;;
      2) z_vi_ref_2="${z_vi_ref}"; z_vi_prov_2="${z_vi_prov}" ;;
      3) z_vi_ref_3="${z_vi_ref}"; z_vi_prov_3="${z_vi_prov}" ;;
    esac
  done

  # Assemble vouch steps via shared helper
  local -r z_vouch_steps_accumulator="${ZRBFV_VOUCH_PREFIX}steps.json"
  zrbfc_assemble_vouch_steps "${z_vouch_steps_accumulator}" "${ZRBFV_VOUCH_PREFIX}"

  buc_log_args "Composing vouch Build resource JSON"
  local -r z_vouch_build_file="${ZRBFV_VOUCH_PREFIX}build.json"

  jq -n \
    --slurpfile zjq_steps    "${z_vouch_steps_accumulator}" \
    --arg zjq_sa             "${z_mason_sa}" \
    --arg zjq_gar_host       "${z_gar_host}" \
    --arg zjq_gar_path       "${z_gar_path}" \
    --arg zjq_hallmarks_root "${RBGL_HALLMARKS_ROOT}" \
    --arg zjq_hallmark       "${z_hallmark}" \
    --arg zjq_vessel         "${RBRV_SIGIL}" \
    --arg zjq_vessel_mode    "${RBRV_VESSEL_MODE}" \
    --arg zjq_bind_source    "${z_bind_source}" \
    --arg zjq_graft_source   "${z_graft_source}" \
    --arg zjq_vi_ref_1       "${z_vi_ref_1}" \
    --arg zjq_vi_prov_1      "${z_vi_prov_1}" \
    --arg zjq_vi_ref_2       "${z_vi_ref_2}" \
    --arg zjq_vi_prov_2      "${z_vi_prov_2}" \
    --arg zjq_vi_ref_3       "${z_vi_ref_3}" \
    --arg zjq_vi_prov_3      "${z_vi_prov_3}" \
    --arg zjq_pool           "${RBDC_POOL_AIRGAP}" \
    --arg zjq_timeout        "${RBRR_GCB_TIMEOUT}" \
    --arg zjq_basename_image  "${RBGC_ARK_BASENAME_IMAGE}" \
    --arg zjq_basename_vouch  "${RBGC_ARK_BASENAME_VOUCH}" \
    --arg zjq_basename_attest "${RBGC_ARK_BASENAME_ATTEST}" \
    '{
      steps: $zjq_steps[0],
      substitutions: {
        _RBGV_GAR_HOST:            $zjq_gar_host,
        _RBGV_GAR_PATH:            $zjq_gar_path,
        _RBGV_HALLMARKS_ROOT:      $zjq_hallmarks_root,
        _RBGV_HALLMARK:            $zjq_hallmark,
        _RBGV_VESSEL:              $zjq_vessel,
        _RBGV_VESSEL_MODE:         $zjq_vessel_mode,
        _RBGV_BIND_SOURCE:         $zjq_bind_source,
        _RBGV_GRAFT_SOURCE:        $zjq_graft_source,
        _RBGV_IMAGE_1:             $zjq_vi_ref_1,
        _RBGV_IMAGE_1_PROVENANCE:  $zjq_vi_prov_1,
        _RBGV_IMAGE_2:             $zjq_vi_ref_2,
        _RBGV_IMAGE_2_PROVENANCE:  $zjq_vi_prov_2,
        _RBGV_IMAGE_3:             $zjq_vi_ref_3,
        _RBGV_IMAGE_3_PROVENANCE:  $zjq_vi_prov_3,
        _RBGV_ARK_BASENAME_IMAGE:  $zjq_basename_image,
        _RBGV_ARK_BASENAME_VOUCH:  $zjq_basename_vouch,
        _RBGV_ARK_BASENAME_ATTEST: $zjq_basename_attest
      },
      serviceAccount: $zjq_sa,
      options: {
        automapSubstitutions: true,
        logging: "CLOUD_LOGGING_ONLY",
        pool: { name: $zjq_pool }
      },
      timeout: $zjq_timeout
    }' > "${z_vouch_build_file}" \
    || buc_die "Failed to compose vouch build JSON"

  buc_log_args "Vouch build JSON: ${z_vouch_build_file}"

  rbrd_check "${z_token}"

  buc_step "Submitting vouch Cloud Build"
  rbuh_json "POST" "${ZRBFC_GCB_PROJECT_BUILDS_URL}" "${z_token}" \
    "vouch_build_create" "${z_vouch_build_file}"
  rbuh_require_ok "Vouch build submission" "vouch_build_create"

  local z_build_id=""
  z_build_id=$(rbuh_json_field_capture "vouch_build_create" '.metadata.build.id') || z_build_id=""
  test -n "${z_build_id}" || buc_die "Build ID not found in builds.create response"
  echo "${z_build_id}" > "${ZRBFC_BUILD_ID_FILE}" || buc_die "Failed to persist build ID"

  local -r z_console_url="${ZRBFC_CLOUD_QUERY_BASE};region=${RBGD_GCB_REGION}/${z_build_id}?project=${RBGD_GCB_PROJECT_ID}"
  buc_info "Vouch build submitted: ${z_build_id}"
  buc_link "Click to " "Open build in Cloud Console" "${z_console_url}"

  zrbfc_wait_build_completion "${ZRBFC_BUILD_POLL_CEILING_VOUCH}" "Vouch"
}

######################################################################
# Batch Vouch

rbfv_batch_vouch() {
  zrbfv_sentinel

  buc_doc_brief "Vouch every pending hallmark (image+about present, vouch absent)"
  buc_doc_shown || return 0

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  buc_step "Enumerating hallmarks under ${RBGL_HALLMARKS_ROOT}/"
  zrbfc_list_packages_capture "${z_token}" "${RBGL_HALLMARKS_ROOT}"

  # Load-then-iterate. A synthetic sentinel element appended to the array
  # lets the final hallmark flush through the same boundary branch as every
  # intermediate one (single flush site).
  local z_lines=()
  local z_line=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    z_lines+=("${z_line}")
  done < "${ZRBFC_PACKAGE_LIST_FILE}"
  z_lines+=("__SENTINEL__ __SENTINEL__")

  # Pass 1: state machine identifies pending hallmarks (image+about present,
  # vouch absent). Accumulate into an array rather than a file so the later
  # processing loop can iterate in-memory (no FD held open across rbfv_vouch
  # calls, which issue curl/source and would silently consume loop stdin).
  local z_pending=()
  local z_prev_h=""
  local z_prev_img=0 z_prev_abt=0 z_prev_vch=0
  local z_i="" z_h="" z_b=""

  for z_i in "${!z_lines[@]}"; do
    z_line="${z_lines[$z_i]}"
    test -n "${z_line}" || continue

    z_h="${z_line%% *}"
    z_b="${z_line#* }"
    test -n "${z_h}" || continue
    test -n "${z_b}" || continue

    if test "${z_h}" != "${z_prev_h}"; then
      if test -n "${z_prev_h}"; then
        if test "${z_prev_img}" = "1" \
          && test "${z_prev_abt}" = "1" \
          && test "${z_prev_vch}" != "1"; then
          z_pending+=("${z_prev_h}")
        fi
      fi

      case "${z_h}" in
        __SENTINEL__) break ;;
      esac

      z_prev_h="${z_h}"
      z_prev_img=0
      z_prev_abt=0
      z_prev_vch=0
    fi

    case "${z_b}" in
      "${RBGC_ARK_BASENAME_IMAGE}") z_prev_img=1 ;;
      "${RBGC_ARK_BASENAME_ABOUT}") z_prev_abt=1 ;;
      "${RBGC_ARK_BASENAME_VOUCH}") z_prev_vch=1 ;;
    esac
  done

  # Forensic record of pending set.
  local -r z_pending_file="${BURD_TEMP_DIR}/rbfv_batch_pending.txt"
  : > "${z_pending_file}" || buc_die "Failed to initialize ${z_pending_file}"
  local z_j=""
  for z_j in "${!z_pending[@]}"; do
    printf '%s\n' "${z_pending[$z_j]}" >> "${z_pending_file}" \
      || buc_die "Failed to record pending hallmark ${z_pending[$z_j]}"
  done

  local -r z_total="${#z_pending[@]}"
  case "${z_total}" in
    0)
      buc_info "No pending hallmarks found (no hallmark has image+about without vouch)"
      buc_success "Batch vouch complete — 0 hallmarks processed"
      return 0
      ;;
  esac

  buc_info "Found ${z_total} pending hallmark(s) to vouch"

  # Pass 2: for each pending hallmark, extract about ark, read vessel_name
  # from build_info.json, resolve vessel_dir, call rbfv_vouch. rbfv_vouch
  # fails via buc_die on any vouch failure — batch terminates fail-fast at
  # the broken hallmark rather than masking problems behind a summary count.
  local z_vouched_n=0 z_idx=0 z_vessel=""
  local z_hallmark="" z_about_extract="" z_about_pkg=""
  local z_build_info="" z_vessel_scratch="" z_vessel_dir=""

  for z_j in "${!z_pending[@]}"; do
    z_hallmark="${z_pending[$z_j]}"
    test -n "${z_hallmark}" || continue
    z_idx=$(( z_idx + 1 ))

    buc_step "[${z_idx}/${z_total}] Resolving vessel for ${z_hallmark}"

    z_about_extract="${BURD_TEMP_DIR}/rbfv_batch_about_${z_hallmark}"
    z_about_pkg="${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_ABOUT}"

    zrbfc_gar_extract_artifact "${z_token}" "${z_about_pkg}" "${z_hallmark}" "${z_about_extract}" \
      || buc_die "Failed to extract about ark for ${z_hallmark} (expected at ${z_about_pkg}:${z_hallmark})"

    z_build_info="${z_about_extract}/build_info.json"
    test -f "${z_build_info}" \
      || buc_die "build_info.json missing in about ark for ${z_hallmark}"

    z_vessel_scratch="${BURD_TEMP_DIR}/rbfv_batch_vessel.txt"
    jq -r '.vessel_name // empty' "${z_build_info}" > "${z_vessel_scratch}" \
      || buc_die "Failed to read vessel_name from ${z_build_info}"
    z_vessel=$(<"${z_vessel_scratch}")
    test -n "${z_vessel}" \
      || buc_die "vessel_name empty in about ark for ${z_hallmark}"

    z_vessel_dir="${RBRR_VESSEL_DIR}/${z_vessel}"
    test -d "${z_vessel_dir}" \
      || buc_die "Vessel directory not found: ${z_vessel_dir} (from about build_info.vessel_name for ${z_hallmark})"

    buc_info "Vouching ${z_hallmark} (vessel: ${z_vessel})"
    rbfv_vouch "${z_vessel_dir}" "${z_hallmark}"
    z_vouched_n=$(( z_vouched_n + 1 ))
  done

  echo ""
  buc_success "Batch vouch complete — ${z_vouched_n}/${z_total} hallmark(s) vouched"
}

# eof
