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
# Recipe Bottle Regime Depot - Validator Module

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBRD_SOURCED:-}" || buc_die "Module rbrd multiply sourced - check sourcing hierarchy"
ZRBRD_SOURCED=1

######################################################################
# Internal Functions (zrbrd_*)

zrbrd_kindle() {
  test -z "${ZRBRD_KINDLED:-}" || buc_die "Module rbrd already kindled"

  # No defaults set — buv uses ${!varname:-} for safe indirect expansion under set -u.
  # Unset variables are detected distinctly from empty by zbuv_check_capture.

  # Enroll all RBRD variables — single source of truth for validation and rendering

  buv_regime_enroll RBRD

  buv_group_enroll "Depot Identity"
  buv_string_enroll  RBRD_CLOUD_PREFIX         2   11  "Prefix for cloud-visible resource names (depot project, GAR repo, pool stem)"
  buv_string_enroll  RBRD_DEPOT_MONIKER        1   26  "Depot moniker — paired with CLOUD_PREFIX to derive depot project ID, GAR repo, and pool stem"

  buv_group_enroll "GCP Region"
  buv_gname_enroll   RBRD_GCP_REGION           1   32  "GCP region"

  buv_group_enroll "Google Cloud Build Pool"
  buv_gname_enroll   RBRD_GCB_MACHINE_TYPE     3   64  "Machine type for Cloud Build private worker pool (CE format)"

  # Guard against unexpected RBRD_ variables not in enrollment
  buv_scope_sentinel RBRD RBRD_

  # Lock all enrolled RBRD_ variables against mutation
  buv_lock RBRD

  readonly ZRBRD_KINDLED=1
}

zrbrd_sentinel() {
  test "${ZRBRD_KINDLED:-}" = "1" || buc_die "Module rbrd not kindled - call zrbrd_kindle first"
}

# Enforce all RBRD enrollment validations and custom format checks
zrbrd_enforce() {
  zrbrd_sentinel

  buv_vet RBRD

  [[ "${RBRD_DEPOT_MONIKER}" =~ ^[a-z][a-z0-9]*$ ]] \
    || buc_reject "${BUBC_band_regime}" "Invalid RBRD_DEPOT_MONIKER format: ${RBRD_DEPOT_MONIKER} (expected lowercase alphanumeric starting with letter; no hyphens)"

  [[ "${RBRD_CLOUD_PREFIX}" =~ ^[a-z][a-z0-9-]*-$ ]] \
    || buc_reject "${BUBC_band_regime}" "Invalid RBRD_CLOUD_PREFIX format: ${RBRD_CLOUD_PREFIX} (expected lowercase starting with letter, ending in hyphen)"

  # Joint-length cap: GCP project IDs max 30 chars. RBDC_DEPOT_PROJECT_ID
  # composes as "${RBRD_CLOUD_PREFIX}d-${RBRD_DEPOT_MONIKER}".
  #
  # Test fixtures (rbtdrp_lifecycle, rbtdrk_freehold) compose BURS_TINCTURE
  # (1-3 chars) into BOTH the prefix and the moniker before writing rbrd.env
  # for parallel-station disjointness on a shared payor manor. The cap below
  # applies to whatever is in rbrd.env at validation time — production-
  # authored or fixture-written. Fixture bases are short (≤7 chars) so
  # tinctured fixture values stay well under the cap; the joint check exists
  # to catch operator-authored prefix+moniker pairs that would overflow.
  # The validator does not cross-reference BURS_TINCTURE (BURS may not be
  # kindled in every RBRD-enforce context); the literal field values are
  # the contract.
  local -r z_prefix_len=${#RBRD_CLOUD_PREFIX}
  local -r z_moniker_len=${#RBRD_DEPOT_MONIKER}
  local -r z_joint_len=$(( z_prefix_len + 2 + z_moniker_len ))
  test "${z_joint_len}" -le 30 \
    || buc_reject "${BUBC_band_regime}" "Joint length exceeds 30-char GCP project ID limit: RBRD_CLOUD_PREFIX(${z_prefix_len}) + 'd-'(2) + RBRD_DEPOT_MONIKER(${z_moniker_len}) = ${z_joint_len}"
}

# eof
