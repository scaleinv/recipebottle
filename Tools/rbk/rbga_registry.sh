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
# Recipe Bottle GCP Artifact Registry - Implementation

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBGA_SOURCED:-}" || buc_die "Module rbga multiply sourced - check sourcing hierarchy"
ZRBGA_SOURCED=1

######################################################################
# Internal Functions (zrbga_*)

zrbga_kindle() {
  test -z "${ZRBGA_KINDLED:-}" || buc_die "Module rbga already kindled"

  test -n "${RBDC_DEPOT_PROJECT_ID:-}"     || buc_die "RBDC_DEPOT_PROJECT_ID is not set"
  test   "${#RBDC_DEPOT_PROJECT_ID}" -gt 0 || buc_die "RBDC_DEPOT_PROJECT_ID is empty"

  buc_log_args "Ensure dependencies are kindled first"
  zrbgc_sentinel
  zrbgo_sentinel
  zrbuh_sentinel
  zrbgi_sentinel

  readonly ZRBGA_PREFIX="${BURD_TEMP_DIR}/rbga_"
  readonly ZRBGA_EMPTY_JSON="${ZRBGA_PREFIX}empty.json"
  printf '{}' > "${ZRBGA_EMPTY_JSON}"

  # Infix values for HTTP operations
  readonly ZRBGA_INFIX_CREATE_REPO="create_repo"
  readonly ZRBGA_INFIX_VERIFY_REPO="verify_repo"
  readonly ZRBGA_INFIX_DELETE_REPO="delete_repo"
  readonly ZRBGA_INFIX_GET_REPO="get_repo"
  readonly ZRBGA_INFIX_REPO_IAM_GET="repo_iam_get"
  readonly ZRBGA_INFIX_REPO_IAM_SET="repo_iam_set"

  readonly ZRBGA_KINDLED=1
}

zrbga_sentinel() {
  test "${ZRBGA_KINDLED:-}" = "1" || buc_die "Module rbga not kindled - call zrbga_kindle first"
}

######################################################################
# External Functions (rbga_*)

rbga_repo_create() {
  zrbga_sentinel

  local z_repo_name="${1:-}"
  local z_location="${2:-${RBGC_GAR_LOCATION}}"
  local z_format="${3:-DOCKER}"

  buc_doc_brief "Create an Artifact Registry repository"
  buc_doc_param "repo_name" "Name of the repository to create"
  buc_doc_param "location" "Location for the repository (optional, defaults to RBGC_GAR_LOCATION)"
  buc_doc_param "format" "Repository format (optional, defaults to DOCKER)"
  buc_doc_shown || return 0

  test -n "${z_repo_name}" || buc_die "Repository name required"
  test -n "${z_location}" || buc_die "Location required"

  buc_step "Creating Artifact Registry repository: ${z_repo_name} in ${z_location}"

  buc_log_args 'Get OAuth token from admin'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  local z_parent="projects/${RBDC_DEPOT_PROJECT_ID}${RBGC_PATH_LOCATIONS}/${z_location}"
  local z_resource="${z_parent}${RBGC_PATH_REPOSITORIES}/${z_repo_name}"
  local z_create_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_parent}${RBGC_PATH_REPOSITORIES}?repositoryId=${z_repo_name}"
  local z_create_body="${BURD_TEMP_DIR}/rbga_create_repo_body.json"

  jq -n --arg format "${z_format}" '{format: $format}' > "${z_create_body}" || buc_die "Failed to build create-repo body"

  buc_step "Create ${z_format} format repository"
  rbge_lro_ok                                              \
    "Create Artifact Registry repo"                                  \
    "${z_token}"                                                     \
    "${z_create_url}"                                                \
    "${ZRBGA_INFIX_CREATE_REPO}"                                     \
    "${z_create_body}"                                               \
    ".name"                                                          \
    "${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}"   \
    "${RBGC_OP_PREFIX_GLOBAL}"                                       \
    "${RBGC_EVENTUAL_CONSISTENCY_SEC}"                               \
    "${RBGC_MAX_CONSISTENCY_SEC}"

  buc_success "Repository ${z_repo_name} created in ${z_location}"
}

rbga_repo_get() {
  zrbga_sentinel

  local z_repo_name="${1:-}"
  local z_location="${2:-${RBGC_GAR_LOCATION}}"

  buc_doc_brief "Get Artifact Registry repository details"
  buc_doc_param "repo_name" "Name of the repository to retrieve"
  buc_doc_param "location" "Location of the repository (optional, defaults to RBGC_GAR_LOCATION)"
  buc_doc_shown || return 0

  test -n "${z_repo_name}" || buc_die "Repository name required"
  test -n "${z_location}" || buc_die "Location required"

  buc_step "Getting Artifact Registry repository: ${z_repo_name} in ${z_location}"

  buc_log_args 'Get OAuth token from admin'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  local z_resource="projects/${RBDC_DEPOT_PROJECT_ID}${RBGC_PATH_LOCATIONS}/${z_location}${RBGC_PATH_REPOSITORIES}/${z_repo_name}"
  local z_get_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_resource}"

  buc_step 'Get repository via REST API'
  rbuh_json "GET" "${z_get_url}" "${z_token}" "${ZRBGA_INFIX_GET_REPO}"
  rbuh_require_ok "Get repository" "${ZRBGA_INFIX_GET_REPO}" 404 "not found"

  local z_http_code
  z_http_code=$(rbuh_code_capture "${ZRBGA_INFIX_GET_REPO}")
  if test "${z_http_code}" = "404"; then
    buc_info "Repository not found: ${z_repo_name} in ${z_location}"
    return 1
  fi

  buc_log_args 'Verify repository format'
  local z_format
  z_format=$(rbuh_json_field_capture "${ZRBGA_INFIX_GET_REPO}" '.format') || z_format="UNKNOWN"
  buc_success "Repository found: ${z_repo_name} (format: ${z_format}) in ${z_location}"
  return 0
}

rbga_repo_set_iam() {
  zrbga_sentinel

  local z_repo_name="${1:-}"
  local z_location="${2:-${RBGC_GAR_LOCATION}}"
  local z_policy_json="${3:-}"

  buc_doc_brief "Set IAM policy on an Artifact Registry repository"
  buc_doc_param "repo_name" "Name of the repository"
  buc_doc_param "location" "Location of the repository (optional, defaults to RBGC_GAR_LOCATION)"
  buc_doc_param "policy_json" "IAM policy JSON (from file or string)"
  buc_doc_shown || return 0

  test -n "${z_repo_name}" || buc_die "Repository name required"
  test -n "${z_location}" || buc_die "Location required"
  test -n "${z_policy_json}" || buc_die "Policy JSON required"

  buc_step "Setting IAM policy on repository: ${z_repo_name} in ${z_location}"

  buc_log_args 'Get OAuth token from admin'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  local z_resource="projects/${RBDC_DEPOT_PROJECT_ID}${RBGC_PATH_LOCATIONS}/${z_location}${RBGC_PATH_REPOSITORIES}/${z_repo_name}"
  local z_set_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_resource}:setIamPolicy"
  local z_policy_file="${BURD_TEMP_DIR}/rbga_repo_set_iam.json"

  if test -f "${z_policy_json}"; then
    jq -n --slurpfile policy "${z_policy_json}" '{ policy: $policy[0] }' > "${z_policy_file}"
  else
    jq -n --argjson policy "${z_policy_json}" '{ policy: $policy }' > "${z_policy_file}"
  fi

  rbuh_json "POST" "${z_set_url}" "${z_token}" \
                                  "${ZRBGA_INFIX_REPO_IAM_SET}" "${z_policy_file}"
  rbuh_require_ok "Set repository IAM policy" "${ZRBGA_INFIX_REPO_IAM_SET}"

  buc_success "IAM policy set on repository: ${z_repo_name} in ${z_location}"
}

rbga_repo_add_iam_role() {
  zrbga_sentinel

  local z_repo_name="${1:-}"
  local z_location="${2:-${RBGC_GAR_LOCATION}}"
  local z_member="${3:-}"
  local z_role="${4:-}"

  buc_doc_brief "Add IAM role to a member on an Artifact Registry repository"
  buc_doc_param "repo_name" "Name of the repository"
  buc_doc_param "location" "Location of the repository (optional, defaults to RBGC_GAR_LOCATION)"
  buc_doc_param "member" "Member to grant role to (serviceAccount:email or user:email)"
  buc_doc_param "role" "Role to grant (e.g., roles/artifactregistry.reader)"
  buc_doc_shown || return 0

  test -n "${z_repo_name}" || buc_die "Repository name required"
  test -n "${z_location}" || buc_die "Location required"
  test -n "${z_member}" || buc_die "Member required"
  test -n "${z_role}" || buc_die "Role required"

  buc_step "Adding IAM role ${z_role} to ${z_member} on repository: ${z_repo_name} in ${z_location}"

  buc_log_args 'Get OAuth token from admin'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  # Extract email from member if it's in serviceAccount:email format
  local z_account_email="${z_member}"
  if [[ "${z_member}" =~ ^serviceAccount:(.+)$ ]]; then
    z_account_email="${BASH_REMATCH[1]}"
  fi

  buc_log_args 'Use rbgi_add_repo_iam_role'
  rbgi_add_repo_iam_role "${z_token}" "${RBDC_DEPOT_PROJECT_ID}" "${z_account_email}" "${z_location}" "${z_repo_name}" "${z_role}"

  buc_success "Added IAM role ${z_role} to ${z_member} on repository: ${z_repo_name} in ${z_location}"
}

rbga_repo_delete() {
  zrbga_sentinel

  local z_repo_name="${1:-}"
  local z_location="${2:-${RBGC_GAR_LOCATION}}"

  buc_doc_brief "Delete an Artifact Registry repository"
  buc_doc_param "repo_name" "Name of the repository to delete"
  buc_doc_param "location" "Location of the repository (optional, defaults to RBGC_GAR_LOCATION)"
  buc_doc_shown || return 0

  test -n "${z_repo_name}" || buc_die "Repository name required"
  test -n "${z_location}" || buc_die "Location required"

  buc_step "Deleting Artifact Registry repository: ${z_repo_name} in ${z_location}"

  buc_log_args 'Get OAuth token from admin'
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"

  local z_resource="projects/${RBDC_DEPOT_PROJECT_ID}${RBGC_PATH_LOCATIONS}/${z_location}${RBGC_PATH_REPOSITORIES}/${z_repo_name}"
  buc_log_args "Delete Artifact Registry repo '${z_repo_name}' in ${z_location}"
  local z_delete_code
  rbuh_json "DELETE"                                                           \
    "${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_resource}"    \
                            "${z_token}" "${ZRBGA_INFIX_DELETE_REPO}"
  z_delete_code=$(rbuh_code_capture "${ZRBGA_INFIX_DELETE_REPO}") || z_delete_code="000"
  case "${z_delete_code}" in
    200|204) buc_success "Repository ${z_repo_name} deleted" ;;
    404)     buc_info "Repository ${z_repo_name} not found (already deleted)" ;;
    *)
      local z_err
      z_err=$(rbuh_json_field_capture "${ZRBGA_INFIX_DELETE_REPO}" '.error.message') || z_err="Unknown error"
      buc_die "Failed to delete repository: ${z_err}"
      ;;
  esac
}

# eof
