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
# Recipe Bottle GCP Governor - Project Orchestration


# ----------------------------------------------------------------------
# Operational Invariants (RBGG is single writer; 409 is fatal)
#
# - Single admin actor: All RBGG operations are executed by a single admin
#   identity. There are no concurrent writers in the same project.
# - Pristine-state expectation: RBGG init/creation flows assume the project
#   is pristine for the resources they manage. If a resource "already exists"
#   (HTTP 409), that's treated as state drift or prior manual activity.
# - Policy: All HTTP 409 Conflict responses are fatal (buc_die). We do not
#   treat 409 as idempotent success anywhere in RBGG.
#   If you see a 409, resolve state drift first (destroy/reset), then rerun.
# ----------------------------------------------------------------------

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBGG_SOURCED:-}" || buc_die "Module rbgg multiply sourced - check sourcing hierarchy"
ZRBGG_SOURCED=1

######################################################################
# Internal Functions (zrbgg_*)

zrbgg_kindle() {
  test -z "${ZRBGG_KINDLED:-}" || buc_die "Module rbgg already kindled"

  test -n "${RBDC_DEPOT_PROJECT_ID:-}"     || buc_die "RBDC_DEPOT_PROJECT_ID is not set"
  test   "${#RBDC_DEPOT_PROJECT_ID}" -gt 0 || buc_die "RBDC_DEPOT_PROJECT_ID is empty"

  buc_log_args 'Ensure dependencies are kindled first'
  zrbgc_sentinel
  zrbgo_sentinel
  zrbuh_sentinel
  zrbgi_sentinel

  # Infix values for HTTP operations
  readonly ZRBGG_INFIX_PROJECT_INFO="project_info"
  readonly ZRBGG_INFIX_API_CHECK="api_checking"
  readonly ZRBGG_INFIX_BUCKET_CREATE="bucket_create"
  readonly ZRBGG_INFIX_BUCKET_DELETE="bucket_delete"
  readonly ZRBGG_INFIX_BUCKET_LIST="bucket_list"
  readonly ZRBGG_INFIX_OBJECT_DELETE="object_delete"
  readonly ZRBGG_INFIX_LIST_LIENS="list_liens"
  readonly ZRBGG_INFIX_PROJECT_DELETE="project_delete"
  readonly ZRBGG_INFIX_PROJECT_STATE="project_state"
  readonly ZRBGG_INFIX_PROJECT_RESTORE="project_restore"

  readonly ZRBGG_KINDLED=1
}

zrbgg_sentinel() {
  test "${ZRBGG_KINDLED:-}" = "1" || buc_die "Module rbgg not kindled - call zrbgg_kindle first"
}

######################################################################
######################################################################
# Capture: list required services that are NOT enabled (blank = all enabled)
zrbgg_required_apis_missing_capture() {
  zrbgg_sentinel

  local z_token="${1:-}"
  test -n "${z_token}" || { echo ""; return 1; }

  local z_missing=""
  local z_api=""
  local z_service=""
  local z_infix=""
  local z_state=""
  local z_code=""

  for z_api in                       \
    "${RBGC_API_SU_VERIFY_CRM}"      \
    "${RBGC_API_SU_VERIFY_GAR}"      \
    "${RBGC_API_SU_VERIFY_IAM}"      \
    "${RBGC_API_SU_VERIFY_BUILD}"    \
    "${RBGC_API_SU_VERIFY_ANALYSIS}" \
    "${RBGC_API_SU_VERIFY_STORAGE}"
  do
    z_service="${z_api##*/}"
    z_infix="${ZRBGG_INFIX_API_CHECK}_${z_service}"

    rbuh_json "GET" "${z_api}" "${z_token}" "${z_infix}" || true

    buc_log_args 'If we cannot even read an HTTP code file, that is a processing failure.'
    z_code=$(rbuh_code_capture "${z_infix}") || z_code=""
    test -n "${z_code}" || return 1

    if test "${z_code}" = "200"; then
      z_state=$(rbuh_json_field_capture "${z_infix}" ".state") || z_state=""
      test "${z_state}" = "ENABLED" || z_missing="${z_missing} ${z_service}"
    else
      buc_log_args 'Any non-200 (403/404/5xx/etc) => treat as NOT enabled'
      z_missing="${z_missing} ${z_service}"
    fi
  done

  printf '%s' "${z_missing# }"
}

zrbgg_create_gcs_bucket() {
  zrbgg_sentinel

  local z_token="${1}"
  local z_bucket_name="${2}"

  buc_log_args 'Create bucket request JSON for '"${z_bucket_name}"
  local z_bucket_req="${BURD_TEMP_DIR}/rbgg_bucket_create_req.json"
  jq -n --arg name "${z_bucket_name}" --arg location "${RBGC_GAR_LOCATION}" '
{
  name: $name,
  location: $location,
  storageClass: "STANDARD",
  lifecycle: { rule: [ { action: { type: "Delete" }, condition: { age: 1 } } ] }
}' > "${z_bucket_req}" || buc_die "Failed to create bucket request JSON"

  buc_log_args 'Send bucket creation request'
  local z_code
  local z_err
  rbuh_json "POST" "${RBGD_API_GCS_BUCKET_CREATE}" "${z_token}" \
                                  "${ZRBGG_INFIX_BUCKET_CREATE}" "${z_bucket_req}"
  z_code=$(rbuh_code_capture "${ZRBGG_INFIX_BUCKET_CREATE}") || buc_die "Bad bucket creation HTTP code"
  z_err=$(rbuh_json_field_capture "${ZRBGG_INFIX_BUCKET_CREATE}" '.error.message') || z_err="HTTP ${z_code}"

  case "${z_code}" in
    200|201) buc_info "Bucket ${z_bucket_name} created";                    return 0 ;;
    409)     buc_die  "Bucket ${z_bucket_name} already exists (pristine-state violation)" ;;
    *)       buc_die  "Failed to create bucket: ${z_err}"                             ;;
  esac
}

zrbgg_list_bucket_objects_capture() {
  zrbgg_sentinel

  local z_token="${1}"
  local z_bucket_name="${2}"

  local z_list_url_base="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}/o"
  local z_page_token=""
  local z_first=1

  while :; do
    buc_log_args "Build URL with optional pageToken -> ${z_first}"
    local z_url="${z_list_url_base}"
    if test -n "${z_page_token}"; then
      buc_log_args 'pageToken must be URL-encoded'
      local z_tok_enc
      z_tok_enc=$(rbuh_urlencode_capture "${z_page_token}") || return 1
      z_url="${z_url}?pageToken=${z_tok_enc}"
    fi

    buc_log_args 'Use a unique infix per page to avoid clobbering files'
    local z_infix="${ZRBGG_INFIX_BUCKET_LIST}${z_first}"
    rbuh_json "GET" "${z_url}" "${z_token}" "${z_infix}"

    local z_code
    z_code=$(rbuh_code_capture "${z_infix}") || return 1
    test "${z_code}" = "200" || return 1

    buc_log_args 'Print names from this page (if any)'
    buc_log_args 'Next page?'
    jq -r                '.items[]?.name // empty' "${ZRBUH_PREFIX}${z_infix}${ZRBUH_POSTFIX_JSON}"  || return 1
    z_page_token=$(rbuh_json_field_capture "${z_infix}" '.nextPageToken') || z_page_token=""

    test -n "${z_page_token}" || break
    z_first=$((z_first + 1))
  done
}

zrbgg_get_project_number_capture() {
  zrbgg_sentinel

  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || return 1

  rbuh_json "GET" "${RBGD_API_CRM_GET_PROJECT}" "${z_token}" "${ZRBGG_INFIX_PROJECT_INFO}"
  rbuh_require_ok "Get project info"                         "${ZRBGG_INFIX_PROJECT_INFO}" || return 1

  local z_project_number
  z_project_number=$(rbuh_json_field_capture "${ZRBGG_INFIX_PROJECT_INFO}" '.projectNumber') || return 1
  test -n "${z_project_number}" || return 1

  echo "${z_project_number}"
}

zrbgg_empty_gcs_bucket() {
  zrbgg_sentinel

  local z_token="${1}"
  local z_bucket_name="${2}"

  buc_log_args 'Get list of objects to delete'
  local z_objects
  z_objects=$(zrbgg_list_bucket_objects_capture "${z_token}" "${z_bucket_name}") || {
    buc_log_args 'No objects found or bucket not accessible'
    return 0
  }

  test -n "${z_objects}" || { buc_log_args 'Bucket is empty'; return 0; }

  buc_log_args 'Delete each object'
  local z_object=""
  local z_delete_url=""
  local z_delete_code=""
  while IFS= read -r z_object; do
    test -n "${z_object}" || continue
    buc_log_args "Deleting object: ${z_object}"

    local z_object_enc
    z_object_enc=$(rbuh_urlencode_capture "${z_object}") || z_object_enc=""
    test -n "${z_object_enc}" || { buc_warn "Failed to encode object name: ${z_object}"; continue; }
    z_delete_url="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}/o/${z_object_enc}"

    rbuh_json "DELETE" "${z_delete_url}" \
                              "${z_token}" "${ZRBGG_INFIX_OBJECT_DELETE}"
    z_delete_code=$(rbuh_code_capture "${ZRBGG_INFIX_OBJECT_DELETE}") || z_delete_code=""
    case "${z_delete_code}" in
      204|404) buc_log_args "Object ${z_object}: deleted or not found"                     ;;
      *)       buc_warn     "Object ${z_object}: Failed to delete (HTTP ${z_delete_code})" ;;
    esac
  done <<< "${z_objects}"
}

zrbgg_delete_gcs_bucket_predicate() {
  zrbgg_sentinel

  local z_token="${1}"
  local z_bucket_name="${2}"

  buc_log_args 'Empty bucket before deletion: '"${z_bucket_name}"
  zrbgg_empty_gcs_bucket "${z_token}" "${z_bucket_name}"

  buc_log_args 'Delete the bucket'
  local z_code
  local z_err
  local z_delete_url="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}"
  rbuh_json "DELETE" "${z_delete_url}" \
                      "${z_token}" "${ZRBGG_INFIX_BUCKET_DELETE}"
  z_code=$(rbuh_code_capture "${ZRBGG_INFIX_BUCKET_DELETE}") || z_code=""
  z_err=$(rbuh_json_field_capture "${ZRBGG_INFIX_BUCKET_DELETE}" '.error.message') || z_err="HTTP ${z_code}"
  case "${z_code}" in
    204) buc_info "Bucket ${z_bucket_name} deleted";                           return 0 ;;
    404) buc_warn "Bucket ${z_bucket_name} not found (already deleted)";       return 0 ;;
    409) buc_warn "Bucket ${z_bucket_name} not empty or has retention policy"; return 1 ;;
    *)   buc_warn "Bucket ${z_bucket_name} failed delete";                     return 1 ;;
  esac
}

######################################################################
# External Functions (rbgg_*)

rbgg_destroy_project() {
  zrbgg_sentinel
  buc_doc_brief "DEPRECATED: Use rbgp_project_delete instead - moved to Payor module for billing/destructive ops"
  buc_doc_shown || return 0

  buc_warn "========================================================================"
  buc_warn "DEPRECATION NOTICE: rbgg_destroy_project is deprecated"
  buc_warn "========================================================================"
  buc_warn ""
  buc_warn "Project deletion has been moved to the Payor module which handles"
  buc_warn "all billing and destructive lifecycle operations."
  buc_warn ""
  buc_warn "Use instead:"
  buc_warn "  rbgp_project_delete - Full project deletion with proper safeguards"
  buc_warn ""
  buc_warn "The Payor module provides additional features like lien management,"
  buc_warn "billing detachment, and project restoration capabilities."
  buc_warn "========================================================================"

  buc_die "Function moved to Payor module - use rbgp_project_delete"

  if [[ "${DEBUG_ONLY:-0}" != "1" ]]; then
    buc_die "This dangerous operation requires DEBUG_ONLY=1 environment variable"
  fi

  buc_step 'Mint admin OAuth token'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  buc_step 'Triple confirmation required'
  buc_warn ""
  buc_warn "========================================================================"
  buc_warn "CRITICAL WARNING: You are about to PERMANENTLY DELETE the entire project:"
  buc_warn "  Project: ${RBDC_DEPOT_PROJECT_ID}"
  buc_warn "This will:"
  buc_warn "  - Delete ALL resources in the project"
  buc_warn "  - Delete ALL data permanently"
  buc_warn "  - Break billing associations"
  buc_warn "  - Make the project unusable immediately"
  buc_warn "  - Cannot be undone after 30-day grace period"
  buc_warn "========================================================================"
  buc_warn ""

  buc_require "Type the exact project ID to confirm deletion" "${RBDC_DEPOT_PROJECT_ID}"
  buc_require "Confirm you understand this DELETES EVERYTHING in the project" "DELETE-EVERYTHING"
  buc_require "Final confirmation - type OBLITERATE to proceed" "OBLITERATE"

  buc_step 'Check for liens (will block deletion)'
  rbuh_json "GET" "${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/liens?parent=projects/${RBDC_DEPOT_PROJECT_ID}" "${z_token}" "${ZRBGG_INFIX_LIST_LIENS}"
  rbuh_require_ok "List liens" "${ZRBGG_INFIX_LIST_LIENS}"

  local z_lien_count
  z_lien_count=$(rbuh_json_field_capture "${ZRBGG_INFIX_LIST_LIENS}" '.liens // [] | length') || buc_die "Failed to parse liens response"

  if [[ "${z_lien_count}" -gt 0 ]]; then
    buc_step 'BLOCKED: Liens exist on project'
    buc_warn "Project has ${z_lien_count} lien(s) that prevent deletion"
    buc_warn "You must remove all liens first:"
    buc_code "  gcloud resource-manager liens list --project=${RBDC_DEPOT_PROJECT_ID}"
    buc_code "  gcloud resource-manager liens delete LIEN_NAME --project=${RBDC_DEPOT_PROJECT_ID}"
    buc_warn "Then re-run this command."
    buc_die "Cannot proceed with active liens"
  fi

  buc_step 'Delete project (immediate lifecycle change to DELETE_REQUESTED)'
  rbuh_json "DELETE" "${RBGD_API_CRM_DELETE_PROJECT}" "${z_token}" "${ZRBGG_INFIX_PROJECT_DELETE}"
  rbuh_require_ok "Delete project" "${ZRBGG_INFIX_PROJECT_DELETE}"

  buc_step 'Verify deletion state'
  rbuh_json "GET" "${RBGD_API_CRM_GET_PROJECT}" "${z_token}" "${ZRBGG_INFIX_PROJECT_STATE}"
  rbuh_require_ok "Get project state" "${ZRBGG_INFIX_PROJECT_STATE}"

  local z_lifecycle_state
  z_lifecycle_state=$(rbuh_json_field_capture "${ZRBGG_INFIX_PROJECT_STATE}" '.lifecycleState // "UNKNOWN"') || buc_die "Failed to parse project state"

  if test "${z_lifecycle_state}" = "DELETE_REQUESTED"; then
    buc_success "Project successfully marked for deletion"
    buc_step "Project Status: ${z_lifecycle_state}"
    buc_step "Grace period: Up to 30 days"
    buc_code "To restore (if still possible): rbgg_restore_project"
    buc_step "WARNING: Project is now unusable but may remain visible in listings"
  else
    buc_die "Unexpected project state after deletion: ${z_lifecycle_state}"
  fi
}

rbgg_restore_project() {
  zrbgg_sentinel
  buc_doc_brief "Attempt to restore a deleted project within the 30-day grace period"
  buc_doc_shown || return 0

  buc_step 'Mint admin OAuth token'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  buc_step 'Check current project state'
  rbuh_json "GET" "${RBGD_API_CRM_GET_PROJECT}" "${z_token}" "${ZRBGG_INFIX_PROJECT_STATE}"

  if ! rbuh_code_ok_predicate "${ZRBGG_INFIX_PROJECT_STATE}"; then
    buc_die "Cannot access project - it may have been permanently deleted or never existed"
  fi

  local z_lifecycle_state
  z_lifecycle_state=$(rbuh_json_field_capture "${ZRBGG_INFIX_PROJECT_STATE}" '.lifecycleState // "UNKNOWN"') || buc_die "Failed to parse project state"

  if test "${z_lifecycle_state}" != "DELETE_REQUESTED"; then
    buc_die "Project state is ${z_lifecycle_state} - can only restore projects in DELETE_REQUESTED state"
  fi

  buc_step 'Confirm restoration'
  buc_log_args "Project Status: ${z_lifecycle_state}"
  buc_log_args "Attempting to restore project: ${RBDC_DEPOT_PROJECT_ID}"
  buc_log_args "WARNING: Restore may fail if deletion process has already started"
  buc_require "Confirm restoration of project" "RESTORE"

  buc_step 'Attempt project restoration'
  rbuh_json "POST" "${RBGD_API_CRM_UNDELETE_PROJECT}" "${z_token}" "${ZRBGG_INFIX_PROJECT_RESTORE}"
  if rbuh_code_ok_predicate                                                    "${ZRBGG_INFIX_PROJECT_RESTORE}"; then
    buc_step 'Verify restoration'
    rbuh_json "GET" "${RBGD_API_CRM_GET_PROJECT}" "${z_token}" "${ZRBGG_INFIX_PROJECT_STATE}"
    rbuh_require_ok "Get restored project state"               "${ZRBGG_INFIX_PROJECT_STATE}"

    z_lifecycle_state=$(rbuh_json_field_capture "${ZRBGG_INFIX_PROJECT_STATE}" '.lifecycleState // "UNKNOWN"') || buc_die "Failed to parse restored project state"

    if test "${z_lifecycle_state}" = "${RBGC_STATE_ACTIVE}"; then
      buc_success "Project successfully restored to ACTIVE state"
      buc_log_args "Project Status: ${z_lifecycle_state}"
      buc_log_args "Project is now usable again"
    else
      buc_die "Restoration completed but project state is unexpected: ${z_lifecycle_state}"
    fi
  else
    local z_error_msg
    z_error_msg=$(rbuh_json_field_capture "${ZRBGG_INFIX_PROJECT_RESTORE}" '.error.message // "Unknown error"') || z_error_msg="Failed to parse error"
    buc_die "Project restoration failed: ${z_error_msg}"
  fi
}

# eof

