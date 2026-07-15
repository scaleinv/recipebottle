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
# Recipe Bottle Workforce Regime - Validator Module

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBRW_SOURCED:-}" || buc_die "Module rbrw multiply sourced - check sourcing hierarchy"
ZRBRW_SOURCED=1

######################################################################
# Internal Functions (zrbrw_*)

zrbrw_kindle() {
  test -z "${ZRBRW_KINDLED:-}" || buc_die "Module rbrw already kindled"

  # No defaults set — buv uses ${!varname:-} for safe indirect expansion under set -u.
  # Unset variables are detected distinctly from empty by zbuv_check_capture.

  # Enroll all RBRW variables — single source of truth for validation and rendering

  buv_regime_enroll RBRW

  buv_group_enroll "Workforce Pool Identity"
  buv_string_enroll  RBRW_ORG_ID               6   32  "GCP organization numeric ID owning the manor's one workforce pool"
  buv_string_enroll  RBRW_WORKFORCE_POOL_ID    4   32  "The manor's one workforce identity pool ID — org-scoped, every foedus a provider beneath it"
  buv_string_enroll  RBRW_SESSION_DURATION     2   10  "Workforce pool session duration — the sitting cap (e.g. 3600s), bounded 900s-43200s"

  # Guard against unexpected RBRW_ variables not in enrollment
  buv_scope_sentinel RBRW RBRW_

  # Lock all enrolled RBRW_ variables against mutation
  buv_lock RBRW

  readonly ZRBRW_KINDLED=1
}

zrbrw_sentinel() {
  test "${ZRBRW_KINDLED:-}" = "1" || buc_die "Module rbrw not kindled - call zrbrw_kindle first"
}

# Enforce all RBRW enrollment validations and custom format checks
zrbrw_enforce() {
  zrbrw_sentinel

  buv_vet RBRW

  [[ "${RBRW_ORG_ID}" =~ ^[0-9]{6,}$ ]] \
    || buc_reject "${BUBC_band_regime}" "RBRW_ORG_ID must be a numeric GCP organization ID: ${RBRW_ORG_ID}"

  # GCP workforce-pool id: lowercase letter-led, [a-z0-9-], no trailing hyphen,
  # 4-32 chars, and the gcp- prefix is reserved by GCP (RBSRW).
  [[ "${RBRW_WORKFORCE_POOL_ID}" =~ ^[a-z][a-z0-9-]{2,30}[a-z0-9]$ ]] \
    || buc_reject "${BUBC_band_regime}" "Invalid RBRW_WORKFORCE_POOL_ID: ${RBRW_WORKFORCE_POOL_ID} (lowercase letter-led, [a-z0-9-], no trailing hyphen, 4-32 chars)"
  [[ "${RBRW_WORKFORCE_POOL_ID}" != gcp-* ]] \
    || buc_reject "${BUBC_band_regime}" "RBRW_WORKFORCE_POOL_ID must not start with the reserved gcp- prefix: ${RBRW_WORKFORCE_POOL_ID}"

  # Session duration: NNNs form, bounded 900s (15 min) to 43200s (12 hours) per RBSRW.
  [[ "${RBRW_SESSION_DURATION}" =~ ^[0-9]+s$ ]] \
    || buc_reject "${BUBC_band_regime}" "Invalid RBRW_SESSION_DURATION: ${RBRW_SESSION_DURATION} (expected NNNs, e.g. 3600s)"
  (( 10#${RBRW_SESSION_DURATION%s} >= 900 && 10#${RBRW_SESSION_DURATION%s} <= 43200 )) \
    || buc_reject "${BUBC_band_regime}" "RBRW_SESSION_DURATION out of bounds: ${RBRW_SESSION_DURATION} (must be 900s-43200s)"
}

# eof
