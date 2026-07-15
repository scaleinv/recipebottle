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
# Recipe Bottle GCP Cloud Storage Buckets - Implementation

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBGB_SOURCED:-}" || buc_die "Module rbgb multiply sourced - check sourcing hierarchy"
ZRBGB_SOURCED=1

######################################################################
# Internal Functions (zrbgb_*)

zrbgb_kindle() {
  test -z "${ZRBGB_KINDLED:-}" || buc_die "Module rbgb already kindled"

  test -n "${RBDC_DEPOT_PROJECT_ID:-}"     || buc_die "RBDC_DEPOT_PROJECT_ID is not set"
  test   "${#RBDC_DEPOT_PROJECT_ID}" -gt 0 || buc_die "RBDC_DEPOT_PROJECT_ID is empty"

  buc_log_args "Ensure dependencies are kindled first"
  zrbgc_sentinel
  zrbgo_sentinel
  zrbuh_sentinel
  zrbgi_sentinel

  readonly ZRBGB_PREFIX="${BURD_TEMP_DIR}/rbgb_"
  readonly ZRBGB_EMPTY_JSON="${ZRBGB_PREFIX}empty.json"
  printf '{}' > "${ZRBGB_EMPTY_JSON}"

  # Infix values for HTTP operations
  readonly ZRBGB_INFIX_CREATE="bucket_create"
  readonly ZRBGB_INFIX_ENSURE="bucket_ensure"
  readonly ZRBGB_INFIX_GET="bucket_get"
  readonly ZRBGB_INFIX_DELETE="bucket_delete"
  readonly ZRBGB_INFIX_LIST="bucket_list"
  readonly ZRBGB_INFIX_OBJECT_DELETE="object_delete"
  readonly ZRBGB_INFIX_IAM_GET="bucket_iam_get"
  readonly ZRBGB_INFIX_IAM_SET="bucket_iam_set"
  readonly ZRBGB_INFIX_LIFECYCLE_SET="bucket_lifecycle_set"
  readonly ZRBGB_INFIX_MF_CREATE="managed_folder_create"
  readonly ZRBGB_INFIX_MF_DELETE="managed_folder_delete"
  readonly ZRBGB_INFIX_MF_LIST="managed_folder_list"

  readonly ZRBGB_KINDLED=1
}

zrbgb_sentinel() {
  test "${ZRBGB_KINDLED:-}" = "1" || buc_die "Module rbgb not kindled - call zrbgb_kindle first"
}

zrbgb_list_bucket_objects_capture() {
  zrbgb_sentinel

  local z_token="${1}"
  local z_bucket_name="${2}"
  local -r z_prefix="${3:-}"

  local z_list_url_base="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}/o"
  local z_page_token=""
  local z_first=1

  buc_log_args 'Optional prefix narrows the listing to one managed-folder subtree'
  local z_prefix_q=""
  if test -n "${z_prefix}"; then
    local z_prefix_enc
    z_prefix_enc=$(rbuh_urlencode_capture "${z_prefix}") || return 1
    z_prefix_q="prefix=${z_prefix_enc}"
  fi

  while :; do
    buc_log_args "Build URL with optional prefix + pageToken -> ${z_first}"
    local z_query="${z_prefix_q}"
    if test -n "${z_page_token}"; then
      buc_log_args 'pageToken must be URL-encoded'
      local z_tok_enc
      z_tok_enc=$(rbuh_urlencode_capture "${z_page_token}") || return 1
      test -z "${z_query}" || z_query="${z_query}&"
      z_query="${z_query}pageToken=${z_tok_enc}"
    fi
    local z_url="${z_list_url_base}"
    test -z "${z_query}" || z_url="${z_url}?${z_query}"

    buc_log_args 'Use a unique infix per page to avoid clobbering files'
    local z_infix="${ZRBGB_INFIX_LIST}${z_first}"
    rbuh_json "GET" "${z_url}" "${z_token}" "${z_infix}"

    local z_code
    z_code=$(rbuh_code_capture "${z_infix}") || return 1
    test "${z_code}" = "200" || return 1

    buc_log_args 'Print names from this page (if any)'
    buc_log_args 'Next page?'
    jq -r                '.items[]?.name // empty' "${ZRBUH_PREFIX}${z_infix}${ZRBUH_POSTFIX_JSON}"  || return 1
    z_page_token=$(jq -r '.nextPageToken // empty' "${ZRBUH_PREFIX}${z_infix}${ZRBUH_POSTFIX_JSON}") || return 1

    test -n "${z_page_token}" || break
    z_first=$((z_first + 1))
  done
}

zrbgb_empty_gcs_bucket() {
  zrbgb_sentinel

  local z_token="${1}"
  local z_bucket_name="${2}"

  buc_log_args 'Get list of objects to delete'
  local z_objects
  z_objects=$(zrbgb_list_bucket_objects_capture "${z_token}" "${z_bucket_name}") || {
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
                              "${z_token}" "${ZRBGB_INFIX_OBJECT_DELETE}"
    z_delete_code=$(rbuh_code_capture "${ZRBGB_INFIX_OBJECT_DELETE}") || z_delete_code=""
    case "${z_delete_code}" in
      204|404) buc_log_args "Object ${z_object}: deleted or not found"                     ;;
      *)       buc_warn     "Object ${z_object}: Failed to delete (HTTP ${z_delete_code})" ;;
    esac
  done <<< "${z_objects}"
}

######################################################################
# External Functions (rbgb_*)

rbgb_bucket_create() {
  zrbgb_sentinel

  local z_bucket_name="${1:-}"

  buc_doc_brief "Create a Cloud Storage bucket"
  buc_doc_param "bucket_name" "Name of the bucket to create"
  buc_doc_shown || return 0

  test -n "${z_bucket_name}" || buc_die "Bucket name required"

  buc_step "Creating Cloud Storage bucket: ${z_bucket_name}"

  buc_log_args 'Get OAuth token from admin'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  buc_log_args 'Create bucket request JSON'
  local z_bucket_req="${BURD_TEMP_DIR}/rbgb_bucket_create_req.json"
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
                                  "${ZRBGB_INFIX_CREATE}" "${z_bucket_req}"
  z_code=$(rbuh_code_capture "${ZRBGB_INFIX_CREATE}") || buc_die "Bad bucket creation HTTP code"
  z_err=$(rbuh_json_field_capture "${ZRBGB_INFIX_CREATE}" '.error.message') || z_err="HTTP ${z_code}"

  case "${z_code}" in
    200|201) buc_success "Bucket ${z_bucket_name} created";        return 0 ;;
    409)     buc_die     "Bucket ${z_bucket_name} already exists (pristine-state violation)" ;;
    *)       buc_die     "Failed to create bucket: ${z_err}"                ;;
  esac
}

rbgb_bucket_get() {
  zrbgb_sentinel

  local z_bucket_name="${1:-}"

  buc_doc_brief "Get Cloud Storage bucket details"
  buc_doc_param "bucket_name" "Name of the bucket to retrieve"
  buc_doc_shown || return 0

  test -n "${z_bucket_name}" || buc_die "Bucket name required"

  buc_step "Getting Cloud Storage bucket: ${z_bucket_name}"

  buc_log_args 'Get OAuth token from admin'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  buc_log_args 'Get bucket via REST API'
  rbuh_json "GET" "${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}" "${z_token}" "${ZRBGB_INFIX_GET}"
  rbuh_require_ok "Get bucket" "${ZRBGB_INFIX_GET}" 404 "not found"

  local z_http_code
  z_http_code=$(rbuh_code_capture "${ZRBGB_INFIX_GET}")
  if test "${z_http_code}" = "404"; then
    buc_info "Bucket not found: ${z_bucket_name}"
    return 1
  fi

  buc_success "Bucket found: ${z_bucket_name}"
  return 0
}

rbgb_bucket_set_iam() {
  zrbgb_sentinel

  local z_bucket_name="${1:-}"
  local z_policy_json="${2:-}"

  buc_doc_brief "Set IAM policy on a Cloud Storage bucket"
  buc_doc_param "bucket_name" "Name of the bucket"
  buc_doc_param "policy_json" "IAM policy JSON (from file or string)"
  buc_doc_shown || return 0

  test -n "${z_bucket_name}" || buc_die "Bucket name required"
  test -n "${z_policy_json}" || buc_die "Policy JSON required"

  buc_step "Setting IAM policy on bucket: ${z_bucket_name}"

  buc_log_args 'Get OAuth token from admin'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  buc_log_args 'Set IAM policy'
  local z_iam_url="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}/iam"
  local z_policy_file="${BURD_TEMP_DIR}/rbgb_bucket_set_iam.json"

  if test -f "${z_policy_json}"; then
    cp "${z_policy_json}" "${z_policy_file}"
  else
    printf '%s\n' "${z_policy_json}" > "${z_policy_file}"
  fi

  rbuh_json "PUT" "${z_iam_url}" "${z_token}" \
                                  "${ZRBGB_INFIX_IAM_SET}" "${z_policy_file}"
  rbuh_require_ok "Set bucket IAM policy" "${ZRBGB_INFIX_IAM_SET}"

  buc_success "IAM policy set on bucket: ${z_bucket_name}"
}

rbgb_bucket_add_iam_role() {
  zrbgb_sentinel

  local z_bucket_name="${1:-}"
  local z_member="${2:-}"
  local z_role="${3:-}"

  buc_doc_brief "Add IAM role to a member on a Cloud Storage bucket"
  buc_doc_param "bucket_name" "Name of the bucket"
  buc_doc_param "member" "Member to grant role to (serviceAccount:email or user:email)"
  buc_doc_param "role" "Role to grant (e.g., roles/storage.objectViewer)"
  buc_doc_shown || return 0

  test -n "${z_bucket_name}" || buc_die "Bucket name required"
  test -n "${z_member}" || buc_die "Member required"
  test -n "${z_role}" || buc_die "Role required"

  buc_step "Adding IAM role ${z_role} to ${z_member} on bucket: ${z_bucket_name}"

  buc_log_args 'Get OAuth token from admin'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  buc_log_args 'Use rbgi_add_bucket_iam_role'
  rbgi_add_bucket_iam_role "${z_token}" "${z_bucket_name}" "${z_member}" "${z_role}"

  buc_success "Added IAM role ${z_role} to ${z_member} on bucket: ${z_bucket_name}"
}

rbgb_bucket_set_lifecycle() {
  zrbgb_sentinel

  local z_bucket_name="${1:-}"
  local z_lifecycle_json="${2:-}"

  buc_doc_brief "Set lifecycle policy on a Cloud Storage bucket"
  buc_doc_param "bucket_name" "Name of the bucket"
  buc_doc_param "lifecycle_json" "Lifecycle policy JSON (from file or string)"
  buc_doc_shown || return 0

  test -n "${z_bucket_name}" || buc_die "Bucket name required"
  test -n "${z_lifecycle_json}" || buc_die "Lifecycle JSON required"

  buc_step "Setting lifecycle policy on bucket: ${z_bucket_name}"

  buc_log_args 'Get OAuth token from admin'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  buc_log_args 'Set lifecycle policy'
  local z_lifecycle_url="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}"
  local z_lifecycle_file="${BURD_TEMP_DIR}/rbgb_bucket_set_lifecycle.json"

  if test -f "${z_lifecycle_json}"; then
    jq -n --slurpfile lifecycle "${z_lifecycle_json}" '{ lifecycle: $lifecycle[0] }' > "${z_lifecycle_file}"
  else
    jq -n --argjson lifecycle "${z_lifecycle_json}" '{ lifecycle: $lifecycle }' > "${z_lifecycle_file}"
  fi

  rbuh_json "PATCH" "${z_lifecycle_url}" "${z_token}" \
                                  "${ZRBGB_INFIX_LIFECYCLE_SET}" "${z_lifecycle_file}"
  rbuh_require_ok "Set bucket lifecycle policy" "${ZRBGB_INFIX_LIFECYCLE_SET}"

  buc_success "Lifecycle policy set on bucket: ${z_bucket_name}"
}

rbgb_bucket_delete() {
  zrbgb_sentinel

  local z_bucket_name="${1:-}"
  local z_force="${2:-false}"

  buc_doc_brief "Delete a Cloud Storage bucket"
  buc_doc_param "bucket_name" "Name of the bucket to delete"
  buc_doc_param "force" "If 'true', empty bucket before deletion (optional, default: false)"
  buc_doc_shown || return 0

  test -n "${z_bucket_name}" || buc_die "Bucket name required"

  buc_step "Deleting Cloud Storage bucket: ${z_bucket_name}"

  buc_log_args 'Get OAuth token from admin'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  if test "${z_force}" = "true"; then
    buc_log_args 'Empty bucket before deletion'
    zrbgb_empty_gcs_bucket "${z_token}" "${z_bucket_name}"
  fi

  buc_log_args 'Delete the bucket'
  local z_code
  local z_err
  local z_delete_url="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}"
  rbuh_json "DELETE" "${z_delete_url}" \
                      "${z_token}" "${ZRBGB_INFIX_DELETE}"
  z_code=$(rbuh_code_capture "${ZRBGB_INFIX_DELETE}") || z_code=""
  z_err=$(rbuh_json_field_capture "${ZRBGB_INFIX_DELETE}" '.error.message') || z_err="HTTP ${z_code}"
  case "${z_code}" in
    204) buc_success "Bucket ${z_bucket_name} deleted";                           return 0 ;;
    404) buc_info    "Bucket ${z_bucket_name} not found (already deleted)";       return 0 ;;
    409) buc_warn "Bucket ${z_bucket_name} not empty or has retention policy"; return 1 ;;
    *)   buc_warn "Bucket ${z_bucket_name} failed delete";                     return 1 ;;
  esac
}

rbgb_bucket_ensure() {
  zrbgb_sentinel

  local -r z_token="${1:-}"
  local -r z_project_id="${2:-}"
  local -r z_bucket_name="${3:-}"
  local -r z_location="${4:-}"

  buc_doc_brief "Idempotently ensure a durable Cloud Storage bucket exists with Uniform Bucket-Level Access"
  buc_doc_param "token"       "OAuth bearer token authorized to create buckets in the project"
  buc_doc_param "project_id"  "Project that will own the bucket"
  buc_doc_param "bucket_name" "Globally-unique bucket name"
  buc_doc_param "location"    "Bucket location (e.g. a GCP region)"
  buc_doc_shown || return 0

  test -n "${z_token}"       || buc_die "Token required"
  test -n "${z_project_id}"  || buc_die "Project id required"
  test -n "${z_bucket_name}" || buc_die "Bucket name required"
  test -n "${z_location}"    || buc_die "Location required"

  buc_step "Ensuring Cloud Storage bucket: ${z_bucket_name} (project ${z_project_id})"

  buc_log_args 'Build request: UBLA enabled (managed folders require it); no expiry lifecycle (durable)'
  local -r z_req="${BURD_TEMP_DIR}/rbgb_bucket_ensure_req.json"
  jq -n --arg name "${z_bucket_name}" --arg location "${z_location}" '
{
  name: $name,
  location: $location,
  storageClass: "STANDARD",
  iamConfiguration: { uniformBucketLevelAccess: { enabled: true } }
}' > "${z_req}" || buc_die "Failed to build bucket ensure request JSON"

  buc_log_args 'POST create; tolerate 409 as idempotent already-present (contrast rbgb_bucket_create, which is pristine 409-fatal)'
  local -r z_url="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b?project=${z_project_id}"
  rbuh_json "POST" "${z_url}" "${z_token}" "${ZRBGB_INFIX_ENSURE}" "${z_req}"

  local z_code
  z_code=$(rbuh_code_capture "${ZRBGB_INFIX_ENSURE}") || buc_die "Bad bucket ensure HTTP code"
  case "${z_code}" in
    200|201) buc_success "Bucket ${z_bucket_name} created";                          return 0 ;;
    409)     buc_info    "Bucket ${z_bucket_name} already present (idempotent)";      return 0 ;;
    *)       local z_err
             z_err=$(rbuh_json_field_capture "${ZRBGB_INFIX_ENSURE}" '.error.message') || z_err="HTTP ${z_code}"
             buc_die "Failed to ensure bucket ${z_bucket_name}: ${z_err}" ;;
  esac
}

rbgb_managed_folder_ensure() {
  zrbgb_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket_name="${2:-}"
  local -r z_folder="${3:-}"

  buc_doc_brief "Idempotently ensure a managed folder exists in a UBLA bucket"
  buc_doc_param "token"       "OAuth bearer token"
  buc_doc_param "bucket_name" "Bucket holding the managed folder"
  buc_doc_param "folder"      "Managed folder name, a slash-terminated prefix (e.g. 'depot-project-id/')"
  buc_doc_shown || return 0

  test -n "${z_token}"       || buc_die "Token required"
  test -n "${z_bucket_name}" || buc_die "Bucket name required"
  test -n "${z_folder}"      || buc_die "Managed folder name required"

  buc_step "Ensuring managed folder: ${z_folder} in ${z_bucket_name}"

  local -r z_req="${BURD_TEMP_DIR}/rbgb_managed_folder_create_req.json"
  jq -n --arg name "${z_folder}" '{ name: $name }' > "${z_req}" \
    || buc_die "Failed to build managed folder request JSON"

  local -r z_url="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}/managedFolders"
  rbuh_json "POST" "${z_url}" "${z_token}" "${ZRBGB_INFIX_MF_CREATE}" "${z_req}"

  local z_code
  z_code=$(rbuh_code_capture "${ZRBGB_INFIX_MF_CREATE}") || buc_die "Bad managed folder create HTTP code"
  case "${z_code}" in
    200|201) buc_success "Managed folder ${z_folder} created";                      return 0 ;;
    409)     buc_info    "Managed folder ${z_folder} already present (idempotent)";  return 0 ;;
    *)       local z_err
             z_err=$(rbuh_json_field_capture "${ZRBGB_INFIX_MF_CREATE}" '.error.message') || z_err="HTTP ${z_code}"
             buc_die "Failed to ensure managed folder ${z_folder}: ${z_err}" ;;
  esac
}

rbgb_managed_folder_purge() {
  zrbgb_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket_name="${2:-}"
  local -r z_folder="${3:-}"

  buc_doc_brief "Delete a managed folder and the objects under its prefix (folder-aware teardown)"
  buc_doc_param "token"       "OAuth bearer token"
  buc_doc_param "bucket_name" "Bucket holding the managed folder"
  buc_doc_param "folder"      "Managed folder name to purge (slash-terminated prefix)"
  buc_doc_shown || return 0

  test -n "${z_token}"       || buc_die "Token required"
  test -n "${z_bucket_name}" || buc_die "Bucket name required"
  test -n "${z_folder}"      || buc_die "Managed folder name required"

  buc_step "Purging managed folder: ${z_folder} in ${z_bucket_name}"

  buc_log_args 'A managed folder deletes only when empty — clear the objects under its prefix first'
  local z_objects
  z_objects=$(zrbgb_list_bucket_objects_capture "${z_token}" "${z_bucket_name}" "${z_folder}") || z_objects=""

  if test -n "${z_objects}"; then
    local z_object=""
    local z_object_enc=""
    local z_obj_code=""
    while IFS= read -r z_object || test -n "${z_object}"; do
      test -n "${z_object}" || continue
      buc_log_args "Deleting object under folder: ${z_object}"
      z_object_enc=$(rbuh_urlencode_capture "${z_object}") || z_object_enc=""
      test -n "${z_object_enc}" || { buc_warn "Failed to encode object name: ${z_object}"; continue; }
      rbuh_json "DELETE" "${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}/o/${z_object_enc}" \
                                "${z_token}" "${ZRBGB_INFIX_OBJECT_DELETE}"
      z_obj_code=$(rbuh_code_capture "${ZRBGB_INFIX_OBJECT_DELETE}") || z_obj_code=""
      case "${z_obj_code}" in
        204|404) buc_log_args "Object ${z_object}: deleted or absent"                     ;;
        *)       buc_warn     "Object ${z_object}: delete failed (HTTP ${z_obj_code})"    ;;
      esac
    done <<< "${z_objects}"
  fi

  buc_log_args 'Delete the now-empty managed folder'
  local z_folder_enc
  z_folder_enc=$(rbuh_urlencode_capture "${z_folder}") || buc_die "Failed to encode managed folder name"
  rbuh_json "DELETE" "${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}/managedFolders/${z_folder_enc}" \
                            "${z_token}" "${ZRBGB_INFIX_MF_DELETE}"

  local z_del_code
  z_del_code=$(rbuh_code_capture "${ZRBGB_INFIX_MF_DELETE}") || z_del_code=""
  case "${z_del_code}" in
    204) buc_success "Managed folder ${z_folder} deleted";                        return 0 ;;
    404) buc_info    "Managed folder ${z_folder} not present (already gone)";     return 0 ;;
    *)   local z_err
         z_err=$(rbuh_json_field_capture "${ZRBGB_INFIX_MF_DELETE}" '.error.message') || z_err="HTTP ${z_del_code}"
         buc_warn "Managed folder ${z_folder} delete failed: ${z_err}";          return 1 ;;
  esac
}

# rbgb_managed_folders_capture <token> <bucket>
# List every managed folder in a UBLA bucket (paged), one slash-terminated
# folder name per line on stdout. Returns 1 on any list deficit — the caller
# decides error handling (capture contract).
rbgb_managed_folders_capture() {
  zrbgb_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket_name="${2:-}"

  test -n "${z_token}"       || return 1
  test -n "${z_bucket_name}" || return 1

  local -r z_list_url_base="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}/managedFolders"
  local z_page_token=""
  local z_page=1
  local z_url=""
  local z_tok_enc=""
  local z_infix=""
  local z_code=""

  while :; do
    z_url="${z_list_url_base}"
    if test -n "${z_page_token}"; then
      z_tok_enc=$(rbuh_urlencode_capture "${z_page_token}") || return 1
      z_url="${z_url}?pageToken=${z_tok_enc}"
    fi

    z_infix="${ZRBGB_INFIX_MF_LIST}${z_page}"
    rbuh_json "GET" "${z_url}" "${z_token}" "${z_infix}"

    z_code=$(rbuh_code_capture "${z_infix}") || return 1
    test "${z_code}" = "200" || return 1

    jq -r                '.items[]?.name // empty' "${ZRBUH_PREFIX}${z_infix}${ZRBUH_POSTFIX_JSON}"  || return 1
    z_page_token=$(jq -r '.nextPageToken // empty' "${ZRBUH_PREFIX}${z_infix}${ZRBUH_POSTFIX_JSON}") || return 1

    test -n "${z_page_token}" || break
    z_page=$((z_page + 1))
  done
}

rbgb_managed_folder_add_iam_role() {
  zrbgb_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket_name="${2:-}"
  local -r z_folder="${3:-}"
  local -r z_member="${4:-}"
  local -r z_role="${5:-}"

  buc_doc_brief "Grant an IAM role to a member on a managed folder (mirrors the AR repo-IAM grant idiom)"
  buc_doc_param "token"       "OAuth bearer token authorized to set the managed folder's IAM"
  buc_doc_param "bucket_name" "Bucket holding the managed folder"
  buc_doc_param "folder"      "Managed folder name (slash-terminated prefix)"
  buc_doc_param "member"      "Service account email (bare or serviceAccount:-prefixed)"
  buc_doc_param "role"        "Role to grant (e.g. roles/storage.objectAdmin)"
  buc_doc_shown || return 0

  test -n "${z_token}"       || buc_die "Token required"
  test -n "${z_bucket_name}" || buc_die "Bucket name required"
  test -n "${z_folder}"      || buc_die "Managed folder required"
  test -n "${z_member}"      || buc_die "Member required"
  test -n "${z_role}"        || buc_die "Role required"

  buc_step "Adding managed-folder IAM role ${z_role} to ${z_member} on ${z_folder}"

  buc_log_args 'Normalize to a bare account email — the rbgi primitive re-prefixes serviceAccount:'
  local -r z_account_email="${z_member#serviceAccount:}"

  rbgi_add_managed_folder_iam_role "${z_token}" "${z_bucket_name}" "${z_folder}" "${z_account_email}" "${z_role}"

  buc_success "Added managed-folder IAM role ${z_role} to ${z_member} on ${z_folder}"
}

# eof
