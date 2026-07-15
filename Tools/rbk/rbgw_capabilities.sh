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
# Recipe Bottle Capability-Sets - per-role resource-grant lists, named once.
#
# The single home for the three role capability-sets (governor, director,
# retriever). Each set is the role's complete resource-grant list, applied
# identically to a bridge-legacy enrobed service account and to the role's
# mantle service account established at depot levy. The member email is the
# only per-call variable. Sourced by both enrobe CLIs (rbgg / rbgp) and levy.

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBGW_SOURCED:-}" || buc_die "Module rbgw multiply sourced - check sourcing hierarchy"
ZRBGW_SOURCED=1

######################################################################
# Internal Functions (zrbgw_*)

zrbgw_kindle() {
  test -z "${ZRBGW_KINDLED:-}" || buc_die "Module rbgw already kindled"

  buv_dir_exists "${BURD_TEMP_DIR}"

  buc_log_args 'Ensure dependencies are kindled first'
  zrbgc_sentinel
  zrbdc_sentinel
  zrbgd_sentinel
  zrbgi_sentinel
  zrbuh_sentinel

  readonly ZRBGW_KINDLED=1
}

zrbgw_sentinel() {
  test "${ZRBGW_KINDLED:-}" = "1" || buc_die "Module rbgw not kindled - call zrbgw_kindle first"
}

######################################################################
# External Functions (rbgw_*)

# Retriever capability-set — the role's resource-grant list as named code.
# Applied to z_member_email: the enrobed retriever SA today, the retriever
# mantle SA at levy. The member is the only per-call variable.
rbgw_grant_retriever_capabilities() {
  zrbgw_sentinel

  local -r z_token="${1:-}"
  local -r z_member_email="${2:-}"

  test -n "${z_token}"        || buc_die "rbgw_grant_retriever_capabilities: token required"
  test -n "${z_member_email}" || buc_die "rbgw_grant_retriever_capabilities: member email required"

  buc_step 'Adding Artifact Registry Reader role'
  rbgi_add_project_iam_role                 \
    "${z_token}"                            \
    "Grant Artifact Registry Reader"        \
    "${RBGD_PROJECT_RESOURCE}"              \
    "${RBGC_ROLE_ARTIFACTREGISTRY_READER}"  \
    "serviceAccount:${z_member_email}"      \
    "retriever-reader"

  buc_step 'Adding Container Analysis Occurrences Viewer role'
  rbgi_add_project_iam_role                              \
    "${z_token}"                                         \
    "Grant Container Analysis Occurrences Viewer"        \
    "${RBGD_PROJECT_RESOURCE}"                           \
    "${RBGC_ROLE_CONTAINERANALYSIS_OCCURRENCES_VIEWER}"  \
    "serviceAccount:${z_member_email}"                   \
    "retriever-analysis"
}

# Director capability-set — the role's resource-grant list as named code.
# Applied to z_member_email: the enrobed director SA today, the director mantle
# SA at levy. Heterogeneous by nature (project grants, Mason and self actAs, a
# self-actAs read-back poll, the complete AR repo-policy ceremony) — which is why
# it is a function, not a flat list. The member is the only per-call variable.
rbgw_grant_director_capabilities() {
  zrbgw_sentinel

  local -r z_token="${1:-}"
  local -r z_member_email="${2:-}"

  test -n "${z_token}"        || buc_die "rbgw_grant_director_capabilities: token required"
  test -n "${z_member_email}" || buc_die "rbgw_grant_director_capabilities: member email required"

  buc_step 'Adding Cloud Build Editor role (project scope)'
  rbgi_add_project_iam_role                 \
    "${z_token}"                            \
    "Grant Cloud Build Editor"              \
    "${RBGD_PROJECT_RESOURCE}"              \
    "${RBGC_ROLE_CLOUDBUILD_BUILDS_EDITOR}" \
    "serviceAccount:${z_member_email}"      \
    "director-cb"

  rbgi_add_project_iam_role                 \
    "${z_token}"                            \
    "Grant Project Viewer"                  \
    "${RBGD_PROJECT_RESOURCE}"              \
    "roles/viewer"                          \
    "serviceAccount:${z_member_email}"      \
    "director-viewer"

  rbgi_add_project_iam_role                 \
    "${z_token}"                            \
    "Grant Worker Pool User"               \
    "${RBGD_PROJECT_RESOURCE}"              \
    "roles/cloudbuild.workerPoolUser"       \
    "serviceAccount:${z_member_email}"      \
    "director-pool"

  buc_step 'Grant serviceAccountUser on Mason'
  rbgi_add_sa_iam_role "${z_token}" "${RBGD_MASON_EMAIL}" "${z_member_email}" "roles/iam.serviceAccountUser"

  buc_step 'Grant serviceAccountUser on self (Director runs cloud-dispatched delete builds as itself)'
  # The cloud-dispatched banish/abjure delete build runs AS the Director SA — the
  # only identity holding repoAdmin/delete (Mason stays writer-only). The Director-
  # authenticated submit therefore needs actAs on the Director SA itself: the
  # self-actAs binding that lets a SA run a build as itself. workerPoolUser and
  # builds.create (Cloud Build Editor) are already granted above; no new GAR grant
  # is needed because Director already holds repoAdmin.
  rbgi_add_sa_iam_role "${z_token}" "${z_member_email}" "${z_member_email}" "roles/iam.serviceAccountUser"

  buc_step 'Read-back: confirm self-actAs binding visible before declaring enrobe complete'
  # The first post-enrobe builds.create exercises this binding (the spine
  # dispatch has no tolerance for a PERMISSION_DENIED actAs flap), so the
  # Class-C propagation wait is confined here, enrobe-side, rather than
  # spread to every spine rider's submit path.
  rbgi_poll_sa_iam_binding "${z_token}" "${z_member_email}" "${z_member_email}" "roles/iam.serviceAccountUser"

  buc_step 'Grant Artifact Registry roles (complete expected policy)'
  # Complete policy: Director repoAdmin + Mason writer in one setIamPolicy.
  # Prevents read-modify-write race where stale getIamPolicy omits Mason's binding.
  local -r z_gar_resource="projects/${RBGD_GAR_PROJECT_ID}/locations/${RBGD_GAR_LOCATION}/repositories/${RBDC_GAR_REPOSITORY}"
  local -r z_gar_get_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_gar_resource}:getIamPolicy?options.requestedPolicyVersion=3"
  local -r z_gar_set_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/${z_gar_resource}:setIamPolicy"

  # Propagation retry — AR repo is resource-scope: member-visibility 400s plus
  # caller-recently-empowered 403 from the resource-scope IAM cache (the
  # governor's roles/owner grant may not yet have reached the AR cache).
  local -ra z_gar_tolerance=(
    "400" "*does not exist*"
    "400" "*is not deleted*"
    "403" ""
  )
  local z_gar_prop_delay=${RBGC_PROPAGATION_INITIAL_DELAY_SEC}
  local z_gar_prop_elapsed=0
  local -r z_gar_prop_deadline=${RBGC_PROPAGATION_DEADLINE_SEC}
  local z_gar_prop_attempt=0
  local z_gar_get_infix=""
  local z_gar_set_infix=""
  local z_gar_get_code=""

  while :; do
    z_gar_prop_attempt=$((z_gar_prop_attempt + 1))
    z_gar_get_infix="director_gar_get_iam-${z_gar_prop_elapsed}s"
    z_gar_set_infix="director_gar_set_iam-${z_gar_prop_elapsed}s"

    rbuh_json "GET" "${z_gar_get_url}" "${z_token}" "${z_gar_get_infix}"
    z_gar_get_code=$(rbuh_code_capture "${z_gar_get_infix}") || z_gar_get_code=""

    # Propagation retry on GET — covers newly-empowered governor (403) and
    # newly-created Director SA member-visibility lag (400 patterns).
    if zrbgi_propagation_error_predicate "${z_gar_get_infix}" "${z_gar_get_code}" "${z_gar_tolerance[@]}"; then
      test "${z_gar_prop_elapsed}" -lt "${z_gar_prop_deadline}" \
        || buc_die "GAR IAM: propagation timeout after ${z_gar_prop_elapsed}s"
      buc_log_args "GAR getIamPolicy returned ${z_gar_get_code} (propagation delay; attempt ${z_gar_prop_attempt}, ${z_gar_prop_elapsed}s)"
      sleep "${z_gar_prop_delay}"
      z_gar_prop_elapsed=$((z_gar_prop_elapsed + z_gar_prop_delay))
      z_gar_prop_delay=$((z_gar_prop_delay * 2))
      test "${z_gar_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_gar_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    rbuh_require_ok "Get GAR repo IAM policy" "${z_gar_get_infix}"

    # Build complete expected policy: Director repoAdmin + Mason writer
    local z_gar_partial
    z_gar_partial=$(rbgi_jq_add_member_to_role_capture "${z_gar_get_infix}" \
      "roles/artifactregistry.repoAdmin" "serviceAccount:${z_member_email}" "") \
      || buc_die "Failed to add Director repoAdmin to GAR IAM policy"

    local z_gar_intermediate="${BURD_TEMP_DIR}/rbuh_director_gar_complete_iam_u_resp.json"
    printf '%s\n' "${z_gar_partial}" > "${z_gar_intermediate}" \
      || buc_die "Failed to write intermediate GAR IAM policy"

    local z_gar_complete
    z_gar_complete=$(rbgi_jq_add_member_to_role_capture "director_gar_complete_iam" \
      "roles/artifactregistry.writer" "serviceAccount:${RBGD_MASON_EMAIL}" "") \
      || buc_die "Failed to add Mason writer to GAR IAM policy"

    local z_gar_set_body="${BURD_TEMP_DIR}/rbgg_gar_complete_policy_body.json"
    printf '{"policy":%s}\n' "${z_gar_complete}" > "${z_gar_set_body}" \
      || buc_die "Failed to write GAR setIamPolicy body"
    rbuh_json "POST" "${z_gar_set_url}" "${z_token}" "${z_gar_set_infix}" "${z_gar_set_body}"

    local z_gar_set_code
    z_gar_set_code=$(rbuh_code_capture "${z_gar_set_infix}") || buc_die "No HTTP code from GAR setIamPolicy"

    # Propagation retry on SET — same tolerance list as GET.
    if zrbgi_propagation_error_predicate "${z_gar_set_infix}" "${z_gar_set_code}" "${z_gar_tolerance[@]}"; then
      test "${z_gar_prop_elapsed}" -lt "${z_gar_prop_deadline}" \
        || buc_die "GAR IAM: propagation timeout after ${z_gar_prop_elapsed}s"
      buc_log_args "GAR setIamPolicy returned ${z_gar_set_code} (propagation delay; attempt ${z_gar_prop_attempt}, ${z_gar_prop_elapsed}s)"
      sleep "${z_gar_prop_delay}"
      z_gar_prop_elapsed=$((z_gar_prop_elapsed + z_gar_prop_delay))
      z_gar_prop_delay=$((z_gar_prop_delay * 2))
      test "${z_gar_prop_delay}" -le "${RBGC_PROPAGATION_MAX_DELAY_SEC}" || z_gar_prop_delay=${RBGC_PROPAGATION_MAX_DELAY_SEC}
      continue
    fi

    rbuh_require_ok "Set GAR repo IAM policy (complete)" "${z_gar_set_infix}"
    break
  done
}

# Governor capability-set — the role's resource-grant list as named code.
# Applied to z_member_email: the governor SA created at enrobe today, the governor
# mantle SA at levy. roles/owner on the depot project is the whole set, named so
# levy can grant it to the mantle SA verbatim.
rbgw_grant_governor_capabilities() {
  zrbgw_sentinel

  local -r z_token="${1:-}"
  local -r z_member_email="${2:-}"

  test -n "${z_token}"        || buc_die "rbgw_grant_governor_capabilities: token required"
  test -n "${z_member_email}" || buc_die "rbgw_grant_governor_capabilities: member email required"

  buc_step 'Grant roles/owner on depot project'
  rbgi_add_project_iam_role \
    "${z_token}" \
    "Grant Governor Owner" \
    "projects/${RBDC_DEPOT_PROJECT_ID}" \
    "roles/owner" \
    "serviceAccount:${z_member_email}" \
    "governor-owner"
}

# eof
