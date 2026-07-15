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
# BURS Regime - Bash Utility Regime Station Module

set -euo pipefail

# Multiple inclusion detection
test -z "${ZBURS_SOURCED:-}" || buc_die "Module burs multiply sourced - check sourcing hierarchy"
ZBURS_SOURCED=1

######################################################################
# Internal Functions (zburs_*)

zburs_kindle() {
  test -z "${ZBURS_KINDLED:-}" || buc_die "Module burs already kindled"

  # No defaults set — buv uses ${!varname:-} for safe indirect expansion under set -u.
  # Unset variables are detected distinctly from empty by zbuv_check_capture.

  # Enroll all BURS variables — single source of truth for validation and rendering

  buv_regime_enroll BURS

  buv_group_enroll "Developer Identity"
  buv_xname_enroll   BURS_USER     1   32  "Local developer username (routes to ${BURD_MOORINGS_DIR}/${BUBC_rbmu_users_subdir}/ profiles)"
  buv_string_enroll  BURS_TINCTURE 1    3  "Per-station tincture composed by test fixtures into cloud/runtime prefixes and family stems for parallel-run disjointness on a shared payor manor (lowercase alphanumeric, leading letter, no hyphen)"

  buv_group_enroll "Developer Logging"
  buv_string_enroll  BURS_LOG_DIR  1  512  "Directory for BUK operation logs"

  # Guard against unexpected BURS_ variables not in enrollment
  buv_scope_sentinel BURS BURS_

  # Lock all enrolled BURS_ variables against mutation
  buv_lock BURS

  readonly ZBURS_KINDLED=1
}

zburs_sentinel() {
  test "${ZBURS_KINDLED:-}" = "1" || buc_die "Module burs not kindled - call zburs_kindle first"
}

# Enforce all BURS enrollment validations
zburs_enforce() {
  zburs_sentinel

  buv_vet BURS

  [[ "${BURS_TINCTURE}" =~ ^[a-z][a-z0-9]{0,2}$ ]] \
    || buc_reject "${BUBC_band_regime}" "Invalid BURS_TINCTURE format: ${BURS_TINCTURE} (expected 1-3 chars, lowercase alphanumeric starting with letter; no hyphens)"
}

# eof
