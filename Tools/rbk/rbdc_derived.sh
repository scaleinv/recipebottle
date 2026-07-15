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
# Recipe Bottle Derived Constants - Credential file path resolution

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBDC_SOURCED:-}" || buc_die "Module rbdc multiply sourced - check sourcing hierarchy"
ZRBDC_SOURCED=1

######################################################################
# Internal Functions (zrbdc_*)

zrbdc_kindle() {
  test -z "${ZRBDC_KINDLED:-}" || buc_die "Module rbdc already kindled"
  zrbrr_sentinel

  # Ensure the payor secrets subdirectory exists — the sole durable secret is the
  # payor's RBRO refresh token (bare-named: a derived resource-name string).
  mkdir -p "${RBRR_SECRETS_DIR}/${RBCC_account_unhewn_payor}" \
    || buc_die "Failed to create secrets directories under: ${RBRR_SECRETS_DIR}"

  # Derive the payor credential file path from RBRR_SECRETS_DIR
  readonly RBDC_PAYOR_RBRO_FILE="${RBRR_SECRETS_DIR}/${RBCC_account_unhewn_payor}/${RBCC_rbro_file}"

  # Derive depot identity from (RBRD_CLOUD_PREFIX, RBRD_DEPOT_MONIKER).
  # Project ID, GAR repository, and pool stem fall out at kindle.
  # Project-ID infix lifted to RBGC tinder (`RBGC_depot_project_infix`),
  # available at source time without rbgc kindle ordering dependency.
  readonly RBDC_DEPOT_PROJECT_ID="${RBRD_CLOUD_PREFIX}${RBGC_depot_project_infix}${RBRD_DEPOT_MONIKER}"
  readonly RBDC_GAR_REPOSITORY="${RBRD_CLOUD_PREFIX}${RBRD_DEPOT_MONIKER}-gar"
  readonly RBDC_GCB_POOL_STEM="${RBRD_CLOUD_PREFIX}${RBRD_DEPOT_MONIKER}-pool"

  # Derive full pool resource paths from stem (suffixes match RBGC_POOL_SUFFIX_TETHER/AIRGAP)
  readonly RBDC_POOL_TETHER="projects/${RBDC_DEPOT_PROJECT_ID}/locations/${RBRD_GCP_REGION}/workerPools/${RBDC_GCB_POOL_STEM}-tether"
  readonly RBDC_POOL_AIRGAP="projects/${RBDC_DEPOT_PROJECT_ID}/locations/${RBRD_GCP_REGION}/workerPools/${RBDC_GCB_POOL_STEM}-airgap"

  readonly ZRBDC_KINDLED=1
}

zrbdc_sentinel() {
  test "${ZRBDC_KINDLED:-}" = "1" || buc_die "Module rbdc not kindled - call zrbdc_kindle first"
}

# eof
