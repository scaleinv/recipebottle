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
# Recipe Bottle Foundry Retriever - summon operation
# Retriever credentials

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBFR_SOURCED:-}" || buc_die "Module rbfr multiply sourced - check sourcing hierarchy"
ZRBFR_SOURCED=1

# Source shared Foundry Core module
source "${BASH_SOURCE[0]%/*}/rbfc0_core.sh"

######################################################################
# Internal Functions (zrbfr_*)

zrbfr_kindle() {
  test -z "${ZRBFR_KINDLED:-}" || buc_die "Module rbfr already kindled"

  buc_log_args 'Validate Foundry Core is kindled'
  zrbfc_sentinel

  buc_log_args 'Define retriever temp file prefix'
  readonly ZRBFR_TEMP_PREFIX="${BURD_TEMP_DIR}/rbfr_"

  readonly ZRBFR_KINDLED=1
}

zrbfr_sentinel() {
  zrbfc_sentinel
  test "${ZRBFR_KINDLED:-}" = "1" || buc_die "Module rbfr not kindled - call zrbfr_kindle first"
}

######################################################################
# Public Functions (rbfr_*)

rbfr_summon() {
  zrbfr_sentinel

  local -r z_express="${BUZ_FOLIO:-}"

  # Documentation block
  buc_doc_brief "Summon an ark (pull -image, -about, and -vouch artifacts as a coherent unit)"
  buc_doc_param "hallmark" "Full hallmark (e.g., c260305133650-r260305160530); optional — absent, falls back to the hallmark the prior build chained forward"
  buc_doc_shown || return 0

  # Relay-then-read (RBr_3e7): forward the chain baton before any read or failure point.
  buf_relay || buc_die "Failed to relay chained facts"

  # Resolve the hallmark express-or-chain: an express argument wins; absent, fall
  # back to the hallmark a prior build (ordain or kludge) handed forward through
  # the depth-1 chain — so a no-arg summon immediately after a build pulls the
  # just-built hallmark.
  local z_hallmark=""
  z_hallmark=$(buf_elect_fact_capture "${z_express}" "${RBF_FACT_HALLMARK}") \
    || buc_reject "${BUBC_band_chain}" "No hallmark — pass one (use rbw-ft to tally vouched hallmarks) or run a build immediately before summon"

  buc_step "Authenticating for retrieval"
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_retriever}") || buc_die "Failed to get OAuth token"

  # Ark package paths — all basename siblings under the hallmark subtree
  local -r z_image_pkg="${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_IMAGE}"
  local -r z_about_pkg="${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_ABOUT}"
  local -r z_vouch_pkg="${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_VOUCH}"

  buc_step "Verifying ark existence"

  # Check if image ark exists (tag = hallmark)
  local z_image_status_file="${ZRBFR_TEMP_PREFIX}summon_image_status.txt"
  local z_image_response_file="${ZRBFR_TEMP_PREFIX}summon_image_response.json"

  local z_curl_status=0
  curl --head -s                                     \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
    --max-time "${RBCC_CURL_MAX_TIME_SEC}"           \
    -H "Authorization: Bearer ${z_token}"           \
    -H "Accept: ${ZRBFC_ACCEPT_MANIFEST_MTYPES}"     \
    -w "%{http_code}"                               \
    -o "${z_image_response_file}"                   \
    "${ZRBFC_REGISTRY_API_BASE}/${z_image_pkg}/manifests/${z_hallmark}" \
    > "${z_image_status_file}" || z_curl_status=$?
  test "${z_curl_status}" -eq 0 || buc_die "HEAD request failed for image ark (curl exit ${z_curl_status})"

  local z_image_http_code
  z_image_http_code=$(<"${z_image_status_file}")
  test -n "${z_image_http_code}" || buc_die "HTTP status code is empty for image ark"

  local z_image_exists=false
  if test "${z_image_http_code}" = "200"; then
    z_image_exists=true
  elif test "${z_image_http_code}" != "404"; then
    buc_die "Unexpected HTTP status ${z_image_http_code} when checking image ark"
  fi

  # Check if about ark exists
  local z_about_status_file="${ZRBFR_TEMP_PREFIX}summon_about_status.txt"
  local z_about_response_file="${ZRBFR_TEMP_PREFIX}summon_about_response.json"

  curl --head -s                                     \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
    --max-time "${RBCC_CURL_MAX_TIME_SEC}"           \
    -H "Authorization: Bearer ${z_token}"           \
    -H "Accept: ${ZRBFC_ACCEPT_MANIFEST_MTYPES}"     \
    -w "%{http_code}"                               \
    -o "${z_about_response_file}"                   \
    "${ZRBFC_REGISTRY_API_BASE}/${z_about_pkg}/manifests/${z_hallmark}" \
    > "${z_about_status_file}" || z_curl_status=$?
  test "${z_curl_status}" -eq 0 || buc_die "HEAD request failed for about ark (curl exit ${z_curl_status})"

  local z_about_http_code
  z_about_http_code=$(<"${z_about_status_file}")
  test -n "${z_about_http_code}" || buc_die "HTTP status code is empty for about ark"

  local z_about_exists=false
  if test "${z_about_http_code}" = "200"; then
    z_about_exists=true
  elif test "${z_about_http_code}" != "404"; then
    buc_die "Unexpected HTTP status ${z_about_http_code} when checking about ark"
  fi

  # Check if vouch ark exists
  local z_vouch_status_file="${ZRBFR_TEMP_PREFIX}summon_vouch_status.txt"
  local z_vouch_response_file="${ZRBFR_TEMP_PREFIX}summon_vouch_response.json"

  curl --head -s                                     \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
    --max-time "${RBCC_CURL_MAX_TIME_SEC}"           \
    -H "Authorization: Bearer ${z_token}"           \
    -H "Accept: ${ZRBFC_ACCEPT_MANIFEST_MTYPES}"     \
    -w "%{http_code}"                               \
    -o "${z_vouch_response_file}"                   \
    "${ZRBFC_REGISTRY_API_BASE}/${z_vouch_pkg}/manifests/${z_hallmark}" \
    > "${z_vouch_status_file}" || z_curl_status=$?
  test "${z_curl_status}" -eq 0 || buc_die "HEAD request failed for vouch ark (curl exit ${z_curl_status})"

  local z_vouch_http_code
  z_vouch_http_code=$(<"${z_vouch_status_file}")
  test -n "${z_vouch_http_code}" || buc_die "HTTP status code is empty for vouch ark"

  local z_vouch_exists=false
  if test "${z_vouch_http_code}" = "200"; then
    z_vouch_exists=true
  elif test "${z_vouch_http_code}" != "404"; then
    buc_die "Unexpected HTTP status ${z_vouch_http_code} when checking vouch ark"
  fi

  # Evaluate ark state
  if test "${z_image_exists}" = "false" && test "${z_about_exists}" = "false"; then
    buc_reject "${BUBC_band_vacant}" "Hallmark not found: neither image nor about ark exists"
  fi

  if test "${z_image_exists}" = "true" && test "${z_about_exists}" = "false"; then
    buc_warn "Orphaned artifact detected: image ark exists but about is missing"
  elif test "${z_image_exists}" = "false" && test "${z_about_exists}" = "true"; then
    buc_warn "Orphaned artifact detected: about ark exists but image is missing"
  fi

  buc_step "Logging into container registry"

  # Docker login to GAR
  rbgo_docker_login "${z_token}" "${ZRBFC_REGISTRY_HOST}"

  # Pull image ark if exists
  if test "${z_image_exists}" = "true"; then
    buc_step "Pulling image ark"

    local z_image_ref="${ZRBFC_REGISTRY_HOST}/${ZRBFC_REGISTRY_PATH}/${z_image_pkg}:${z_hallmark}"
    docker pull "${z_image_ref}" || buc_die "Failed to pull image ark"
    buc_info "Retrieved: ${z_image_ref}"
  fi

  # Pull about ark if exists
  if test "${z_about_exists}" = "true"; then
    buc_step "Pulling about ark"

    local z_about_ref="${ZRBFC_REGISTRY_HOST}/${ZRBFC_REGISTRY_PATH}/${z_about_pkg}:${z_hallmark}"
    docker pull "${z_about_ref}" || buc_die "Failed to pull about ark"
    buc_info "Retrieved: ${z_about_ref}"
  fi

  # Pull vouch ark if exists
  if test "${z_vouch_exists}" = "true"; then
    buc_step "Pulling vouch ark"

    local z_vouch_ref="${ZRBFC_REGISTRY_HOST}/${ZRBFC_REGISTRY_PATH}/${z_vouch_pkg}:${z_hallmark}"
    docker pull "${z_vouch_ref}" || buc_die "Failed to pull vouch ark"
    buc_info "Retrieved: ${z_vouch_ref}"
  fi

  # Display results
  echo ""
  buc_success "Hallmark summoned: ${z_hallmark}"
  if test "${z_image_exists}" = "true"; then
    echo "  - ${RBGC_GAR_CATEGORY_HALLMARKS}/${z_hallmark}/${RBGC_ARK_BASENAME_IMAGE} retrieved"
  fi
  if test "${z_about_exists}" = "true"; then
    echo "  - ${RBGC_GAR_CATEGORY_HALLMARKS}/${z_hallmark}/${RBGC_ARK_BASENAME_ABOUT} retrieved"
  fi
  if test "${z_vouch_exists}" = "true"; then
    echo "  - ${RBGC_GAR_CATEGORY_HALLMARKS}/${z_hallmark}/${RBGC_ARK_BASENAME_VOUCH} retrieved"
  fi
}

# eof
