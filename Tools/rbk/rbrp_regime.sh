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
# Recipe Bottle Payor Regime - Validator Module

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBRP_SOURCED:-}" || buc_die "Module rbrp multiply sourced - check sourcing hierarchy"
ZRBRP_SOURCED=1

######################################################################
# Internal Functions (zrbrp_*)

zrbrp_kindle() {
  test -z "${ZRBRP_KINDLED:-}" || buc_die "Module rbrp already kindled"

  # No defaults set — buv uses ${!varname:-} for safe indirect expansion under set -u.
  # Unset variables are detected distinctly from empty by zbuv_check_capture.

  # Enroll all RBRP variables — single source of truth for validation and rendering

  buv_regime_enroll RBRP

  buv_group_enroll "Payor Project Identity"
  buv_string_enroll  RBRP_PAYOR_PROJECT_ID  1  128  "GCP project hosting OAuth client"

  buv_group_enroll "Billing Configuration"
  buv_string_enroll  RBRP_BILLING_ACCOUNT_ID  0  20  "Billing account for depot projects"

  buv_group_enroll "OAuth Configuration"
  # min=0 deliberate — not every operator has a Payor identity (Retriever-only
  # operators authenticate via JWT SA, never via Payor OAuth). Required-at-use
  # is enforced by test -n in rbgp_payor.sh consumers. Do not tighten to min=1.
  buv_string_enroll  RBRP_OAUTH_CLIENT_ID  0  256  "OAuth 2.0 client identifier"

  buv_group_enroll "Operator Identity"
  buv_string_enroll  RBRP_OPERATOR_EMAIL  0  256  "Operator Google account email for console access"

  # Guard against unexpected RBRP_ variables not in enrollment
  buv_scope_sentinel RBRP RBRP_

  # Lock all enrolled RBRP_ variables against mutation
  buv_lock RBRP

  readonly ZRBRP_KINDLED=1
}

zrbrp_sentinel() {
  test "${ZRBRP_KINDLED:-}" = "1" || buc_die "Module rbrp not kindled - call zrbrp_kindle first"
}

# Enforce all RBRP enrollment validations and custom format checks
zrbrp_enforce() {
  zrbrp_sentinel

  buv_vet RBRP

  # Custom format checks beyond buv_ type system
  zrbgc_sentinel
  [[ "${RBRP_PAYOR_PROJECT_ID}" =~ ${RBGC_GLOBAL_PAYOR_REGEX} ]] \
    || buc_reject "${BUBC_band_regime}" "RBRP_PAYOR_PROJECT_ID does not match payor project pattern"

  if test -n "${RBRP_BILLING_ACCOUNT_ID}"; then
    [[ "${RBRP_BILLING_ACCOUNT_ID}" =~ ^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$ ]] \
      || buc_reject "${BUBC_band_regime}" "RBRP_BILLING_ACCOUNT_ID must be XXXXXX-XXXXXX-XXXXXX format"
  fi

  if test -n "${RBRP_OAUTH_CLIENT_ID}"; then
    [[ "${RBRP_OAUTH_CLIENT_ID}" =~ \.apps\.googleusercontent\.com$ ]] \
      || buc_reject "${BUBC_band_regime}" "RBRP_OAUTH_CLIENT_ID must end with .apps.googleusercontent.com"
  fi
}

# eof
