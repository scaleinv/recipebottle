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
# Recipe Bottle GCP Depot Constants - Project-dependent Implementation

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBGD_SOURCED:-}" || buc_die "Module rbgd multiply sourced - check sourcing hierarchy"
ZRBGD_SOURCED=1

######################################################################
# Internal Functions (zrbgd_*)

zrbgd_kindle() {
  test -z "${ZRBGD_KINDLED:-}" || buc_die "Module rbgd already kindled"

  # Depot-specific Constants — derive from RBDC kindle constants.
  # RBDC_DEPOT_PROJECT_ID is itself derived from
  # (RBRD_CLOUD_PREFIX, RBRD_DEPOT_MONIKER) at zrbdc_kindle time.

  # Service-specific Aliases
  readonly RBGD_GAR_PROJECT_ID="${RBDC_DEPOT_PROJECT_ID}"
  readonly RBGD_GAR_LOCATION="${RBRD_GCP_REGION}"
  readonly RBGD_GCB_PROJECT_ID="${RBDC_DEPOT_PROJECT_ID}"
  readonly RBGD_GCB_REGION="${RBRD_GCP_REGION}"

  # Project-dependent API Paths
  readonly RBGD_PROJECT_RESOURCE="${RBGC_PATH_PROJECTS}/${RBDC_DEPOT_PROJECT_ID}"

  # Common API Base Paths (hoisted for reuse)
  readonly RBGD_API_BASE_SERVICEUSAGE="${RBGC_API_ROOT_SERVICEUSAGE}${RBGC_SERVICEUSAGE_V1}${RBGC_PATH_PROJECTS}/${RBDC_DEPOT_PROJECT_ID}${RBGC_SERVICEUSAGE_PATH_SERVICES}"
  readonly RBGD_API_BASE_CRM_PROJECT="${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}${RBGC_PATH_PROJECTS}/${RBDC_DEPOT_PROJECT_ID}"
  readonly RBGD_API_BASE_CRM_PROJECT_V3="${RBGC_API_ROOT_CRM}${RBGC_CRM_V3}${RBGC_PATH_PROJECTS}/${RBDC_DEPOT_PROJECT_ID}"
  readonly RBGD_API_BASE_IAM_PROJECT="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}${RBGC_PATH_PROJECTS}/${RBDC_DEPOT_PROJECT_ID}"

  # IAM Service Accounts
  readonly RBGD_API_SERVICE_ACCOUNTS="${RBGD_API_BASE_IAM_PROJECT}${RBGC_PATH_SERVICE_ACCOUNTS}"
  readonly RBGD_SA_EMAIL_FULL="${RBDC_DEPOT_PROJECT_ID}.${RBGC_SA_EMAIL_DOMAIN}"

  # Depot name (the moniker) — input to RBGD_MASON_EMAIL. Moniker is the
  # operator-set RBRR field.
  readonly RBGD_DEPOT_NAME="${RBRD_DEPOT_MONIKER}"
  readonly RBGD_MASON_EMAIL="${RBCC_account_unhewn_mason}-${RBGD_DEPOT_NAME}@${RBGD_SA_EMAIL_FULL}"

  # Cloud Resource Manager (CRM) APIs. The IAM-policy pair rides CRM v3: Google's
  # Data Access audit-log procedure is documented only against v3 getIamPolicy/
  # setIamPolicy, and CRM v1 is on the deprecation path (see RBSMF audit-log step).
  # The project-lifecycle reads/deletes below stay on the v1 base they were proven against.
  readonly RBGD_API_CRM_GET_IAM_POLICY="${RBGD_API_BASE_CRM_PROJECT_V3}${RBGC_CRM_GET_IAM_POLICY_SUFFIX}"
  readonly RBGD_API_CRM_SET_IAM_POLICY="${RBGD_API_BASE_CRM_PROJECT_V3}${RBGC_CRM_SET_IAM_POLICY_SUFFIX}"
  readonly RBGD_API_CRM_GET_PROJECT="${RBGD_API_BASE_CRM_PROJECT}"
  readonly RBGD_API_CRM_DELETE_PROJECT="${RBGD_API_BASE_CRM_PROJECT}"
  readonly RBGD_API_CRM_UNDELETE_PROJECT="${RBGD_API_BASE_CRM_PROJECT}:undelete"

  # Service Usage - API Enablement
  readonly RBGD_API_SU_ENABLE_IAM="${RBGD_API_BASE_SERVICEUSAGE}/${RBGC_SERVICE_IAM}${RBGC_SERVICEUSAGE_ENABLE_SUFFIX}"
  readonly RBGD_API_SU_ENABLE_CRM="${RBGD_API_BASE_SERVICEUSAGE}/${RBGC_SERVICE_CRM}${RBGC_SERVICEUSAGE_ENABLE_SUFFIX}"
  readonly RBGD_API_SU_ENABLE_GAR="${RBGD_API_BASE_SERVICEUSAGE}/${RBGC_SERVICE_ARTIFACTREGISTRY}${RBGC_SERVICEUSAGE_ENABLE_SUFFIX}"
  readonly RBGD_API_SU_ENABLE_BUILD="${RBGD_API_BASE_SERVICEUSAGE}/cloudbuild.googleapis.com${RBGC_SERVICEUSAGE_ENABLE_SUFFIX}"
  readonly RBGD_API_SU_ENABLE_ANALYSIS="${RBGD_API_BASE_SERVICEUSAGE}/containeranalysis.googleapis.com${RBGC_SERVICEUSAGE_ENABLE_SUFFIX}"
  readonly RBGD_API_SU_ENABLE_STORAGE="${RBGD_API_BASE_SERVICEUSAGE}/storage.googleapis.com${RBGC_SERVICEUSAGE_ENABLE_SUFFIX}"

  # Service Usage - API Verification
  readonly RBGD_API_SU_VERIFY_IAM="${RBGD_API_BASE_SERVICEUSAGE}/${RBGC_SERVICE_IAM}"
  readonly RBGD_API_SU_VERIFY_CRM="${RBGD_API_BASE_SERVICEUSAGE}/${RBGC_SERVICE_CRM}"
  readonly RBGD_API_SU_VERIFY_GAR="${RBGD_API_BASE_SERVICEUSAGE}/${RBGC_SERVICE_ARTIFACTREGISTRY}"
  readonly RBGD_API_SU_VERIFY_BUILD="${RBGD_API_BASE_SERVICEUSAGE}/cloudbuild.googleapis.com"
  readonly RBGD_API_SU_VERIFY_ANALYSIS="${RBGD_API_BASE_SERVICEUSAGE}/containeranalysis.googleapis.com"
  readonly RBGD_API_SU_VERIFY_STORAGE="${RBGD_API_BASE_SERVICEUSAGE}/storage.googleapis.com"

  # Google Cloud Storage (GCS) APIs
  readonly RBGD_API_GCS_BUCKET_CREATE="${RBGC_API_GCS_BUCKETS}?project=${RBDC_DEPOT_PROJECT_ID}"

  readonly ZRBGD_KINDLED=1
}

zrbgd_sentinel() {
  test "${ZRBGD_KINDLED:-}" = "1" || buc_die "Module rbgd not kindled - call zrbgd_kindle first"
}

# eof
