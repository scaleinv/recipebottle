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
# Recipe Bottle Regime Vessel - Validator Module

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBRV_SOURCED:-}" || buc_die "Module rbrv multiply sourced - check sourcing hierarchy"
ZRBRV_SOURCED=1

######################################################################
# Internal Functions (zrbrv_*)

zrbrv_kindle() {
  test -z "${ZRBRV_KINDLED:-}" || buc_die "Module rbrv already kindled"

  # No defaults set — buv uses ${!varname:-} for safe indirect expansion under set -u.
  # Unset variables are detected distinctly from empty by zbuv_check_capture.

  # Enroll all RBRV variables — single source of truth for validation and rendering

  buv_regime_enroll RBRV

  buv_group_enroll "Core Vessel Identity"
  buv_xname_enroll  RBRV_SIGIL             1   64  "Unique identifier (must match directory name)"
  buv_string_enroll RBRV_DESCRIPTION       0  512  "Human-readable description"
  buv_string_enroll RBRV_USER              0   64  "Container runtime user (unset means image default)"
  buv_enum_enroll   RBRV_VESSEL_MODE               "Operation mode: bind, conjure, or graft" \
                    rbnve_bind rbnve_conjure rbnve_graft

  buv_group_enroll "Tool Image Reliquary"
  buv_string_enroll RBRV_RELIQUARY             1   14  "Reliquary Lode touchmark (e.g., r260324193326) — identifies the conclave tool-image Lode in GAR"

  buv_group_enroll "Egress Mode"
  buv_enum_enroll   RBRV_EGRESS_MODE                   "Pool routing for primary build operation" \
                    rbnve_tether rbnve_airgap

  buv_group_enroll "Binding Configuration"
  buv_gate_enroll   RBRV_VESSEL_MODE  rbnve_bind
  buv_fqin_enroll   RBRV_BIND_IMAGE                1  512  "Source image to copy from registry"
  buv_string_enroll RBRV_BIND_OPTIONAL_DOCKERFILE  0  512  "Optional Dockerfile for about recipe.txt"

  buv_group_enroll "Conjuring Configuration"
  buv_gate_enroll   RBRV_VESSEL_MODE  rbnve_conjure
  buv_string_enroll RBRV_CONJURE_DOCKERFILE    1  512  "Dockerfile path relative to repo root"
  buv_string_enroll RBRV_CONJURE_BLDCONTEXT    1  512  "Build context relative to repo root"
  buv_string_enroll RBRV_CONJURE_PLATFORMS     1  512  "Space-separated target platforms"

  buv_group_enroll "Image Group"
  buv_gate_enroll   RBRV_VESSEL_MODE  rbnve_conjure
  buv_string_enroll RBRV_IMAGE_1_ORIGIN   0  512  "Upstream base image tag slot 1 (e.g., python:3.11-slim)"
  buv_string_enroll RBRV_IMAGE_1_ANCHOR   0  512  "GAR base locator slot 1 (package-path:tag, e.g. rbi_ld/<touchmark>:rbi_bole; written by the bole derived-pull election at ordain time)"
  buv_string_enroll RBRV_IMAGE_2_ORIGIN   0  512  "Upstream base image tag slot 2"
  buv_string_enroll RBRV_IMAGE_2_ANCHOR   0  512  "GAR base locator slot 2 (package-path:tag, e.g. rbi_ld/<touchmark>:rbi_bole; written by the bole derived-pull election at ordain time)"
  buv_string_enroll RBRV_IMAGE_3_ORIGIN   0  512  "Upstream base image tag slot 3"
  buv_string_enroll RBRV_IMAGE_3_ANCHOR   0  512  "GAR base locator slot 3 (package-path:tag, e.g. rbi_ld/<touchmark>:rbi_bole; written by the bole derived-pull election at ordain time)"

  buv_group_enroll "Grafting Configuration"
  buv_gate_enroll   RBRV_VESSEL_MODE  rbnve_graft
  buv_string_enroll RBRV_GRAFT_IMAGE                1  512  "Local image reference for graft operations"
  buv_string_enroll RBRV_GRAFT_OPTIONAL_DOCKERFILE  0  512  "Optional Dockerfile for about recipe.txt"

  # Guard against unexpected RBRV_ variables not in enrollment
  buv_scope_sentinel RBRV RBRV_

  # Lock all enrolled RBRV_ variables against mutation
  buv_lock RBRV

  readonly ZRBRV_KINDLED=1
}

zrbrv_sentinel() {
  test "${ZRBRV_KINDLED:-}" = "1" || buc_die "Module rbrv not kindled - call zrbrv_kindle first"
}

# Enforce all RBRV enrollment validations and custom format checks
zrbrv_enforce() {
  zrbrv_sentinel

  buv_vet RBRV

  # Bind vessels must be digest-pinned: the vouch's verify-provenance pins the
  # mirrored image against the @sha256: digest in RBRV_BIND_IMAGE, so a tag-only
  # source passes the mirror but fails the vouch deep in the cloud build. Reject
  # it here at config time. Invariant homed in RBSRV.
  if test "${RBRV_VESSEL_MODE}" = "rbnve_bind"; then
    local z_bind_digest_re='@sha256:[0-9a-f]{64}$'
    [[ "${RBRV_BIND_IMAGE}" =~ ${z_bind_digest_re} ]] \
      || buc_reject "${BUBC_band_regime}" "RBRV_BIND_IMAGE must be digest-pinned (name@sha256:<64-hex>), not a bare tag, for a bind vessel; got '${RBRV_BIND_IMAGE}'"
  fi
}

######################################################################
# Public Functions (rbrv_*)

# List available vessel sigils as space-separated tokens
# Prerequisite: RBRR kindled (needs RBRR_VESSEL_DIR)
rbrv_list_capture() {
  zrbrr_sentinel

  local z_result=""
  local z_dirs=("${RBRR_VESSEL_DIR}"/*)
  local z_i=""
  for z_i in "${!z_dirs[@]}"; do
    local z_d="${z_dirs[$z_i]}"
    test -d "${z_d}" || continue
    test -f "${z_d}/${RBCC_rbrv_file}" || continue
    local z_s="${z_d%/}"
    z_result="${z_result}${z_result:+ }${z_s##*/}"
  done
  test -n "${z_result}" || return 1
  echo "${z_result}"
}

# eof
