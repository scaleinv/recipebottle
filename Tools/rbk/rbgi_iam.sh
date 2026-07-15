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
# Recipe Bottle Google IAM - Implementation

# ----------------------------------------------------------------------
# Operational Invariants (RBGI is single writer; 409 is fatal)
#
# - Single admin actor: All RBGI operations are executed by a single admin
#   identity. There are no concurrent writers in the same project.
# - Pristine-state expectation: RBGI init/creation flows assume the project
#   is pristine for the resources they manage. If a resource "already exists"
#   (HTTP 409), that's treated as state drift or prior manual activity.
# - Policy: All HTTP 409 Conflict responses are fatal (buc_die). We do not
#   treat 409 as idempotent success anywhere in RBGI.
#   If you see a 409, resolve state drift first (destroy/reset), then rerun.
# - Note: 409 has two distinct meanings in RBGI operations:
#   (a) Resource creation: "already exists" — state drift or prior manual activity.
#   (b) setIamPolicy: "ABORTED" — etag mismatch from concurrent policy change.
#   Both are fatal under single-writer invariant. Google-internal auto-provisioning
#   can trigger (b) outside our control; the 409 surfaces a real concurrency issue.
# ----------------------------------------------------------------------

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBGI_SOURCED:-}" || buc_die "Module rbgi multiply sourced - check sourcing hierarchy"
ZRBGI_SOURCED=1

######################################################################
# Internal Functions (zrbgi_*)

zrbgi_kindle() {
  test -z "${ZRBGI_KINDLED:-}" || buc_die "Module rbgi already kindled"

  # Validate dependencies
  buv_dir_exists "${BURD_TEMP_DIR}"

  # Ensure dependencies are kindled
  zrbgc_sentinel
  zrbuh_sentinel
  zrbge_sentinel

  # Module prefix for temp files
  readonly ZRBGI_PREFIX="${BURD_TEMP_DIR}/rbgi_"
  readonly ZRBGI_EMPTY_JSON="${ZRBGI_PREFIX}empty.json"
  printf '{}' > "${ZRBGI_EMPTY_JSON}"

  readonly ZRBGI_VERSION3_BODY="${ZRBGI_PREFIX}version3_body.json"
  printf '%s\n' '{"options":{"requestedPolicyVersion":3}}' > "${ZRBGI_VERSION3_BODY}"

  # Infix values for IAM operations
  readonly ZRBGI_INFIX_ROLE="role"
  readonly ZRBGI_INFIX_ROLE_SET="role_set"
  readonly ZRBGI_INFIX_REPO_ROLE="repo_role"
  readonly ZRBGI_INFIX_REPO_ROLE_SET="repo_role_set"
  readonly ZRBGI_INFIX_SA_IAM_VERIFY="sa_iamverify"
  readonly ZRBGI_INFIX_SA_BINDING_POLL="sa_binding_poll"
  readonly ZRBGI_INFIX_BUCKET_IAM="bucket_iam"
  readonly ZRBGI_INFIX_BUCKET_IAM_SET="bucket_iam_set"
  readonly ZRBGI_INFIX_MF_IAM="managed_folder_iam"
  readonly ZRBGI_INFIX_MF_IAM_SET="managed_folder_iam_set"
  readonly ZRBGI_INFIX_SECRET_IAM="secret_iam"
  readonly ZRBGI_INFIX_SECRET_IAM_SET="secret_iam_set"

  # Revoke (member removal) infixes — parallel the add-side SA/repo infixes so a
  # grant and a revoke response capture never collide in a single enrobe+defrock run.
  readonly ZRBGI_INFIX_SA_REVOKE="sa_revoke"
  readonly ZRBGI_INFIX_SA_REVOKE_SET="sa_revoke_set"
  readonly ZRBGI_INFIX_REPO_REVOKE="repo_revoke"
  readonly ZRBGI_INFIX_REPO_REVOKE_SET="repo_revoke_set"

  # Principal-member SA-binding infixes — the federated workforce principal
  # (principal://) variants the polity admission verbs use. Distinct from the
  # serviceAccount-member SA infixes so a brevet (add) and an unseat (revoke)
  # response capture never collide in one process.
  readonly ZRBGI_INFIX_SA_PRIN_VERIFY="sa_prin_iamverify"
  readonly ZRBGI_INFIX_SA_PRIN_ROLE="sa_prin_role"
  readonly ZRBGI_INFIX_SA_PRIN_ROLE_SET="sa_prin_role_set"
  readonly ZRBGI_INFIX_SA_PRIN_REVOKE="sa_prin_revoke"
  readonly ZRBGI_INFIX_SA_PRIN_REVOKE_SET="sa_prin_revoke_set"

  readonly ZRBGI_POSTFIX_JSON="_i_resp.json"

  readonly ZRBGI_KINDLED=1
}

zrbgi_sentinel() {
  test "${ZRBGI_KINDLED:-}" = "1" || buc_die "Module rbgi not kindled - call zrbgi_kindle first"
}

# Classify an HTTP response against a caller-supplied tolerance list.
# Each tolerance is a (code, body-glob) pair passed as two positional args
# after the infix and code. An empty body-glob matches any response body
# for that code — short-circuits without loading the error message.
#
# Three propagation classes are encoded as tolerance pairs:
#   (400, "*does not exist*") — forward member-visibility lag
#   (400, "*is not deleted*") — backward member-visibility lag
#   (403, "")                 — caller-recently-empowered (resource-scope cache lag)
#
# Project-scope sites declare only the two 400 patterns; resource-scope sites
# (AR repo, SA, bucket, secret) add the 403 pair. Time-bound on 403 is the
# discriminator: real propagation succeeds within budget, real denial waits
# the budget and fails cleanly.
#
# Returns 0 (true) if response matches any tolerance pair, 1 otherwise.
zrbgi_propagation_error_predicate() {
  local -r z_infix="${1}"
  local -r z_code="${2}"
  shift 2

  local z_err_msg=""
  local z_err_loaded=0
  local z_tol_code=""
  local z_tol_glob=""

  while test "$#" -ge 2; do
    z_tol_code="${1}"
    z_tol_glob="${2}"
    shift 2

    test "${z_code}" = "${z_tol_code}" || continue

    test -n "${z_tol_glob}" || return 0

    if test "${z_err_loaded}" = "0"; then
      z_err_msg=$(rbge_error_message_capture "${z_infix}") || z_err_msg=""
      z_err_loaded=1
    fi

    case "${z_err_msg}" in
      ${z_tol_glob}) return 0 ;;
    esac
  done

  return 1
}

######################################################################
# External Functions (rbgi_*)

# Add a project-scoped IAM role binding with optimistic concurrency and strong read-back.
rbgi_add_project_iam_role() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_label="${2:-}"
  local -r z_resource="${3:-}"  # resource_base: Base resource URL
  local -r z_role="${4:-}"
  local -r z_member="${5:-}"
  local -r z_parent_infix="${6:-}"

  test -n "${z_token}" || buc_die "Token required"
  buc_log_args "Using admin token (value not logged)"

  local -r z_resource_path="${z_resource#/}"  # strip leading slash if present
  local -r z_base="${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/${z_resource_path}"
  local -r z_get_url="${z_base}${RBGC_CRM_GET_IAM_POLICY_SUFFIX}"
  local -r z_set_url="${z_base}${RBGC_CRM_SET_IAM_POLICY_SUFFIX}"

  test -n "${z_resource}" || buc_die "resource required"
  test -n "${z_role}"     || buc_die "role required"
  test -n "${z_member}"   || buc_die "member required"

  buc_log_args "${z_label}: add ${z_member} to ${z_role}"

  # Propagation retry — project-scope tolerance: forward/backward
  # member-visibility (400 patterns). Class C (403 resource-scope cache lag)
  # does not apply at project scope.
  local -ra z_tolerance=(
    "400" "*does not exist*"
    "400" "*is not deleted*"
  )
  local z_prop_delay=${RBGC_PROPAGATION_INITIAL_DELAY_SEC}
  local z_prop_elapsed=0
  local -r z_prop_deadline=${RBGC_PROPAGATION_DEADLINE_SEC}
  local z_prop_attempt=0
  local z_prop_succeeded=0

  while :; do
    z_prop_attempt=$((z_prop_attempt + 1))

    buc_log_args "1) GET policy (v3) [attempt ${z_prop_attempt}]"
    buc_log_args "GET_POLICY_URL_DEBUG z_resource:${z_resource} z_get_url:${z_get_url}"
    local z_get_body="${ZRBGI_PREFIX}${z_parent_infix}_get_body.json"
    local z_get_infix="${z_parent_infix}-get-${z_prop_elapsed}s"
    printf '%s\n' '{"options":{"requestedPolicyVersion":3}}' > "${z_get_body}"
    rbuh_json "POST" "${z_get_url}" "${z_token}" "${z_get_infix}" "${z_get_body}"

    local z_get_code=""
    z_get_code=$(rbuh_code_capture "${z_get_infix}") || buc_die "No HTTP code from getIamPolicy"

    # Check for propagation error on GET
    if zrbgi_propagation_error_predicate "${z_get_infix}" "${z_get_code}" "${z_tolerance[@]}"; then
      buc_log_args "${z_label}: getIamPolicy returned ${z_get_code} (propagation delay)"
      test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
        || buc_die "${z_label}: propagation timeout after ${z_prop_elapsed}s waiting for member visibility"
      buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
      sleep "${z_prop_delay}"
      z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
      z_prop_delay=$((z_prop_delay * 2))
      test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    # Not a propagation error on GET — require success
    rbuh_require_ok "${z_label} (get policy)" "${z_get_infix}"

    buc_log_args 'Extract etag; require non-empty'
    local z_etag=""
    z_etag=$(rbuh_json_field_capture "${z_get_infix}" ".etag") || buc_die "Missing etag"
    test -n "${z_etag}" || buc_die "Empty etag"

    buc_log_args "Using etag ${z_etag}"

    buc_log_args '2) Build new policy JSON in temp (bindings unique; version=3; keep etag)'
    local z_new_policy_json=""
    z_new_policy_json=$(rbgi_jq_add_member_to_role_capture "${z_get_infix}" "${z_role}" "${z_member}" "${z_etag}") \
      || buc_die "Failed to compose policy JSON"

    local z_set_body="${ZRBGI_PREFIX}${z_parent_infix}_set_body.json"
    printf '{"policy":%s}\n' "${z_new_policy_json}" > "${z_set_body}"

    buc_log_args '3) setIamPolicy (fatal on 409 — etag mismatch)'
    local z_set_elapsed=0
    local z_set_infix=""
    local z_set_succeeded=0
    while :; do
      z_set_infix="${z_parent_infix}-set-${z_prop_elapsed}s-${z_set_elapsed}s"
      rbuh_json "POST" "${z_set_url}" "${z_token}" "${z_set_infix}" "${z_set_body}"

      local z_code=""
      z_code=$(rbuh_code_capture "${z_set_infix}") || buc_die "No HTTP code"

      # Check for propagation error on SET — break inner loop to retry outer
      if zrbgi_propagation_error_predicate "${z_set_infix}" "${z_code}" "${z_tolerance[@]}"; then
        buc_log_args "${z_label}: setIamPolicy returned ${z_code} (propagation delay)"
        break
      fi

      case "${z_code}" in
        200)                 z_set_succeeded=1; break ;;
        409)                 buc_die "${z_label}: HTTP 409 ABORTED (etag mismatch — concurrent policy change)" ;;
        429|500|502|503|504) buc_log_args "Transient ${z_code} at ${z_set_elapsed}s; retry" ;;
        *)                   rbuh_require_ok "${z_label} (set policy)" "${z_set_infix}" "" ;;
      esac

      test "${z_set_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" || buc_die "${z_label}: timeout setting policy"
      sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
      z_set_elapsed=$((z_set_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
    done

    # If setIamPolicy succeeded, break outer propagation loop
    test "${z_set_succeeded}" != "1" || { z_prop_succeeded=1; break; }

    # setIamPolicy hit propagation error — retry outer loop with fresh getIamPolicy
    test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
      || buc_die "${z_label}: propagation timeout after ${z_prop_elapsed}s waiting for member visibility"
    buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
    sleep "${z_prop_delay}"
    z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
    z_prop_delay=$((z_prop_delay * 2))
    test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
  done

  test "${z_prop_succeeded}" = "1" || buc_die "${z_label}: propagation retry loop exited without success"

  # The setIamPolicy 200 is the authoritative grant confirmation: the policy was
  # written atomically with this binding. A post-set read-back verify loop was
  # removed here. Against a standing depot, repeated defrock/enrobe cycles leave
  # same-email `deleted:serviceAccount:...?uid=` tombstones in the policy (accepted
  # — re-levy is quota-limited), and the email→uid read reconciliation can lag the
  # getIamPolicy read past any bounded poll, producing a false timeout on a grant
  # that already succeeded. The read-back never made the grant effective — that
  # propagates on GCP's clock regardless and cannot be accelerated by polling — so
  # it was non-load-bearing and is gone.
  buc_log_args "${z_label}: granted (setIamPolicy 200)"
  return 0
}

rbgi_add_repo_iam_role() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_project_id="${2:-}"
  local -r z_account_email="${3:-}"
  local -r z_location="${4:-}"
  local -r z_repository="${5:-}"
  local -r z_role="${6:-}"

  test -n "${z_token}"         || buc_die "Token required"
  test -n "${z_project_id}"    || buc_die "Project ID required"
  test -n "${z_account_email}" || buc_die "Service account email required"
  test -n "${z_location}"      || buc_die "Location is required"
  test -n "${z_repository}"    || buc_die "Repository is required"
  test -n "${z_role}"          || buc_die "Role is required"

  buc_log_args "Using admin token (value not logged)"

  local -r z_resource="projects/${z_project_id}/locations/${z_location}/repositories/${z_repository}"
  local -r z_get_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_resource}:getIamPolicy?options.requestedPolicyVersion=3"
  local -r z_set_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_resource}:setIamPolicy"

  buc_log_args 'Adding repo-scoped IAM role' \
               " ${z_role} to ${z_account_email} on ${z_location}/${z_repository}"

  # Propagation retry — AR repo is resource-scope: member-visibility 400s
  # plus caller-recently-empowered 403 from the resource-scope IAM cache.
  local -ra z_tolerance=(
    "400" "*does not exist*"
    "400" "*is not deleted*"
    "403" ""
  )
  local z_prop_delay=${RBGC_PROPAGATION_INITIAL_DELAY_SEC}
  local z_prop_elapsed=0
  local -r z_prop_deadline=${RBGC_PROPAGATION_DEADLINE_SEC}
  local z_prop_attempt=0

  local z_prop_succeeded=0

  while :; do
    z_prop_attempt=$((z_prop_attempt + 1))
    local z_get_infix="${ZRBGI_INFIX_REPO_ROLE}-${z_prop_elapsed}s"

    buc_log_args "1) GET repo IAM policy (v3) [attempt ${z_prop_attempt}]"
    rbuh_json "GET" "${z_get_url}" "${z_token}" "${z_get_infix}"

    local z_get_code
    z_get_code=$(rbuh_code_capture "${z_get_infix}") || buc_die "No HTTP code from repo getIamPolicy"

    # Check for propagation error on GET
    if zrbgi_propagation_error_predicate "${z_get_infix}" "${z_get_code}" "${z_tolerance[@]}"; then
      buc_log_args "Repo getIamPolicy returned ${z_get_code} (propagation delay)"
      test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
        || buc_die "Repo IAM: propagation timeout after ${z_prop_elapsed}s"
      buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
      sleep "${z_prop_delay}"
      z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
      z_prop_delay=$((z_prop_delay * 2))
      test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    # Not a propagation error on GET — require success
    rbuh_require_ok "Get repo IAM policy" "${z_get_infix}"

    buc_log_args 'Extract etag; require non-empty'
    local z_etag=""
    z_etag=$(rbuh_json_field_capture "${z_get_infix}" ".etag") || buc_die "Missing repo etag"
    test -n "${z_etag}" || buc_die "Empty repo etag"

    buc_log_args "Using etag ${z_etag}"

    buc_log_args '2) Build new policy JSON (bindings unique; version=3; keep etag)'
    local z_updated_policy_json=""
    z_updated_policy_json=$(rbgi_jq_add_member_to_role_capture "${z_get_infix}" \
      "${z_role}" "serviceAccount:${z_account_email}" "${z_etag}") \
      || buc_die "Failed to update policy JSON"

    buc_log_args '3) setIamPolicy (fatal on 409 — etag mismatch)'
    local z_repo_set_body="${BURD_TEMP_DIR}/rbgi_repo_set_policy_body.json"
    printf '{"policy":%s}\n' "${z_updated_policy_json}" > "${z_repo_set_body}" \
      || buc_die "Failed to build repo setIamPolicy body"

    local z_set_elapsed=0
    local z_set_infix=""
    local z_set_succeeded=0
    while :; do
      z_set_infix="${ZRBGI_INFIX_REPO_ROLE_SET}-${z_prop_elapsed}s-${z_set_elapsed}s"
      rbuh_json "POST" "${z_set_url}" "${z_token}" "${z_set_infix}" "${z_repo_set_body}"

      local z_set_code=""
      z_set_code=$(rbuh_code_capture "${z_set_infix}") || buc_die "No HTTP code from setIamPolicy"

      # Check for propagation error on SET — break inner loop to retry outer
      if zrbgi_propagation_error_predicate "${z_set_infix}" "${z_set_code}" "${z_tolerance[@]}"; then
        buc_log_args "Repo setIamPolicy returned ${z_set_code} (propagation delay)"
        break
      fi

      case "${z_set_code}" in
        200)                 z_set_succeeded=1; break ;;
        409)                 buc_die "Repo IAM: HTTP 409 ABORTED (etag mismatch — concurrent policy change)" ;;
        429|500|502|503|504) buc_log_args "Transient ${z_set_code} at ${z_set_elapsed}s; retry" ;;
        *)                   rbuh_require_ok "Set repo IAM policy" "${z_set_infix}" "" ;;
      esac

      test "${z_set_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" || buc_die "Repo IAM: timeout setting policy"
      sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
      z_set_elapsed=$((z_set_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
    done

    # If setIamPolicy succeeded, break outer propagation loop
    test "${z_set_succeeded}" != "1" || { z_prop_succeeded=1; break; }

    # setIamPolicy hit propagation error — retry outer loop with fresh getIamPolicy
    test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
      || buc_die "Repo IAM: propagation timeout after ${z_prop_elapsed}s"
    buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
    sleep "${z_prop_delay}"
    z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
    z_prop_delay=$((z_prop_delay * 2))
    test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
  done

  test "${z_prop_succeeded}" = "1" || buc_die "Repo IAM: propagation retry loop exited without success"

  buc_log_args 'Successfully added repo-scoped role' "${z_role}"
}

rbgi_add_sa_iam_role() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_target_sa_email="${2:-}"
  local -r z_member_email="${3:-}"  # email only; function adds serviceAccount: prefix
  local -r z_role="${4:-}"

  test -n "${z_token}" || buc_die "Token required"

  buc_log_args "Using admin token (value not logged)"
  buc_log_args "Granting ${z_role} on SA ${z_target_sa_email} to ${z_member_email}"

  # Caller must have already primed Cloud Build if this is the runtime SA.
  # We do a hard existence check and crash if not accessible.

  buc_log_args 'Verify target SA exists'
  local z_target_encoded
  z_target_encoded=$(rbuh_urlencode_capture "${z_target_sa_email}") \
    || buc_die "Failed to encode SA email"

  local z_verify_code
  rbuh_json "GET" \
    "${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/-/serviceAccounts/${z_target_encoded}" \
                            "${z_token}" "${ZRBGI_INFIX_SA_IAM_VERIFY}"
  z_verify_code=$(rbuh_code_capture "${ZRBGI_INFIX_SA_IAM_VERIFY}") || buc_die "No HTTP code from SA verify"
  test "${z_verify_code}" = "200" || \
    buc_die "Target service account not accessible: ${z_target_sa_email} (HTTP ${z_verify_code})"

  local -r z_sa_resource="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/-/serviceAccounts/${z_target_encoded}"

  # Propagation retry — SA is resource-scope: member-visibility 400s plus
  # caller-recently-empowered 403 from the resource-scope IAM cache.
  local -ra z_tolerance=(
    "400" "*does not exist*"
    "400" "*is not deleted*"
    "403" ""
  )
  local z_prop_delay=${RBGC_PROPAGATION_INITIAL_DELAY_SEC}
  local z_prop_elapsed=0
  local -r z_prop_deadline=${RBGC_PROPAGATION_DEADLINE_SEC}
  local z_prop_attempt=0

  local z_prop_succeeded=0

  while :; do
    z_prop_attempt=$((z_prop_attempt + 1))
    local z_get_infix="${ZRBGI_INFIX_ROLE}-${z_prop_elapsed}s"

    buc_log_args "1) GET SA IAM policy (v3) [attempt ${z_prop_attempt}]"
    rbuh_json "POST" "${z_sa_resource}:getIamPolicy" "${z_token}" \
      "${z_get_infix}" "${ZRBGI_VERSION3_BODY}"

    local z_code
    z_code=$(rbuh_code_capture "${z_get_infix}") || buc_die "No HTTP code from SA getIamPolicy"

    # Check for propagation error on GET
    if zrbgi_propagation_error_predicate "${z_get_infix}" "${z_code}" "${z_tolerance[@]}"; then
      buc_log_args "SA getIamPolicy returned ${z_code} (propagation delay)"
      test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
        || buc_die "SA IAM: propagation timeout after ${z_prop_elapsed}s"
      buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
      sleep "${z_prop_delay}"
      z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
      z_prop_delay=$((z_prop_delay * 2))
      test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    # Not a propagation error on GET — require success
    rbuh_require_ok "Get SA IAM policy" "${z_get_infix}"

    buc_log_args 'Extract etag; require non-empty'
    local z_etag=""
    z_etag=$(rbuh_json_field_capture "${z_get_infix}" ".etag") || buc_die "Missing SA etag"
    test -n "${z_etag}" || buc_die "Empty SA etag"

    buc_log_args "Using etag ${z_etag}"

    buc_log_args '2) Build new policy JSON (bindings unique; version=3; keep etag)'
    local z_updated_policy_json=""
    z_updated_policy_json=$(rbgi_jq_add_member_to_role_capture "${z_get_infix}" \
      "${z_role}" "serviceAccount:${z_member_email}" "${z_etag}") \
      || buc_die "Failed to update SA IAM policy"

    buc_log_args '3) setIamPolicy (fatal on 409 — etag mismatch)'
    local z_set_body="${BURD_TEMP_DIR}/rbgi_sa_set_policy_body.json"
    printf '{"policy":%s}\n' "${z_updated_policy_json}" > "${z_set_body}" \
      || buc_die "Failed to build SA setIamPolicy body"

    local z_set_elapsed=0
    local z_set_infix=""
    local z_set_succeeded=0
    while :; do
      z_set_infix="${ZRBGI_INFIX_ROLE_SET}-${z_prop_elapsed}s-${z_set_elapsed}s"
      rbuh_json "POST" "${z_sa_resource}:setIamPolicy" "${z_token}" \
        "${z_set_infix}" "${z_set_body}"

      local z_set_code=""
      z_set_code=$(rbuh_code_capture "${z_set_infix}") || buc_die "No HTTP code from setIamPolicy"

      # Check for propagation error on SET — break inner loop to retry outer
      if zrbgi_propagation_error_predicate "${z_set_infix}" "${z_set_code}" "${z_tolerance[@]}"; then
        buc_log_args "SA setIamPolicy returned ${z_set_code} (propagation delay)"
        break
      fi

      case "${z_set_code}" in
        200)                 z_set_succeeded=1; break ;;
        409)                 buc_die "SA IAM: HTTP 409 ABORTED (etag mismatch — concurrent policy change)" ;;
        429|500|502|503|504) buc_log_args "Transient ${z_set_code} at ${z_set_elapsed}s; retry" ;;
        *)                   rbuh_require_ok "Set SA IAM policy" "${z_set_infix}" "" ;;
      esac

      test "${z_set_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" || buc_die "SA IAM: timeout setting policy"
      sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
      z_set_elapsed=$((z_set_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
    done

    # If setIamPolicy succeeded, break outer propagation loop
    test "${z_set_succeeded}" != "1" || { z_prop_succeeded=1; break; }

    # setIamPolicy hit propagation error — retry outer loop with fresh getIamPolicy
    test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
      || buc_die "SA IAM: propagation timeout after ${z_prop_elapsed}s"
    buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
    sleep "${z_prop_delay}"
    z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
    z_prop_delay=$((z_prop_delay * 2))
    test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
  done

  test "${z_prop_succeeded}" = "1" || buc_die "SA IAM: propagation retry loop exited without success"

  buc_log_args 'Successfully granted SA role' "${z_role}"
}

# Add an SA-scoped IAM role binding whose MEMBER is a federated workforce
# principal (principal://…), not a service account. Distinct canonical path from
# rbgi_add_sa_iam_role (BCG Interface Contamination: one canonical member form
# per entry point — no serviceAccount: prefix is applied here, the member is
# passed verbatim). The polity admission verb brevet uses this to grant a
# avowed citizen tokenCreator on a mantle SA. The propagation/etag machinery
# mirrors the serviceAccount-member sibling; only the member-string formation and
# the capture infixes differ.
rbgi_add_sa_principal_iam_role() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_target_sa_email="${2:-}"
  local -r z_member_principal="${3:-}"  # full principal://… member, passed verbatim
  local -r z_role="${4:-}"

  test -n "${z_token}"            || buc_die "Token required"
  test -n "${z_target_sa_email}"  || buc_die "Target SA email required"
  test -n "${z_member_principal}" || buc_die "Member principal required"
  test -n "${z_role}"             || buc_die "Role required"

  buc_log_args "Using admin token (value not logged)"
  buc_log_args "Granting ${z_role} on SA ${z_target_sa_email} to ${z_member_principal}"

  buc_log_args 'Verify target SA exists'
  local z_target_encoded
  z_target_encoded=$(rbuh_urlencode_capture "${z_target_sa_email}") \
    || buc_die "Failed to encode SA email"

  local z_verify_code
  rbuh_json "GET" \
    "${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/-/serviceAccounts/${z_target_encoded}" \
                            "${z_token}" "${ZRBGI_INFIX_SA_PRIN_VERIFY}"
  z_verify_code=$(rbuh_code_capture "${ZRBGI_INFIX_SA_PRIN_VERIFY}") || buc_die "No HTTP code from SA verify"
  test "${z_verify_code}" = "200" || \
    buc_die "Target service account not accessible: ${z_target_sa_email} (HTTP ${z_verify_code})"

  local -r z_sa_resource="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/-/serviceAccounts/${z_target_encoded}"

  # Propagation retry — SA is resource-scope: member-visibility 400s plus
  # caller-recently-empowered 403 from the resource-scope IAM cache.
  local -ra z_tolerance=(
    "400" "*does not exist*"
    "400" "*is not deleted*"
    "403" ""
  )
  local z_prop_delay=${RBGC_PROPAGATION_INITIAL_DELAY_SEC}
  local z_prop_elapsed=0
  local -r z_prop_deadline=${RBGC_PROPAGATION_DEADLINE_SEC}
  local z_prop_attempt=0

  local z_prop_succeeded=0

  while :; do
    z_prop_attempt=$((z_prop_attempt + 1))
    local z_get_infix="${ZRBGI_INFIX_SA_PRIN_ROLE}-${z_prop_elapsed}s"

    buc_log_args "1) GET SA IAM policy (v3) [attempt ${z_prop_attempt}]"
    rbuh_json "POST" "${z_sa_resource}:getIamPolicy" "${z_token}" \
      "${z_get_infix}" "${ZRBGI_VERSION3_BODY}"

    local z_code
    z_code=$(rbuh_code_capture "${z_get_infix}") || buc_die "No HTTP code from SA getIamPolicy"

    if zrbgi_propagation_error_predicate "${z_get_infix}" "${z_code}" "${z_tolerance[@]}"; then
      buc_log_args "SA getIamPolicy returned ${z_code} (propagation delay)"
      test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
        || buc_die "SA IAM: propagation timeout after ${z_prop_elapsed}s"
      buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
      sleep "${z_prop_delay}"
      z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
      z_prop_delay=$((z_prop_delay * 2))
      test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    rbuh_require_ok "Get SA IAM policy" "${z_get_infix}"

    buc_log_args 'Extract etag; require non-empty'
    local z_etag=""
    z_etag=$(rbuh_json_field_capture "${z_get_infix}" ".etag") || buc_die "Missing SA etag"
    test -n "${z_etag}" || buc_die "Empty SA etag"

    buc_log_args "Using etag ${z_etag}"

    buc_log_args '2) Build new policy JSON (bindings unique; version=3; keep etag)'
    local z_updated_policy_json=""
    z_updated_policy_json=$(rbgi_jq_add_member_to_role_capture "${z_get_infix}" \
      "${z_role}" "${z_member_principal}" "${z_etag}") \
      || buc_die "Failed to update SA IAM policy"

    buc_log_args '3) setIamPolicy (fatal on 409 — etag mismatch)'
    local z_set_body="${BURD_TEMP_DIR}/rbgi_sa_prin_set_policy_body.json"
    printf '{"policy":%s}\n' "${z_updated_policy_json}" > "${z_set_body}" \
      || buc_die "Failed to build SA setIamPolicy body"

    local z_set_elapsed=0
    local z_set_infix=""
    local z_set_succeeded=0
    while :; do
      z_set_infix="${ZRBGI_INFIX_SA_PRIN_ROLE_SET}-${z_prop_elapsed}s-${z_set_elapsed}s"
      rbuh_json "POST" "${z_sa_resource}:setIamPolicy" "${z_token}" \
        "${z_set_infix}" "${z_set_body}"

      local z_set_code=""
      z_set_code=$(rbuh_code_capture "${z_set_infix}") || buc_die "No HTTP code from setIamPolicy"

      if zrbgi_propagation_error_predicate "${z_set_infix}" "${z_set_code}" "${z_tolerance[@]}"; then
        buc_log_args "SA setIamPolicy returned ${z_set_code} (propagation delay)"
        break
      fi

      case "${z_set_code}" in
        200)                 z_set_succeeded=1; break ;;
        409)                 buc_die "SA IAM: HTTP 409 ABORTED (etag mismatch — concurrent policy change)" ;;
        429|500|502|503|504) buc_log_args "Transient ${z_set_code} at ${z_set_elapsed}s; retry" ;;
        *)                   rbuh_require_ok "Set SA IAM policy" "${z_set_infix}" "" ;;
      esac

      test "${z_set_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" || buc_die "SA IAM: timeout setting policy"
      sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
      z_set_elapsed=$((z_set_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
    done

    test "${z_set_succeeded}" != "1" || { z_prop_succeeded=1; break; }

    test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
      || buc_die "SA IAM: propagation timeout after ${z_prop_elapsed}s"
    buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
    sleep "${z_prop_delay}"
    z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
    z_prop_delay=$((z_prop_delay * 2))
    test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
  done

  test "${z_prop_succeeded}" = "1" || buc_die "SA IAM: propagation retry loop exited without success"

  buc_log_args 'Successfully granted SA role to principal' "${z_role}"
}

# Read-back gate: poll a SA's IAM policy until a (role, member) binding is
# visible. The grant's setIamPolicy 200 is authoritative for the write, but a
# freshly granted binding joins the Class-C propagation race — a consumer that
# exercises it immediately (builds.create's actAs check against an
# enrobe-fresh self-actAs binding) can die on a flap, not a defect. Visibility
# is the strongest pre-consumer signal available; confining the wait here
# keeps consumer paths simple. Distinct from the project-scope post-set
# read-back that was removed as non-load-bearing: there, same-email deleted:
# tombstone uid-reconciliation on a standing depot could lag the policy read
# past any bounded poll, false-timing-out a grant that had already succeeded.
# An SA's own policy dies with the SA, so a recreated SA reads back
# tombstone-free and this poll converges on GCP's normal cache clock.
rbgi_poll_sa_iam_binding() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_target_sa_email="${2:-}"
  local -r z_member_email="${3:-}"  # email only; function adds serviceAccount: prefix
  local -r z_role="${4:-}"

  test -n "${z_token}"           || buc_die "Token required"
  test -n "${z_target_sa_email}" || buc_die "Target SA email required"
  test -n "${z_member_email}"    || buc_die "Member email required"
  test -n "${z_role}"            || buc_die "Role required"

  local z_target_encoded
  z_target_encoded=$(rbuh_urlencode_capture "${z_target_sa_email}") \
    || buc_die "Failed to encode SA email"
  local -r z_sa_resource="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/-/serviceAccounts/${z_target_encoded}"
  local -r z_member="serviceAccount:${z_member_email}"

  buc_log_args "Read-back: waiting for ${z_role} on ${z_target_sa_email} to show ${z_member}"

  local z_elapsed=0
  while :; do
    local z_poll_infix="${ZRBGI_INFIX_SA_BINDING_POLL}-${z_elapsed}s"
    rbuh_json "POST" "${z_sa_resource}:getIamPolicy" "${z_token}" \
      "${z_poll_infix}" "${ZRBGI_VERSION3_BODY}" || true

    local z_code=""
    z_code=$(rbuh_code_capture "${z_poll_infix}") || z_code=""

    if test "${z_code}" = "200"; then
      local z_resp_file="${ZRBUH_PREFIX}${z_poll_infix}${ZRBUH_POSTFIX_JSON}"
      local z_hits_file="${ZRBGI_PREFIX}${z_poll_infix}_binding_hits.txt"
      local z_hits_stderr="${ZRBGI_PREFIX}${z_poll_infix}_binding_stderr.txt"
      jq -r --arg role "${z_role}" --arg member "${z_member}" \
        '[.bindings[]? | select(.role == $role) | .members[]? | select(. == $member)] | length' \
        "${z_resp_file}" > "${z_hits_file}" 2>"${z_hits_stderr}" \
        || buc_die "Failed to inspect SA IAM policy for binding — see ${z_hits_stderr}"
      local z_hits=$(<"${z_hits_file}")
      test -n "${z_hits}" || buc_die "Empty binding count from SA IAM policy inspection"
      if test "${z_hits}" != "0"; then
        buc_log_args "Binding visible after ${z_elapsed}s"
        return 0
      fi
      buc_log_args "Binding not yet visible (read lags the grant), waiting ${RBGC_EVENTUAL_CONSISTENCY_SEC}s..."
    else
      buc_log_args "SA getIamPolicy returned HTTP ${z_code} during read-back, waiting ${RBGC_EVENTUAL_CONSISTENCY_SEC}s..."
    fi

    test "${z_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" \
      || buc_die "Binding ${z_role} for ${z_member} on ${z_target_sa_email} not visible after ${RBGC_MAX_CONSISTENCY_SEC}s"
    sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
    z_elapsed=$((z_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
  done
}

rbgi_add_bucket_iam_role() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket_name="${2:-}"
  local -r z_account_email="${3:-}"
  local -r z_role="${4:-}"

  test -n "${z_token}" || buc_die "Token required"

  buc_log_args "Using admin token (value not logged)"
  buc_log_args "Adding bucket IAM role ${z_role} to ${z_account_email}"

  local -r z_iam_url="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}/iam"

  # Propagation retry — bucket is resource-scope: member-visibility 400s plus
  # caller-recently-empowered 403 from the resource-scope IAM cache.
  local -ra z_tolerance=(
    "400" "*does not exist*"
    "400" "*is not deleted*"
    "403" ""
  )
  local z_prop_delay=${RBGC_PROPAGATION_INITIAL_DELAY_SEC}
  local z_prop_elapsed=0
  local -r z_prop_deadline=${RBGC_PROPAGATION_DEADLINE_SEC}
  local z_prop_attempt=0

  local z_prop_succeeded=0

  while :; do
    z_prop_attempt=$((z_prop_attempt + 1))
    local z_get_infix="${ZRBGI_INFIX_BUCKET_IAM}-${z_prop_elapsed}s"

    buc_log_args "1) GET bucket IAM policy (v3) [attempt ${z_prop_attempt}]"
    rbuh_json "GET" "${z_iam_url}?optionsRequestedPolicyVersion=3" "${z_token}" "${z_get_infix}"

    local z_code
    z_code=$(rbuh_code_capture "${z_get_infix}") || buc_die "No HTTP code from bucket getIamPolicy"

    # Check for propagation error on GET
    if zrbgi_propagation_error_predicate "${z_get_infix}" "${z_code}" "${z_tolerance[@]}"; then
      buc_log_args "Bucket getIamPolicy returned ${z_code} (propagation delay)"
      test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
        || buc_die "Bucket IAM: propagation timeout after ${z_prop_elapsed}s"
      buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
      sleep "${z_prop_delay}"
      z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
      z_prop_delay=$((z_prop_delay * 2))
      test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    # Not a propagation error on GET — require success
    rbuh_require_ok "Get bucket IAM policy" "${z_get_infix}"

    buc_log_args 'Extract etag; require non-empty'
    local z_etag=""
    z_etag=$(rbuh_json_field_capture "${z_get_infix}" ".etag") || buc_die "Missing bucket etag"
    test -n "${z_etag}" || buc_die "Empty bucket etag"

    buc_log_args "Using etag ${z_etag}"

    buc_log_args '2) Build new policy JSON (bindings unique; keep etag)'
    local z_updated_policy_json=""
    z_updated_policy_json=$(rbgi_jq_add_member_to_role_capture "${z_get_infix}" \
      "${z_role}" "serviceAccount:${z_account_email}" "${z_etag}") \
      || buc_die "Failed to update bucket IAM policy"

    buc_log_args '3) setIamPolicy (fatal on 412 — etag mismatch; Storage uses 412 not 409)'
    local z_bucket_set_body="${BURD_TEMP_DIR}/rbgi_bucket_set_policy_body.json"
    printf '%s\n' "${z_updated_policy_json}" > "${z_bucket_set_body}" \
      || buc_die "Failed to write bucket policy body"

    local z_set_elapsed=0
    local z_set_infix=""
    local z_set_succeeded=0
    while :; do
      z_set_infix="${ZRBGI_INFIX_BUCKET_IAM_SET}-${z_prop_elapsed}s-${z_set_elapsed}s"
      rbuh_json "PUT" "${z_iam_url}" "${z_token}" "${z_set_infix}" "${z_bucket_set_body}"

      local z_set_code=""
      z_set_code=$(rbuh_code_capture "${z_set_infix}") || buc_die "No HTTP code from setIamPolicy"

      # Check for propagation error on SET — break inner loop to retry outer
      if zrbgi_propagation_error_predicate "${z_set_infix}" "${z_set_code}" "${z_tolerance[@]}"; then
        buc_log_args "Bucket setIamPolicy returned ${z_set_code} (propagation delay)"
        break
      fi

      case "${z_set_code}" in
        200)                 z_set_succeeded=1; break ;;
        412)                 buc_die "Bucket IAM: HTTP 412 Precondition Failed (etag mismatch)" ;;
        409)                 buc_die "Bucket IAM: HTTP 409 ABORTED (defensive — unexpected for Storage)" ;;
        429|500|502|503|504) buc_log_args "Transient ${z_set_code} at ${z_set_elapsed}s; retry" ;;
        *)                   rbuh_require_ok "Set bucket IAM policy" "${z_set_infix}" "" ;;
      esac

      test "${z_set_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" || buc_die "Bucket IAM: timeout setting policy"
      sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
      z_set_elapsed=$((z_set_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
    done

    # If setIamPolicy succeeded, break outer propagation loop
    test "${z_set_succeeded}" != "1" || { z_prop_succeeded=1; break; }

    # setIamPolicy hit propagation error — retry outer loop with fresh getIamPolicy
    test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
      || buc_die "Bucket IAM: propagation timeout after ${z_prop_elapsed}s"
    buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
    sleep "${z_prop_delay}"
    z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
    z_prop_delay=$((z_prop_delay * 2))
    test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
  done

  test "${z_prop_succeeded}" = "1" || buc_die "Bucket IAM: propagation retry loop exited without success"

  buc_log_args "Successfully added bucket role ${z_role}"
}

# Grant an IAM role binding on a GCS managed folder with optimistic concurrency
# and propagation retry. Managed folders ride the same Storage JSON IAM family as
# buckets (GET v3 + PUT raw policy, 412-fatal etag), so this mirrors
# rbgi_add_bucket_iam_role exactly; only the resource path differs (the folder
# name is a slash-terminated prefix and must be URL-encoded into the path).
rbgi_add_managed_folder_iam_role() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket_name="${2:-}"
  local -r z_managed_folder="${3:-}"
  local -r z_account_email="${4:-}"
  local -r z_role="${5:-}"

  test -n "${z_token}"          || buc_die "Token required"
  test -n "${z_bucket_name}"    || buc_die "Bucket name required"
  test -n "${z_managed_folder}" || buc_die "Managed folder required"
  test -n "${z_account_email}"  || buc_die "Account email required"
  test -n "${z_role}"           || buc_die "Role required"

  buc_log_args "Using admin token (value not logged)"
  buc_log_args "Adding managed-folder IAM role ${z_role} to ${z_account_email} on ${z_managed_folder}"

  local z_mf_enc
  z_mf_enc=$(rbuh_urlencode_capture "${z_managed_folder}") || buc_die "Failed to encode managed folder name"
  local -r z_iam_url="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}/b/${z_bucket_name}/managedFolders/${z_mf_enc}/iam"

  # Propagation retry — managed folder is resource-scope (same shape as bucket):
  # member-visibility 400s plus caller-recently-empowered 403 from the cache.
  local -ra z_tolerance=(
    "400" "*does not exist*"
    "400" "*is not deleted*"
    "403" ""
  )
  local z_prop_delay=${RBGC_PROPAGATION_INITIAL_DELAY_SEC}
  local z_prop_elapsed=0
  local -r z_prop_deadline=${RBGC_PROPAGATION_DEADLINE_SEC}
  local z_prop_attempt=0

  local z_prop_succeeded=0

  while :; do
    z_prop_attempt=$((z_prop_attempt + 1))
    local z_get_infix="${ZRBGI_INFIX_MF_IAM}-${z_prop_elapsed}s"

    buc_log_args "1) GET managed-folder IAM policy (v3) [attempt ${z_prop_attempt}]"
    rbuh_json "GET" "${z_iam_url}?optionsRequestedPolicyVersion=3" "${z_token}" "${z_get_infix}"

    local z_code
    z_code=$(rbuh_code_capture "${z_get_infix}") || buc_die "No HTTP code from managed-folder getIamPolicy"

    # Check for propagation error on GET
    if zrbgi_propagation_error_predicate "${z_get_infix}" "${z_code}" "${z_tolerance[@]}"; then
      buc_log_args "Managed-folder getIamPolicy returned ${z_code} (propagation delay)"
      test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
        || buc_die "Managed-folder IAM: propagation timeout after ${z_prop_elapsed}s"
      buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
      sleep "${z_prop_delay}"
      z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
      z_prop_delay=$((z_prop_delay * 2))
      test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    # Not a propagation error on GET — require success
    rbuh_require_ok "Get managed-folder IAM policy" "${z_get_infix}"

    buc_log_args 'Extract etag; require non-empty'
    local z_etag=""
    z_etag=$(rbuh_json_field_capture "${z_get_infix}" ".etag") || buc_die "Missing managed-folder etag"
    test -n "${z_etag}" || buc_die "Empty managed-folder etag"

    buc_log_args "Using etag ${z_etag}"

    buc_log_args '2) Build new policy JSON (bindings unique; keep etag)'
    local z_updated_policy_json=""
    z_updated_policy_json=$(rbgi_jq_add_member_to_role_capture "${z_get_infix}" \
      "${z_role}" "serviceAccount:${z_account_email}" "${z_etag}") \
      || buc_die "Failed to update managed-folder IAM policy"

    buc_log_args '3) setIamPolicy (fatal on 412 — etag mismatch; Storage uses 412 not 409)'
    local z_mf_set_body="${BURD_TEMP_DIR}/rbgi_managed_folder_set_policy_body.json"
    printf '%s\n' "${z_updated_policy_json}" > "${z_mf_set_body}" \
      || buc_die "Failed to write managed-folder policy body"

    local z_set_elapsed=0
    local z_set_infix=""
    local z_set_succeeded=0
    while :; do
      z_set_infix="${ZRBGI_INFIX_MF_IAM_SET}-${z_prop_elapsed}s-${z_set_elapsed}s"
      rbuh_json "PUT" "${z_iam_url}" "${z_token}" "${z_set_infix}" "${z_mf_set_body}"

      local z_set_code=""
      z_set_code=$(rbuh_code_capture "${z_set_infix}") || buc_die "No HTTP code from setIamPolicy"

      # Check for propagation error on SET — break inner loop to retry outer
      if zrbgi_propagation_error_predicate "${z_set_infix}" "${z_set_code}" "${z_tolerance[@]}"; then
        buc_log_args "Managed-folder setIamPolicy returned ${z_set_code} (propagation delay)"
        break
      fi

      case "${z_set_code}" in
        200)                 z_set_succeeded=1; break ;;
        412)                 buc_die "Managed-folder IAM: HTTP 412 Precondition Failed (etag mismatch)" ;;
        409)                 buc_die "Managed-folder IAM: HTTP 409 ABORTED (defensive — unexpected for Storage)" ;;
        429|500|502|503|504) buc_log_args "Transient ${z_set_code} at ${z_set_elapsed}s; retry" ;;
        *)                   rbuh_require_ok "Set managed-folder IAM policy" "${z_set_infix}" "" ;;
      esac

      test "${z_set_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" || buc_die "Managed-folder IAM: timeout setting policy"
      sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
      z_set_elapsed=$((z_set_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
    done

    # If setIamPolicy succeeded, break outer propagation loop
    test "${z_set_succeeded}" != "1" || { z_prop_succeeded=1; break; }

    # setIamPolicy hit propagation error — retry outer loop with fresh getIamPolicy
    test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
      || buc_die "Managed-folder IAM: propagation timeout after ${z_prop_elapsed}s"
    buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
    sleep "${z_prop_delay}"
    z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
    z_prop_delay=$((z_prop_delay * 2))
    test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
  done

  test "${z_prop_succeeded}" = "1" || buc_die "Managed-folder IAM: propagation retry loop exited without success"

  buc_log_args "Successfully added managed-folder role ${z_role}"
}

# Grant an IAM role binding on a Secret Manager secret with optimistic concurrency and propagation retry.
rbgi_grant_secret_iam() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_secret_resource_path="${2:-}"
  local -r z_member="${3:-}"
  local -r z_role="${4:-}"
  local -r z_parent_infix="${5:-}"

  test -n "${z_token}"                || buc_die "Token required"
  test -n "${z_secret_resource_path}" || buc_die "Secret resource path required"
  test -n "${z_member}"               || buc_die "Member required"
  test -n "${z_role}"                 || buc_die "Role required"
  test -n "${z_parent_infix}"         || buc_die "Parent infix required"

  buc_log_args "Using admin token (value not logged)"
  buc_log_args "Granting ${z_role} on secret ${z_secret_resource_path} to ${z_member}"

  local -r z_get_url="${RBGC_API_ROOT_SECRETMANAGER}${RBGC_SECRETMANAGER_V1}/${z_secret_resource_path}:getIamPolicy?options.requestedPolicyVersion=3"
  local -r z_set_url="${RBGC_API_ROOT_SECRETMANAGER}${RBGC_SECRETMANAGER_V1}/${z_secret_resource_path}:setIamPolicy"

  # Propagation retry — secret is resource-scope: member-visibility 400s plus
  # caller-recently-empowered 403 from the resource-scope IAM cache.
  local -ra z_tolerance=(
    "400" "*does not exist*"
    "400" "*is not deleted*"
    "403" ""
  )
  local z_prop_delay=${RBGC_PROPAGATION_INITIAL_DELAY_SEC}
  local z_prop_elapsed=0
  local -r z_prop_deadline=${RBGC_PROPAGATION_DEADLINE_SEC}
  local z_prop_attempt=0

  local z_prop_succeeded=0

  while :; do
    z_prop_attempt=$((z_prop_attempt + 1))
    local z_get_infix="${z_parent_infix}-get-${z_prop_elapsed}s"

    buc_log_args "1) GET secret IAM policy (v3) [attempt ${z_prop_attempt}]"
    rbuh_json "GET" "${z_get_url}" "${z_token}" "${z_get_infix}"

    local z_get_code
    z_get_code=$(rbuh_code_capture "${z_get_infix}") || buc_die "No HTTP code from secret getIamPolicy"

    # Check for propagation error on GET
    if zrbgi_propagation_error_predicate "${z_get_infix}" "${z_get_code}" "${z_tolerance[@]}"; then
      buc_log_args "Secret getIamPolicy returned ${z_get_code} (propagation delay)"
      test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
        || buc_die "Secret IAM: propagation timeout after ${z_prop_elapsed}s"
      buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
      sleep "${z_prop_delay}"
      z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
      z_prop_delay=$((z_prop_delay * 2))
      test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    # Not a propagation error on GET — require success
    rbuh_require_ok "Get secret IAM policy" "${z_get_infix}"

    buc_log_args 'Extract etag; require non-empty'
    local z_etag=""
    z_etag=$(rbuh_json_field_capture "${z_get_infix}" ".etag") || buc_die "Missing secret etag"
    test -n "${z_etag}" || buc_die "Empty secret etag"

    buc_log_args "Using etag ${z_etag}"

    buc_log_args '2) Build new policy JSON (bindings unique; version=3; keep etag)'
    local z_updated_policy_json=""
    z_updated_policy_json=$(rbgi_jq_add_member_to_role_capture "${z_get_infix}" \
      "${z_role}" "${z_member}" "${z_etag}") \
      || buc_die "Failed to update secret IAM policy"

    buc_log_args '3) setIamPolicy (fatal on 409 — etag mismatch)'
    local z_set_body="${ZRBGI_PREFIX}${z_parent_infix}_set_body.json"
    printf '{"policy":%s}\n' "${z_updated_policy_json}" > "${z_set_body}" \
      || buc_die "Failed to build secret setIamPolicy body"

    local z_set_elapsed=0
    local z_set_infix=""
    local z_set_succeeded=0
    while :; do
      z_set_infix="${z_parent_infix}-set-${z_prop_elapsed}s-${z_set_elapsed}s"
      rbuh_json "POST" "${z_set_url}" "${z_token}" "${z_set_infix}" "${z_set_body}"

      local z_set_code=""
      z_set_code=$(rbuh_code_capture "${z_set_infix}") || buc_die "No HTTP code from setIamPolicy"

      # Check for propagation error on SET — break inner loop to retry outer
      if zrbgi_propagation_error_predicate "${z_set_infix}" "${z_set_code}" "${z_tolerance[@]}"; then
        buc_log_args "Secret setIamPolicy returned ${z_set_code} (propagation delay)"
        break
      fi

      case "${z_set_code}" in
        200)                 z_set_succeeded=1; break ;;
        409)                 buc_die "Secret IAM: HTTP 409 ABORTED (etag mismatch — concurrent policy change)" ;;
        429|500|502|503|504) buc_log_args "Transient ${z_set_code} at ${z_set_elapsed}s; retry" ;;
        *)                   rbuh_require_ok "Set secret IAM policy" "${z_set_infix}" "" ;;
      esac

      test "${z_set_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" || buc_die "Secret IAM: timeout setting policy"
      sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
      z_set_elapsed=$((z_set_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
    done

    # If setIamPolicy succeeded, break outer propagation loop
    test "${z_set_succeeded}" != "1" || { z_prop_succeeded=1; break; }

    # setIamPolicy hit propagation error — retry outer loop with fresh getIamPolicy
    test "${z_prop_elapsed}" -lt "${z_prop_deadline}" \
      || buc_die "Secret IAM: propagation timeout after ${z_prop_elapsed}s"
    buc_log_args "Retry ${z_prop_attempt} at ${z_prop_elapsed}s (next delay ${z_prop_delay}s)"
    sleep "${z_prop_delay}"
    z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
    z_prop_delay=$((z_prop_delay * 2))
    test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
  done

  test "${z_prop_succeeded}" = "1" || buc_die "Secret IAM: propagation retry loop exited without success"

  buc_log_args "Successfully granted secret role ${z_role}"
}

######################################################################
# Revoke (member removal) — inverse of the add_*_iam_role trio.
#
# Three regular functions, not one: CRM / ArtifactRegistry / IAM are distinct
# APIs with distinct getIamPolicy/setIamPolicy shapes (BCG load-bearing). They
# share only the jq member-removal transform.
#
# Leaner than the add trio, but not class-free. The member being revoked is
# long-established, so the member-visibility classes (400 forward "does not
# exist" / backward "is not deleted") cannot fire on a revoke and are dropped.
# Class C — caller-recently-empowered (403) — DOES fire: it is about the governor,
# not the member, and a governor freshly re-enrobed before a teardown has not yet
# propagated its roles/owner to the resource-scope IAM cache. So the
# resource-scope revokes (repo, sa) retry the GET on 403 against the propagation
# deadline; project-scope revoke needs none (project caches absorb governor
# empowerment instantly). setIamPolicy stays lean: it is gated by the same
# roles/owner permission as the GET, so once the GET clears the SET will not 403;
# 409 stays fatal under the single-writer invariant, transient 5xx retried.
# Removing an absent member is a jq no-op, so revoke is idempotent. Fatal on
# failure like every regular function — defrock calls them as ordinary commands.

# Revoke a project-scoped IAM member binding — inverse of rbgi_add_project_iam_role.
rbgi_revoke_project_member() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_label="${2:-}"
  local -r z_resource="${3:-}"
  local -r z_role="${4:-}"
  local -r z_member="${5:-}"
  local -r z_parent_infix="${6:-}"

  test -n "${z_token}"    || buc_die "Token required"
  test -n "${z_resource}" || buc_die "resource required"
  test -n "${z_role}"     || buc_die "role required"
  test -n "${z_member}"   || buc_die "member required"

  buc_log_args "Using admin token (value not logged)"

  local -r z_resource_path="${z_resource#/}"
  local -r z_base="${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/${z_resource_path}"
  local -r z_get_url="${z_base}${RBGC_CRM_GET_IAM_POLICY_SUFFIX}"
  local -r z_set_url="${z_base}${RBGC_CRM_SET_IAM_POLICY_SUFFIX}"

  buc_log_args "${z_label}: revoke ${z_member} from ${z_role}"

  buc_log_args '1) GET project IAM policy (v3)'
  local -r z_get_infix="${z_parent_infix}-revoke-get"
  local -r z_get_body="${ZRBGI_PREFIX}${z_parent_infix}_revoke_get_body.json"
  printf '%s\n' '{"options":{"requestedPolicyVersion":3}}' > "${z_get_body}" || buc_die "Failed to write getIamPolicy body"
  rbuh_json "POST" "${z_get_url}" "${z_token}" "${z_get_infix}" "${z_get_body}"
  rbuh_require_ok "${z_label} (get policy)" "${z_get_infix}"

  local z_etag=""
  z_etag=$(rbuh_json_field_capture "${z_get_infix}" ".etag") || buc_die "Missing etag"
  test -n "${z_etag}" || buc_die "Empty etag"

  local z_new_policy_json=""
  z_new_policy_json=$(rbgi_jq_remove_member_from_role_capture "${z_get_infix}" "${z_role}" "${z_member}" "${z_etag}") \
    || buc_die "Failed to compose policy JSON"

  local -r z_set_body="${ZRBGI_PREFIX}${z_parent_infix}_revoke_set_body.json"
  printf '{"policy":%s}\n' "${z_new_policy_json}" > "${z_set_body}" || buc_die "Failed to write setIamPolicy body"

  buc_log_args '2) setIamPolicy (409 fatal — single-writer invariant; transient retried)'
  local z_set_elapsed=0
  local z_set_infix=""
  local z_set_code=""
  while :; do
    z_set_infix="${z_parent_infix}-revoke-set-${z_set_elapsed}s"
    rbuh_json "POST" "${z_set_url}" "${z_token}" "${z_set_infix}" "${z_set_body}"

    z_set_code=$(rbuh_code_capture "${z_set_infix}") || buc_die "No HTTP code from setIamPolicy"

    case "${z_set_code}" in
      200)                 break ;;
      409)                 buc_die "${z_label}: HTTP 409 ABORTED (etag mismatch — concurrent policy change)" ;;
      429|500|502|503|504) buc_log_args "${z_label}: transient ${z_set_code} at ${z_set_elapsed}s; retry" ;;
      *)                   rbuh_require_ok "${z_label} (set policy)" "${z_set_infix}" ;;
    esac

    test "${z_set_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" || buc_die "${z_label}: timeout setting policy"
    sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
    z_set_elapsed=$((z_set_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
  done

  buc_log_args "${z_label}: revoked (setIamPolicy 200)"
}

# Revoke a repo-scoped IAM member binding — inverse of rbgi_add_repo_iam_role.
rbgi_revoke_repo_member() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_project_id="${2:-}"
  local -r z_account_email="${3:-}"
  local -r z_location="${4:-}"
  local -r z_repository="${5:-}"
  local -r z_role="${6:-}"

  test -n "${z_token}"         || buc_die "Token required"
  test -n "${z_project_id}"    || buc_die "Project ID required"
  test -n "${z_account_email}" || buc_die "Service account email required"
  test -n "${z_location}"      || buc_die "Location is required"
  test -n "${z_repository}"    || buc_die "Repository is required"
  test -n "${z_role}"          || buc_die "Role is required"

  buc_log_args "Using admin token (value not logged)"

  local -r z_resource="projects/${z_project_id}/locations/${z_location}/repositories/${z_repository}"
  local -r z_get_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_resource}:getIamPolicy?options.requestedPolicyVersion=3"
  local -r z_set_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_resource}:setIamPolicy"

  buc_log_args 'Revoking repo-scoped IAM role' " ${z_role} from ${z_account_email} on ${z_location}/${z_repository}"

  # GET with Class C (403) propagation retry only — a freshly-enrobed governor's
  # read permission on this resource-scope target can lag the resource IAM cache.
  # The member-visibility classes (400) cannot fire on a revoke.
  local -ra z_tolerance=(
    "403" ""
  )
  local z_prop_delay=${RBGC_PROPAGATION_INITIAL_DELAY_SEC}
  local z_prop_elapsed=0
  local z_get_infix=""
  local z_get_code=""
  while :; do
    z_get_infix="${ZRBGI_INFIX_REPO_REVOKE}-${z_prop_elapsed}s"
    buc_log_args "1) GET repo IAM policy (v3) [${z_prop_elapsed}s]"
    rbuh_json "GET" "${z_get_url}" "${z_token}" "${z_get_infix}"
    z_get_code=$(rbuh_code_capture "${z_get_infix}") || buc_die "No HTTP code from repo getIamPolicy"

    if zrbgi_propagation_error_predicate "${z_get_infix}" "${z_get_code}" "${z_tolerance[@]}"; then
      test "${z_prop_elapsed}" -lt "${RBGC_PROPAGATION_DEADLINE_SEC}" \
        || buc_die "Repo IAM: governor empowerment propagation timeout after ${z_prop_elapsed}s (last HTTP ${z_get_code})"
      buc_log_args "Repo getIamPolicy ${z_get_code} (caller-empowerment propagating); retry at ${z_prop_elapsed}s"
      sleep "${z_prop_delay}"
      z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
      z_prop_delay=$((z_prop_delay * 2))
      test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    rbuh_require_ok "Get repo IAM policy" "${z_get_infix}"
    break
  done

  local z_etag=""
  z_etag=$(rbuh_json_field_capture "${z_get_infix}" ".etag") || buc_die "Missing repo etag"
  test -n "${z_etag}" || buc_die "Empty repo etag"

  local z_updated_policy_json=""
  z_updated_policy_json=$(rbgi_jq_remove_member_from_role_capture "${z_get_infix}" \
    "${z_role}" "serviceAccount:${z_account_email}" "${z_etag}") \
    || buc_die "Failed to update policy JSON"

  local -r z_set_body="${BURD_TEMP_DIR}/rbgi_repo_revoke_set_policy_body.json"
  printf '{"policy":%s}\n' "${z_updated_policy_json}" > "${z_set_body}" || buc_die "Failed to write repo setIamPolicy body"

  buc_log_args '2) setIamPolicy (409 fatal — single-writer invariant; transient retried)'
  local z_set_elapsed=0
  local z_set_infix=""
  local z_set_code=""
  while :; do
    z_set_infix="${ZRBGI_INFIX_REPO_REVOKE_SET}-${z_set_elapsed}s"
    rbuh_json "POST" "${z_set_url}" "${z_token}" "${z_set_infix}" "${z_set_body}"

    z_set_code=$(rbuh_code_capture "${z_set_infix}") || buc_die "No HTTP code from setIamPolicy"

    case "${z_set_code}" in
      200)                 break ;;
      409)                 buc_die "Repo IAM: HTTP 409 ABORTED (etag mismatch — concurrent policy change)" ;;
      429|500|502|503|504) buc_log_args "Repo IAM: transient ${z_set_code} at ${z_set_elapsed}s; retry" ;;
      *)                   rbuh_require_ok "Set repo IAM policy" "${z_set_infix}" ;;
    esac

    test "${z_set_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" || buc_die "Repo IAM: timeout setting policy"
    sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
    z_set_elapsed=$((z_set_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
  done

  buc_log_args 'Successfully revoked repo-scoped role' "${z_role}"
}

# Revoke an SA-scoped IAM member binding — inverse of rbgi_add_sa_iam_role.
# getIamPolicy is the existence check, so the grant path's standalone SA-verify
# preflight earns nothing here.
rbgi_revoke_sa_member() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_target_sa_email="${2:-}"
  local -r z_member_email="${3:-}"
  local -r z_role="${4:-}"

  test -n "${z_token}"           || buc_die "Token required"
  test -n "${z_target_sa_email}" || buc_die "Target SA email required"
  test -n "${z_member_email}"    || buc_die "Member email required"
  test -n "${z_role}"            || buc_die "Role required"

  buc_log_args "Using admin token (value not logged)"
  buc_log_args "Revoking ${z_role} on SA ${z_target_sa_email} from ${z_member_email}"

  local z_target_encoded=""
  z_target_encoded=$(rbuh_urlencode_capture "${z_target_sa_email}") || buc_die "Failed to encode SA email"
  local -r z_sa_resource="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/-/serviceAccounts/${z_target_encoded}"

  # GET with Class C (403) propagation retry only — a freshly-enrobed governor's
  # read permission on this resource-scope target can lag the resource IAM cache.
  # The member-visibility classes (400) cannot fire on a revoke.
  local -ra z_tolerance=(
    "403" ""
  )
  local z_prop_delay=${RBGC_PROPAGATION_INITIAL_DELAY_SEC}
  local z_prop_elapsed=0
  local z_get_infix=""
  local z_get_code=""
  while :; do
    z_get_infix="${ZRBGI_INFIX_SA_REVOKE}-${z_prop_elapsed}s"
    buc_log_args "1) GET SA IAM policy (v3) [${z_prop_elapsed}s]"
    rbuh_json "POST" "${z_sa_resource}:getIamPolicy" "${z_token}" "${z_get_infix}" "${ZRBGI_VERSION3_BODY}"
    z_get_code=$(rbuh_code_capture "${z_get_infix}") || buc_die "No HTTP code from SA getIamPolicy"

    if zrbgi_propagation_error_predicate "${z_get_infix}" "${z_get_code}" "${z_tolerance[@]}"; then
      test "${z_prop_elapsed}" -lt "${RBGC_PROPAGATION_DEADLINE_SEC}" \
        || buc_die "SA IAM: governor empowerment propagation timeout after ${z_prop_elapsed}s (last HTTP ${z_get_code})"
      buc_log_args "SA getIamPolicy ${z_get_code} (caller-empowerment propagating); retry at ${z_prop_elapsed}s"
      sleep "${z_prop_delay}"
      z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
      z_prop_delay=$((z_prop_delay * 2))
      test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    rbuh_require_ok "Get SA IAM policy" "${z_get_infix}"
    break
  done

  local z_etag=""
  z_etag=$(rbuh_json_field_capture "${z_get_infix}" ".etag") || buc_die "Missing SA etag"
  test -n "${z_etag}" || buc_die "Empty SA etag"

  local z_updated_policy_json=""
  z_updated_policy_json=$(rbgi_jq_remove_member_from_role_capture "${z_get_infix}" \
    "${z_role}" "serviceAccount:${z_member_email}" "${z_etag}") \
    || buc_die "Failed to update SA IAM policy"

  local -r z_set_body="${BURD_TEMP_DIR}/rbgi_sa_revoke_set_policy_body.json"
  printf '{"policy":%s}\n' "${z_updated_policy_json}" > "${z_set_body}" || buc_die "Failed to write SA setIamPolicy body"

  buc_log_args '2) setIamPolicy (409 fatal — single-writer invariant; transient retried)'
  local z_set_elapsed=0
  local z_set_infix=""
  local z_set_code=""
  while :; do
    z_set_infix="${ZRBGI_INFIX_SA_REVOKE_SET}-${z_set_elapsed}s"
    rbuh_json "POST" "${z_sa_resource}:setIamPolicy" "${z_token}" "${z_set_infix}" "${z_set_body}"

    z_set_code=$(rbuh_code_capture "${z_set_infix}") || buc_die "No HTTP code from setIamPolicy"

    case "${z_set_code}" in
      200)                 break ;;
      409)                 buc_die "SA IAM: HTTP 409 ABORTED (etag mismatch — concurrent policy change)" ;;
      429|500|502|503|504) buc_log_args "SA IAM: transient ${z_set_code} at ${z_set_elapsed}s; retry" ;;
      *)                   rbuh_require_ok "Set SA IAM policy" "${z_set_infix}" ;;
    esac

    test "${z_set_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" || buc_die "SA IAM: timeout setting policy"
    sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
    z_set_elapsed=$((z_set_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
  done

  buc_log_args 'Successfully revoked SA role' "${z_role}"
}

# Revoke an SA-scoped IAM binding whose MEMBER is a federated workforce principal
# (principal://…) — inverse of rbgi_add_sa_principal_iam_role, federated-member
# sibling of rbgi_revoke_sa_member. The member is passed verbatim (no
# serviceAccount: prefix). unseat uses this to remove a citizen's tokenCreator on
# a mantle SA; the depot-scoped serviceUsageConsumer binding is deliberately NOT
# touched here — that survives as suspension and is swept only by attaint.
rbgi_revoke_sa_principal_member() {
  zrbgi_sentinel

  local -r z_token="${1:-}"
  local -r z_target_sa_email="${2:-}"
  local -r z_member_principal="${3:-}"
  local -r z_role="${4:-}"

  test -n "${z_token}"            || buc_die "Token required"
  test -n "${z_target_sa_email}"  || buc_die "Target SA email required"
  test -n "${z_member_principal}" || buc_die "Member principal required"
  test -n "${z_role}"             || buc_die "Role required"

  buc_log_args "Using admin token (value not logged)"
  buc_log_args "Revoking ${z_role} on SA ${z_target_sa_email} from ${z_member_principal}"

  local z_target_encoded=""
  z_target_encoded=$(rbuh_urlencode_capture "${z_target_sa_email}") || buc_die "Failed to encode SA email"
  local -r z_sa_resource="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}/projects/-/serviceAccounts/${z_target_encoded}"

  # GET with Class C (403) propagation retry only — a freshly-enrobed governor's
  # read permission on this resource-scope target can lag the resource IAM cache.
  # The member-visibility classes (400) cannot fire on a revoke.
  local -ra z_tolerance=(
    "403" ""
  )
  local z_prop_delay=${RBGC_PROPAGATION_INITIAL_DELAY_SEC}
  local z_prop_elapsed=0
  local z_get_infix=""
  local z_get_code=""
  while :; do
    z_get_infix="${ZRBGI_INFIX_SA_PRIN_REVOKE}-${z_prop_elapsed}s"
    buc_log_args "1) GET SA IAM policy (v3) [${z_prop_elapsed}s]"
    rbuh_json "POST" "${z_sa_resource}:getIamPolicy" "${z_token}" "${z_get_infix}" "${ZRBGI_VERSION3_BODY}"
    z_get_code=$(rbuh_code_capture "${z_get_infix}") || buc_die "No HTTP code from SA getIamPolicy"

    if zrbgi_propagation_error_predicate "${z_get_infix}" "${z_get_code}" "${z_tolerance[@]}"; then
      test "${z_prop_elapsed}" -lt "${RBGC_PROPAGATION_DEADLINE_SEC}" \
        || buc_die "SA IAM: governor empowerment propagation timeout after ${z_prop_elapsed}s (last HTTP ${z_get_code})"
      buc_log_args "SA getIamPolicy ${z_get_code} (caller-empowerment propagating); retry at ${z_prop_elapsed}s"
      sleep "${z_prop_delay}"
      z_prop_elapsed=$((z_prop_elapsed + z_prop_delay))
      z_prop_delay=$((z_prop_delay * 2))
      test "${z_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    rbuh_require_ok "Get SA IAM policy" "${z_get_infix}"
    break
  done

  local z_etag=""
  z_etag=$(rbuh_json_field_capture "${z_get_infix}" ".etag") || buc_die "Missing SA etag"
  test -n "${z_etag}" || buc_die "Empty SA etag"

  local z_updated_policy_json=""
  z_updated_policy_json=$(rbgi_jq_remove_member_from_role_capture "${z_get_infix}" \
    "${z_role}" "${z_member_principal}" "${z_etag}") \
    || buc_die "Failed to update SA IAM policy"

  local -r z_set_body="${BURD_TEMP_DIR}/rbgi_sa_prin_revoke_set_policy_body.json"
  printf '{"policy":%s}\n' "${z_updated_policy_json}" > "${z_set_body}" || buc_die "Failed to write SA setIamPolicy body"

  buc_log_args '2) setIamPolicy (409 fatal — single-writer invariant; transient retried)'
  local z_set_elapsed=0
  local z_set_infix=""
  local z_set_code=""
  while :; do
    z_set_infix="${ZRBGI_INFIX_SA_PRIN_REVOKE_SET}-${z_set_elapsed}s"
    rbuh_json "POST" "${z_sa_resource}:setIamPolicy" "${z_token}" "${z_set_infix}" "${z_set_body}"

    z_set_code=$(rbuh_code_capture "${z_set_infix}") || buc_die "No HTTP code from setIamPolicy"

    case "${z_set_code}" in
      200)                 break ;;
      409)                 buc_die "SA IAM: HTTP 409 ABORTED (etag mismatch — concurrent policy change)" ;;
      429|500|502|503|504) buc_log_args "SA IAM: transient ${z_set_code} at ${z_set_elapsed}s; retry" ;;
      *)                   rbuh_require_ok "Set SA IAM policy" "${z_set_infix}" ;;
    esac

    test "${z_set_elapsed}" -lt "${RBGC_MAX_CONSISTENCY_SEC}" || buc_die "SA IAM: timeout setting policy"
    sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
    z_set_elapsed=$((z_set_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))
  done

  buc_log_args 'Successfully revoked SA role from principal' "${z_role}"
}

# Compose service account email from name and project ID.
# Args: account_name project_id
# Returns: name@project.iam.gserviceaccount.com
rbgi_sa_email_capture() {
  zrbgi_sentinel

  local -r z_name="${1:-}"
  local -r z_project="${2:-}"

  test -n "${z_name}"    || return 1
  test -n "${z_project}" || return 1

  echo "${z_name}@${z_project}.${RBGC_SA_EMAIL_DOMAIN}"
}

# Add member to IAM policy role binding with version=3 enforcement
#
# RBGU IAM Policy Standard: All IAM policies are standardized to version=3
# to ensure consistent conditional role binding support across Google Cloud APIs.
# This is enforced by default in all policy operations to prevent version drift.
#
# Args: infix role member [etag_optional]
# Returns: JSON policy string with added member and version=3
rbgi_jq_add_member_to_role_capture() {
  zrbgi_sentinel

  local -r z_infix="${1:-}"
  local -r z_role="${2:-}"
  local -r z_member="${3:-}"
  local -r z_etag_opt="${4:-}"

  local -r z_policy_file="${ZRBUH_PREFIX}${z_infix}${ZRBUH_POSTFIX_JSON}"

  test -n "${z_policy_file}" || return 1
  test -f "${z_policy_file}" || return 1
  test -n "${z_role}"        || return 1
  test -n "${z_member}"      || return 1

  local z_out=""
  z_out=$(
    jq --arg role "${z_role}" --arg member "${z_member}" --arg etag "${z_etag_opt}" '
      # Enforce RBGU standard: version=3 for all IAM policies
      .version = 3 |
      .bindings = (.bindings // []) |
      if ([.bindings[]? | .role] | index($role))
      then .bindings |= map(if .role == $role
                            then .members = ((.members // []) + [$member] | unique)
                            else . end)
      else .bindings += [{role: $role, members: [$member]}]
      end
      # Set etag if provided (optimistic concurrency)
      | (if $etag != "" then .etag = $etag else . end)
    ' "${z_policy_file}"
  ) || return 1

  test -n "${z_out}" || return 1
  printf '%s\n' "${z_out}"
}

# Remove a member from a role binding with version=3 enforcement — inverse of
# rbgi_jq_add_member_to_role_capture. This is the one legitimate shared helper
# (BCG load-bearing: pure JSON transform, no API, same failure class for every
# scope). jq subtraction drops all occurrences of the member, so an absent
# member is a no-op (idempotent). A binding left with no members is pruned —
# setIamPolicy rejects an empty members list; only the named role can empty out,
# since other bindings are untouched and arrive non-empty from getIamPolicy.
#
# Args: infix role member [etag_optional]
# Returns: JSON policy string with member removed and version=3
rbgi_jq_remove_member_from_role_capture() {
  zrbgi_sentinel

  local -r z_infix="${1:-}"
  local -r z_role="${2:-}"
  local -r z_member="${3:-}"
  local -r z_etag_opt="${4:-}"

  local -r z_policy_file="${ZRBUH_PREFIX}${z_infix}${ZRBUH_POSTFIX_JSON}"

  test -n "${z_policy_file}" || return 1
  test -f "${z_policy_file}" || return 1
  test -n "${z_role}"        || return 1
  test -n "${z_member}"      || return 1

  local z_out=""
  z_out=$(
    jq --arg role "${z_role}" --arg member "${z_member}" --arg etag "${z_etag_opt}" '
      # Enforce RBGU standard: version=3 for all IAM policies
      .version = 3 |
      .bindings = (.bindings // []) |
      # Drop the member from the named role, then prune any binding left empty
      .bindings |= ( map(if .role == $role
                         then .members = ((.members // []) - [$member])
                         else . end)
                     | map(select((.members // []) | length > 0)) )
      # Set etag if provided (optimistic concurrency)
      | (if $etag != "" then .etag = $etag else . end)
    ' "${z_policy_file}"
  ) || return 1

  test -n "${z_out}" || return 1
  printf '%s\n' "${z_out}"
}

# Provision service agent (Google-managed service account) for an enabled API.
# Uses serviceusage.googleapis.com generateServiceIdentity to deterministically
# ensure the service agent exists before granting it IAM roles.
# Prints the service agent email to stdout.
rbgi_provision_service_agent() {
  zrbgi_sentinel

  local -r z_api_service="${1}"
  local -r z_project_id="${2}"
  local -r z_token="${3}"

  test -n "${z_api_service}" || buc_die "rbgi_provision_service_agent: API service name required"
  test -n "${z_project_id}" || buc_die "rbgi_provision_service_agent: project ID required"
  test -n "${z_token}" || buc_die "rbgi_provision_service_agent: access token required"

  buc_log_args "Provisioning service agent for ${z_api_service} in ${z_project_id}"

  local -r z_infix="provision-sa-${z_api_service}"
  local -r z_url="https://serviceusage.googleapis.com/v1beta1/projects/${z_project_id}/services/${z_api_service}.googleapis.com:generateServiceIdentity"

  rbuh_json "POST" "${z_url}" "${z_token}" "${z_infix}" ""
  rbuh_require_ok "Provision service agent ${z_api_service}" "${z_infix}"

  local z_done
  z_done=$(rbuh_json_field_capture "${z_infix}" ".done") || z_done=""

  local z_final_infix="${z_infix}"
  if test "${z_done}" != "true"; then
    local z_op_name
    z_op_name=$(rbuh_json_field_capture "${z_infix}" ".name") || buc_die "Provision ${z_api_service}: no operation name"
    local -r z_poll_url="https://serviceusage.googleapis.com/v1beta1/${z_op_name}"

    local z_elapsed=0
    while :; do
      sleep "${RBGC_EVENTUAL_CONSISTENCY_SEC}"
      z_elapsed=$((z_elapsed + RBGC_EVENTUAL_CONSISTENCY_SEC))

      z_final_infix="${z_infix}-poll-${z_elapsed}s"
      rbuh_json "GET" "${z_poll_url}" "${z_token}" "${z_final_infix}"

      local z_code
      z_code=$(rbuh_code_capture "${z_final_infix}") || z_code=""
      test "${z_code}" = "200" || buc_die "Provision ${z_api_service}: poll failed (HTTP ${z_code})"

      z_done=$(rbuh_json_field_capture "${z_final_infix}" ".done") || z_done=""
      test "${z_done}" != "true" || break

      test "${z_elapsed}" -ge "${RBGC_MAX_CONSISTENCY_SEC}" \
        && buc_die "Provision ${z_api_service}: timeout after ${RBGC_MAX_CONSISTENCY_SEC}s"
      buc_log_args "Provision ${z_api_service}: still running at ${z_elapsed}s..."
    done
  fi

  local z_email
  z_email=$(rbuh_json_field_capture "${z_final_infix}" ".response.email") || z_email=""
  test -n "${z_email}" || buc_die "Provision service agent ${z_api_service}: no email in response"

  buc_log_args "Service agent provisioned: ${z_email}"
  printf '%s' "${z_email}"
}

# eof

