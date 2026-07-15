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
# Recipe Bottle Regime Repo - Validator Module

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBRR_SOURCED:-}" || buc_die "Module rbrr multiply sourced - check sourcing hierarchy"
ZRBRR_SOURCED=1

######################################################################
# Internal Functions (zrbrr_*)

zrbrr_kindle() {
  test -z "${ZRBRR_KINDLED:-}" || buc_die "Module rbrr already kindled"

  # No defaults set — buv uses ${!varname:-} for safe indirect expansion under set -u.
  # Unset variables are detected distinctly from empty by zbuv_check_capture.

  # Enroll all RBRR variables — single source of truth for validation and rendering

  buv_regime_enroll RBRR

  buv_group_enroll "Runtime Prefix"
  buv_string_enroll  RBRR_RUNTIME_PREFIX       2   11  "Prefix prepended to local container and network names"

  buv_group_enroll "Vessel and Local Configuration"
  buv_string_enroll  RBRR_VESSEL_DIR           1  255  "Vessel definitions directory"
  buv_string_enroll  RBRR_BOTTLE_WORKSPACE     1   64  "Container workspace path for bottle working directory"
  buv_ipv4_enroll    RBRR_DNS_SERVER                   "DNS server for containers"

  buv_group_enroll "Google Cloud Build Configuration"
  buv_string_enroll  RBRR_GCB_TIMEOUT                2   10  "Build timeout (e.g., 1200s)"
  buv_decimal_enroll RBRR_GCB_MIN_CONCURRENT_BUILDS  1  999  "Min concurrent builds required"

  buv_group_enroll "Secrets Directory"
  buv_string_enroll  RBRR_SECRETS_DIR              1  512  "Directory containing credential files"

  buv_group_enroll "Public Docs"
  buv_string_enroll  RBRR_PUBLIC_DOCS_URL          1  512  "Public docs URL — readme target for buh_tlt glossary links, updated per-release or per-incorporation"

  buv_group_enroll "Active Foedus"
  buv_xname_enroll   RBRR_ACTIVE_FOEDUS            6   64  "Active-foedus selector — the rbef_ subdirectory of the moorings foedera library the manor authenticates against"

  # Guard against unexpected RBRR_ variables not in enrollment
  buv_scope_sentinel RBRR RBRR_

  # Build docker env args array from validated values
  # Usage: docker run "${ZRBRR_DOCKER_ENV[@]}" ...
  ZRBRR_DOCKER_ENV=("-e" "RBRR_DNS_SERVER=${RBRR_DNS_SERVER}")
  readonly ZRBRR_DOCKER_ENV

  # Lock all enrolled RBRR_ variables against mutation
  buv_lock RBRR

  readonly ZRBRR_KINDLED=1
}

zrbrr_sentinel() {
  test "${ZRBRR_KINDLED:-}" = "1" || buc_die "Module rbrr not kindled - call zrbrr_kindle first"
}

# Enforce all RBRR enrollment validations and custom format checks
zrbrr_enforce() {
  zrbrr_sentinel

  buv_vet RBRR

  test -d "${RBRR_VESSEL_DIR}" \
    || buc_reject "${BUBC_band_regime}" "RBRR_VESSEL_DIR directory not found: ${RBRR_VESSEL_DIR}"
  test -d "${RBRR_SECRETS_DIR}" \
    || buc_reject "${BUBC_band_regime}" "RBRR_SECRETS_DIR directory not found: ${RBRR_SECRETS_DIR}"

  [[ "${RBRR_GCB_TIMEOUT}" =~ ^[0-9]+s$ ]] \
    || buc_reject "${BUBC_band_regime}" "Invalid RBRR_GCB_TIMEOUT format: ${RBRR_GCB_TIMEOUT} (expected NNNs)"

  [[ "${RBRR_RUNTIME_PREFIX}" =~ ^[a-z][a-z0-9-]*-$ ]] \
    || buc_reject "${BUBC_band_regime}" "Invalid RBRR_RUNTIME_PREFIX format: ${RBRR_RUNTIME_PREFIX} (expected lowercase starting with letter, ending in hyphen)"

  [[ "${RBRR_ACTIVE_FOEDUS}" == rbef_* ]] \
    || buc_reject "${BUBC_band_regime}" "RBRR_ACTIVE_FOEDUS must bear the rbef_ foedus-instance sprue: ${RBRR_ACTIVE_FOEDUS}"
}

# eof
