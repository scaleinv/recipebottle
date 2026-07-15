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
# Recipe Bottle GCP Payor - Billing and Destructive Lifecycle Operations
#
# Scope: this file mixes two concerns; entry points are interleaved.
#   OAuth credential flow:
#     zrbgp_refresh_capture         (~76)   refresh-token exchange
#     zrbgp_authenticate_capture    (~122)  load + exchange
#     rbgp_payor_install            (~400)  full install ceremony
#   Depot lifecycle operations:
#     zrbgp_billing_attach/detach, liens, bucket helpers (~196-395)
#     rbgp_depot_levy / unmake / list (~568-1163)

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBGP_SOURCED:-}" || buc_die "Module rbgp multiply sourced - check sourcing hierarchy"
ZRBGP_SOURCED=1

######################################################################
# Internal Functions (zrbgp_*)

zrbgp_kindle() {
  test -z "${ZRBGP_KINDLED:-}" || buc_die "Module rbgp already kindled"

  buc_log_args "Ensure dependencies are kindled first"
  zrbgc_sentinel
  zrbgo_sentinel
  zrbuh_sentinel
  zrbgi_sentinel

  readonly ZRBGP_PREFIX="${BURD_TEMP_DIR}/rbgp_"
  readonly ZRBGP_EMPTY_JSON="${ZRBGP_PREFIX}empty.json"
  printf '{}' > "${ZRBGP_EMPTY_JSON}"

  readonly ZRBGP_SCRATCH_FILE="${BURD_TEMP_DIR}/rbgp_scratch.txt"

  # Infix values for HTTP operations
  readonly ZRBGP_INFIX_LIST_LIENS="list_liens"
  readonly ZRBGP_INFIX_DELETE_LIEN="delete_lien"
  readonly ZRBGP_INFIX_BILLING_ATTACH="billing_attach"
  readonly ZRBGP_INFIX_BILLING_DETACH="billing_detach"
  readonly ZRBGP_INFIX_PROJECT_INFO="project_info"
  readonly ZRBGP_INFIX_BUCKET_CREATE="bucket_create"
  readonly ZRBGP_INFIX_API_CHECK="api_checking"
  readonly ZRBGP_INFIX_GOV_LIST_SA="gov_list_sa"
  readonly ZRBGP_INFIX_GOV_DELETE_SA="gov_delete_sa"
  readonly ZRBGP_INFIX_GOV_CREATE_SA="gov_create_sa"
  readonly ZRBGP_INFIX_GOV_KEY="gov_key"

  # Pool build await budget — applies to any Cloud Build dispatched against
  # one of the depot's worker pools (probe at levy, posture check at info).
  # 120 polls × 5s = 10-minute ceiling, generous for cold-start worker
  # assignment and image pulls, well under Cloud Build's default
  # queueTtl=3600s. Foundry builds carry user payload and use the
  # ZRBFC_BUILD_POLL_CEILING_* family kindled in rbfc.
  readonly ZRBGP_POOL_BUILD_POLL_CEILING=120
  readonly ZRBGP_POOL_BUILD_POLL_INTERVAL_SEC=5

  # Posture-check per-request ceiling — cloud-side curl --max-time used by
  # the posture assertion script (zrbgp_write_posture_check) when probing
  # public/Google reachability from inside a Cloud Build worker. Value is
  # interpolated host-side into the cloud-destined script.
  readonly ZRBGP_POSTURE_REQUEST_MAX_TIME_SEC=10

  # Terrier bucket — manor-grain, homed in the Manor's payor project (RBS0), so
  # the name derives from the payor project, not the depot. One terrier bucket per
  # manor; durable, UBLA-enabled. Constant home is here (rbgp kindle runs after
  # the RBRP regime is enforced; rbdc_derived runs before it and is depot-facet).
  test -n "${RBRP_PAYOR_PROJECT_ID:-}" \
    || buc_die "RBRP_PAYOR_PROJECT_ID not set — terrier bucket name cannot be derived"
  readonly RBGP_TERRIER_BUCKET="${RBRP_PAYOR_PROJECT_ID}-terrier"

  readonly ZRBGP_KINDLED=1
}

zrbgp_sentinel() {
  test "${ZRBGP_KINDLED:-}" = "1" || buc_die "Module rbgp not kindled - call zrbgp_kindle first"
}


######################################################################
# OAuth Authentication Functions (zrbgp_oauth_*)

zrbgp_refresh_capture() {
  zrbgp_sentinel

  # RBRO credentials already loaded and validated by caller (rba_rbro_load)
  zrbro_sentinel
  test -n "${RBRP_OAUTH_CLIENT_ID:-}" || buc_die "RBRP_OAUTH_CLIENT_ID not set in environment"

  buc_log_args "Exchanging refresh token for access token"

  # Request body rides a process substitution into curl - secrets never touch disk
  local z_curl_status=0
  local z_response
  z_response=$(
    curl -sS -X POST \
      --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
      --max-time "${RBCC_CURL_MAX_TIME_SEC}" \
      -H "Content-Type: application/json" \
      -d @<(jq -n \
        --arg refresh_token "${RBRO_REFRESH_TOKEN}" \
        --arg client_id "${RBRP_OAUTH_CLIENT_ID}" \
        --arg client_secret "${RBRO_CLIENT_SECRET}" \
        --arg grant_type "refresh_token" \
        '{refresh_token: $refresh_token, client_id: $client_id, client_secret: $client_secret, grant_type: $grant_type}') \
      "${RBGC_OAUTH_TOKEN_URL}") || z_curl_status=$?
  test "${z_curl_status}" -eq 0 || buc_die "Failed to execute OAuth refresh request (curl exit ${z_curl_status})"

  # Check for error in response. invalid_rapt is discriminated from the
  # generic expired-or-invalid die: the token is healthy but the organization's
  # sign-in policy has lapsed the session, and the remedy is a re-install with
  # the SAME saved client JSON — no rotation, no console act.
  local z_error
  z_error=$(jq -r '.error // empty' <<<"${z_response}")
  if test -n "${z_error}"; then
    local z_error_subtype
    z_error_subtype=$(jq -r '.error_subtype // empty' <<<"${z_response}")
    local z_error_desc
    z_error_desc=$(jq -r '.error_description // .error // "Unknown error"' <<<"${z_response}")
    test "${z_error_subtype}" != "invalid_rapt" \
      || buc_die "Payor sign-in session lapsed under your organization's sign-in policy - re-run the Install tabtarget with the saved client-secret JSON: ${z_error_desc}"
    buc_die "OAuth credentials expired or invalid - reinstall payor credentials: ${z_error_desc}"
  fi

  local z_access_token
  z_access_token=$(jq -r '.access_token // empty' <<<"${z_response}")
  test -n "${z_access_token}" || buc_die "OAuth response missing access_token"

  echo "${z_access_token}"
}

# RBTOE: Payor OAuth Authentication Pattern
# Establishes Payor OAuth context by loading RBRO credentials and obtaining access token.
# Tokens are deliberately not cached — each call refreshes. Rationale: simplicity
# and freshness; refresh tokens are long-lived so the extra roundtrips are cheap
# relative to the depot operations they authorize, and uncached tokens can't grow
# stale between distinct Payor ceremonies.
zrbgp_authenticate_capture() {
  zrbgp_sentinel

  # Credless guard gate — first, before the RBRO credential load, so a guarded
  # run rejects before any credential touch (reveille cases must never reach creds).
  test "${BURE_TWEAK_NAME:-}" != "${RBCC_tweak_credless_guard}" \
    || buc_reject "${BUBC_band_credless}" "Credless guard: Payor OAuth token mint refused — this run carries the reveille-tier guard (reveille cases must never reach credentials)"

  buc_log_args "Establishing Payor OAuth authentication context"

  # Load RBRO credentials
  rba_rbro_load
  
  # Load RBRP_OAUTH_CLIENT_ID from environment
  test -n "${RBRP_OAUTH_CLIENT_ID:-}" || buc_die "RBRP_OAUTH_CLIENT_ID not set in environment"
  
  # Exchange refresh token for access token
  local z_access_token
  z_access_token=$(zrbgp_refresh_capture) || buc_die "Failed to exchange OAuth refresh token"
  
  test -n "${z_access_token}" || buc_die "Empty access token from OAuth exchange"
  
  buc_log_args "Payor OAuth authentication successful"
  echo "${z_access_token}"
}

# Probe per-installation depot states and emit per-moniker fact files.
# Uses CRM v3 projects:search with displayName anchor as discriminator —
# query "displayName:RBGC-DEPOT*" returns ACTIVE and DELETE_REQUESTED
# projects together (no billing-account enumeration required).  Moniker is
# derived by stripping the "${RBGC_DEPOT_DISPLAY_PREFIX} " prefix from each
# project's displayName.  Fact files are namespaced by cloud_prefix to keep
# same-moniker depots under different cloud_prefixes from colliding:
# "<cloud_prefix>/<moniker>.${RBCC_fact_ext_depot}" (state) and
# "<cloud_prefix>/<moniker>.${RBCC_fact_ext_depot_project}" (project_id) are
# written via buf_write_fact_multi; the cloud_prefix subdir is derived from
# projectId (everything before the "-d-" infix). Consumers walking by
# moniker alone restrict to their own subdir; consumers auditing across all
# depots walk all subdirs.
#
# No RBRP_BILLING_ACCOUNT_ID required for enumeration; no Mason SA IAM scan.
# The displayName anchor is the sole discriminator.  Projects whose
# displayName does not parse to a valid RBRR-canonical moniker are skipped.
#
# Paginated via nextPageToken; per-page infixes keep response files distinct.
#
# Single-shot per dispatch — buf_write_fact_multi dies on preexist.
#
# Args: <oauth_access_token>
zrbgp_depot_state_emit() {
  zrbgp_sentinel

  local -r z_token="${1:-}"
  test -n "${z_token}" || buc_die "zrbgp_depot_state_emit: token required"

  local -r z_search_query="displayName:${RBGC_DEPOT_DISPLAY_PREFIX}*"
  local -r z_search_url_base="${RBGC_API_ROOT_CRM}${RBGC_CRM_V3}/projects:search"

  # Anchor prefix string used inside loop for displayName stripping.
  local -r z_display_prefix="${RBGC_DEPOT_DISPLAY_PREFIX} "

  # Per-iteration synthesized locals (BCG exception 2 — declare outside, assign inside)
  local z_search_page=1
  local z_search_page_token=""
  local z_search_url=""
  local z_query_enc=""
  local z_tok_enc=""
  local z_search_infix=""
  local z_project_count=0
  local z_index=0
  local z_project_id=""
  local z_display_name=""
  local z_crm_state=""
  local z_state=""
  local z_moniker=""
  local z_get_url=""
  local z_get_infix=""
  local z_get_code=""
  local z_prefix_dir=""

  z_query_enc=$(rbuh_urlencode_capture "${z_search_query}") \
    || buc_die "Failed to URL-encode CRM v3 search query"

  while :; do
    z_search_url="${z_search_url_base}?query=${z_query_enc}"
    if test -n "${z_search_page_token}"; then
      z_tok_enc=$(rbuh_urlencode_capture "${z_search_page_token}") \
        || buc_die "Failed to URL-encode CRM v3 pageToken"
      z_search_url="${z_search_url}&pageToken=${z_tok_enc}"
    fi

    z_search_infix="depot_state_search_${z_search_page}"
    rbuh_json "GET" "${z_search_url}" "${z_token}" "${z_search_infix}"
    rbuh_require_ok "CRM v3 projects:search" "${z_search_infix}"

    z_project_count=$(rbuh_json_field_capture "${z_search_infix}" '.projects // [] | length') \
      || z_project_count=0

    z_index=0
    while test "${z_index}" -lt "${z_project_count}"; do
      z_project_id=$(rbuh_json_field_capture "${z_search_infix}" ".projects[${z_index}].projectId") \
        || { z_index=$((z_index + 1)); continue; }

      z_display_name=$(rbuh_json_field_capture "${z_search_infix}" ".projects[${z_index}].displayName") \
        || { z_index=$((z_index + 1)); continue; }

      # Strip the anchor prefix (including trailing space) to get the moniker.
      # displayName format: "${RBGC_DEPOT_DISPLAY_PREFIX} <moniker>"
      if [[ "${z_display_name}" != "${z_display_prefix}"* ]]; then
        buc_log_args "Skipping project — displayName does not match anchor: ${z_display_name}"
        z_index=$((z_index + 1))
        continue
      fi
      z_moniker="${z_display_name#"${z_display_prefix}"}"

      # Validate moniker is RBRR-canonical: ^[a-z][a-z0-9]*$
      if ! [[ "${z_moniker}" =~ ^[a-z][a-z0-9]*$ ]]; then
        buc_log_args "Skipping project — moniker fails validation (${z_moniker}): ${z_display_name}"
        z_index=$((z_index + 1))
        continue
      fi

      # CRM v3 projects:search lags state mutations (notably post-delete transitions).
      # GET against the strongly-consistent endpoint for authoritative state.
      z_get_url="${RBGC_API_ROOT_CRM}${RBGC_CRM_V3}/projects/${z_project_id}"
      z_get_infix="depot_state_get_${z_project_id}"
      rbuh_json "GET" "${z_get_url}" "${z_token}" "${z_get_infix}"
      z_get_code=$(rbuh_code_capture "${z_get_infix}") || z_get_code=""
      case "${z_get_code}" in
        200)
          z_crm_state=$(rbuh_json_field_capture "${z_get_infix}" '.state // "UNKNOWN"') \
            || z_crm_state="UNKNOWN"
          ;;
        404)
          # Project completed deletion between search and GET — emit nothing.
          z_index=$((z_index + 1))
          continue
          ;;
        *)
          buc_log_args "Skipping project ${z_project_id} — GET returned ${z_get_code}"
          z_index=$((z_index + 1))
          continue
          ;;
      esac

      if test "${z_crm_state}" = "DELETE_REQUESTED"; then
        z_state="${RBGP_DEPOT_STATE_DELETE_REQUESTED}"
      elif test "${z_crm_state}" = "${RBGC_STATE_ACTIVE}"; then
        z_state="${RBGP_DEPOT_STATE_COMPLETE}"
      else
        buc_log_args "Skipping project ${z_project_id} with unrecognized state: ${z_crm_state}"
        z_index=$((z_index + 1))
        continue
      fi

      # Namespace per cloud_prefix so two depots that share a moniker under
      # different cloud_prefixes can coexist (see fact-file layout note above).
      z_prefix_dir="${z_project_id%%-d-*}"
      mkdir -p "${BURD_OUTPUT_DIR}/${z_prefix_dir}" \
        || buc_die "Failed to mkdir output cloud_prefix subdir: ${z_prefix_dir}"
      mkdir -p "${BURD_TEMP_DIR}/${z_prefix_dir}" \
        || buc_die "Failed to mkdir temp cloud_prefix subdir: ${z_prefix_dir}"
      buf_write_fact_multi "${z_prefix_dir}/${z_moniker}" "${RBCC_fact_ext_depot}"         "${z_state}"
      buf_write_fact_multi "${z_prefix_dir}/${z_moniker}" "${RBCC_fact_ext_depot_project}" "${z_project_id}"

      z_index=$((z_index + 1))
    done

    z_search_page_token=$(rbuh_json_field_capture "${z_search_infix}" '.nextPageToken') \
      || z_search_page_token=""
    test -n "${z_search_page_token}" || break
    z_search_page=$((z_search_page + 1))
  done
}

# Post-lifecycle hook: refresh per-moniker depot fact files.
# Called by levy and unmake at end-of-operation so observers (theurge
# autodetect, manual inspection) see fresh state.
zrbgp_depot_list_update() {
  zrbgp_sentinel

  buc_log_args "Refreshing per-moniker depot fact files"

  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate for depot fact refresh"

  zrbgp_depot_state_emit "${z_token}"
}

######################################################################
# External Functions (rbgp_*)

zrbgp_billing_attach() {
  zrbgp_sentinel

  local -r z_billing_account="${1:-}"

  buc_doc_brief "Attach a billing account to the project"
  buc_doc_param "billing_account" "Billing account ID to attach"
  buc_doc_shown || return 0

  test -n "${z_billing_account}" || buc_die "Billing account ID required"

  buc_step "Attaching billing account: ${z_billing_account}"

  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"
  local -r z_billing_body="${BURD_TEMP_DIR}/rbgp_billing_attach.json"
  jq -n --arg billingAccountName "billingAccounts/${z_billing_account}" \
    --arg projectId "${RBDC_DEPOT_PROJECT_ID}" \
    '{
      billingAccountName: $billingAccountName,
      projectId: $projectId,
      billingEnabled: true
    }' > "${z_billing_body}" || buc_die "Failed to build billing attach body"

  local -r z_billing_url="${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/projects/${RBDC_DEPOT_PROJECT_ID}:setBillingInfo"
  rbuh_json "PUT" "${z_billing_url}" "${z_token}" \
                                  "${ZRBGP_INFIX_BILLING_ATTACH}" "${z_billing_body}"
  rbuh_require_ok "Attach billing account" "${ZRBGP_INFIX_BILLING_ATTACH}"

  buc_success "Billing account ${z_billing_account} attached to project"
}

zrbgp_billing_detach() {
  zrbgp_sentinel

  buc_doc_brief "Detach billing account from the project"
  buc_doc_shown || return 0

  buc_step "Detaching billing account from project"

  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"
  local -r z_billing_body="${BURD_TEMP_DIR}/rbgp_billing_detach.json"
  jq -n --arg projectId "${RBDC_DEPOT_PROJECT_ID}" \
    '{
      projectId: $projectId,
      billingEnabled: false
    }' > "${z_billing_body}" || buc_die "Failed to build billing detach body"

  local -r z_billing_url="${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/projects/${RBDC_DEPOT_PROJECT_ID}:setBillingInfo"
  rbuh_json "PUT" "${z_billing_url}" "${z_token}" \
                                  "${ZRBGP_INFIX_BILLING_DETACH}" "${z_billing_body}"
  rbuh_require_ok "Detach billing account" "${ZRBGP_INFIX_BILLING_DETACH}"

  buc_success "Billing account detached from project"
}



zrbgp_liens_list() {
  zrbgp_sentinel

  buc_doc_brief "List all liens on the project"
  buc_doc_shown || return 0

  buc_step "Listing liens on project: ${RBDC_DEPOT_PROJECT_ID}"

  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"
  rbuh_json "GET" "${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/liens?parent=projects/${RBDC_DEPOT_PROJECT_ID}" "${z_token}" "${ZRBGP_INFIX_LIST_LIENS}"
  rbuh_require_ok "List liens" "${ZRBGP_INFIX_LIST_LIENS}"

  local z_lien_count
  z_lien_count=$(rbuh_json_field_capture "${ZRBGP_INFIX_LIST_LIENS}" '.liens // [] | length') || buc_die "Failed to parse liens response"

  if test "${z_lien_count}" -eq 0; then
    buc_info "No liens found on project"
    return 0
  fi

  buc_step "Found ${z_lien_count} lien(s):"
  jq -r '.liens[]? | "  - " + .name + " (reason: " + .reason + ")"' \
    "${ZRBUH_PREFIX}${ZRBGP_INFIX_LIST_LIENS}${ZRBUH_POSTFIX_JSON}" || true

  return 0
}

zrbgp_lien_delete() {
  zrbgp_sentinel

  local -r z_lien_name="${1:-}"

  buc_doc_brief "Delete a specific lien from the project"
  buc_doc_param "lien_name" "Full resource name of the lien to delete"
  buc_doc_shown || return 0

  test -n "${z_lien_name}" || buc_die "Lien name required"

  buc_step "Deleting lien: ${z_lien_name}"

  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || buc_die "Failed to get admin token"
  rbuh_json "DELETE" "${RBGC_API_CRM_DELETE_LIEN}/${z_lien_name}" "${z_token}" "${ZRBGP_INFIX_DELETE_LIEN}"
  rbuh_require_ok "Delete lien" "${ZRBGP_INFIX_DELETE_LIEN}" 404 "not found (already deleted)"

  buc_success "Lien deleted: ${z_lien_name}"
}


######################################################################
# Capture: list required services that are NOT enabled (blank = all enabled)
zrbgp_required_apis_missing_capture() {
  zrbgp_sentinel

  local -r z_token="${1:-}"
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
    z_infix="${ZRBGP_INFIX_API_CHECK}_${z_service}"

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

zrbgp_get_project_number_capture() {
  zrbgp_sentinel

  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_governor}") || return 1

  rbuh_json "GET" "${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}${RBGC_PATH_PROJECTS}/${RBDC_DEPOT_PROJECT_ID}" "${z_token}" "${ZRBGP_INFIX_PROJECT_INFO}"
  rbuh_require_ok "Get project info" "${ZRBGP_INFIX_PROJECT_INFO}" || return 1

  local z_project_number
  z_project_number=$(rbuh_json_field_capture "${ZRBGP_INFIX_PROJECT_INFO}" '.projectNumber') || return 1
  test -n "${z_project_number}" || return 1

  echo "${z_project_number}"
}


zrbgp_create_gcs_bucket() {
  zrbgp_sentinel

  local -r z_token="${1}"
  local -r z_bucket_name="${2}"

  buc_log_args 'Create bucket request JSON for '"${z_bucket_name}"
  local -r z_bucket_req="${BURD_TEMP_DIR}/rbgp_bucket_create_req.json"
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
  rbuh_json "POST" "${RBGC_API_GCS_BUCKETS}?project=${RBDC_DEPOT_PROJECT_ID}" "${z_token}" \
                                  "${ZRBGP_INFIX_BUCKET_CREATE}" "${z_bucket_req}"
  z_code=$(rbuh_code_capture "${ZRBGP_INFIX_BUCKET_CREATE}") || buc_die "Bad bucket creation HTTP code"
  z_err=$(rbuh_json_field_capture "${ZRBGP_INFIX_BUCKET_CREATE}" '.error.message') || z_err="HTTP ${z_code}"

  case "${z_code}" in
    200|201) buc_info "Bucket ${z_bucket_name} created";                         return 0 ;;
    409)     buc_die  "Bucket ${z_bucket_name} already exists (pristine-state violation)" ;;
    *)       buc_die  "Failed to create bucket: ${z_err}"                                 ;;
  esac
}

# Write the posture-check assertion script for a pool variant to the
# caller-provided path. Side-effect only — caller hands the same path
# to the pool-build submitter. The script is cloud-side bash run as
# step 1 of the per-pool build (probe or posture-only). SUCCESS terminal
# exit means reality matches the pool's stamped egress posture. Curl is
# deliberately used WITHOUT -f so HTTP 4xx/5xx responses from a reached
# server still count as "reached" — the test is reachability vs
# connection failure, not authorization. Only honest curl failures (DNS,
# connection refused, timeout) trip the assertion.
# Args: variant (tether|airgap) path
zrbgp_write_posture_check() {
  zrbgp_sentinel

  local -r z_variant="${1:-}"
  local -r z_path="${2:-}"
  test -n "${z_variant}" || buc_die "zrbgp_write_posture_check: variant required"
  test -n "${z_path}"    || buc_die "zrbgp_write_posture_check: path required"

  case "${z_variant}" in
    tether)
      # quay blob-CDN: podvm immure blob pulls 302-redirect from quay.io to its
      # CDN family (cdn01/02/03.quay.io — Red Hat's published allowlist set).
      # First breakage point if the pool's egress posture ever tightens to an
      # allowlist; probe one representative host. Connection-level reachability
      # only — the no -f rule above means the CDN's 4xx to a bare GET still
      # counts as reached.
      printf '%s\n' \
        '#!/bin/bash' \
        'set -euo pipefail' \
        "curl -sS -o /dev/null --max-time ${ZRBGP_POSTURE_REQUEST_MAX_TIME_SEC} https://example.com || { echo \"tether: ERROR public unreachable (connection failure)\" >&2; exit 1; }" \
        'echo "tether: public reached"' \
        "curl -sS -o /dev/null --max-time ${ZRBGP_POSTURE_REQUEST_MAX_TIME_SEC} https://storage.googleapis.com || { echo \"tether: ERROR google unreachable (connection failure)\" >&2; exit 1; }" \
        'echo "tether: google reached"' \
        "curl -sS -o /dev/null --max-time ${ZRBGP_POSTURE_REQUEST_MAX_TIME_SEC} https://cdn01.quay.io || { echo \"tether: ERROR quay blob-CDN unreachable (connection failure)\" >&2; exit 1; }" \
        'echo "tether: quay blob-CDN reached"' \
        > "${z_path}" \
        || buc_die "Failed to write tether posture check"
      ;;
    airgap)
      printf '%s\n' \
        '#!/bin/bash' \
        'set -euo pipefail' \
        "if curl -sS -o /dev/null --max-time ${ZRBGP_POSTURE_REQUEST_MAX_TIME_SEC} https://example.com; then echo \"airgap: ERROR public is reachable (expected blocked)\" >&2; exit 1; fi" \
        'echo "airgap: public blocked"' \
        "curl -sS -o /dev/null --max-time ${ZRBGP_POSTURE_REQUEST_MAX_TIME_SEC} https://storage.googleapis.com || { echo \"airgap: ERROR google unreachable (connection failure)\" >&2; exit 1; }" \
        'echo "airgap: google reached"' \
        > "${z_path}" \
        || buc_die "Failed to write airgap posture check"
      ;;
    *)
      buc_die "Unknown pool variant: ${z_variant}"
      ;;
  esac
}

# Submit a pre-composed Cloud Build against one of the depot's worker pools
# and await its terminal state. Shared primitive between the levy probe
# (which dispatches a 2-step build: posture check + marker push) and the
# depot-info posture submit (which dispatches the posture check alone).
# Pool builds are intentionally tiny; wall-clock is dominated by Cloud
# Build infrastructure overhead (worker assignment, image pulls). Typical
# happy path is 60-120s; budget is ZRBGP_POOL_BUILD_POLL_CEILING ×
# ZRBGP_POOL_BUILD_POLL_INTERVAL_SEC = 10 minutes, well under Cloud Build's
# default queueTtl=3600s. Synchronous: the levy/info caller blocks until
# terminal.
# The previous fire-and-forget pattern caused a late-clearing-probe-collision
# wedge: a queued probe cleared minutes later and wedged the next build behind
# it until queueTtl expired. SUCCESS terminal is the happy path; any non-2xx submission
# is fatal (the prior 400-tolerance branch defended a folkloric "quota
# row materialization" theory that has been retired).
# Args: token pool_variant pool_id build_json_file infix_prefix operation_label artifact_ref
#   artifact_ref empty → omit the "  Artifact: …" line (posture path)
zrbgp_pool_build_submit_await() {
  zrbgp_sentinel

  local -r z_token="${1:-}"
  local -r z_pool_variant="${2:-}"
  local -r z_pool_id="${3:-}"
  local -r z_build_json_file="${4:-}"
  local -r z_infix_prefix="${5:-}"
  local -r z_operation_label="${6:-}"
  local -r z_artifact_ref="${7:-}"

  test -n "${z_token}"           || buc_die "zrbgp_pool_build_submit_await: token required"
  test -n "${z_pool_variant}"    || buc_die "zrbgp_pool_build_submit_await: pool_variant required"
  test -n "${z_pool_id}"         || buc_die "zrbgp_pool_build_submit_await: pool_id required"
  test -n "${z_build_json_file}" || buc_die "zrbgp_pool_build_submit_await: build_json_file required"
  test -n "${z_infix_prefix}"    || buc_die "zrbgp_pool_build_submit_await: infix_prefix required"
  test -n "${z_operation_label}" || buc_die "zrbgp_pool_build_submit_await: operation_label required"

  local -r z_region="${RBRD_GCP_REGION}"
  local -r z_build_url="${RBGC_API_ROOT_CLOUDBUILD}${RBGC_CLOUDBUILD_V1}/projects/${RBDC_DEPOT_PROJECT_ID}/locations/${z_region}/builds"
  local -r z_infix="${z_infix_prefix}_${z_pool_variant}_submit"

  rbuh_json "POST" "${z_build_url}" "${z_token}" "${z_infix}" "${z_build_json_file}"
  local z_submit_code
  z_submit_code=$(rbuh_code_capture "${z_infix}") \
    || buc_die "Bad ${z_operation_label} submission HTTP code for ${z_pool_variant}"

  buc_info "${z_operation_label}: ${z_pool_variant}"
  buc_info "  Pool:     ${z_pool_id}"
  if test -n "${z_artifact_ref}"; then
    buc_info "  Artifact: ${z_artifact_ref}"
  fi

  case "${z_submit_code}" in
    200|201) : ;;
    *)
      local z_err
      z_err=$(rbuh_json_field_capture "${z_infix}" '.error.message') || z_err="HTTP ${z_submit_code}"
      buc_die "${z_operation_label} submission failed for ${z_pool_variant}: ${z_err}"
      ;;
  esac

  local z_build_id
  z_build_id=$(rbuh_json_field_capture "${z_infix}" '.metadata.build.id') || z_build_id=""
  test -n "${z_build_id}" \
    || buc_die "${z_operation_label} submission for ${z_pool_variant} returned no build ID (HTTP ${z_submit_code})"

  buc_info "  Build:    ${z_build_id} (awaiting terminal state)"
  buc_link "  " "Open ${z_operation_label} build in Cloud Console" \
    "${RBGC_CONSOLE_URL}cloud-build/builds;region=${z_region}/${z_build_id}?project=${RBDC_DEPOT_PROJECT_ID}"

  local -r z_build_get_url="${z_build_url}/${z_build_id}"
  local z_status="PENDING"
  local z_polls=0
  local z_poll_infix=""
  while true; do
    case "${z_status}" in PENDING|QUEUED|WORKING) : ;; *) break ;; esac
    sleep "${ZRBGP_POOL_BUILD_POLL_INTERVAL_SEC}"
    z_polls=$((z_polls + 1))
    test "${z_polls}" -le "${ZRBGP_POOL_BUILD_POLL_CEILING}" \
      || buc_die "${z_operation_label} ${z_pool_variant}: timeout after ${ZRBGP_POOL_BUILD_POLL_CEILING} polls (${ZRBGP_POOL_BUILD_POLL_INTERVAL_SEC}s interval); last status=${z_status}"
    z_poll_infix="${z_infix_prefix}_${z_pool_variant}_poll_${z_polls}"
    rbuh_json "GET" "${z_build_get_url}" "${z_token}" "${z_poll_infix}"
    z_status=$(rbuh_json_field_capture "${z_poll_infix}" '.status') || z_status="UNKNOWN"
    buc_info "  ${z_operation_label} ${z_pool_variant}: ${z_status} (poll ${z_polls}/${ZRBGP_POOL_BUILD_POLL_CEILING})"
  done
  buc_info "  ${z_operation_label} ${z_pool_variant}: terminal = ${z_status}"
}

# Levy-time per-pool probe. Composes a 2-step Cloud Build (posture check
# + marker push) and delegates to zrbgp_pool_build_submit_await. The
# probe's effects: (1) submission itself populates the per-pool quota row
# in Google's console UI; (2) step 1 confirms the pool exhibits its
# stamped egress posture; (3) step 2 confirms the worker can authenticate
# and push to rbi_df under the depot's GAR repository. SUCCESS is the
# expected terminal; FAILURE means the in-build posture assertion tripped
# and the operator should inspect via the console link.
# Builder images are Google-hosted only — airgap cannot reach docker.io.
# Args: token pool_variant pool_id mason_email posture_check_file
zrbgp_pool_probe_submit() {
  zrbgp_sentinel

  local -r z_token="${1}"
  local -r z_pool_variant="${2}"
  local -r z_pool_id="${3}"
  local -r z_mason_email="${4}"
  local -r z_posture_check_file="${5}"

  local -r z_region="${RBRD_GCP_REGION}"
  local -r z_pool_resource="projects/${RBDC_DEPOT_PROJECT_ID}/locations/${z_region}/workerPools/${z_pool_id}"
  local -r z_mason_sa="projects/${RBDC_DEPOT_PROJECT_ID}/serviceAccounts/${z_mason_email}"
  local -r z_probe_ref="${z_region}${RBGC_GAR_HOST_SUFFIX}/${RBDC_DEPOT_PROJECT_ID}/${RBDC_GAR_REPOSITORY}/${RBGC_GAR_CATEGORY_DEPOT_FACTS}/probe-${z_pool_variant}:probe"

  # Push script — pool-specific values baked in at host-side, so Cloud Build
  # sees a fully-resolved script with no substitutions. Heredocs inside this
  # file are cloud-side bash (executed by the build worker); BCG host-side
  # heredoc prohibition does not apply to content destined for cloud execution.
  local -r z_push_script_file="${BURD_TEMP_DIR}/rbgp_probe_${z_pool_variant}_push.sh"
  printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'mkdir -p /workspace/probe' \
    'cat > /workspace/probe/probe-marker.txt <<MARKER' \
    'RecipeBottle depot levy probe' \
    "pool:    ${z_pool_id}" \
    "variant: ${z_pool_variant}" \
    "depot:   ${RBDC_DEPOT_PROJECT_ID}" \
    'MARKER' \
    'cat > /workspace/probe/Dockerfile <<DF' \
    'FROM scratch' \
    'COPY probe-marker.txt /' \
    'DF' \
    "docker build -t \"${z_probe_ref}\" /workspace/probe" \
    "docker push \"${z_probe_ref}\"" \
    "echo \"GAR push OK: ${z_probe_ref}\"" \
    > "${z_push_script_file}" \
    || buc_die "Failed to write probe push script for ${z_pool_variant}"

  local -r z_build_file="${BURD_TEMP_DIR}/rbgp_probe_${z_pool_variant}_build.json"
  jq -n \
    --arg     posture_image   "gcr.io/google.com/cloudsdktool/cloud-sdk:alpine" \
    --arg     docker_image    "gcr.io/cloud-builders/docker" \
    --rawfile posture_check   "${z_posture_check_file}" \
    --rawfile push_script     "${z_push_script_file}" \
    --arg     pool_resource   "${z_pool_resource}" \
    --arg     service_account "${z_mason_sa}" \
    '{
      steps: [
        {
          name:   $posture_image,
          id:     "assert-egress-posture",
          script: $posture_check
        },
        {
          name:   $docker_image,
          id:     "probe-gar-push",
          script: $push_script
        }
      ],
      serviceAccount: $service_account,
      options: {
        logging: "CLOUD_LOGGING_ONLY",
        pool: { name: $pool_resource }
      }
    }' > "${z_build_file}" \
    || buc_die "Failed to compose probe build JSON for ${z_pool_variant}"

  zrbgp_pool_build_submit_await \
    "${z_token}" "${z_pool_variant}" "${z_pool_id}" \
    "${z_build_file}" "depot_probe" "Per-pool probe" "${z_probe_ref}"
}

# Depot-info per-pool posture check. Composes a 1-step Cloud Build that
# runs the posture-check assertion against an existing worker pool and
# delegates to zrbgp_pool_build_submit_await. Distinct from the levy's
# 2-step probe: no marker push, no GAR write — purely an egress-posture
# diagnostic against a pool that has already been levied and probed.
# SUCCESS terminal = pool's egress posture matches its stamped config;
# FAILURE = drift worth investigating via the console link.
# Args: token pool_variant pool_id mason_email posture_check_file
zrbgp_pool_posture_submit() {
  zrbgp_sentinel

  local -r z_token="${1:-}"
  local -r z_pool_variant="${2:-}"
  local -r z_pool_id="${3:-}"
  local -r z_mason_email="${4:-}"
  local -r z_posture_check_file="${5:-}"

  test -n "${z_token}"              || buc_die "zrbgp_pool_posture_submit: token required"
  test -n "${z_pool_variant}"       || buc_die "zrbgp_pool_posture_submit: pool_variant required"
  test -n "${z_pool_id}"            || buc_die "zrbgp_pool_posture_submit: pool_id required"
  test -n "${z_mason_email}"        || buc_die "zrbgp_pool_posture_submit: mason_email required"
  test -n "${z_posture_check_file}" || buc_die "zrbgp_pool_posture_submit: posture_check_file required"

  local -r z_region="${RBRD_GCP_REGION}"
  local -r z_pool_resource="projects/${RBDC_DEPOT_PROJECT_ID}/locations/${z_region}/workerPools/${z_pool_id}"
  local -r z_mason_sa="projects/${RBDC_DEPOT_PROJECT_ID}/serviceAccounts/${z_mason_email}"

  local -r z_build_file="${BURD_TEMP_DIR}/rbgp_posture_${z_pool_variant}_build.json"
  jq -n \
    --arg     posture_image   "gcr.io/google.com/cloudsdktool/cloud-sdk:alpine" \
    --rawfile posture_check   "${z_posture_check_file}" \
    --arg     pool_resource   "${z_pool_resource}" \
    --arg     service_account "${z_mason_sa}" \
    '{
      steps: [
        {
          name:   $posture_image,
          id:     "assert-egress-posture",
          script: $posture_check
        }
      ],
      serviceAccount: $service_account,
      options: {
        logging: "CLOUD_LOGGING_ONLY",
        pool: { name: $pool_resource }
      }
    }' > "${z_build_file}" \
    || buc_die "Failed to compose posture build JSON for ${z_pool_variant}"

  zrbgp_pool_build_submit_await \
    "${z_token}" "${z_pool_variant}" "${z_pool_id}" \
    "${z_build_file}" "depot_posture" "Posture check" ""
}

######################################################################
# External Functions (rbgp_*)

rbgp_payor_install() {
  zrbgp_sentinel

  local -r z_oauth_json_file="${BUZ_FOLIO:-}"

  buc_doc_brief "Install Payor OAuth credentials from client JSON file following RBAGS specification"
  buc_doc_param "oauth_json_file" "Path to downloaded OAuth client JSON file from establish procedure"
  buc_doc_lines "REQUIREMENT: OAuth consent-screen audience must be Internal (instaurate gates it)"
  buc_doc_lines "            and the Payor project must have required APIs enabled"
  buc_doc_lines "REQUIREMENT: RBRP_BILLING_ACCOUNT_ID must be set in environment"
  buc_doc_shown || return 0

  buc_step 'Validate environment prerequisites'
  test -n "${RBRP_BILLING_ACCOUNT_ID:-}" || buc_die "RBRP_BILLING_ACCOUNT_ID not set in environment - obtain from Cloud Console Billing and set before proceeding"

  buc_step 'Validate input parameters'
  test -n "${z_oauth_json_file}" || buc_die "OAuth JSON file path required as first argument"
  test -f "${z_oauth_json_file}" || buc_die "OAuth JSON file not found: ${z_oauth_json_file}"

  buc_step 'Parse OAuth client JSON'
  local z_client_id="" z_client_secret="" z_project_id=""
  jq -r '
    (.installed.client_id // .client_id // ""),
    (.installed.client_secret // .client_secret // ""),
    (.installed.project_id // .project_id // "")
  ' "${z_oauth_json_file}" > "${ZRBGP_SCRATCH_FILE}" 2>/dev/null \
    || buc_die "Failed to parse OAuth JSON file"
  { read -r z_client_id
    read -r z_client_secret
    read -r z_project_id
  } < "${ZRBGP_SCRATCH_FILE}"
  test -n "${z_client_id}" || buc_die "OAuth JSON file missing client_id field"
  test -n "${z_client_secret}" || buc_die "OAuth JSON file missing client_secret field"
  test -n "${z_project_id}" || buc_die "OAuth JSON file missing project_id field"

  buc_step 'Check existing credentials'
  local -r z_rbro_file="${RBDC_PAYOR_RBRO_FILE}"
  if test -f "${z_rbro_file}"; then
    buc_log_args "Existing RBRO credentials will be replaced"
  fi

  local z_refresh_token=""
  buc_step 'OAuth authorization flow'
  # Loopback redirect — Google's documented OOB successor for desktop/CLI
  # (OOB is blocked for production apps, and an Internal app is production
  # from birth). No listener runs: the browser lands on an unreachable
  # localhost page and the authorization code rides the address-bar URL,
  # which the operator pastes back. prompt=consent forces the consent screen
  # on re-install so a refresh token is always minted (a skipped screen
  # returns none).
  local -r z_redirect_uri="http://localhost:8085/"
  local z_redirect_enc
  z_redirect_enc=$(rbuh_urlencode_capture "${z_redirect_uri}") || buc_die "Failed to URL-encode redirect URI"
  local -r z_auth_url="${RBGC_OAUTH_AUTHORIZE_URL}?client_id=${z_client_id}&redirect_uri=${z_redirect_enc}&scope=openid%20email%20https://www.googleapis.com/auth/cloud-platform%20https://www.googleapis.com/auth/cloud-billing&response_type=code&access_type=offline&prompt=consent"

  buh_e
  buh_link "Open this URL in your browser: " "Google OAuth Authorization" "${z_auth_url}"
  buh_e
  buh_line "You will see four or five screens:"
  buyy_ui_yawp "Choose an account"; local -r z_yelp_choose="${z_buym_yelp}"
  buh_line "  1. ${z_yelp_choose} - Select the Google account for this payor"
  buyy_ui_yawp "Sign in to Recipe Bottle Payor"; local -r z_yelp_signin="${z_buym_yelp}"
  buyy_ui_yawp "Continue"; local -r z_yelp_continue="${z_buym_yelp}"
  buh_line "  2. ${z_yelp_signin} - Confirms account selection and previews the email-address scope; click ${z_yelp_continue}"
  buyy_ui_yawp "Google hasn't verified this app"; local -r z_yelp_unverified="${z_buym_yelp}"
  buh_line "  3. If screen says ${z_yelp_unverified}, click ${z_yelp_continue}"
  buh_line "     Otherwise, proceed to next step"
  buyy_ui_yawp "Recipe Bottle Payor wants access"; local -r z_yelp_access="${z_buym_yelp}"
  buh_line "  4. ${z_yelp_access} - Review the requested permissions"
  buh_line "     Check the permission checkboxes to grant access, then click ${z_yelp_continue}"
  buh_line "  5. The browser then shows 'This site can't be reached / localhost refused to connect'"
  buh_line "     - that page IS the success landing: the authorization code rides its address-bar URL"
  buh_e
  local z_auth_paste
  z_auth_paste=$(buh_prompt_secret "Copy the full URL from the address bar and paste here: ")
  test -n "${z_auth_paste}" || buc_die "Authorization redirect URL is required"

  # Accept the full redirect URL or a bare code: strip through 'code=', drop
  # trailing query params, then percent-decode (the code's slash arrives %2F).
  local z_auth_code="${z_auth_paste}"
  case "${z_auth_code}" in
    *code=*) z_auth_code="${z_auth_code#*code=}" ;;
  esac
  z_auth_code="${z_auth_code%%&*}"
  z_auth_code="${z_auth_code%%#*}"
  z_auth_code=$(printf '%b' "${z_auth_code//\%/\\x}") || buc_die "Failed to percent-decode authorization code"
  test -n "${z_auth_code}" || buc_die "Could not extract an authorization code from the pasted value"

  buc_log_args "Exchanging authorization code for tokens"

  # Request body rides a process substitution into curl - secrets never touch disk
  local z_curl_status=0
  local z_response
  z_response=$(
    curl -sS -X POST \
      --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
      --max-time "${RBCC_CURL_MAX_TIME_SEC}" \
      -H "Content-Type: application/json" \
      -d @<(jq -n \
        --arg code "${z_auth_code}" \
        --arg client_id "${z_client_id}" \
        --arg client_secret "${z_client_secret}" \
        --arg redirect_uri "${z_redirect_uri}" \
        --arg grant_type "authorization_code" \
        '{code: $code, client_id: $client_id, client_secret: $client_secret, redirect_uri: $redirect_uri, grant_type: $grant_type}') \
      "${RBGC_OAUTH_TOKEN_URL}") || z_curl_status=$?
  test "${z_curl_status}" -eq 0 || buc_die "Failed to execute token exchange request (curl exit ${z_curl_status})"

  # Check for error in response
  local z_error
  z_error=$(jq -r '.error // empty' <<<"${z_response}")
  if test -n "${z_error}"; then
    local z_error_desc
    z_error_desc=$(jq -r '.error_description // .error // "Unknown error"' <<<"${z_response}")
    buc_info "OAuth token exchange failed (Google reported: ${z_error} - ${z_error_desc})"
    buc_info "Authorization codes are single-use and expire within minutes."
    buc_info "Re-run this command, then copy the full code and paste it promptly."
    buc_die "OAuth token exchange failed: ${z_error_desc}"
  fi

  z_refresh_token=$(jq -r '.refresh_token // empty' <<<"${z_response}")
  test -n "${z_refresh_token}" || buc_die "OAuth response missing refresh_token field"

  buc_step 'Create credentials directory'
  local -r z_rbro_dir="${z_rbro_file%/*}"
  mkdir -p "${z_rbro_dir}" || buc_die "Failed to create credentials directory: ${z_rbro_dir}"
  chmod 700 "${z_rbro_dir}" || buc_die "Failed to set credentials directory permissions"

  buc_step 'Store OAuth credentials'
  (
    umask 077
    {
      echo "RBRO_CLIENT_SECRET=${z_client_secret}"
      echo "RBRO_REFRESH_TOKEN=${z_refresh_token}"
    } > "${z_rbro_file}"
  ) || buc_die "Failed to write RBRO credentials file"
  chmod 600 "${z_rbro_file}" || buc_die "Failed to set RBRO file permissions"
  
  buc_step 'Validate public configuration'
  buc_log_args "Validating RBRP_OAUTH_CLIENT_ID matches OAuth JSON"

  if test -z "${RBRP_OAUTH_CLIENT_ID:-}"; then
    buc_info "RBRP_OAUTH_CLIENT_ID missing from ${RBCC_rbrp_file}"
    buc_info "Add this line to ${RBCC_rbrp_file} and commit:"
    buc_code "echo 'RBRP_OAUTH_CLIENT_ID=${z_client_id}' >> ${RBCC_rbrp_file}"
    buc_die "RBRP_OAUTH_CLIENT_ID must be configured before payor_install"
  fi

  if test "${RBRP_OAUTH_CLIENT_ID}" != "${z_client_id}"; then
    buc_info "RBRP_OAUTH_CLIENT_ID mismatch"
    buc_info "  ${RBCC_rbrp_file} has: ${RBRP_OAUTH_CLIENT_ID}"
    buc_info "  OAuth JSON:   ${z_client_id}"
    buc_info "Fix with:"
    buc_code "sed -i '' 's|^RBRP_OAUTH_CLIENT_ID=.*|RBRP_OAUTH_CLIENT_ID=${z_client_id}|' ${RBCC_rbrp_file}"
    buc_die "RBRP_OAUTH_CLIENT_ID in ${RBCC_rbrp_file} does not match OAuth JSON"
  fi

  buc_log_args "RBRP_OAUTH_CLIENT_ID validated: ${z_client_id}"
  
  buc_step 'Test OAuth authentication'
  local z_access_token
  z_access_token=$(zrbgp_authenticate_capture) || buc_die "Failed to test OAuth authentication"
  test -n "${z_access_token}" || buc_die "OAuth authentication test returned empty token"
  
  buc_step 'Discover operator email'
  rbuh_json "GET" "${RBGC_OAUTH_USERINFO_URL}" "${z_access_token}" "payor_userinfo"
  rbuh_require_ok "Discover operator email" "payor_userinfo"
  local z_operator_email
  z_operator_email=$(rbuh_json_field_capture "payor_userinfo" '.email') \
    || buc_die "Userinfo response missing email — ensure OAuth scope includes email"
  test -n "${z_operator_email}" || buc_die "Userinfo response missing email"
  buc_info "Operator email: ${z_operator_email}"

  buc_step 'Verify payor project access'
  local -r z_project_info_url="${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/projects/${z_project_id}"
  rbuh_json "GET" "${z_project_info_url}" "${z_access_token}" "payor_verify" 
  rbuh_require_ok "Verify payor project" "payor_verify"
  
  local z_project_state
  z_project_state=$(rbuh_json_field_capture "payor_verify" '.lifecycleState') || buc_die "Failed to get project state"
  test "${z_project_state}" = "${RBGC_STATE_ACTIVE}" || buc_die "Payor project is not ACTIVE (state: ${z_project_state})"

  buc_success "Payor OAuth installation completed successfully"
  buc_info "Credentials stored: ${z_rbro_file}"
  buc_info ""
  buc_info "Verifying ${RBCC_rbrp_file} against the installed credentials:"

  local z_config_ok="true"

  if test "${RBRP_PAYOR_PROJECT_ID:-}" = "${z_project_id}"; then
    buc_info "  RBRP_PAYOR_PROJECT_ID=${z_project_id}"
  else
    buc_warn "RBRP_PAYOR_PROJECT_ID is '${RBRP_PAYOR_PROJECT_ID:-<unset>}'; expected '${z_project_id}'"
    z_config_ok="false"
  fi

  if test "${RBRP_OAUTH_CLIENT_ID:-}" = "${z_client_id}"; then
    buc_info "  RBRP_OAUTH_CLIENT_ID=${z_client_id}"
  else
    buc_warn "RBRP_OAUTH_CLIENT_ID is '${RBRP_OAUTH_CLIENT_ID:-<unset>}'; expected '${z_client_id}'"
    z_config_ok="false"
  fi

  if test "${RBRP_OPERATOR_EMAIL:-}" = "${z_operator_email}"; then
    buc_info "  RBRP_OPERATOR_EMAIL=${z_operator_email}"
  else
    buc_warn "RBRP_OPERATOR_EMAIL is '${RBRP_OPERATOR_EMAIL:-<unset>}'; expected '${z_operator_email}' (the authorized account)"
    z_config_ok="false"
  fi

  if test -n "${RBRP_BILLING_ACCOUNT_ID:-}"; then
    buc_info "  RBRP_BILLING_ACCOUNT_ID=${RBRP_BILLING_ACCOUNT_ID}"
  else
    buc_warn "RBRP_BILLING_ACCOUNT_ID is unset; obtain it from the Cloud Console Billing page and set it in ${RBCC_rbrp_file}"
    z_config_ok="false"
  fi

  buc_info ""
  if test "${z_config_ok}" = "true"; then
    buc_info "Next: instaurate the manor — idempotently enables payor-project APIs, links billing, and founds the manor substrate"
    buc_info "(set RBRD_DEPOT_MONIKER and RBRD_GCP_REGION in rbrd.env first — the depot regime is enforced and the terrier bucket's region rides RBRD_GCP_REGION):"
    buc_tabtarget "${RBZ_INSTAURATE_MANOR}"
    buc_info "Then levy the depot:"
    buc_tabtarget "${RBZ_LEVY_DEPOT}"
  else
    buc_warn "Resolve the items above in ${RBCC_rbrp_file} before instaurating the manor."
  fi
}

# Establish one mantle service account at levy: create + propagation poll.
# The email is deterministic (<account_id>@RBGD_SA_EMAIL_FULL); the caller computes
# it for the capability-set grant. Pristine-state expectation as Mason: a 409 is
# fatal (rbuh_require_ok), not idempotent success.
zrbgp_establish_mantle_sa() {
  zrbgp_sentinel

  local -r z_token="${1:-}"
  local -r z_account_id="${2:-}"
  local -r z_role="${3:-}"

  test -n "${z_token}"      || buc_die "zrbgp_establish_mantle_sa: token required"
  test -n "${z_account_id}" || buc_die "zrbgp_establish_mantle_sa: account id required"
  test -n "${z_role}"       || buc_die "zrbgp_establish_mantle_sa: role required"

  buc_step "Create ${z_role} mantle service account: ${z_account_id}"
  local -r z_display_name="${RBGC_DEPOT_DISPLAY_PREFIX} mantle ${z_role} ${RBRD_DEPOT_MONIKER}"
  local -r z_create_body="${BURD_TEMP_DIR}/rbgp_create_mantle_${z_role}.json"

  jq -n \
    --arg accountId "${z_account_id}" \
    --arg displayName "${z_display_name}" \
    '{
      accountId: $accountId,
      serviceAccount: {
        displayName: $displayName
      }
    }' > "${z_create_body}" || buc_die "Failed to build ${z_role} mantle creation body"

  local -r z_create_url="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/${RBDC_DEPOT_PROJECT_ID}/serviceAccounts"
  rbuh_json "POST" "${z_create_url}" "${z_token}" "mantle_${z_role}_create" "${z_create_body}"
  rbuh_require_ok "Create ${z_role} mantle service account" "mantle_${z_role}_create"

  buc_step "Verify ${z_role} mantle service account propagation"
  local -r z_sa_email="${z_account_id}@${RBGD_SA_EMAIL_FULL}"
  local -r z_sa_url="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/${RBDC_DEPOT_PROJECT_ID}/serviceAccounts/${z_sa_email}"
  rbuh_poll_until_ok "${z_role} mantle SA" "${z_sa_url}" "${z_token}" "mantle_${z_role}_preflight"
}

# Enable Artifact Registry Data-Access audit logs on the depot project (spike V3):
# ADMIN_READ + DATA_READ on the using service artifactregistry.googleapis.com,
# never on iamcredentials. auditConfigs are dropped unless the write carries them,
# so the v3 set masks updateMask=auditConfigs,etag — writing only the audit config,
# never bindings, riding the read etag for concurrency. See RBSMF.
zrbgp_enable_ar_audit_logs() {
  zrbgp_sentinel

  local -r z_token="${1:-}"
  test -n "${z_token}" || buc_die "zrbgp_enable_ar_audit_logs: token required"

  buc_step 'Enable Artifact Registry Data-Access audit logs'
  local -r z_get_body="${BURD_TEMP_DIR}/rbgp_audit_get.json"
  printf '%s\n' '{"options":{"requestedPolicyVersion":3}}' > "${z_get_body}" \
    || buc_die "Failed to write audit getIamPolicy body"
  rbuh_json "POST" "${RBGD_API_CRM_GET_IAM_POLICY}" "${z_token}" "depot_audit_get" "${z_get_body}"
  rbuh_require_ok "Get project IAM policy for audit config" "depot_audit_get"

  local z_etag
  z_etag=$(rbuh_json_field_capture "depot_audit_get" '.etag') || buc_die "Failed to read project policy etag"
  test -n "${z_etag}" || buc_die "Empty project policy etag"

  local -r z_set_body="${BURD_TEMP_DIR}/rbgp_audit_set.json"
  jq -n --arg etag "${z_etag}" \
    '{
      policy: {
        auditConfigs: [
          {
            service: "artifactregistry.googleapis.com",
            auditLogConfigs: [
              { logType: "ADMIN_READ" },
              { logType: "DATA_READ" }
            ]
          }
        ],
        etag: $etag
      },
      updateMask: "auditConfigs,etag"
    }' > "${z_set_body}" || buc_die "Failed to build audit setIamPolicy body"

  rbuh_json "POST" "${RBGD_API_CRM_SET_IAM_POLICY}" "${z_token}" "depot_audit_set" "${z_set_body}"
  rbuh_require_ok "Enable Artifact Registry audit logs" "depot_audit_set"

  # Content gate: setIamPolicy returns the resulting policy, which must carry the
  # Artifact Registry auditConfigs entry. A masked write that silently dropped
  # auditConfigs still returns HTTP 200, so the status check is not sufficient — this
  # confirms the entry actually landed. See RBSMF "Enable Artifact Registry Data-Access
  # Audit Logs" (the returned-policy require).
  local z_audit_service
  z_audit_service=$(rbuh_json_field_capture "depot_audit_set" \
    '.auditConfigs[]? | select(.service=="artifactregistry.googleapis.com") | .service') \
    || buc_die "setIamPolicy returned without the Artifact Registry auditConfigs entry"
  buc_log_args "Confirmed Data-Access audit config on ${z_audit_service}"
}

rbgp_manor_affiance() {
  zrbgp_sentinel

  buc_doc_brief "Affiance the manor to its external OIDC IdP — seat this foedus's provider and attribute mapping under the manor's standing workforce pool (RBSMA)"
  buc_doc_shown || return 0

  # Dirty-tree guard — affiance's provider id is the committed RBRF value, and
  # the IdP redirect-URI and the accessor's STS audience thread through it; the
  # provider it seats must answer to a committed name.
  bug_require_clean_tree_creed "${RBCC_creed_clean_affiance}"

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  # The manor pool coordinates (org / pool id) are read from the kindled RBRW
  # regime (manor-level, RBSRW); the per-foedus provider id from the kindled
  # RBRF regime. affiance is folio-addressed (param1, RBSMA): the caller's furnish
  # folio-resolves the RBRF from the operator-supplied foedus, then sources,
  # kindles, and enforces both before dispatch (like RBRD/RBRP for depot_levy), so
  # the body stays foedus-blind — it works whatever foedus the furnish sourced.
  # The org-level workforcePoolAdmin
  # grant (spike F1) is the finisher's to seat (RBSMS) — affiance assumes it
  # present; a payor lacking it meets a 403 at provider creation, directing them
  # to run the finisher first (RBSMA F1 NOTE).
  local -r z_org="organizations/${RBRW_ORG_ID}"
  local -r z_pool_id="${RBRW_WORKFORCE_POOL_ID}"
  local -r z_provider_id="${RBRF_PROVIDER_ID}"
  local -r z_iam_root="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}"
  local -r z_pools_base="${z_iam_root}/locations/global/workforcePools"

  # Require the manor workforce pool present and live (RBSMA pool-present gate).
  # The pool is manor-level, founded once by the manor-setup finisher and
  # standing for the manor's lifetime (RBSRW); affiance founds no pool — it only
  # hangs a provider beneath the standing one. Absent (404) or soft-deleted
  # (200, state DELETED) is fatal, directing the operator to the finisher.
  buc_step 'Require manor workforce pool present'
  buyy_tt_yawp "${RBZ_INSTAURATE_MANOR}"; local -r z_finisher_tt="${z_buym_yelp}"
  local -r z_pool_get_url="${z_pools_base}/${z_pool_id}"
  rbuh_json "GET" "${z_pool_get_url}" "${z_token}" "affiance_pool_get"
  local z_pool_code
  z_pool_code=$(rbuh_code_capture "affiance_pool_get") || buc_die "No HTTP code from workforcePools.get"

  case "${z_pool_code}" in
    200)
      local z_pool_state
      z_pool_state=$(rbuh_json_field_capture "affiance_pool_get" ".state // \"${RBGC_STATE_UNSPECIFIED}\"") \
        || z_pool_state="${RBGC_STATE_UNSPECIFIED}"
      test "${z_pool_state}" != "${RBGC_STATE_DELETED}" \
        || buc_die "Workforce pool ${z_pool_id} is soft-deleted (state DELETED) — affiance founds no pool; run the manor-setup finisher first: ${z_finisher_tt}"
      buc_info "Manor workforce pool ${z_pool_id} standing (state ${z_pool_state})"
      ;;
    404)
      buc_die "Workforce pool ${z_pool_id} absent under ${z_org} — affiance founds no pool; run the manor-setup finisher first: ${z_finisher_tt}"
      ;;
    *)
      rbuh_require_ok "Workforce pool get" "affiance_pool_get"
      ;;
  esac

  # Ensure the pool provider and its attribute mapping (idempotent).
  buc_step 'Ensure workforce pool provider and attribute mapping'
  local -r z_providers_base="${z_pools_base}/${z_pool_id}/providers"
  local -r z_provider_get_url="${z_providers_base}/${z_provider_id}"
  rbuh_json "GET" "${z_provider_get_url}" "${z_token}" "affiance_provider_get"
  local z_provider_code
  z_provider_code=$(rbuh_code_capture "affiance_provider_get") || buc_die "No HTTP code from providers.get"

  case "${z_provider_code}" in
    200)
      # Provider present under the pool (RBSMA branch dispatch). Read its state: a
      # live provider runs the re-sync arm directly; a soft-deleted one (state
      # DELETED) is undeleted first, then re-synced exactly as live. Undelete
      # restores the provider's LAST uploaded key snapshot, so under the programmatic
      # mechanism only the re-sync patch converges the ephemeral JWKS — a
      # delete/undelete cycle alone cannot (RBSMA re-sync-arm NOTE).
      local z_provider_state
      z_provider_state=$(rbuh_json_field_capture "affiance_provider_get" '.state // "UNKNOWN"') \
        || z_provider_state="UNKNOWN"
      if test "${z_provider_state}" = "${RBGC_STATE_DELETED}"; then
        buc_step 'Undelete soft-deleted provider'
        buc_info "Provider ${z_provider_id} soft-deleted (state DELETED) — undeleting before re-sync"
        rbge_lro_ok \
          "Undelete workforce pool provider" \
          "${z_token}" \
          "${z_provider_get_url}:undelete" \
          "affiance_provider_undelete" \
          "" \
          ".name" \
          "${z_iam_root}" \
          "" \
          "${RBGC_EVENTUAL_CONSISTENCY_SEC}" \
          "${RBGC_MAX_CONSISTENCY_SEC}"
        buc_info "Provider ${z_provider_id} undeleted under pool ${z_pool_id}"
      else
        buc_info "Provider ${z_provider_id} present (state ${z_provider_state}) — ensuring current"
      fi

      # Re-sync arm (RBSMA), mechanism-conditional. Under the programmatic mechanism
      # the uploaded public JWKS is ephemeral — the realm signing key is minted fresh
      # per charge (RBSFK) — so a standing provider validates self-supplied JWTs
      # against a stale key until this patch rewrites the snapshot (the twiddle). The
      # updateMask names ONLY oidc.jwksJson, the instaurate pool-reconcile precedent;
      # every other field is left as it stands (full drift-reconcile deferred). Under
      # the interactive mechanism the keys are issuer-discovered — nothing is uploaded
      # to re-sync, so the present branch is a pure no-op.
      case "${RBRF_MECHANISM}" in
        rbnfe_programmatic)
          buc_step 'Re-sync programmatic provider JWKS'
          local -r z_patch_body="${BURD_TEMP_DIR}/rbgp_affiance_jwks_patch.json"
          jq -n --arg jwks "${RBRF_IDP_JWKS_JSON}" \
            '{ oidc: { jwksJson: $jwks } }' > "${z_patch_body}" \
            || buc_die "Failed to build provider JWKS patch body"
          rbuh_json "PATCH" "${z_provider_get_url}?updateMask=oidc.jwksJson" "${z_token}" "affiance_provider_patch" "${z_patch_body}"
          rbuh_require_ok "Re-sync provider JWKS" "affiance_provider_patch"
          buc_info "Provider ${z_provider_id} JWKS re-synced (updateMask=oidc.jwksJson)"
          ;;
        rbnfe_interactive)
          buc_info "Provider ${z_provider_id} interactive — issuer-discovered keys, no JWKS re-sync"
          ;;
        *)
          buc_die "Unknown RBRF_MECHANISM: ${RBRF_MECHANISM}"
          ;;
      esac
      ;;
    404)
      # The provider oidc block is the one mechanism-variant part of affiance
      # (RBSMA): pool, attributeMapping, issuerUri, and clientId are
      # mechanism-invariant; interactive adds device-flow web-sso over
      # issuer-discovered keys, programmatic adds the uploaded public JWKS GCP
      # validates self-supplied JWTs against. affiance treats RBRF_IDP_JWKS_JSON as
      # an opaque regime value — it never reads realm contents (vendor-blind).
      # attributeMapping is parsed from the regime's comma-separated key=value
      # string inside jq (the validator guarantees it maps google.subject).
      local -r z_provider_body="${BURD_TEMP_DIR}/rbgp_affiance_provider.json"
      case "${RBRF_MECHANISM}" in
        rbnfe_interactive)
          # webSsoConfig (ID_TOKEN / ONLY_ID_TOKEN_CLAIMS) is the spike-proven
          # shape that serves the device flow.
          jq -n \
            --arg displayName "${z_provider_id}" \
            --arg issuerUri   "${RBRF_IDP_ISSUER}" \
            --arg clientId    "${RBRF_IDP_CLIENT_ID}" \
            --arg mapping     "${RBRF_ATTRIBUTE_MAPPING}" \
            '{
              displayName: $displayName,
              attributeMapping: ($mapping | split(",") | map(split("=") | {(.[0]): .[1]}) | add),
              oidc: {
                issuerUri: $issuerUri,
                clientId: $clientId,
                webSsoConfig: {
                  responseType: "ID_TOKEN",
                  assertionClaimsBehavior: "ONLY_ID_TOKEN_CLAIMS"
                }
              }
            }' > "${z_provider_body}" || buc_die "Failed to build interactive provider body"
          ;;
        rbnfe_programmatic)
          # jwksJson is the uploaded public JWKS as a string (REST oidc.jwksJson,
          # the --jwk-json-path target); the orchestrator (rbxk_keycloak) strips it
          # to the strict RSA members and re-syncs it per charge. webSsoConfig is
          # inert under this mechanism (GCP validates against the JWKS, not
          # web-sso) but is carried because the proof observed gcloud demand the
          # web-sso flags alongside --jwk-json-path; whether the REST create
          # likewise requires it is an impl-confirm to settle at the orchestrator's
          # first live create (RBSMA webSsoConfig NOTE).
          jq -n \
            --arg displayName "${z_provider_id}" \
            --arg issuerUri   "${RBRF_IDP_ISSUER}" \
            --arg clientId    "${RBRF_IDP_CLIENT_ID}" \
            --arg mapping     "${RBRF_ATTRIBUTE_MAPPING}" \
            --arg jwks        "${RBRF_IDP_JWKS_JSON}" \
            '{
              displayName: $displayName,
              attributeMapping: ($mapping | split(",") | map(split("=") | {(.[0]): .[1]}) | add),
              oidc: {
                issuerUri: $issuerUri,
                clientId: $clientId,
                jwksJson: $jwks,
                webSsoConfig: {
                  responseType: "ID_TOKEN",
                  assertionClaimsBehavior: "ONLY_ID_TOKEN_CLAIMS"
                }
              }
            }' > "${z_provider_body}" || buc_die "Failed to build programmatic provider body"
          ;;
        *)
          buc_die "Unknown RBRF_MECHANISM: ${RBRF_MECHANISM}"
          ;;
      esac

      local -r z_provider_create_url="${z_providers_base}?workforcePoolProviderId=${z_provider_id}"
      rbge_lro_ok \
        "Create workforce pool provider" \
        "${z_token}" \
        "${z_provider_create_url}" \
        "affiance_provider_create" \
        "${z_provider_body}" \
        ".name" \
        "${z_iam_root}" \
        "" \
        "${RBGC_EVENTUAL_CONSISTENCY_SEC}" \
        "${RBGC_MAX_CONSISTENCY_SEC}"
      buc_info "Provider ${z_provider_id} created under pool ${z_pool_id}"
      ;;
    *)
      rbuh_require_ok "Provider get" "affiance_provider_get"
      ;;
  esac

  buc_step 'Manor affianced'
  buc_info "Manor affianced: provider=${z_provider_id} under pool=${z_pool_id} org=${z_org}"
  buyy_tt_yawp "${RBZ_CHECK_AVOWAL}"; local -r z_acf_tt="${z_buym_yelp}"
  buc_info "Verify the trust by avowing — run ${z_acf_tt}"
}

rbgp_manor_jilt() {
  zrbgp_sentinel

  buc_doc_brief "Jilt one foedus — delete its provider from the manor's standing workforce pool, dissolving that trust (RBSMJ)"
  buc_doc_shown || return 0

  # Affiance's structural inverse — provider-grain (RBSMJ): jilt deletes exactly
  # the provider affiance seated and nothing else; the shared pool stands for
  # every other foedus (pool teardown is the separate manor raze, never jilt).
  # Reads the pool coordinates from the kindled RBRW regime and the provider id
  # from the kindled RBRF regime. jilt is folio-addressed (param1, RBSMJ): the
  # caller's furnish folio-resolves the RBRF from the operator-supplied foedus and
  # enforces both, so the body deletes that folio's provider while staying
  # foedus-blind. Mechanism-blind: deleting the provider ends the trust regardless of how
  # citizens acquired tokens against it — no RBRF_MECHANISM arm (RBSMJ).
  local -r z_org="organizations/${RBRW_ORG_ID}"
  local -r z_pool_id="${RBRW_WORKFORCE_POOL_ID}"
  local -r z_provider_id="${RBRF_PROVIDER_ID}"
  local -r z_iam_root="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}"
  local -r z_provider_url="${z_iam_root}/locations/global/workforcePools/${z_pool_id}/providers/${z_provider_id}"

  # Safety gate first (zero traffic). Deleting the provider ends federated access
  # for citizens asserted through this foedus; the operator types the provider id
  # to confirm. buc_require honors BURE_CONFIRM=skip for non-interactive test runs.
  buc_step 'Safety confirmation required'
  buc_require "Dissolve foedus provider ${z_provider_id} under pool ${z_pool_id} — ends federated access for citizens asserted through this foedus (the pool stands)" "${z_provider_id}"

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  # Probe the provider. Idempotent: an absent provider (404) or one already
  # soft-deleted (200, state DELETED) is reported already-dissolved and exits
  # clean — no delete issued.
  buc_step 'Probe pool provider'
  rbuh_json "GET" "${z_provider_url}" "${z_token}" "jilt_provider_get"
  local z_provider_code
  z_provider_code=$(rbuh_code_capture "jilt_provider_get") || buc_die "No HTTP code from providers.get"

  case "${z_provider_code}" in
    404)
      buc_success "Provider ${z_provider_id} absent under pool ${z_pool_id} — already dissolved (no-op)"
      return 0
      ;;
    200)
      local z_provider_state
      z_provider_state=$(rbuh_json_field_capture "jilt_provider_get" '.state // "UNKNOWN"') || z_provider_state="UNKNOWN"
      if test "${z_provider_state}" = "${RBGC_STATE_DELETED}"; then
        buc_success "Provider ${z_provider_id} already soft-deleted (state DELETED) — already dissolved (no-op)"
        buc_info "A fresh affiance re-seats the provider under the standing pool"
        return 0
      fi
      ;;
    *)
      rbuh_require_ok "Provider get" "jilt_provider_get"
      ;;
  esac

  # Delete the provider. workforcePools.providers.delete returns an LRO; confirm
  # acceptance, then poll the resource to its terminal state. Only the provider
  # is deleted; the manor pool is never touched by jilt.
  buc_step 'Delete pool provider (the pool stands)'
  rbuh_json "DELETE" "${z_provider_url}" "${z_token}" "jilt_provider_delete"
  rbuh_require_ok "Delete provider" "jilt_provider_delete"
  buc_info "Provider ${z_provider_id} delete accepted — awaiting dissolution"

  # Verify dissolution: poll until state DELETED (soft-delete terminal) or 404
  # (gone). Either is success — the verify tolerates whether the GET surfaces a
  # soft-deleted provider, mirroring the depot-unmake resource-state poll (RBSMJ).
  buc_step 'Verify dissolution'
  # Loop counter/accumulator + per-iteration synthesized locals (BCG Exceptions
  # 1/2/4 — declare outside, assign inside)
  local z_jilt_elapsed=0
  local z_jilt_dissolved=""
  local z_verify_infix=""
  local z_verify_code=""
  local z_verify_state=""
  while :; do
    sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
    z_jilt_elapsed=$((z_jilt_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))

    z_verify_infix="jilt_provider_verify_${z_jilt_elapsed}s"
    rbuh_json "GET" "${z_provider_url}" "${z_token}" "${z_verify_infix}"
    z_verify_code=$(rbuh_code_capture "${z_verify_infix}") || z_verify_code=""

    if test "${z_verify_code}" = "404"; then
      z_jilt_dissolved="404"
      break
    fi
    if test "${z_verify_code}" = "200"; then
      z_verify_state=$(rbuh_json_field_capture "${z_verify_infix}" '.state // "UNKNOWN"') || z_verify_state="UNKNOWN"
      if test "${z_verify_state}" = "${RBGC_STATE_DELETED}"; then
        z_jilt_dissolved="${RBGC_STATE_DELETED}"
        break
      fi
    fi

    test "${z_jilt_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" \
      || buc_die "Jilt: provider ${z_provider_id} did not reach a dissolved state within ${RBGC_MAX_CONSISTENCY_SEC}s (last HTTP ${z_verify_code})"
    buc_log_args "Provider still present at ${z_jilt_elapsed}s (HTTP ${z_verify_code}) — polling"
  done

  buc_step 'Foedus jilted'
  buc_success "Foedus jilted: provider ${z_provider_id} dissolved (${z_jilt_dissolved}) under pool ${z_pool_id} of ${z_org}"
  buc_info "The pool and every other foedus's provider stand; depot-scoped mantle bindings untouched"
  buc_info "A fresh affiance recreates the provider under the standing pool"
}

rbgp_manor_raze() {
  zrbgp_sentinel

  buc_doc_brief "Raze the manor — force-delete its workforce pool to start from a clean manor (internal release-ladder infra)"
  buc_doc_shown || return 0

  # The deliberate inverse of the ensure-exists manor finisher: a dangerous,
  # standalone pool-destroyer that lets a release ladder wipe the manor back to
  # nothing before re-founding. Distinct from manor_jilt on purpose — jilt is the
  # everyday provider-level break, while raze levels the whole pool, re-enrolling
  # every citizen under the manor by construction (bindings key on the pool). The
  # danger lives in this separate, scary-gated verb so everyday jilt can never nuke
  # the pool. Reads the one configured pool from the kindled RBRW regime (manor-
  # level; the caller's furnish enforces it before dispatch, like manor_jilt) — no
  # CLI folio: raze targets the regime's pool, never an operator-supplied one.
  local -r z_org="organizations/${RBRW_ORG_ID}"
  local -r z_pool_id="${RBRW_WORKFORCE_POOL_ID}"
  local -r z_iam_root="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}"
  local -r z_pool_url="${z_iam_root}/locations/global/workforcePools/${z_pool_id}"

  # Safety gate first (zero traffic). Razing the pool re-enrolls every citizen
  # under the manor; the operator types the pool id to confirm. buc_require honors
  # BURE_CONFIRM=skip for non-interactive test runs.
  buc_step 'Safety confirmation required'
  buc_require "DANGER: Force-delete workforce pool ${z_pool_id} under ${z_org} — re-enrolls EVERY citizen under the manor" "${z_pool_id}"

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  # Probe the pool. Idempotent: an absent pool (404) or one already soft-deleted
  # (200, state DELETED) is reported razed and exits clean — no delete issued, so
  # a release ladder can run raze unconditionally to reach a clean manor.
  buc_step 'Probe workforce identity pool'
  rbuh_json "GET" "${z_pool_url}" "${z_token}" "raze_pool_get"
  local z_pool_code
  z_pool_code=$(rbuh_code_capture "raze_pool_get") || buc_die "No HTTP code from workforcePools.get"

  case "${z_pool_code}" in
    404)
      buc_success "Workforce pool ${z_pool_id} absent under ${z_org} — already razed (no-op)"
      return 0
      ;;
    200)
      local z_pool_state
      z_pool_state=$(rbuh_json_field_capture "raze_pool_get" '.state // "UNKNOWN"') || z_pool_state="UNKNOWN"
      if test "${z_pool_state}" = "${RBGC_STATE_DELETED}"; then
        buc_success "Workforce pool ${z_pool_id} already soft-deleted (state DELETED) — already razed (no-op)"
        buc_info "The razed id stays burned for the ~30-day purge window — a fresh trust takes a fresh id: set RBRW_WORKFORCE_POOL_ID to a new id, commit, then run the manor-setup finisher and re-affiance the foedera"
        return 0
      fi
      ;;
    *)
      rbuh_require_ok "Workforce pool get" "raze_pool_get"
      ;;
  esac

  # Force-delete the pool. The provider is namespaced beneath the pool and cascades
  # with the deletion — no separate provider delete. workforcePools.delete returns
  # an LRO; confirm acceptance, then poll the resource to its terminal state.
  buc_step 'Force-delete workforce pool (provider cascades)'
  rbuh_json "DELETE" "${z_pool_url}" "${z_token}" "raze_pool_delete"
  rbuh_require_ok "Delete workforce pool" "raze_pool_delete"
  buc_info "Workforce pool ${z_pool_id} delete accepted — awaiting soft-delete transition"

  # Verify razing: poll until state DELETED (soft-delete terminal) or 404
  # (hard-gone). Either is success — robust to whether get surfaces soft-deleted
  # resources. Mirrors manor_jilt and the depot-unmake resource-state poll.
  buc_step 'Verify razing'
  local z_raze_elapsed=0
  local z_raze_dissolved=""
  while :; do
    sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
    z_raze_elapsed=$((z_raze_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))

    local z_verify_infix="raze_pool_verify_${z_raze_elapsed}s"
    rbuh_json "GET" "${z_pool_url}" "${z_token}" "${z_verify_infix}"
    local z_verify_code
    z_verify_code=$(rbuh_code_capture "${z_verify_infix}") || z_verify_code=""

    if test "${z_verify_code}" = "404"; then
      z_raze_dissolved="404"
      break
    fi
    if test "${z_verify_code}" = "200"; then
      local z_verify_state
      z_verify_state=$(rbuh_json_field_capture "${z_verify_infix}" '.state // "UNKNOWN"') || z_verify_state="UNKNOWN"
      if test "${z_verify_state}" = "${RBGC_STATE_DELETED}"; then
        z_raze_dissolved="${RBGC_STATE_DELETED}"
        break
      fi
    fi

    test "${z_raze_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" \
      || buc_die "Raze: pool ${z_pool_id} did not reach a dissolved state within ${RBGC_MAX_CONSISTENCY_SEC}s (last HTTP ${z_verify_code})"
    buc_log_args "Pool still present at ${z_raze_elapsed}s (HTTP ${z_verify_code}) — polling"
  done

  buc_step 'Manor razed'
  buc_success "Manor razed: workforce pool ${z_pool_id} force-deleted (${z_raze_dissolved}) under ${z_org}"
  buc_info "Provider cascaded with the pool; the razed id stays burned for the ~30-day purge window"
  buc_info "Re-found under a fresh id: set RBRW_WORKFORCE_POOL_ID to a new id, commit, then run the manor-setup finisher and re-affiance the foedera"
}

# The manor-setup finisher (RBSMS): one idempotent, payor-credentialed verb that founds
# the manor's scriptable substrate after the manual payor guide — the ensure-exists
# inverse of manor_raze. First readies the payor project itself (the required-API set,
# billing linkage — the two steps migrated out of the manual guide across the
# credential boundary), then founds three things: the org-level workforcePoolAdmin grant
# (spike F1), the ONE workforce pool (via a list-and-match drift guard, never a bare
# get-by-id — a drifted RBRW_WORKFORCE_POOL_ID must surface, not silently spawn a
# second empty pool), and the terrier bucket (manor-grain, in the payor project). The
# depot-grain polity folder + grain IAM are founded at depot levy, not here. Ensure-
# exists throughout — created when absent, reconciled when present, NEVER deleted
# (clearing the ground is manor_raze). Reads the pool from RBRW and the bucket region
# from RBRD (enforced by the caller's furnish); RBRP supplies the payor project and
# operator email.
rbgp_manor_instaurate() {
  zrbgp_sentinel

  buc_doc_brief "Instaurate the manor — idempotently ensure the workforce pool and terrier bucket (post-payor-guide manor-setup finisher)"
  buc_doc_shown || return 0

  local -r z_org="organizations/${RBRW_ORG_ID}"
  local -r z_pool_id="${RBRW_WORKFORCE_POOL_ID}"
  local -r z_iam_root="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}"
  local -r z_pools_base="${z_iam_root}/locations/global/workforcePools"
  local -r z_pool_url="${z_pools_base}/${z_pool_id}"

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  # === Ensure the payor-project APIs (migrated from the manual payor guide) ===
  # The payor project is the OAuth client's home and so the quota project of every
  # payor-token call — an API must be on here even when the resource lives elsewhere.
  # iam (workforce pools), storage (terrier bucket), cloudresourcemanager (the
  # org grant), and iap (the audience gate's brand read) serve this finisher's
  # own steps; cloudbilling (the billing links),
  # artifactregistry (levy's region validation against the payor project), cloudbuild
  # (levy's worker-pool ops), and iamcredentials carry the levy that follows.
  # serviceusage leads: enabling rides the Service Usage API itself, so a project
  # with it off entirely fails loud on the first call (new projects ship it on; one
  # manual Console enable recovers, and the finisher re-runs cleanly).
  buc_step 'Ensure payor-project APIs enabled'
  local -r z_payor_api_services="serviceusage cloudresourcemanager cloudbilling iam iamcredentials storage artifactregistry cloudbuild iap"
  local z_api_service=""
  for z_api_service in ${z_payor_api_services}; do
    rbge_api_enable "${z_api_service}" "${RBRP_PAYOR_PROJECT_ID}" "${z_token}" \
      || buc_die "Failed to enable payor-project API: ${z_api_service}"
  done

  # === Gate the consent-screen audience (Internal-only manor law) ===
  # The payor project's OAuth brand must be org-internal: External leaves the
  # manor under the test-user gate and 7-day token expiry. The IAP brands API
  # is the only programmatic surface over the brand and exposes orgInternalOnly
  # read-only (create/get/list, no update) — so this is a check with a console
  # remedy, never an ensure step. Placed first among the substrate checks: a
  # misconfigured audience fails fast, before any manor mutation beyond API
  # enablement.
  buc_step 'Gate the consent-screen audience (Internal-only)'
  local -r z_brands_url="${RBGC_API_ROOT_IAP}${RBGC_IAP_V1}/projects/${RBRP_PAYOR_PROJECT_ID}/brands"
  rbuh_json "GET" "${z_brands_url}" "${z_token}" "instaurate_brands_list"
  rbuh_require_ok "List payor OAuth brands" "instaurate_brands_list"
  local z_brand_count
  z_brand_count=$(rbuh_json_field_capture "instaurate_brands_list" '.brands // [] | length') || z_brand_count=0
  if test "${z_brand_count}" = "0"; then
    buc_info "No OAuth brand means the consent screen was never configured — the establish guide (rbw-gPE) walks that founding"
    buc_die "No OAuth brand on payor project ${RBRP_PAYOR_PROJECT_ID} — establish the manor first, then re-run"
  fi
  local z_brand_internal
  z_brand_internal=$(rbuh_json_field_capture "instaurate_brands_list" '.brands[0].orgInternalOnly // false') || z_brand_internal="false"
  if test "${z_brand_internal}" = "true"; then
    buc_info "Consent-screen audience is Internal — conformant"
  else
    buc_warn "Consent-screen audience is External on payor project ${RBRP_PAYOR_PROJECT_ID} — the test-user gate and 7-day token expiry stay in force"
    buc_info "Remedy: Console > Google Auth Platform > Audience > 'Make internal', then re-run (the brands API cannot flip this)"
    buc_die "Consent-screen audience must be Internal"
  fi

  # === Ensure billing linked to the payor project (migrated from the manual guide) ===
  # Must precede the terrier bucket — bucket creation requires an active billing
  # link. GET-then-PUT: a matching link is a no-op; absent links; drifted reconciles
  # to the committed record (RBRP is authoritative) with a warning — the same
  # reconcile posture as the pool's session-duration.
  buc_step "Ensure billing linked to payor project ${RBRP_PAYOR_PROJECT_ID}"
  local -r z_billing_url="${RBGC_API_ROOT_CLOUDBILLING}${RBGC_CLOUDBILLING_V1}/projects/${RBRP_PAYOR_PROJECT_ID}/billingInfo"
  rbuh_json "GET" "${z_billing_url}" "${z_token}" "instaurate_billing_read"
  rbuh_require_ok "Read payor billing info" "instaurate_billing_read"
  # An unlinked project reads back an absent/empty billingAccountName; the capture
  # helper signals empty-or-null as nonzero, so fold that to "" (not linked) here.
  local z_billing_live
  z_billing_live=$(rbuh_json_field_capture "instaurate_billing_read" '.billingAccountName') || z_billing_live=""
  local -r z_billing_want="billingAccounts/${RBRP_BILLING_ACCOUNT_ID}"
  if test "${z_billing_live}" = "${z_billing_want}"; then
    buc_log_args "Billing already linked: ${z_billing_want}"
  else
    test -z "${z_billing_live}" \
      || buc_warn "Reconciling payor billing from ${z_billing_live} to ${z_billing_want} (RBRP is the committed record)"
    local -r z_billing_body="${BURD_TEMP_DIR}/rbgp_instaurate_billing.json"
    jq -n --arg billingAccountName "${z_billing_want}" '{billingAccountName: $billingAccountName}' \
      > "${z_billing_body}" || buc_die "Failed to build billing link body"
    rbuh_json "PUT" "${z_billing_url}" "${z_token}" "instaurate_billing_link" "${z_billing_body}"
    rbuh_require_ok "Link billing to payor project" "instaurate_billing_link"
  fi

  # Spike Finding F1: pool creation 403s until the payor holds
  # roles/iam.workforcePoolAdmin at the organization. Must precede the pool founding.
  # Idempotent (etag read-modify-write) — a payor already holding it passes straight
  # through. Affiance assumes the finisher already seated this (RBSMA F1 NOTE).
  buc_step 'Seat org-level workforcePoolAdmin (spike F1 — must precede pool founding)'
  rbgi_add_project_iam_role \
    "${z_token}" \
    "Instaurate: seat workforcePoolAdmin" \
    "${z_org}" \
    "roles/iam.workforcePoolAdmin" \
    "user:${RBRP_OPERATOR_EMAIL}" \
    "instaurate_org_grant"

  # === Ensure the manor workforce pool via LIST-AND-MATCH (RBSMS drift guard) ===
  # Page workforcePools.list under the org with showDeleted=true (so a soft-deleted
  # pool squatting the id is visible as drift, never a silent create-over). The pool
  # AT the expected id (RBRW_WORKFORCE_POOL_ID) is ours by COORDINATE — matched by id
  # regardless of its description, so a pool predating the marker convention (a spike or
  # hand-created pool) is recognized and reconciled, never create-over'd. The RB marker
  # (description == the founding marker) is only how we recognize OUR pool among
  # unrelated org pools for the DIFFERENT-id drift check. Then: expected-id + live ->
  # reconcile sessionDuration and backfill the marker; expected-id + DELETED -> refuse
  # (squatting, coordinate drift); a live RB-marked pool at a DIFFERENT id -> refuse
  # (coordinate drift); none -> create. A bare get-by-id would silently found a second
  # empty pool the moment RBRW_WORKFORCE_POOL_ID drifted — that is the guard's purpose.
  buc_step 'Ensure workforce identity pool (list-and-match drift guard)'
  local z_org_enc=""
  z_org_enc=$(rbuh_urlencode_capture "${z_org}") || buc_die "Failed to URL-encode org parent"

  # Per-iteration synthesized locals (BCG — declare outside, assign inside)
  local z_page=1
  local z_page_token=""
  local z_url=""
  local z_tok_enc=""
  local z_infix=""
  local z_code=""
  local z_count=0
  local z_index=0
  local z_p_name=""
  local z_p_id=""
  local z_p_state=""
  local z_p_desc=""
  local z_p_session=""
  local z_expected_state=""
  local z_expected_session=""
  local z_expected_desc=""
  local z_other_live_id=""
  local z_mask=""

  while :; do
    z_url="${z_pools_base}?parent=${z_org_enc}&showDeleted=true"
    if test -n "${z_page_token}"; then
      z_tok_enc=$(rbuh_urlencode_capture "${z_page_token}") \
        || buc_die "Failed to URL-encode workforcePools.list pageToken"
      z_url="${z_url}&pageToken=${z_tok_enc}"
    fi

    z_infix="instaurate_pools_list_${z_page}"
    rbuh_json "GET" "${z_url}" "${z_token}" "${z_infix}"
    z_code=$(rbuh_code_capture "${z_infix}") \
      || buc_die "No HTTP code from workforcePools.list under ${z_org}"
    test "${z_code}" = "200" \
      || buc_die "Unexpected HTTP ${z_code} from workforcePools.list under ${z_org}"

    z_count=$(rbuh_json_field_capture "${z_infix}" '.workforcePools // [] | length') || z_count=0

    z_index=0
    while test "${z_index}" -lt "${z_count}"; do
      z_p_name=$(rbuh_json_field_capture "${z_infix}" ".workforcePools[${z_index}].name") || z_p_name=""
      z_p_id="${z_p_name##*/}"
      z_p_state=$(rbuh_json_field_capture "${z_infix}" ".workforcePools[${z_index}].state // \"${RBGC_STATE_UNSPECIFIED}\"") || z_p_state="${RBGC_STATE_UNSPECIFIED}"
      z_p_session=$(rbuh_json_field_capture "${z_infix}" ".workforcePools[${z_index}].sessionDuration // \"\"") || z_p_session=""
      z_p_desc=$(rbuh_json_field_capture "${z_infix}" ".workforcePools[${z_index}].description // \"\"") || z_p_desc=""
      if test "${z_p_id}" = "${z_pool_id}"; then
        # The pool at the expected id is OURS by coordinate — matched by id, not marker,
        # so a pool predating the marker convention still counts (the fix the live run
        # forced: a spike pool at the id but without the marker was create-over'd).
        z_expected_state="${z_p_state}"
        z_expected_session="${z_p_session}"
        z_expected_desc="${z_p_desc}"
      elif test -n "${z_p_id}" && test "${z_p_desc}" = "${RBGC_WORKFORCE_POOL_MARKER}" \
           && test "${z_p_state}" != "${RBGC_STATE_DELETED}" && test -z "${z_other_live_id}"; then
        # A live RB-marked pool at a DIFFERENT id — the marker recognizes OUR pool among
        # unrelated org pools for the drift check.
        z_other_live_id="${z_p_id}"
      fi
      z_index=$((z_index + 1))
    done

    z_page_token=$(rbuh_json_field_capture "${z_infix}" '.nextPageToken // ""') || z_page_token=""
    test -n "${z_page_token}" || break
    z_page=$((z_page + 1))
  done

  if test -n "${z_expected_state}"; then
    # An RB-marked pool stands at the expected id.
    if test "${z_expected_state}" = "${RBGC_STATE_DELETED}"; then
      buc_warn "Workforce pool ${z_pool_id} is soft-deleted (state DELETED) — squatting its id through the ~30-day purge window"
      buc_info "The finisher never resurrects a dissolved pool (ensure-exists, never undelete). Set a free RBRW_WORKFORCE_POOL_ID and re-run, or wait for purge."
      buc_die "Workforce pool ${z_pool_id} soft-deleted — coordinate drift, refusing to found a second pool"
    fi
    # Live at the expected id -> ours. Reconcile session-duration (config drives cloud)
    # and backfill the RB marker if this pool predates the convention, both in one
    # non-destructive PATCH whose updateMask names only the fields that actually differ.
    z_mask=""
    test "${z_expected_session}" = "${RBRW_SESSION_DURATION}" || z_mask="sessionDuration"
    if test "${z_expected_desc}" != "${RBGC_WORKFORCE_POOL_MARKER}"; then
      if test -n "${z_mask}"; then
        z_mask="${z_mask},description"
      else
        z_mask="description"
      fi
    fi
    if test -z "${z_mask}"; then
      buc_info "Workforce pool ${z_pool_id} present (state ${z_expected_state}, session ${z_expected_session}) — already conformant, leaving in place"
    else
      buc_step "Reconcile pool ${z_pool_id} (updateMask=${z_mask})"
      local -r z_patch_body="${BURD_TEMP_DIR}/rbgp_instaurate_pool_patch.json"
      jq -n \
        --arg sessionDuration "${RBRW_SESSION_DURATION}" \
        --arg description     "${RBGC_WORKFORCE_POOL_MARKER}" \
        '{ sessionDuration: $sessionDuration, description: $description }' > "${z_patch_body}" \
        || buc_die "Failed to build workforce pool patch body"
      rbuh_json "PATCH" "${z_pool_url}?updateMask=${z_mask}" "${z_token}" "instaurate_pool_patch" "${z_patch_body}"
      rbuh_require_ok "Reconcile pool" "instaurate_pool_patch"
      buc_info "Workforce pool ${z_pool_id} reconciled (updateMask=${z_mask})"
    fi
  elif test -n "${z_other_live_id}"; then
    # A live RB pool stands under a different id — refuse rather than found a second.
    buc_warn "A live Recipe Bottle workforce pool stands under id '${z_other_live_id}', but RBRW_WORKFORCE_POOL_ID is '${z_pool_id}' (coordinate drift)"
    buc_info "The finisher refuses to found a second pool. Reconcile RBRW_WORKFORCE_POOL_ID with the standing pool's id (org+pool-id are pool-time-immutable, RBSRW)."
    buc_die "Workforce pool coordinate drift: configured id '${z_pool_id}' does not match the standing RB pool '${z_other_live_id}'"
  else
    # No RB-marked pool under the org -> create it at the configured id. The org is an
    # immutable body field (parent), never a query parameter (RBSMA create-shape).
    buc_step "Create workforce identity pool ${z_pool_id} under ${z_org}"
    local -r z_pool_body="${BURD_TEMP_DIR}/rbgp_instaurate_pool.json"
    jq -n \
      --arg parent          "${z_org}" \
      --arg displayName     "${z_pool_id}" \
      --arg description     "${RBGC_WORKFORCE_POOL_MARKER}" \
      --arg sessionDuration "${RBRW_SESSION_DURATION}" \
      '{
        parent: $parent,
        displayName: $displayName,
        description: $description,
        sessionDuration: $sessionDuration
      }' > "${z_pool_body}" || buc_die "Failed to build workforce pool body"

    rbge_lro_ok \
      "Create workforce pool" \
      "${z_token}" \
      "${z_pools_base}?workforcePoolId=${z_pool_id}" \
      "instaurate_pool_create" \
      "${z_pool_body}" \
      ".name" \
      "${z_iam_root}" \
      "" \
      "${RBGC_EVENTUAL_CONSISTENCY_SEC}" \
      "${RBGC_MAX_CONSISTENCY_SEC}"
    buc_info "Workforce pool ${z_pool_id} created under ${z_org}"
  fi

  # === Ensure the terrier bucket (manor-grain, in the payor project) ===
  # Bucket only: the per-polity managed folder inside it is depot-grain — named by
  # a depot, granted to that depot's governor mantle — and is founded at depot levy.
  buc_step "Ensure terrier bucket ${RBGP_TERRIER_BUCKET} in payor project ${RBRP_PAYOR_PROJECT_ID}"
  rbgb_bucket_ensure "${z_token}" "${RBRP_PAYOR_PROJECT_ID}" "${RBGP_TERRIER_BUCKET}" "${RBRD_GCP_REGION}"

  buc_step 'Manor instaurated'
  buc_success "Manor instaurated: workforce pool ${z_pool_id} under ${z_org}, terrier bucket ${RBGP_TERRIER_BUCKET}"
  buc_info "A foedus is now affianceable under the standing pool (rbw-mA); raze (rbw-mR) is the inverse teardown"
}

# Escheat helper — derive the distinct depot candidates the liveness probe must
# judge: the depot segment of every sound muniment plus every standing polity
# folder (trailing slash stripped). Pure bash over the two survey files; emits
# one candidate per line, deduplicated.
zrbgp_escheat_depots() {
  zrbgp_sentinel

  local -r z_survey_file="${1:-}"
  local -r z_folders_file="${2:-}"
  test -f "${z_survey_file}"  || buc_die "Survey file required: ${z_survey_file}"
  test -f "${z_folders_file}" || buc_die "Folders file required: ${z_folders_file}"

  buc_log_args 'Collect depot candidates from sound muniments and standing folders'
  local z_candidates=()
  local z_line=""
  local z_verdict=""
  local z_detail=""
  local z_name=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    IFS=$'\t' read -r z_verdict z_detail z_name <<<"${z_line}" || buc_die "Malformed survey line: ${z_line}"
    test "${z_verdict}" = "sound" || continue
    z_candidates+=("${z_detail}")
  done < "${z_survey_file}"
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    z_candidates+=("${z_line%/}")
  done < "${z_folders_file}"

  local z_seen="|"
  local z_i=0
  local z_cand=""
  for z_i in "${!z_candidates[@]}"; do
    z_cand="${z_candidates[$z_i]}"
    test -n "${z_cand}" || continue
    case "${z_seen}" in
      *"|${z_cand}|"*) continue ;;
      *) : ;;
    esac
    z_seen="${z_seen}${z_cand}|"
    printf '%s\n' "${z_cand}" || buc_die "Failed to emit depot candidate"
  done
}

# Escheat helper — probe each depot candidate's liveness (RBSME rule): ACTIVE
# with the depot displayName anchor is live; ACTIVE without it is an anomaly
# (kept, flagged); any other state, 403, or 404 is dead. A candidate that cannot
# even be a project id (shape-invalid — e.g. a nested folder name) is dead by
# construction, no probe issued. Emits "«depot»\t«verdict»\t«detail»" per line.
# Any unexpected HTTP outcome dies — a liveness verdict is never guessed.
zrbgp_escheat_liveness() {
  zrbgp_sentinel

  local -r z_token="${1:-}"
  local -r z_depots_file="${2:-}"
  test -n "${z_token}"       || buc_die "Token required"
  test -f "${z_depots_file}" || buc_die "Depots file required: ${z_depots_file}"

  buc_log_args 'Load depot candidates, then probe each (load-then-iterate)'
  local z_depots=()
  local z_line=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    z_depots+=("${z_line}")
  done < "${z_depots_file}"

  local -r z_display_prefix="${RBGC_DEPOT_DISPLAY_PREFIX} "
  local z_i=0
  local z_depot=""
  local z_infix=""
  local z_code=""
  local z_state=""
  local z_display=""
  for z_i in "${!z_depots[@]}"; do
    z_depot="${z_depots[$z_i]}"

    [[ "${z_depot}" =~ ^[a-z][a-z0-9-]*$ ]] || {
      printf '%s\tdead\tinvalid-id\n' "${z_depot}" || buc_die "Failed to emit liveness line"
      continue
    }

    z_infix="escheat_liveness_${z_i}"
    rbuh_json "GET" "${RBGC_API_ROOT_CRM}${RBGC_CRM_V3}/projects/${z_depot}" "${z_token}" "${z_infix}"
    z_code=$(rbuh_code_capture "${z_infix}") || buc_die "No HTTP code from projects.get for ${z_depot}"
    case "${z_code}" in
      200)
        z_state=$(rbuh_json_field_capture "${z_infix}" '.state // "UNKNOWN"') || z_state="UNKNOWN"
        if test "${z_state}" != "${RBGC_STATE_ACTIVE}"; then
          printf '%s\tdead\t%s\n' "${z_depot}" "${z_state}" || buc_die "Failed to emit liveness line"
          continue
        fi
        z_display=$(rbuh_json_field_capture "${z_infix}" '.displayName // ""') || z_display=""
        case "${z_display}" in
          "${z_display_prefix}"*) printf '%s\tlive\t%s\n' "${z_depot}" "${z_state}" || buc_die "Failed to emit liveness line" ;;
          *)                      printf '%s\tanomaly\tactive-without-depot-anchor\n' "${z_depot}" || buc_die "Failed to emit liveness line" ;;
        esac
        ;;
      403|404)
        printf '%s\tdead\thttp-%s\n' "${z_depot}" "${z_code}" || buc_die "Failed to emit liveness line"
        ;;
      *)
        buc_die "Escheat liveness: unexpected HTTP ${z_code} from projects.get for ${z_depot} — a liveness verdict is never guessed"
        ;;
    esac
  done
}

# Escheat helper — compose the plan from the survey, the folder listing, and the
# held liveness verdicts. Pure bash over files; emits one
# "«action»\t«kind»\t«reason»\t«name»" line per item, action keep | flag |
# sweep, kind object | folder. A sound muniment whose depot carries no verdict
# dies — every sound depot was a probe candidate by construction.
zrbgp_escheat_plan() {
  zrbgp_sentinel

  local -r z_survey_file="${1:-}"
  local -r z_folders_file="${2:-}"
  local -r z_liveness_file="${3:-}"
  test -f "${z_survey_file}"   || buc_die "Survey file required: ${z_survey_file}"
  test -f "${z_folders_file}"  || buc_die "Folders file required: ${z_folders_file}"
  test -f "${z_liveness_file}" || buc_die "Liveness file required: ${z_liveness_file}"

  buc_log_args 'Load the liveness verdicts (parallel arrays)'
  local z_lv_depots=()
  local z_lv_verdicts=()
  local z_lv_details=()
  local z_line=""
  local z_depot=""
  local z_verdict=""
  local z_detail=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    IFS=$'\t' read -r z_depot z_verdict z_detail <<<"${z_line}" || buc_die "Malformed liveness line: ${z_line}"
    z_lv_depots+=("${z_depot}")
    z_lv_verdicts+=("${z_verdict}")
    z_lv_details+=("${z_detail}")
  done < "${z_liveness_file}"

  buc_log_args 'Judge every surveyed object'
  local z_survey_lines=()
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    z_survey_lines+=("${z_line}")
  done < "${z_survey_file}"

  local z_i=0
  local z_j=0
  local z_name=""
  local z_found_verdict=""
  local z_found_detail=""
  for z_i in "${!z_survey_lines[@]}"; do
    IFS=$'\t' read -r z_verdict z_detail z_name <<<"${z_survey_lines[$z_i]}" || buc_die "Malformed survey line"
    if test "${z_verdict}" = "stray"; then
      printf 'sweep\tobject\tstray-%s\t%s\n' "${z_detail}" "${z_name}" || buc_die "Failed to emit plan line"
      continue
    fi
    test "${z_verdict}" = "sound" || buc_die "Unknown survey verdict: ${z_verdict}"
    z_found_verdict=""
    z_found_detail=""
    for z_j in "${!z_lv_depots[@]}"; do
      test "${z_lv_depots[$z_j]}" = "${z_detail}" || continue
      z_found_verdict="${z_lv_verdicts[$z_j]}"
      z_found_detail="${z_lv_details[$z_j]}"
      break
    done
    test -n "${z_found_verdict}" || buc_die "No liveness verdict for depot ${z_detail} — a liveness verdict is never guessed"
    case "${z_found_verdict}" in
      live)    printf 'keep\tobject\tlive\t%s\n' "${z_name}" || buc_die "Failed to emit plan line" ;;
      anomaly) printf 'flag\tobject\t%s\t%s\n' "${z_found_detail}" "${z_name}" || buc_die "Failed to emit plan line" ;;
      dead)    printf 'sweep\tobject\torphan-%s\t%s\n' "${z_found_detail}" "${z_name}" || buc_die "Failed to emit plan line" ;;
      *)       buc_die "Unknown liveness verdict: ${z_found_verdict}" ;;
    esac
  done

  buc_log_args 'Judge every standing polity folder'
  local z_folders=()
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    z_folders+=("${z_line}")
  done < "${z_folders_file}"

  local z_folder=""
  for z_i in "${!z_folders[@]}"; do
    z_folder="${z_folders[$z_i]}"
    z_depot="${z_folder%/}"
    z_found_verdict=""
    z_found_detail=""
    for z_j in "${!z_lv_depots[@]}"; do
      test "${z_lv_depots[$z_j]}" = "${z_depot}" || continue
      z_found_verdict="${z_lv_verdicts[$z_j]}"
      z_found_detail="${z_lv_details[$z_j]}"
      break
    done
    test -n "${z_found_verdict}" || buc_die "No liveness verdict for folder depot ${z_depot}"
    case "${z_found_verdict}" in
      live)    printf 'keep\tfolder\tlive\t%s\n' "${z_folder}" || buc_die "Failed to emit plan line" ;;
      anomaly) printf 'flag\tfolder\t%s\t%s\n' "${z_found_detail}" "${z_folder}" || buc_die "Failed to emit plan line" ;;
      dead)    printf 'sweep\tfolder\torphan-%s\t%s\n' "${z_found_detail}" "${z_folder}" || buc_die "Failed to emit plan line" ;;
      *)       buc_die "Unknown liveness verdict: ${z_found_verdict}" ;;
    esac
  done
}

# The manor-hygiene sweep (RBSME): strike from the terrier what no live
# admission path owns — orphaned polity slices (their depot unmade) and
# dead-schema strays (objects failing the RBSTN muniment contract). Plan-then-
# confirm: nothing mutates before the operator confirms against the shown plan
# (the plan IS the confirmation subject, so the gate sits after the survey,
# unlike raze's zero-traffic confirm-first). Already-clean short-circuits to an
# idempotent exit-0 no-op with no prompt. Payor-credentialed of necessity:
# cross-slice deletion exceeds any governor mantle's folder scope, and an
# orphaned slice's governor SA died with its project. The mutating sibling of
# the pure read rbgp_rehearse — rehearse witnesses, escheat removes.
rbgp_manor_escheat() {
  zrbgp_sentinel

  buc_doc_brief "Escheat the terrier — sweep orphaned polity slices and dead-schema strays from the manor terrier (plan-then-confirm)"
  buc_doc_shown || return 0

  local -r z_bucket="${RBGP_TERRIER_BUCKET}"

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  local -r z_survey_file="${ZRBGP_PREFIX}escheat_survey_plan.txt"
  rbgft_escheat_survey "${z_token}" "${z_bucket}" > "${z_survey_file}" \
    || buc_die "Escheat survey failed"

  buc_step 'List the polity managed folders'
  local -r z_folders_file="${ZRBGP_PREFIX}escheat_folders_plan.txt"
  rbgb_managed_folders_capture "${z_token}" "${z_bucket}" > "${z_folders_file}" \
    || buc_reject "${BUBC_band_escheat}" "Escheat: failed to list managed folders in ${z_bucket}"

  local -r z_depots_file="${ZRBGP_PREFIX}escheat_depots.txt"
  zrbgp_escheat_depots "${z_survey_file}" "${z_folders_file}" > "${z_depots_file}" \
    || buc_die "Failed to derive depot candidates"

  buc_step 'Probe depot liveness'
  local -r z_liveness_file="${ZRBGP_PREFIX}escheat_liveness.txt"
  zrbgp_escheat_liveness "${z_token}" "${z_depots_file}" > "${z_liveness_file}" \
    || buc_die "Failed to probe depot liveness"

  buc_step 'Escheat plan — every disposition'
  local -r z_plan_file="${ZRBGP_PREFIX}escheat_plan.txt"
  zrbgp_escheat_plan "${z_survey_file}" "${z_folders_file}" "${z_liveness_file}" > "${z_plan_file}" \
    || buc_die "Failed to compose escheat plan"

  local z_plan_lines=()
  local z_line=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    z_plan_lines+=("${z_line}")
  done < "${z_plan_file}"

  local z_i=0
  local z_action=""
  local z_kind=""
  local z_reason=""
  local z_name=""
  local z_keep_count=0
  local z_flag_count=0
  local z_sweep_objects=0
  local z_sweep_folders=0
  for z_i in "${!z_plan_lines[@]}"; do
    IFS=$'\t' read -r z_action z_kind z_reason z_name <<<"${z_plan_lines[$z_i]}" || buc_die "Malformed plan line"
    case "${z_action}" in
      keep)  z_keep_count=$((z_keep_count + 1))
             buc_info "KEEP   ${z_kind} (${z_reason}): ${z_name}" ;;
      flag)  z_flag_count=$((z_flag_count + 1))
             buc_warn "FLAG   ${z_kind} (${z_reason}): ${z_name} — kept, not provably dead" ;;
      sweep) if test "${z_kind}" = "object"; then
               z_sweep_objects=$((z_sweep_objects + 1))
             else
               z_sweep_folders=$((z_sweep_folders + 1))
             fi
             buc_info "SWEEP  ${z_kind} (${z_reason}): ${z_name}" ;;
      *)     buc_die "Unknown plan action: ${z_action}" ;;
    esac
  done

  if test "$((z_sweep_objects + z_sweep_folders))" -eq 0; then
    buc_success "Terrier clean — nothing to escheat (${z_keep_count} kept, ${z_flag_count} flagged)"
    return 0
  fi

  buc_step 'Safety confirmation required'
  buc_require "DANGER: escheat strikes ${z_sweep_objects} object(s) and ${z_sweep_folders} folder(s) from the terrier record permanently" "${z_bucket}"

  buc_step 'Execute the sweep (objects, then dead polity folders)'
  for z_i in "${!z_plan_lines[@]}"; do
    IFS=$'\t' read -r z_action z_kind z_reason z_name <<<"${z_plan_lines[$z_i]}" || buc_die "Malformed plan line"
    test "${z_action}" = "sweep" || continue
    test "${z_kind}" = "object"  || continue
    rbgft_escheat_expunge_raw "${z_token}" "${z_bucket}" "${z_name}" >/dev/null \
      || buc_die "Escheat: raw expunge failed for ${z_name}"
  done
  for z_i in "${!z_plan_lines[@]}"; do
    IFS=$'\t' read -r z_action z_kind z_reason z_name <<<"${z_plan_lines[$z_i]}" || buc_die "Malformed plan line"
    test "${z_action}" = "sweep" || continue
    test "${z_kind}" = "folder"  || continue
    rbgb_managed_folder_purge "${z_token}" "${z_bucket}" "${z_name}" \
      || buc_reject "${BUBC_band_escheat}" "Escheat: failed to purge dead polity folder ${z_name}"
  done

  buc_step 'Verify the sweep (re-survey; the re-plan must hold no strike)'
  local -r z_survey_verify_file="${ZRBGP_PREFIX}escheat_survey_verify.txt"
  rbgft_escheat_survey "${z_token}" "${z_bucket}" > "${z_survey_verify_file}" \
    || buc_die "Escheat verify survey failed"
  local -r z_folders_verify_file="${ZRBGP_PREFIX}escheat_folders_verify.txt"
  rbgb_managed_folders_capture "${z_token}" "${z_bucket}" > "${z_folders_verify_file}" \
    || buc_reject "${BUBC_band_escheat}" "Escheat verify: failed to re-list managed folders in ${z_bucket}"

  local -r z_replan_file="${ZRBGP_PREFIX}escheat_replan.txt"
  zrbgp_escheat_plan "${z_survey_verify_file}" "${z_folders_verify_file}" "${z_liveness_file}" > "${z_replan_file}" \
    || buc_die "Failed to compose escheat verify plan"

  local z_replan_lines=()
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    z_replan_lines+=("${z_line}")
  done < "${z_replan_file}"

  local z_residual=0
  local z_standing=0
  for z_i in "${!z_replan_lines[@]}"; do
    IFS=$'\t' read -r z_action z_kind z_reason z_name <<<"${z_replan_lines[$z_i]}" || buc_die "Malformed replan line"
    if test "${z_action}" = "sweep"; then
      z_residual=$((z_residual + 1))
    fi
    if test "${z_action}" = "keep" && test "${z_kind}" = "object"; then
      z_standing=$((z_standing + 1))
    fi
  done
  test "${z_residual}" -eq 0 \
    || buc_die "Escheat verify: ${z_residual} sweepable item(s) still standing after the sweep — see ${z_replan_file}"

  buc_step 'Escheated'
  buc_success "Escheat complete: struck ${z_sweep_objects} object(s) and ${z_sweep_folders} folder(s); ${z_standing} sound muniment(s) stand, every roll line naming a live depot in the current schema"
}

rbgp_depot_levy() {
  zrbgp_sentinel

  local -r z_region="${RBRD_GCP_REGION}"

  buc_doc_brief "Create new depot infrastructure following RBAGS specification"
  buc_doc_shown || return 0

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  buc_step 'Validate region against Artifact Registry locations'
  local -r z_locations_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/projects/${RBRP_PAYOR_PROJECT_ID}/locations"
  rbuh_json "GET" "${z_locations_url}" "${z_token}" "region_validation"
  rbuh_require_ok "Validate region" "region_validation"

  local z_valid_regions
  z_valid_regions=$(rbuh_json_field_capture "region_validation" '.locations[].locationId') || buc_die "Failed to parse region list"
  z_valid_regions="${z_valid_regions//$'\n'/ }"

  if ! [[ " ${z_valid_regions} " =~ [[:space:]]${z_region}[[:space:]] ]]; then
    buc_die "Invalid region. Valid regions: ${z_valid_regions}"
  fi

  buc_step 'Create depot project'
  local -r z_create_project_body="${BURD_TEMP_DIR}/rbgp_create_project.json"

  # OAuth users create projects without parent (per MPCR)
  jq -n \
    --arg projectId "${RBDC_DEPOT_PROJECT_ID}" \
    --arg displayName "${RBGC_DEPOT_DISPLAY_PREFIX} ${RBRD_DEPOT_MONIKER}" \
    '{
      projectId: $projectId,
      displayName: $displayName
    }' > "${z_create_project_body}" || buc_die "Failed to build project creation body"

  local -r z_create_project_url="${RBGC_API_ROOT_CRM}${RBGC_CRM_V3}/projects"
  rbge_lro_ok \
    "Create depot project" \
    "${z_token}" \
    "${z_create_project_url}" \
    "depot_project_create" \
    "${z_create_project_body}" \
    ".name" \
    "${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}" \
    "operations/" \
    "${RBGC_EVENTUAL_CONSISTENCY_SEC}" \
    "${RBGC_MAX_CONSISTENCY_SEC}"

  buc_info "Depot project ID: ${RBDC_DEPOT_PROJECT_ID}"
  buc_link "Click to " "Open depot Cloud Build console" "${RBGC_CONSOLE_URL}cloud-build/builds?project=${RBDC_DEPOT_PROJECT_ID}"

  buc_step 'Link billing account'
  local -r z_billing_body="${BURD_TEMP_DIR}/rbgp_billing_link.json"
  jq -n \
    --arg billingAccountName "billingAccounts/${RBRP_BILLING_ACCOUNT_ID}" \
    '{
      billingAccountName: $billingAccountName
    }' > "${z_billing_body}" || buc_die "Failed to build billing link body"

  local -r z_billing_url="${RBGC_API_ROOT_CLOUDBILLING}${RBGC_CLOUDBILLING_V1}/projects/${RBDC_DEPOT_PROJECT_ID}/billingInfo"
  rbuh_json "PUT" "${z_billing_url}" "${z_token}" "depot_billing_link" "${z_billing_body}"

  # Billing-account link quota decode: Google refuses the link with a bare
  # "Precondition check failed." whose QuotaFailure detail names the real
  # cause. Surface the violation and the remedy; the project shell already
  # exists at this point, so name it for disposal. Any other failure falls
  # through to the uniform require_ok die unchanged.
  local z_billing_code
  z_billing_code=$(rbuh_code_capture "depot_billing_link") || z_billing_code=""
  local z_billing_quota=""
  if test "${z_billing_code}" = "400"; then
    z_billing_quota=$(rbuh_json_field_capture "depot_billing_link" \
      '[.error.details[]? | select(."@type" | endswith("QuotaFailure")) | .violations[]?.description] | join("; ")') \
      || z_billing_quota=""
  fi
  if test -n "${z_billing_quota}"; then
    buc_warn "Billing account billingAccounts/${RBRP_BILLING_ACCOUNT_ID} refused a new project link: ${z_billing_quota}"
    buc_warn "The depot project ${RBDC_DEPOT_PROJECT_ID} was created but stands unlinked — unmake it before retrying:"
    buc_tabtarget "${RBZ_UNMAKE_DEPOT}" "${RBDC_DEPOT_PROJECT_ID}"
    buc_warn "Free a link slot by unmaking a stranded depot (unmake unlinks billing; list candidates):"
    buc_tabtarget "${RBZ_LIST_DEPOT}"
    buc_warn "Or request a billing-account quota increase: https://support.google.com/code/contact/billing_quota_increase"
    buc_die "Link billing account: billing-account project-link quota exhausted"
  fi
  rbuh_require_ok "Link billing account" "depot_billing_link"

  buc_step 'Get depot project number'
  local -r z_project_info_url="${RBGC_API_ROOT_CRM}${RBGC_CRM_V3}/projects/${RBDC_DEPOT_PROJECT_ID}"
  rbuh_json "GET" "${z_project_info_url}" "${z_token}" "depot_project_info"
  rbuh_require_ok "Get project info" "depot_project_info"

  local z_project_number
  # CRM v3 returns project number in name field as "projects/{number}"
  z_project_number=$(rbuh_json_field_capture "depot_project_info" '.name | sub("projects/"; "")') || buc_die "Failed to get project number"
  test -n "${z_project_number}" || buc_die "Project number is empty"

  buc_step 'Enable depot project APIs'
  local -r z_api_services="artifactregistry cloudbuild cloudresourcemanager containeranalysis iam serviceusage storage"
  for z_service in ${z_api_services}; do
    rbge_api_enable "${z_service}" "${RBDC_DEPOT_PROJECT_ID}" "${z_token}"
  done

  buc_step 'Create dual worker pools (tether + airgap)'
  local -r z_pool_parent="${RBGC_API_ROOT_CLOUDBUILD}${RBGC_CLOUDBUILD_V1}/projects/${RBDC_DEPOT_PROJECT_ID}/locations/${z_region}${RBGC_PATH_WORKER_POOLS}"

  # Tether pool (default egress — public internet access)
  local -r z_tether_id="${RBDC_GCB_POOL_STEM}${RBGC_POOL_SUFFIX_TETHER}"
  local -r z_tether_create_url="${z_pool_parent}?workerPoolId=${z_tether_id}"
  local -r z_tether_create_body="${BURD_TEMP_DIR}/rbgp_pool_tether_create.json"

  jq -n --arg machineType "${RBRD_GCB_MACHINE_TYPE}" \
    '{
      privatePoolV1Config: {
        workerConfig: {
          machineType: $machineType
        }
      }
    }' > "${z_tether_create_body}" || buc_die "Failed to build tether pool creation body"

  rbge_lro_ok \
    "Create tether worker pool" \
    "${z_token}" \
    "${z_tether_create_url}" \
    "depot_pool_tether_create" \
    "${z_tether_create_body}" \
    ".name" \
    "${RBGC_API_ROOT_CLOUDBUILD}${RBGC_CLOUDBUILD_V1}" \
    "${RBGC_OP_PREFIX_GLOBAL}" \
    "${RBGC_EVENTUAL_CONSISTENCY_SEC}" \
    "${RBGC_MAX_CONSISTENCY_SEC}"

  # Airgap pool (NO_PUBLIC_EGRESS — no public internet)
  local -r z_airgap_id="${RBDC_GCB_POOL_STEM}${RBGC_POOL_SUFFIX_AIRGAP}"
  local -r z_airgap_create_url="${z_pool_parent}?workerPoolId=${z_airgap_id}"
  local -r z_airgap_create_body="${BURD_TEMP_DIR}/rbgp_pool_airgap_create.json"

  jq -n --arg machineType "${RBRD_GCB_MACHINE_TYPE}" \
    '{
      privatePoolV1Config: {
        workerConfig: {
          machineType: $machineType
        },
        networkConfig: {
          egressOption: "NO_PUBLIC_EGRESS"
        }
      }
    }' > "${z_airgap_create_body}" || buc_die "Failed to build airgap pool creation body"

  rbge_lro_ok \
    "Create airgap worker pool" \
    "${z_token}" \
    "${z_airgap_create_url}" \
    "depot_pool_airgap_create" \
    "${z_airgap_create_body}" \
    ".name" \
    "${RBGC_API_ROOT_CLOUDBUILD}${RBGC_CLOUDBUILD_V1}" \
    "${RBGC_OP_PREFIX_GLOBAL}" \
    "${RBGC_EVENTUAL_CONSISTENCY_SEC}" \
    "${RBGC_MAX_CONSISTENCY_SEC}"

  local -r z_pool_resource="projects/${RBDC_DEPOT_PROJECT_ID}/locations/${z_region}/workerPools/${RBDC_GCB_POOL_STEM}"
  buc_log_args "Pool stem: ${z_pool_resource}"

  # Note: OAuth Payor doesn't need explicit permissions on depot since it uses user identity
  # Skip Payor permission grants - OAuth user context provides necessary access

  buc_step 'Verify IAM propagation before resource creation'
  local -r z_preflight_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/projects/${RBDC_DEPOT_PROJECT_ID}/locations/${z_region}/repositories"
  rbuh_poll_until_ok "AR IAM propagation" "${z_preflight_url}" "${z_token}" "iam_preflight"

  buc_step 'Create container repository'
  local -r z_parent="projects/${RBDC_DEPOT_PROJECT_ID}/locations/${z_region}"
  local -r z_create_repo_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_parent}/repositories?repositoryId=${RBDC_GAR_REPOSITORY}"
  local -r z_create_repo_body="${BURD_TEMP_DIR}/rbgp_create_repo.json"
  
  jq -n \
    --arg policy_id "${RBGC_GAR_CLEANUP_POLICY_ID}" \
    --arg older_than "${RBGC_GAR_CLEANUP_OLDER_THAN_SEC}" \
    '{
      format: "DOCKER",
      cleanupPolicyDryRun: false,
      cleanupPolicies: {
        ($policy_id): {
          id: $policy_id,
          action: "DELETE",
          condition: {
            tagState: "UNTAGGED",
            olderThan: $older_than
          }
        }
      }
    }' > "${z_create_repo_body}" || buc_die "Failed to build create-repo body"

  rbge_lro_ok \
    "Create container repository" \
    "${z_token}" \
    "${z_create_repo_url}" \
    "depot_repo_create" \
    "${z_create_repo_body}" \
    ".name" \
    "${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}" \
    "${RBGC_OP_PREFIX_GLOBAL}" \
    "${RBGC_EVENTUAL_CONSISTENCY_SEC}" \
    "${RBGC_MAX_CONSISTENCY_SEC}"

  buc_step 'Verify IAM API is ready for service account creation'
  local -r z_iam_preflight_url="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/${RBDC_DEPOT_PROJECT_ID}/serviceAccounts"
  rbuh_poll_until_ok "IAM API" "${z_iam_preflight_url}" "${z_token}" "iam_sa_preflight"

  buc_step 'Create Mason service account'
  local -r z_mason_name="${RBCC_account_unhewn_mason}-${RBRD_DEPOT_MONIKER}"
  local -r z_mason_display_name="${RBGC_DEPOT_DISPLAY_PREFIX} mason ${RBRD_DEPOT_MONIKER}"
  local -r z_create_sa_body="${BURD_TEMP_DIR}/rbgp_create_mason.json"

  jq -n \
    --arg accountId "${z_mason_name}" \
    --arg displayName "${z_mason_display_name}" \
    '{
      accountId: $accountId,
      serviceAccount: {
        displayName: $displayName
      }
    }' > "${z_create_sa_body}" || buc_die "Failed to build Mason creation body"

  local -r z_create_sa_url="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/${RBDC_DEPOT_PROJECT_ID}/serviceAccounts"
  rbuh_json "POST" "${z_create_sa_url}" "${z_token}" "depot_mason_create" "${z_create_sa_body}"
  rbuh_require_ok "Create Mason service account" "depot_mason_create"

  local z_mason_sa_email
  z_mason_sa_email=$(rbuh_json_field_capture "depot_mason_create" '.email') || buc_die "Failed to get Mason email"

  buc_step 'Verify Mason service account propagation'
  local -r z_mason_sa_url="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/${RBDC_DEPOT_PROJECT_ID}/serviceAccounts/${z_mason_sa_email}"
  rbuh_poll_until_ok "Mason SA" "${z_mason_sa_url}" "${z_token}" "mason_sa_preflight"

  buc_step 'Configure Mason permissions'
  # Repository admin (AR repo IAM requires email, not numeric ID)
  rbgi_add_repo_iam_role "${z_token}" "${RBDC_DEPOT_PROJECT_ID}" "${z_mason_sa_email}" "${z_region}" "${RBDC_GAR_REPOSITORY}" \
    "roles/artifactregistry.writer"

  # Project viewer
  rbgi_add_project_iam_role "${z_token}" "Grant Mason Project Viewer" "projects/${RBDC_DEPOT_PROJECT_ID}" \
    "roles/viewer" "serviceAccount:${z_mason_sa_email}" "mason-viewer"

  # Logs writer (for Cloud Build logs to Cloud Logging)
  rbgi_add_project_iam_role "${z_token}" "Grant Mason Logs Writer" "projects/${RBDC_DEPOT_PROJECT_ID}" \
    "roles/logging.logWriter" "serviceAccount:${z_mason_sa_email}" "mason-logs-writer"

  buc_step 'Provision Cloud Build service agent'
  # The Cloud Build Service Agent (service-{PN}@gcp-sa-cloudbuild.iam.gserviceaccount.com)
  # needs serviceAccountTokenCreator on Mason to impersonate it during builds.create.
  # The service agent is auto-created when the Cloud Build API is enabled; its email is
  # deterministic from the project number. See RBSCIP for the two-SA distinction.
  rbgi_provision_service_agent "cloudbuild" "${RBDC_DEPOT_PROJECT_ID}" "${z_token}" > /dev/null \
    || buc_die "Failed to provision Cloud Build service agent"
  local -r z_cb_service_agent="service-${z_project_number}@gcp-sa-cloudbuild.${RBGC_SA_EMAIL_DOMAIN}"
  buc_log_args "CB service agent: ${z_cb_service_agent}"

  buc_step 'Enable Cloud Build service agent to impersonate Mason'
  rbgi_add_sa_iam_role "${z_token}" "${z_mason_sa_email}" "${z_cb_service_agent}" "${RBGC_ROLE_IAM_SERVICE_ACCOUNT_TOKEN_CREATOR}"

  buc_step 'Establish the mantle service accounts'
  # The three federation mantles (governor/director/retriever) — the impersonatable
  # identities a citizen dons at runtime — created beside Mason and granted their full
  # resource authority once, here, via the shared rbgw capability-sets. See RBSMF.
  local -r z_gov_mantle_email="${RBCC_account_mantle_governor}@${RBGD_SA_EMAIL_FULL}"
  local -r z_dir_mantle_email="${RBCC_account_mantle_director}@${RBGD_SA_EMAIL_FULL}"
  local -r z_ret_mantle_email="${RBCC_account_mantle_retriever}@${RBGD_SA_EMAIL_FULL}"

  zrbgp_establish_mantle_sa "${z_token}" "${RBCC_account_mantle_governor}" "governor"
  rbgw_grant_governor_capabilities "${z_token}" "${z_gov_mantle_email}"

  zrbgp_establish_mantle_sa "${z_token}" "${RBCC_account_mantle_director}" "director"
  rbgw_grant_director_capabilities "${z_token}" "${z_dir_mantle_email}"

  zrbgp_establish_mantle_sa "${z_token}" "${RBCC_account_mantle_retriever}" "retriever"
  rbgw_grant_retriever_capabilities "${z_token}" "${z_ret_mantle_email}"

  # === Found the polity terrier folder + grain IAM (depot-grain, ensure-only) ===
  # The polity managed folder is named by this depot and grants the fresh governor
  # mantle its terrier bindings (own-polity write, manor-wide read) — depot-grain
  # resource IAM, founded here so the settle gate below stays true. The folder
  # lives inside the payor-project terrier bucket, so its creation and grain IAM
  # ride the payor credential in hand (the folder-step credential boundary). The
  # bucket itself is manor-grain, founded by the instaurate finisher — an absent
  # bucket fails loud here, and the remedy is the finisher, then re-levy.
  local -r z_terrier_folder="${RBDC_DEPOT_PROJECT_ID}/"

  buc_step "Ensure the polity managed folder ${z_terrier_folder} (ensure-only)"
  rbgb_managed_folder_ensure "${z_token}" "${RBGP_TERRIER_BUCKET}" "${z_terrier_folder}"

  buc_step 'Grant folder-scoped write to the governor mantle (own-polity)'
  rbgb_managed_folder_add_iam_role "${z_token}" "${RBGP_TERRIER_BUCKET}" "${z_terrier_folder}" \
    "${z_gov_mantle_email}" "${RBGC_ROLE_STORAGE_OBJECT_ADMIN}"

  buc_step 'Grant bucket-level read to the governor mantle (manor-wide)'
  rbgi_add_bucket_iam_role "${z_token}" "${RBGP_TERRIER_BUCKET}" "${z_gov_mantle_email}" "${RBGC_ROLE_STORAGE_OBJECT_VIEWER}"

  buc_step 'Verify bucket-level read via getIamPolicy read-back'
  rbuh_json "GET" \
    "${RBGC_API_BASE_GCS}/b/${RBGP_TERRIER_BUCKET}/iam?optionsRequestedPolicyVersion=3" \
    "${z_token}" "levy_terrier_bucket_iam"
  rbuh_require_ok "Read terrier bucket IAM policy" "levy_terrier_bucket_iam"
  zrbgp_recognosce_require_binding "levy_terrier_bucket_iam" \
    "${RBGC_ROLE_STORAGE_OBJECT_VIEWER}" "serviceAccount:${z_gov_mantle_email}" \
    "terrier bucket (governor manor-wide read)"

  buc_step 'Verify folder-scoped write via getIamPolicy read-back'
  local z_terrier_folder_enc
  z_terrier_folder_enc=$(rbuh_urlencode_capture "${z_terrier_folder}") || buc_die "Failed to encode terrier folder"
  rbuh_json "GET" \
    "${RBGC_API_BASE_GCS}/b/${RBGP_TERRIER_BUCKET}/managedFolders/${z_terrier_folder_enc}/iam?optionsRequestedPolicyVersion=3" \
    "${z_token}" "levy_terrier_folder_iam"
  rbuh_require_ok "Read terrier folder IAM policy" "levy_terrier_folder_iam"
  zrbgp_recognosce_require_binding "levy_terrier_folder_iam" \
    "${RBGC_ROLE_STORAGE_OBJECT_ADMIN}" "serviceAccount:${z_gov_mantle_email}" \
    "terrier folder (governor own-polity write)"

  buc_step 'Settle gate — depot resource IAM frozen'
  # Every resource binding the depot will carry is now written and self-confirmed —
  # the three capability-set grants and the governor's terrier grain bindings; this
  # is the freeze. Post-levy admission writes only the per-citizen tokenCreator +
  # serviceUsageConsumer bindings, never a resource binding.

  zrbgp_enable_ar_audit_logs "${z_token}"

  buc_step 'Submit per-pool probe builds (populate quota rows + assert egress posture + GAR write)'

  local -r z_tether_posture_check="${BURD_TEMP_DIR}/rbgp_tether_posture_check.sh"
  local -r z_airgap_posture_check="${BURD_TEMP_DIR}/rbgp_airgap_posture_check.sh"

  zrbgp_write_posture_check tether "${z_tether_posture_check}"
  zrbgp_write_posture_check airgap "${z_airgap_posture_check}"

  zrbgp_pool_probe_submit "${z_token}" "tether" "${z_tether_id}" "${z_mason_sa_email}" "${z_tether_posture_check}"
  zrbgp_pool_probe_submit "${z_token}" "airgap" "${z_airgap_id}" "${z_mason_sa_email}" "${z_airgap_posture_check}"

  buc_step 'Update depot tracking'
  zrbgp_depot_list_update || buc_die "Failed to update depot tracking after creation"

  buc_step 'Inscribe RBRD tripwire image'
  rbrd_inscribe "${z_token}"

  buc_success 'Depot creation successful'
  buc_info "Next: gird the first Governor for this depot:"
  buc_tabtarget "${RBZ_GIRD_POLITY}"
}

rbgp_depot_unmake() {
  zrbgp_sentinel

  # Folio arrives via BUZ_FOLIO under the param1 channel (rbz_zipper.sh
  # enrolls RBZ_UNMAKE_DEPOT with channel=param1 per BBAA9). buz_exec_lookup
  # extracts $1 into BUZ_FOLIO before exec'ing this function and removes it
  # from $@, so reading $1 here would always be empty.
  local -r z_project_id="${BUZ_FOLIO:-}"

  buc_doc_brief "DANGER: Permanently destroy an entire depot infrastructure"
  buc_doc_param "depot_project_id" "Full GCP project ID of the depot to destroy (matches what rbw-dl displays)"
  buc_doc_shown || return 0

  # Refusal ordering (cheapest first per BBAA9 docket):
  #   1. Empty-arg refusal (zero traffic)
  #   2. Live-disqualify (zero traffic, local string compare)
  #   3. Authenticate
  #   4. projects.get + state=ACTIVE + displayName discriminator

  if test -z "${z_project_id}"; then
    buc_warn "rbgp_depot_unmake requires a depot project ID argument"
    buc_info "Run the depot list to view candidate depots:"
    buc_tabtarget "${RBZ_LIST_DEPOT}"
    buc_die "Depot project ID required as first argument"
  fi

  if test "${z_project_id}" = "${RBDC_DEPOT_PROJECT_ID}"; then
    buc_warn "Refusing to unmake the live RBRD-selected depot: ${z_project_id}"
    buc_info "Recovery: rename RBRD_DEPOT_MONIKER in rbrd.env, or run rbw-MZ to zero regime, then retry."
    buc_die "Live depot cannot be unmade — would orphan local regime state"
  fi

  buc_step 'Safety confirmation required'
  buc_require "DANGER: Permanently destroy depot ${z_project_id} and ALL resources" "${z_project_id}"

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  buc_step 'Validate target depot'
  local -r z_project_info_url="${RBGC_API_ROOT_CRM}${RBGC_CRM_V3}/projects/${z_project_id}"
  rbuh_json "GET" "${z_project_info_url}" "${z_token}" "depot_destroy_validate"
  rbuh_require_ok "Validate depot project" "depot_destroy_validate"

  local z_lifecycle_state
  z_lifecycle_state=$(rbuh_json_field_capture "depot_destroy_validate" '.state // "UNKNOWN"') || buc_die "Failed to parse project state"

  if test "${z_lifecycle_state}" != "${RBGC_STATE_ACTIVE}"; then
    if test "${z_lifecycle_state}" = "DELETE_REQUESTED"; then
      buc_die "Project already marked for deletion"
    else
      buc_die "Project state is ${z_lifecycle_state} - can only destroy ACTIVE projects"
    fi
  fi

  # DisplayName discriminator — symmetric with rbgp_depot_list. Refuses any
  # project whose displayName does not start with the RBGC depot anchor,
  # protecting non-depot projects in the Payor's account from accidental
  # destruction once unmake is decoupled from RBRR.
  local z_display_name
  z_display_name=$(rbuh_json_field_capture "depot_destroy_validate" '.displayName // ""') || buc_die "Failed to parse displayName"
  local -r z_display_prefix="${RBGC_DEPOT_DISPLAY_PREFIX} "
  if [[ "${z_display_name}" != "${z_display_prefix}"* ]]; then
    buc_warn "Project displayName does not match depot anchor: ${z_display_name}"
    buc_info "Run the depot list to view candidate depots:"
    buc_tabtarget "${RBZ_LIST_DEPOT}"
    buc_die "Refusing to unmake non-depot project: ${z_project_id}"
  fi

  # Derive moniker and pool stem from the validated displayName + project_id.
  # displayName format: "${RBGC_DEPOT_DISPLAY_PREFIX} <moniker>"
  # project_id   format: "<cloud_prefix>${RBGC_depot_project_infix}<moniker>"
  # pool_stem    format: "<cloud_prefix><moniker>-pool" (mirrors RBDC_GCB_POOL_STEM)
  local -r z_moniker="${z_display_name#"${z_display_prefix}"}"
  local -r z_cloud_prefix="${z_project_id%"${RBGC_depot_project_infix}""${z_moniker}"}"
  local -r z_pool_stem="${z_cloud_prefix}${z_moniker}-pool"

  buc_step 'Clean up governor service accounts (404-tolerant)'
  # No standalone defrock verb — governor SA lifecycle ends here.  Project
  # deletion would clean these up implicitly, but an explicit DELETE pass
  # gives diagnostic visibility and makes the cleanup contract testable.
  local -r z_unmake_sa_url_base="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/${z_project_id}/serviceAccounts"
  local z_unmake_sa_page_token=""
  local z_unmake_sa_page=1
  local z_unmake_sa_url=""
  local z_unmake_sa_tok_enc=""
  local z_unmake_sa_infix=""
  local z_unmake_sa_count=0
  local z_unmake_sa_index=0
  local z_unmake_sa_email=""
  local z_unmake_gov_delete_infix=""
  local z_governor_sa_count=0
  while :; do
    z_unmake_sa_url="${z_unmake_sa_url_base}"
    if test -n "${z_unmake_sa_page_token}"; then
      z_unmake_sa_tok_enc=$(rbuh_urlencode_capture "${z_unmake_sa_page_token}") \
        || buc_die "Failed to URL-encode pageToken"
      z_unmake_sa_url="${z_unmake_sa_url}?pageToken=${z_unmake_sa_tok_enc}"
    fi
    z_unmake_sa_infix="depot_unmake_gov_list_${z_unmake_sa_page}"
    rbuh_json "GET" "${z_unmake_sa_url}" "${z_token}" "${z_unmake_sa_infix}"
    rbuh_require_ok "List service accounts (page ${z_unmake_sa_page})" "${z_unmake_sa_infix}"

    z_unmake_sa_count=$(rbuh_json_field_capture "${z_unmake_sa_infix}" '.accounts // [] | length') \
      || buc_die "Failed to parse SA list"

    z_unmake_sa_index=0
    while test "${z_unmake_sa_index}" -lt "${z_unmake_sa_count}"; do
      z_unmake_sa_email=$(rbuh_json_field_capture "${z_unmake_sa_infix}" ".accounts[${z_unmake_sa_index}].email") \
        || { z_unmake_sa_index=$((z_unmake_sa_index + 1)); continue; }
      if [[ "${z_unmake_sa_email}" == ${RBCC_account_unhewn_governor}-* ]]; then
        buc_log_args "Deleting governor SA: ${z_unmake_sa_email}"
        z_unmake_gov_delete_infix="depot_unmake_gov_delete_${z_governor_sa_count}"
        rbuh_json "DELETE" "${z_unmake_sa_url_base}/${z_unmake_sa_email}" "${z_token}" "${z_unmake_gov_delete_infix}"
        rbuh_require_ok "Delete governor SA ${z_unmake_sa_email}" "${z_unmake_gov_delete_infix}" \
          404 "not found (already deleted)"
        z_governor_sa_count=$((z_governor_sa_count + 1))
      fi
      z_unmake_sa_index=$((z_unmake_sa_index + 1))
    done

    z_unmake_sa_page_token=$(rbuh_json_field_capture "${z_unmake_sa_infix}" '.nextPageToken') \
      || z_unmake_sa_page_token=""
    test -n "${z_unmake_sa_page_token}" || break
    z_unmake_sa_page=$((z_unmake_sa_page + 1))
  done
  buc_info "Governor SA cleanup: removed ${z_governor_sa_count} account(s)"

  buc_step 'Check for and remove liens'
  local -r z_liens_url="${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/liens?parent=projects%2F${z_project_id}"
  rbuh_json "GET" "${z_liens_url}" "${z_token}" "depot_destroy_liens_list"
  rbuh_require_ok "List liens" "depot_destroy_liens_list"
  
  local z_lien_count
  z_lien_count=$(rbuh_json_field_capture "depot_destroy_liens_list" '.liens // [] | length') || buc_die "Failed to parse liens response"
  
  if test "${z_lien_count}" -gt 0; then
    buc_log_args "Found ${z_lien_count} lien(s) - removing them"
    local z_lien_names
    z_lien_names=$(rbuh_json_field_capture "depot_destroy_liens_list" '.liens[].name') || buc_die "Failed to extract lien names"
    z_lien_names="${z_lien_names//$'\n'/ }"
    
    for z_lien_name in ${z_lien_names}; do
      if test -n "${z_lien_name}"; then
        buc_log_args "Removing lien: ${z_lien_name}"
        local z_delete_lien_url="${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/liens/${z_lien_name}"
        rbuh_json "DELETE" "${z_delete_lien_url}" "${z_token}" "depot_destroy_lien_delete"
        rbuh_require_ok "Delete lien" "depot_destroy_lien_delete"
      fi
    done
  fi

  buc_step 'Unlink billing account (releases quota immediately)'
  local -r z_billing_unlink_body="${BURD_TEMP_DIR}/rbgp_billing_unlink.json"
  echo '{"billingAccountName":""}' > "${z_billing_unlink_body}" || buc_die "Failed to build billing unlink body"

  local -r z_billing_unlink_url="${RBGC_API_ROOT_CLOUDBILLING}${RBGC_CLOUDBILLING_V1}/projects/${z_project_id}/billingInfo"
  rbuh_json "PUT" "${z_billing_unlink_url}" "${z_token}" "depot_destroy_billing_unlink" "${z_billing_unlink_body}"

  local z_billing_unlink_code
  z_billing_unlink_code=$(rbuh_code_capture "depot_destroy_billing_unlink") || z_billing_unlink_code=""
  if test "${z_billing_unlink_code}" = "200"; then
    buc_log_args "Billing account unlinked - quota released"
  else
    buc_warn "Could not unlink billing (HTTP ${z_billing_unlink_code}) - proceeding with deletion anyway"
  fi

  buc_step 'Delete dual worker pools (if exist)'
  # Delete tether pool
  local -r z_tether_del_id="${z_pool_stem}${RBGC_POOL_SUFFIX_TETHER}"
  local -r z_tether_del_url="${RBGC_API_ROOT_CLOUDBUILD}${RBGC_CLOUDBUILD_V1}/projects/${z_project_id}/locations/${RBRD_GCP_REGION}${RBGC_PATH_WORKER_POOLS}/${z_tether_del_id}"
  rbuh_json "DELETE" "${z_tether_del_url}" "${z_token}" "depot_destroy_pool_tether"
  local z_tether_del_code
  z_tether_del_code=$(rbuh_code_capture "depot_destroy_pool_tether") || z_tether_del_code=""
  case "${z_tether_del_code}" in
    200|204|404) buc_log_args "Tether pool ${z_tether_del_id} cleanup: HTTP ${z_tether_del_code}" ;;
    *) buc_warn "Tether pool cleanup failed: HTTP ${z_tether_del_code} — proceeding" ;;
  esac

  # Delete airgap pool
  local -r z_airgap_del_id="${z_pool_stem}${RBGC_POOL_SUFFIX_AIRGAP}"
  local -r z_airgap_del_url="${RBGC_API_ROOT_CLOUDBUILD}${RBGC_CLOUDBUILD_V1}/projects/${z_project_id}/locations/${RBRD_GCP_REGION}${RBGC_PATH_WORKER_POOLS}/${z_airgap_del_id}"
  rbuh_json "DELETE" "${z_airgap_del_url}" "${z_token}" "depot_destroy_pool_airgap"
  local z_airgap_del_code
  z_airgap_del_code=$(rbuh_code_capture "depot_destroy_pool_airgap") || z_airgap_del_code=""
  case "${z_airgap_del_code}" in
    200|204|404) buc_log_args "Airgap pool ${z_airgap_del_id} cleanup: HTTP ${z_airgap_del_code}" ;;
    *) buc_warn "Airgap pool cleanup failed: HTTP ${z_airgap_del_code} — proceeding" ;;
  esac

  buc_step 'Initiate depot deletion'
  local -r z_delete_url="${RBGC_API_ROOT_CRM}${RBGC_CRM_V3}/projects/${z_project_id}"
  rbuh_json "DELETE" "${z_delete_url}" "${z_token}" "depot_destroy_delete"
  
  local z_delete_response
  z_delete_response=$(rbuh_code_capture "depot_destroy_delete") || buc_die "Failed to get deletion response code"
  
  if test "${z_delete_response}" = "200" || test "${z_delete_response}" = "204"; then
    buc_log_args "Project deletion initiated successfully"
  else
    local z_error_msg
    z_error_msg=$(rbuh_json_field_capture "depot_destroy_delete" '.error.message // "Unknown error"') || z_error_msg="HTTP ${z_delete_response}"
    buc_die "Failed to initiate project deletion: ${z_error_msg}"
  fi

  buc_step 'Verify deletion state transition'
  local -r z_max_attempts=12
  local z_attempt=1
  local z_final_state
  
  while test "${z_attempt}" -le "${z_max_attempts}"; do
    sleep 5
    buc_log_args "Checking deletion state (attempt ${z_attempt}/${z_max_attempts})"
    
    rbuh_json "GET" "${z_project_info_url}" "${z_token}" "depot_destroy_state_check"

    local z_state_check_code
    z_state_check_code=$(rbuh_code_capture "depot_destroy_state_check") || z_state_check_code=""
    if test "${z_state_check_code}" = "200"; then
      z_final_state=$(rbuh_json_field_capture "depot_destroy_state_check" '.state // "UNKNOWN"') || z_final_state="UNKNOWN"

      if test "${z_final_state}" = "DELETE_REQUESTED"; then
        break
      fi
    fi
    
    z_attempt=$((z_attempt + 1))
  done
  
  if test "${z_final_state}" != "DELETE_REQUESTED"; then
    buc_die "Failed to verify deletion state transition. Current state: ${z_final_state}"
  fi

  buc_step 'Update depot tracking'
  zrbgp_depot_list_update || buc_log_args "Warning: Failed to update depot tracking after deletion"

  # Success
  buc_success "Depot ${z_project_id} successfully marked for deletion"
  buc_info "Project Status: DELETE_REQUESTED"
  buc_info "Billing: Unlinked (quota released immediately)"
  buc_info "Grace period: Up to 30 days before permanent removal"
  buc_info "All infrastructure (Mason SA, repository, bucket) will be automatically removed"
}

rbgp_depot_list() {
  zrbgp_sentinel

  buc_doc_brief "List all depot instances and their status"
  buc_doc_shown || return 0

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  buc_step 'Probe depot states and emit per-moniker fact files'
  zrbgp_depot_state_emit "${z_token}"

  buc_step 'Render depot summary'
  local z_total_count=0
  local z_complete_count=0
  local z_delete_requested_count=0

  buc_info ""
  buc_info "=== DEPOT SUMMARY ==="
  printf "%-40s %s\n" "PROJECT_ID" "STATUS"

  # Per-iteration synthesized locals (BCG exception 2)
  local z_fact_path=""
  local z_basename=""
  local z_moniker=""
  local z_project_id=""
  local z_project_fact_path=""
  local z_state=""
  local z_dir_path=""

  # Walk emitted depot fact files; layout is <cloud_prefix>/<moniker>.depot,
  # stem is the moniker, content is the state. The sidecar depot-project fact
  # file (same parent dir) carries the canonical project_id.
  shopt -s nullglob
  for z_fact_path in "${BURD_OUTPUT_DIR}"/*/*."${RBCC_fact_ext_depot}"; do
    z_basename="${z_fact_path##*/}"
    z_moniker="${z_basename%."${RBCC_fact_ext_depot}"}"
    z_dir_path="${z_fact_path%/*}"
    z_project_fact_path="${z_dir_path}/${z_moniker}.${RBCC_fact_ext_depot_project}"
    z_state=$(<"${z_fact_path}")
    test -n "${z_state}" || buc_die "Empty state in fact file: ${z_fact_path}"
    test -f "${z_project_fact_path}" || buc_die "Missing depot-project fact file: ${z_project_fact_path}"
    z_project_id=$(<"${z_project_fact_path}")
    test -n "${z_project_id}" || buc_die "Empty project_id in fact file: ${z_project_fact_path}"

    printf "%-40s %s\n" "${z_project_id}" "${z_state}"
    z_total_count=$((z_total_count + 1))
    case "${z_state}" in
      "${RBGP_DEPOT_STATE_COMPLETE}")          z_complete_count=$((z_complete_count + 1)) ;;
      "${RBGP_DEPOT_STATE_DELETE_REQUESTED}")  z_delete_requested_count=$((z_delete_requested_count + 1)) ;;
    esac
  done
  shopt -u nullglob

  if test "${z_total_count}" -eq 0; then
    buc_info "No depot projects found"
    return 0
  fi

  buc_info ""
  buc_info "=== SUMMARY ==="
  buc_info "Total depots:     ${z_total_count}"
  buc_info "Complete:         ${z_complete_count}"
  buc_info "Delete-requested: ${z_delete_requested_count}"
}

rbgp_depot_info() {
  zrbgp_sentinel

  buc_doc_brief "Run egress posture checks against the live depot's tether and airgap worker pools"
  buc_doc_shown || return 0

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  local -r z_mason_email="${RBCC_account_unhewn_mason}-${RBRD_DEPOT_MONIKER}@${RBDC_DEPOT_PROJECT_ID}.${RBGC_SA_EMAIL_DOMAIN}"
  local -r z_tether_id="${RBDC_GCB_POOL_STEM}${RBGC_POOL_SUFFIX_TETHER}"
  local -r z_airgap_id="${RBDC_GCB_POOL_STEM}${RBGC_POOL_SUFFIX_AIRGAP}"

  local -r z_tether_posture_check="${BURD_TEMP_DIR}/rbgp_tether_posture_check.sh"
  local -r z_airgap_posture_check="${BURD_TEMP_DIR}/rbgp_airgap_posture_check.sh"

  buc_step 'Write posture-check scripts'
  zrbgp_write_posture_check tether "${z_tether_posture_check}"
  zrbgp_write_posture_check airgap "${z_airgap_posture_check}"

  buc_step 'Probe tether pool posture'
  zrbgp_pool_posture_submit "${z_token}" "tether" "${z_tether_id}" "${z_mason_email}" "${z_tether_posture_check}"

  buc_step 'Probe airgap pool posture'
  zrbgp_pool_posture_submit "${z_token}" "airgap" "${z_airgap_id}" "${z_mason_email}" "${z_airgap_posture_check}"

  buc_success 'Posture checks complete'
}

# Require one (role, member) binding present in a captured IAM policy, or die
# naming the absent piece. Read-only — mutates nothing. See RBSDC.
zrbgp_recognosce_require_binding() {
  zrbgp_sentinel

  local -r z_infix="${1:-}"
  local -r z_role="${2:-}"
  local -r z_member="${3:-}"
  local -r z_where="${4:-}"

  test -n "${z_infix}"  || buc_die "zrbgp_recognosce_require_binding: infix required"
  test -n "${z_role}"   || buc_die "zrbgp_recognosce_require_binding: role required"
  test -n "${z_member}" || buc_die "zrbgp_recognosce_require_binding: member required"

  local z_hit=""
  z_hit=$(rbuh_json_field_capture "${z_infix}" \
    ".bindings[]? | select(.role==\"${z_role}\") | .members[]? | select(.==\"${z_member}\")") || z_hit=""
  test -n "${z_hit}" \
    || buc_die "recognosce: founding incomplete — ${z_member} missing ${z_role} on ${z_where}"
}

# Recognosce the depot founding (RBSDC): a read-only inspection that confirms,
# against live GCP, that the three mantle SAs exist and carry their full
# capability-sets and that the Artifact Registry Data-Access audit config is in
# force. Exit 0 means, and only means, the founding is whole; any absent piece is
# fatal and named. The expected bindings required below mirror the static grant
# lists rbgw_grant_{governor,director,retriever}_capabilities apply at levy — a
# change to any capability-set's roles must change the matching require here.
rbgp_depot_recognosce() {
  zrbgp_sentinel

  buc_doc_brief "Recognosce the depot founding — confirm the three mantle SAs, their capability-sets, and the Artifact Registry Data-Access audit config against live GCP (read-only)"
  buc_doc_shown || return 0

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  local -r z_gov_email="${RBCC_account_mantle_governor}@${RBGD_SA_EMAIL_FULL}"
  local -r z_dir_email="${RBCC_account_mantle_director}@${RBGD_SA_EMAIL_FULL}"
  local -r z_ret_email="${RBCC_account_mantle_retriever}@${RBGD_SA_EMAIL_FULL}"

  buc_step 'Confirm the three mantle service accounts exist'
  rbuh_json "GET" "${RBGD_API_BASE_IAM_PROJECT}/serviceAccounts/${z_gov_email}" "${z_token}" "recognosce_mantle_governor"
  rbuh_require_ok "recognosce: governor mantle SA (${z_gov_email})" "recognosce_mantle_governor"
  rbuh_json "GET" "${RBGD_API_BASE_IAM_PROJECT}/serviceAccounts/${z_dir_email}" "${z_token}" "recognosce_mantle_director"
  rbuh_require_ok "recognosce: director mantle SA (${z_dir_email})" "recognosce_mantle_director"
  rbuh_json "GET" "${RBGD_API_BASE_IAM_PROJECT}/serviceAccounts/${z_ret_email}" "${z_token}" "recognosce_mantle_retriever"
  rbuh_require_ok "recognosce: retriever mantle SA (${z_ret_email})" "recognosce_mantle_retriever"

  buc_step 'Read project IAM policy (v3) and require project-scoped capability-set bindings'
  local -r z_v3body="${BURD_TEMP_DIR}/rbgp_recognosce_v3body.json"
  printf '%s\n' '{"options":{"requestedPolicyVersion":3}}' > "${z_v3body}" \
    || buc_die "Failed to write recognosce getIamPolicy body"

  rbuh_json "POST" "${RBGD_API_CRM_GET_IAM_POLICY}" "${z_token}" "recognosce_project" "${z_v3body}"
  rbuh_require_ok "recognosce: read project IAM policy" "recognosce_project"

  zrbgp_recognosce_require_binding "recognosce_project" "roles/owner" \
    "serviceAccount:${z_gov_email}" "project (governor capability-set)"
  zrbgp_recognosce_require_binding "recognosce_project" "${RBGC_ROLE_ARTIFACTREGISTRY_READER}" \
    "serviceAccount:${z_ret_email}" "project (retriever capability-set)"
  zrbgp_recognosce_require_binding "recognosce_project" "${RBGC_ROLE_CONTAINERANALYSIS_OCCURRENCES_VIEWER}" \
    "serviceAccount:${z_ret_email}" "project (retriever capability-set)"
  zrbgp_recognosce_require_binding "recognosce_project" "${RBGC_ROLE_CLOUDBUILD_BUILDS_EDITOR}" \
    "serviceAccount:${z_dir_email}" "project (director capability-set)"
  zrbgp_recognosce_require_binding "recognosce_project" "roles/viewer" \
    "serviceAccount:${z_dir_email}" "project (director capability-set)"
  zrbgp_recognosce_require_binding "recognosce_project" "roles/cloudbuild.workerPoolUser" \
    "serviceAccount:${z_dir_email}" "project (director capability-set)"

  buc_step 'Require Artifact Registry Data-Access audit config'
  local z_audit_admin=""
  local z_audit_data=""
  z_audit_admin=$(rbuh_json_field_capture "recognosce_project" \
    '.auditConfigs[]? | select(.service=="artifactregistry.googleapis.com") | .auditLogConfigs[]? | select(.logType=="ADMIN_READ") | .logType') || z_audit_admin=""
  test -n "${z_audit_admin}" \
    || buc_die "recognosce: founding incomplete — artifactregistry.googleapis.com audit config missing ADMIN_READ"
  z_audit_data=$(rbuh_json_field_capture "recognosce_project" \
    '.auditConfigs[]? | select(.service=="artifactregistry.googleapis.com") | .auditLogConfigs[]? | select(.logType=="DATA_READ") | .logType') || z_audit_data=""
  test -n "${z_audit_data}" \
    || buc_die "recognosce: founding incomplete — artifactregistry.googleapis.com audit config missing DATA_READ"

  buc_step 'Read GAR repository IAM policy and require director repoAdmin'
  local -r z_repo_resource="projects/${RBDC_DEPOT_PROJECT_ID}/locations/${RBRD_GCP_REGION}/repositories/${RBDC_GAR_REPOSITORY}"
  local -r z_repo_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_repo_resource}:getIamPolicy?options.requestedPolicyVersion=3"
  rbuh_json "GET" "${z_repo_url}" "${z_token}" "recognosce_repo"
  rbuh_require_ok "recognosce: read GAR repository IAM policy" "recognosce_repo"
  zrbgp_recognosce_require_binding "recognosce_repo" "roles/artifactregistry.repoAdmin" \
    "serviceAccount:${z_dir_email}" "GAR repository (director capability-set)"

  buc_step 'Read Mason SA IAM policy and require director actAs on Mason'
  rbuh_json "POST" "${RBGD_API_BASE_IAM_PROJECT}/serviceAccounts/${RBGD_MASON_EMAIL}:getIamPolicy" \
    "${z_token}" "recognosce_mason_policy" "${z_v3body}"
  rbuh_require_ok "recognosce: read Mason SA IAM policy" "recognosce_mason_policy"
  zrbgp_recognosce_require_binding "recognosce_mason_policy" "roles/iam.serviceAccountUser" \
    "serviceAccount:${z_dir_email}" "Mason SA (director actAs)"

  buc_step 'Read director SA IAM policy and require director self-actAs'
  rbuh_json "POST" "${RBGD_API_BASE_IAM_PROJECT}/serviceAccounts/${z_dir_email}:getIamPolicy" \
    "${z_token}" "recognosce_director_policy" "${z_v3body}"
  rbuh_require_ok "recognosce: read director SA IAM policy" "recognosce_director_policy"
  zrbgp_recognosce_require_binding "recognosce_director_policy" "roles/iam.serviceAccountUser" \
    "serviceAccount:${z_dir_email}" "director SA (self-actAs)"

  buc_success "Depot founding recognosced whole: three mantles, capability-sets, and AR Data-Access audit config confirmed against live GCP"
}

# Polity admission verbs (rbgp_brevet / rbgp_unseat / rbgp_attaint /
# rbgp_rehearse) — the operator-facing federation admission surface under the
# rbw-p launcher family. Each is a thin idempotent composition over the terrier
# muniment sub-ops (rbgft_) and the two IAM binding types: tokenCreator on the
# mantle SA (a principal:// member) and serviceUsageConsumer on the depot project
# (spike F2). Intent-first ordering: the muniment write precedes every binding.
#
# The verbs run as a donned governor mantle (rba_avow then rba_don_capture
# governor — this pace is that accessor's first consumer). The token-agnostic
# *_core helpers carry the composition so the levy founding exception (the payor
# breveting the first governor) and the interim proof can drive the same logic
# payor-credentialed. Contract: the RBSP* polity-verb specs and the paddock
# Verbs-and-orderings table.
#
# Bucket grain: the manor terrier is payor-project grain (RBGP_TERRIER_BUCKET);
# a donned governor reaches it via the manor's payor-project id, which the MVP
# draws from the enforced payor regime (a multi-operator successor would source
# the manor id from federation/depot config instead).

# Map a mantle name (governor|director|retriever) to its mantle SA email in the
# current depot. Dies on an unknown mantle — the only accepted set anywhere.
zrbgp_mantle_sa_email_capture() {
  zrbgp_sentinel
  local -r z_mantle="${1:-}"
  local z_account=""
  case "${z_mantle}" in
    governor)  z_account="${RBCC_account_mantle_governor}"  ;;
    director)  z_account="${RBCC_account_mantle_director}"  ;;
    retriever) z_account="${RBCC_account_mantle_retriever}" ;;
    *) return 1 ;;
  esac
  printf '%s@%s' "${z_account}" "${RBGD_SA_EMAIL_FULL}"
}

# Compose the workforce federated principal member for a subject — the grantable
# identity in every depot under the manor (single home for the principal:// form).
zrbgp_principal_member_capture() {
  zrbgp_sentinel
  local -r z_subject="${1:-}"
  test -n "${z_subject}" || return 1
  printf 'principal://iam.googleapis.com/locations/global/workforcePools/%s/subject/%s' \
    "${RBRW_WORKFORCE_POOL_ID}" "${z_subject}"
}

# brevet core — token-agnostic admission composition. Ensures the muniment first,
# then idempotently ensures both bindings: tokenCreator on the mantle SA and
# serviceUsageConsumer on the depot project. First-vs-further admission differs
# only in that the depot-scoped binding is already present on a further mantle —
# the idempotent ensure absorbs it. Donned-governor verb and payor founding/proof
# paths share this.
zrbgp_brevet_core() {
  zrbgp_sentinel

  local -r z_token="${1:-}"
  local -r z_mantle="${2:-}"
  local -r z_subject="${3:-}"

  test -n "${z_token}"   || buc_die "Token required"
  test -n "${z_mantle}"  || buc_die "Mantle required"
  test -n "${z_subject}" || buc_die "Subject required"

  local -r z_bucket="${RBGP_TERRIER_BUCKET}"
  local -r z_depot="${RBDC_DEPOT_PROJECT_ID}"
  local z_mantle_email
  z_mantle_email=$(zrbgp_mantle_sa_email_capture "${z_mantle}") \
    || buc_die "Unknown mantle '${z_mantle}' (expected governor | director | retriever)"
  local z_principal
  z_principal=$(zrbgp_principal_member_capture "${z_subject}") || buc_die "Failed to compose principal member"

  buc_step "Brevet ${z_subject} onto the ${z_mantle} mantle"

  buc_log_args 'Intent-first: write the muniment before any binding'
  rbgft_engross "${z_token}" "${z_bucket}" "${z_depot}" "${z_mantle}" "${z_subject}" >/dev/null

  buc_log_args 'Ensure tokenCreator on the mantle SA (the don grant)'
  rbgi_add_sa_principal_iam_role "${z_token}" "${z_mantle_email}" "${z_principal}" \
    "${RBGC_ROLE_IAM_SERVICE_ACCOUNT_TOKEN_CREATOR}"

  buc_log_args 'Ensure serviceUsageConsumer on the depot project (Leg-3 quota project)'
  rbgi_add_project_iam_role "${z_token}" "Brevet serviceUsageConsumer for ${z_subject}" \
    "projects/${z_depot}" "${RBGC_ROLE_SERVICEUSAGE_SERVICE_USAGE_CONSUMER}" \
    "${z_principal}" "polity_brevet_suc"

  buc_success "Breveted ${z_subject} onto the ${z_mantle} mantle"
}

# unseat core — token-agnostic withdrawal of one mantle. Withdraws the muniment,
# then removes only the tokenCreator binding; the depot-scoped serviceUsageConsumer
# stays in place — a citizen unseated of every mantle is suspended, not erased, and
# cheap to re-brevet. attaint alone sweeps the depot-scoped binding.
zrbgp_unseat_core() {
  zrbgp_sentinel

  local -r z_token="${1:-}"
  local -r z_mantle="${2:-}"
  local -r z_subject="${3:-}"

  test -n "${z_token}"   || buc_die "Token required"
  test -n "${z_mantle}"  || buc_die "Mantle required"
  test -n "${z_subject}" || buc_die "Subject required"

  local -r z_bucket="${RBGP_TERRIER_BUCKET}"
  local -r z_depot="${RBDC_DEPOT_PROJECT_ID}"
  local z_mantle_email
  z_mantle_email=$(zrbgp_mantle_sa_email_capture "${z_mantle}") \
    || buc_die "Unknown mantle '${z_mantle}' (expected governor | director | retriever)"
  local z_principal
  z_principal=$(zrbgp_principal_member_capture "${z_subject}") || buc_die "Failed to compose principal member"

  buc_step "Unseat ${z_subject} from the ${z_mantle} mantle"

  buc_log_args 'Intent-first: withdraw the muniment before removing the binding'
  rbgft_expunge "${z_token}" "${z_bucket}" "${z_depot}" "${z_mantle}" "${z_subject}" >/dev/null

  buc_log_args 'Remove tokenCreator on the mantle SA (depot-scoped binding stays: suspension)'
  rbgi_revoke_sa_principal_member "${z_token}" "${z_mantle_email}" "${z_principal}" \
    "${RBGC_ROLE_IAM_SERVICE_ACCOUNT_TOKEN_CREATOR}"

  buc_success "Unseated ${z_subject} from the ${z_mantle} mantle"
}

# attaint core — token-agnostic whole-person expulsion from the depot. Unseats the
# subject from every mantle (idempotent — a mantle not held is a no-op), then
# sweeps the depot-scoped serviceUsageConsumer binding unseat leaves behind, then
# notes the deregistration. A partial teardown lands as visible surplus, never a
# resurrection. The IdP-side identity removal is the IdP admin's, out of scope here.
zrbgp_attaint_core() {
  zrbgp_sentinel

  local -r z_token="${1:-}"
  local -r z_subject="${2:-}"

  test -n "${z_token}"   || buc_die "Token required"
  test -n "${z_subject}" || buc_die "Subject required"

  local -r z_depot="${RBDC_DEPOT_PROJECT_ID}"
  local z_principal
  z_principal=$(zrbgp_principal_member_capture "${z_subject}") || buc_die "Failed to compose principal member"

  buc_step "Attaint ${z_subject} — whole-person expulsion from ${z_depot}"

  buc_log_args 'Unseat every mantle (idempotent — an unheld mantle is a no-op)'
  local z_mantle=""
  for z_mantle in governor director retriever; do
    zrbgp_unseat_core "${z_token}" "${z_mantle}" "${z_subject}"
  done

  buc_log_args 'Sweep the depot-scoped serviceUsageConsumer — attaint alone does this'
  rbgi_revoke_project_member "${z_token}" "Attaint sweep serviceUsageConsumer for ${z_subject}" \
    "projects/${z_depot}" "${RBGC_ROLE_SERVICEUSAGE_SERVICE_USAGE_CONSUMER}" \
    "${z_principal}" "polity_attaint_suc"

  buc_info "Deregistered ${z_subject} from ${z_depot}; IdP-side identity removal is the IdP admin's"
  buc_success "Attainted ${z_subject} from ${z_depot}"
}

# rbgp_gird <subject> — the founding exception: the payor seats the FIRST governor of this
# depot, the one admission gesture outside governor wielding. A fresh-levied depot carries
# its mantle SAs but no admitted citizen, so no governor yet exists to brevet one; the
# payor's own OAuth credential drives the shared admission core (zrbgp_brevet_core) instead
# of a donned governor token. Governor-only by construction (no mantle parameter) — once a
# governor is girded, every further admission flows through governor-wielded rbgp_brevet.
# Contract: RBSPG.
rbgp_gird() {
  zrbgp_sentinel

  local -r z_subject="${BUZ_FOLIO:-}"

  buc_doc_brief "Gird the first governor — the payor seats a citizen as this depot's founding governor (payor-wielded founding admission)"
  buc_doc_param "subject" "The citizen's federated workforce subject (the IdP-asserted identity) to seat as the first governor"
  buc_doc_shown || return 0

  test -n "${z_subject}" || buc_die "Subject required as the first argument"

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  zrbgp_brevet_core "${z_token}" "governor" "${z_subject}"
}

# rbgp_brevet <subject> <mantle> — admit an avowed citizen onto a mantle in this
# depot. Wields the governor mantle.
rbgp_brevet() {
  zrbgp_sentinel

  local -r z_subject="${BUZ_FOLIO:-}"
  local -r z_mantle="${1:-}"

  buc_doc_brief "Brevet a citizen onto a mantle in this depot (governor-wielded admission)"
  buc_doc_param "subject" "The citizen's federated workforce subject (the IdP-asserted identity)"
  buc_doc_param "mantle"  "Which mantle to admit onto: governor | director | retriever"
  buc_doc_shown || return 0

  test -n "${z_subject}" || buc_die "Subject required as the first argument"
  test -n "${z_mantle}"  || buc_die "Mantle required as the second argument (governor | director | retriever)"

  # Don the governor mantle — avow runs outside the capture (its device flow
  # needs the terminal); only the mint is captured.
  rba_avow
  local z_token
  z_token=$(rba_don_capture "${RBCC_mantle_governor}") \
    || buc_die "Failed to don the governor mantle — avow if the sitting lapsed, or brevet this identity onto the governor mantle if admission is denied"

  zrbgp_brevet_core "${z_token}" "${z_mantle}" "${z_subject}"
}

# rbgp_unseat <subject> <mantle> — remove a citizen from one mantle (suspension —
# the depot-scoped binding survives). Wields the governor mantle.
rbgp_unseat() {
  zrbgp_sentinel

  local -r z_subject="${BUZ_FOLIO:-}"
  local -r z_mantle="${1:-}"

  buc_doc_brief "Unseat a citizen from one mantle in this depot (suspension, not erasure)"
  buc_doc_param "subject" "The citizen's federated workforce subject"
  buc_doc_param "mantle"  "Which mantle to remove: governor | director | retriever"
  buc_doc_shown || return 0

  test -n "${z_subject}" || buc_die "Subject required as the first argument"
  test -n "${z_mantle}"  || buc_die "Mantle required as the second argument (governor | director | retriever)"

  rba_avow
  local z_token
  z_token=$(rba_don_capture "${RBCC_mantle_governor}") \
    || buc_die "Failed to don the governor mantle — avow if the sitting lapsed, or brevet this identity onto the governor mantle if admission is denied"

  zrbgp_unseat_core "${z_token}" "${z_mantle}" "${z_subject}"
}

# rbgp_attaint <subject> — expel a citizen wholly from this depot (every mantle,
# then sweep the depot-scoped binding). Wields the governor mantle.
rbgp_attaint() {
  zrbgp_sentinel

  local -r z_subject="${BUZ_FOLIO:-}"

  buc_doc_brief "Attaint a citizen — whole-person expulsion from this depot"
  buc_doc_param "subject" "The citizen's federated workforce subject"
  buc_doc_shown || return 0

  test -n "${z_subject}" || buc_die "Subject required as the first argument"

  rba_avow
  local z_token
  z_token=$(rba_don_capture "${RBCC_mantle_governor}") \
    || buc_die "Failed to don the governor mantle — avow if the sitting lapsed, or brevet this identity onto the governor mantle if admission is denied"

  zrbgp_attaint_core "${z_token}" "${z_subject}"
}

# rbgp_rehearse — recount the manor-wide muniment roll (pure read, mutates
# nothing). Wields the governor mantle (bucket-level read, manor-wide).
rbgp_rehearse() {
  zrbgp_sentinel

  buc_doc_brief "Rehearse the manor terrier — recount every muniment (who holds what), read-only"
  buc_doc_shown || return 0

  rba_avow
  local z_token
  z_token=$(rba_don_capture "${RBCC_mantle_governor}") \
    || buc_die "Failed to don the governor mantle — avow if the sitting lapsed, or brevet this identity onto the governor mantle if admission is denied"

  buc_step 'Rehearse the manor terrier (manor-wide muniment roll)'
  local z_muniments
  z_muniments=$(rbgft_peruse_manor "${z_token}" "${RBGP_TERRIER_BUCKET}") \
    || buc_die "Failed to rehearse the manor terrier"

  if test -z "${z_muniments}"; then
    buc_info "No muniments — the manor terrier holds no standing citizens"
  else
    printf '%s\n' "${z_muniments}"
  fi
}

# rbgp_attribution_trail — print the depot's Artifact Registry Data-Access
# attribution trail: the recent audit entries that name WHO acted. Payor-
# credentialed because Cloud Logging Data-Access entries are private-read
# (roles/logging.privateLogViewer) — the mantles deliberately cannot read them.
# Per entry it surfaces the acting principalEmail (the mantle SA) and the
# serviceAccountDelegationInfo[].principalSubject (the human federate, by
# immutable IdP claim — spike V3). Both hops are shown so the spike's quirk is
# visible on screen: the iamcredentials mint hop names the SA with NO subject
# (always-on, correct — never a failure); the artifactregistry use hop carries
# the subject. MVP dumps the most recent entries; time-window and principal
# filters are deferred (docket: someday parameterize).
rbgp_attribution_trail() {
  zrbgp_sentinel

  buc_doc_brief "Print the depot's AR Data-Access attribution trail — recent audit entries naming the acting mantle SA and the human federate subject"
  buc_doc_shown || return 0

  buc_step 'Authenticate as Payor'
  local z_token
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  local -r z_depot="${RBDC_DEPOT_PROJECT_ID}"
  test -n "${z_depot}" || buc_die "RBDC_DEPOT_PROJECT_ID is empty — set RBRD_CLOUD_PREFIX and RBRD_DEPOT_MONIKER in rbrd.env"

  buc_step "Read the Data-Access audit trail on ${z_depot}"
  local -r z_log_name="projects/${z_depot}/logs/${RBGC_AUDIT_LOG_DATA_ACCESS}"
  local -r z_body_file="${BURD_TEMP_DIR}/rbgp_attribution_body.json"
  jq -n                                        \
     --arg proj   "projects/${z_depot}"        \
     --arg filter "logName=\"${z_log_name}\""  \
     '{resourceNames: [$proj], filter: $filter, orderBy: "timestamp desc", pageSize: 25}' \
     > "${z_body_file}" || buc_die "Failed to build entries:list request body"

  local -r z_url="${RBGC_API_ROOT_LOGGING}${RBGC_LOGGING_V2}${RBGC_LOGGING_ENTRIES_LIST_SUFFIX}"
  rbuh_json "POST" "${z_url}" "${z_token}" "attribution_list" "${z_body_file}"

  local z_code
  z_code=$(rbuh_code_capture "attribution_list") || buc_die "Failed to read entries:list HTTP code"
  case "${z_code}" in
    200) : ;;
    403)
      buc_die "Attribution read denied (HTTP 403): the Payor lacks roles/logging.privateLogViewer on ${z_depot}. Data-Access audit entries are private — grant the Payor that role on the depot, then re-run."
      ;;
    *)
      local z_err
      z_err=$(rbge_error_message_capture "attribution_list") || z_err="(no error message)"
      buc_die "Attribution read failed (HTTP ${z_code}): ${z_err}"
      ;;
  esac

  local z_count
  z_count=$(rbuh_json_field_capture "attribution_list" '(.entries // []) | length') \
    || buc_die "Failed to count attribution entries"

  test "${z_count}" -gt 0 || {
    buyy_tt_yawp "${RBZ_CHECK_MANTLE}" "" " retriever"; local -r z_am_tt="${z_buym_yelp}"
    buc_warn "No Data-Access audit entries on ${z_depot} yet. Has a mantle made an Artifact Registry call? Run ${z_am_tt} (avow + don + AR call) first, allow a few seconds for log ingestion, then re-run."
    return 0
  }

  buc_step "Attribution trail — ${z_count} most-recent Data-Access entries (use hop carries the federate subject; mint hop carries none, by design)"

  # Render to a temp file (BCG: external command output via temp file, never
  # captured through $()), then emit each line through buc. Columns: timestamp,
  # service, method, acting principalEmail (the mantle SA), and the delegation
  # principalSubject. The rightmost column has three honest cases: the human
  # federate on a federated use hop (delegation present); "(mint hop …)" on the
  # always-on iamcredentials GenerateAccessToken, which names only the SA by
  # design; and "(direct SA …)" on a use hop made by a non-impersonated SA (e.g.
  # a keyfile credential), which carries no delegation and so no human — the very
  # gap federation closes. Only the first is the attribution this pace proves.
  local -r z_resp_file="${ZRBUH_PREFIX}attribution_list${ZRBUH_POSTFIX_JSON}"
  local -r z_render_file="${BURD_TEMP_DIR}/rbgp_attribution_render.txt"
  jq -r '
    .entries[]?
    | (.protoPayload.serviceName // "-") as $svc
    | ( (.protoPayload.authenticationInfo.serviceAccountDelegationInfo // [])
          | map(.principalSubject // empty) | join(",") ) as $subj
    | [ (.timestamp // "-"),
        $svc,
        ((.protoPayload.methodName // "-") | sub(".*\\."; "")),
        (.protoPayload.authenticationInfo.principalEmail // "-"),
        ( if   $subj != ""                            then $subj
          elif $svc == "iamcredentials.googleapis.com" then "(mint hop — names the SA, no subject by design)"
          else                                              "(direct SA — no delegation, no human)" end )
      ]
    | @tsv
  ' "${z_resp_file}" > "${z_render_file}" \
    || buc_die "Failed to render attribution entries"

  local z_line=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    buc_info "${z_line}"
  done < "${z_render_file}"

  buc_success "Attribution trail rendered for ${z_depot}: find the freehold subject (${RBPC_freehold_subject:-<rbpc not sourced>}) in the rightmost column on artifactregistry rows — that is the human, by immutable IdP claim"
}

# eof

