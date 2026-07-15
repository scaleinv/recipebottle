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
# Recipe Bottle Foundry Ledger - delete cluster (guard-free, sourced by rbflk_):
# jettison a single image tag by locator, or abjure a whole hallmark subtree
# (Director credentials).

set -euo pipefail

######################################################################
# Delete (rbfl_*)

rbfl_jettison() {
  zrbfl_sentinel

  local z_locator="${BUZ_FOLIO:-}"

  # Documentation block
  buc_doc_brief "Jettison an image tag or version from the registry by raw ref (type-blind)"
  buc_doc_param "ref" "Image ref: package:tag or package@sha256:<hex>. Type-blind over any rbi_* namespace. Below-package grain only — whole-package delete is banish/abjure."
  buc_doc_shown || return 0

  # Validate ref parameter
  test -n "${z_locator}" || buc_die "Image ref required (package:tag or package@sha256:<hex>)"

  # Parse the image ref into package path and manifest reference. GAR's two
  # deletable leaves are a tag (package:tag) and a version digest
  # (package@sha256:<hex>); Docker Registry v2 DELETE addresses both by
  # /manifests/<reference>. The @ form is matched first — a digest ref carries
  # a colon too, so a naive split-on-colon would mangle it.
  local z_pkg_path z_ref
  case "${z_locator}" in
    *@*) z_pkg_path="${z_locator%@*}"; z_ref="${z_locator##*@}" ;;
    *:*) z_pkg_path="${z_locator%:*}"; z_ref="${z_locator##*:}" ;;
    *)   buc_die "Invalid image ref. Expected package:tag or package@sha256:<hex>" ;;
  esac
  test -n "${z_pkg_path}" || buc_die "Package path is empty in image ref"
  test -n "${z_ref}"      || buc_die "Reference (tag or digest) is empty in image ref"

  buc_step "Authenticating as Director"

  # Get OAuth token using Director credentials
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_director}") || buc_die "Failed to get OAuth token"

  buc_require "Will jettison: ${z_locator}" "yes"

  buc_step "Jettisoning: ${z_locator}"

  # Jettison by tag reference
  local z_status_file="${ZRBFL_DELETE_PREFIX}status.txt"
  local z_response_file="${ZRBFL_DELETE_PREFIX}response.json"
  local z_stderr_file="${ZRBFL_DELETE_PREFIX}stderr.txt"

  rbuh_request "DELETE"                                                  \
                    "${ZRBFC_REGISTRY_API_BASE}/${z_pkg_path}/manifests/${z_ref}" \
                    "${z_token}"                                              \
                    "${z_response_file}" "${z_status_file}" "${z_stderr_file}" \
    || buc_die "DELETE request failed — see ${z_stderr_file}"

  local z_http_code
  z_http_code=$(<"${z_status_file}")
  test -n "${z_http_code}" || buc_die "HTTP status code is empty"

  # 202/204 = deleted; 404 = already gone. Idempotent delete is the house shape
  # (rbuh_poll_until_gone, the rbgjl06 convergence loop) — a cleanup-of-last-resort
  # verb must not die on already-gone, and the success message is the contract.
  if test "${z_http_code}" != "202" && test "${z_http_code}" != "204" && test "${z_http_code}" != "404"; then
    local z_body="empty"
    if test -f "${z_response_file}"; then z_body=$(<"${z_response_file}"); fi
    buc_warn "Response body: ${z_body}"
    buc_die "Jettison failed with HTTP ${z_http_code}"
  fi

  buc_success "Jettisoned or nonexistent: ${z_locator}"
}

rbfl_abjure() {
  zrbfl_sentinel

  local z_hallmark="${BUZ_FOLIO:-}"

  # Documentation block
  buc_doc_brief "Abjure a hallmark — delete all GAR packages under rbi_hm/<hallmark>/"
  buc_doc_param "hallmark" "Full hallmark (e.g., c260305133650-r260305160530)"
  buc_doc_shown || return 0

  test -n "${z_hallmark}" || buc_die "Hallmark parameter required"

  buc_step "Authenticating as Director"
  local z_token
  z_token=$(rba_token_capture "${RBCC_mantle_director}") || buc_die "Failed to get OAuth token"

  # Enumerate packages under rbi_hm/<hallmark>/ via GAR REST API.
  # Each immediate child of the subtree is one ark (image, vouch, pouch,
  # about, attest, diags). Iterating discovered children rather than a
  # hardcoded suffix list naturally tolerates graft's missing pouch.
  local -r z_subtree="${RBGL_HALLMARKS_ROOT}/${z_hallmark}/"
  buc_step "Enumerating packages under ${z_subtree}"

  local -r z_list_url="${ZRBFC_GAR_API_BASE}/${ZRBFC_GAR_PACKAGE_BASE}/packages?pageSize=1000"
  local -r z_list_infix="rbfl_abjure_list"

  rbuh_json "GET" "${z_list_url}" "${z_token}" "${z_list_infix}"
  rbuh_require_ok "List packages for abjure" "${z_list_infix}"

  # GAR returns package names URL-encoded in the resource name (slashes as
  # %2F); decode and prefix-match to the hallmark subtree.
  local -r z_resp_file="${ZRBUH_PREFIX}${z_list_infix}${ZRBUH_POSTFIX_JSON}"
  local -r z_pkg_file="${ZRBFL_DELETE_PREFIX}packages.txt"

  jq -r --arg subtree "${z_subtree}" '
    .packages[]?.name
    | sub("^.*/packages/"; "")
    | gsub("%2F"; "/")
    | select(startswith($subtree))
  ' "${z_resp_file}" > "${z_pkg_file}" \
    || buc_die "Failed to extract package names for hallmark subtree"

  if ! test -s "${z_pkg_file}"; then
    buc_die "No packages found under ${z_subtree} — hallmark not present in registry"
  fi

  local z_count=0
  local z_count_line=""
  while IFS= read -r z_count_line || test -n "${z_count_line}"; do
    z_count=$((z_count + 1))
  done < "${z_pkg_file}"

  local z_confirm_msg="Will abjure ${z_count} packages under ${z_subtree}:"
  local z_pkg_path=""
  while IFS= read -r z_pkg_path || test -n "${z_pkg_path}"; do
    z_confirm_msg="${z_confirm_msg}\n  - ${z_pkg_path}"
  done < "${z_pkg_file}"
  buc_require "${z_confirm_msg}" "yes"

  # Cloud-dispatched delete: load the enumerated package list and hand the whole
  # set to a single Director-run build (one build per abjure, never per package).
  # The in-pool step loops the list, deleting each package by convergence (GAR's
  # parent-before-child FAILED_PRECONDITION means a single packages.delete of an
  # index web removes nothing) and verifying absence via package GET to 404 — so
  # the build's success IS the delete outcome, closing the host trust-200 LRO
  # gap; see RBSCB and rbgjl06. Load-then-pass (BCG): the file is consumed
  # before dispatch, no FD held across the build.
  local z_packages=()
  local z_pkg_line=""
  while IFS= read -r z_pkg_line || test -n "${z_pkg_line}"; do
    test -n "${z_pkg_line}" || continue
    z_packages+=("${z_pkg_line}")
  done < "${z_pkg_file}"
  test "${#z_packages[@]}" -gt 0 || buc_die "No packages loaded for abjure of ${z_subtree}"

  buc_step "Dispatching cloud delete for ${z_count} package(s) under ${z_subtree}"
  zrbld_cloud_delete_dispatch "${z_token}" "Abjure" "${ZRBFL_DELETE_PREFIX}" "${z_packages[@]}"

  echo ""
  buc_success "Hallmark abjured: ${z_hallmark} (${z_count} packages)"
}

# eof
