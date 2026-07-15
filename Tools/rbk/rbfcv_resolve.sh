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
# Recipe Bottle Foundry Core - vessel-resolution cluster (guard-free, sourced by
# rbfck_): require a vessel sigil, resolve a vessel arg to a directory, and load a
# vessel's rbrv.env configuration.

set -euo pipefail

######################################################################
# Vessel Resolution (rbfc_* / zrbfc_*)

# Validate that a vessel sigil is non-empty and corresponds to a known vessel.
# On missing or invalid sigil, lists available vessels and dies.
# Does NOT resolve to a directory — use zrbfc_resolve_vessel for that.
rbfc_require_vessel_sigil() {
  zrbfc_sentinel

  local -r z_sigil="${1:-}"

  if test -n "${z_sigil}" && test -d "${RBRR_VESSEL_DIR}/${z_sigil}" && test -f "${RBRR_VESSEL_DIR}/${z_sigil}/${RBCC_rbrv_file}"; then
    return 0
  fi

  local z_sigils=""
  z_sigils=$(rbrv_list_capture) || buc_die "No vessels found"
  buc_step "Available vessels:"
  local z_s=""
  for z_s in ${z_sigils}; do
    buc_bare "        ${z_s}"
  done
  if test -z "${z_sigil}"; then
    buc_die "Vessel parameter required"
  fi
  buc_die "Vessel not found: ${z_sigil}"
}

# Resolve vessel argument: accepts a sigil (e.g., rbev-sentry-deb-tether) or a path
# (e.g., rbmv_vessels/rbev-sentry-deb-tether).  On no-arg or invalid arg, lists
# available vessels and dies.  On success, writes resolved path to ZRBFC_VESSEL_RESOLVED_DIR_FILE.
zrbfc_resolve_vessel() {
  zrbfc_sentinel

  local -r z_arg="${1:-}"

  # Try as path first, then as sigil under RBRR_VESSEL_DIR
  if test -n "${z_arg}" && test -d "${z_arg}" && test -f "${z_arg}/${RBCC_rbrv_file}"; then
    printf '%s' "${z_arg}" > "${ZRBFC_VESSEL_RESOLVED_DIR_FILE}" \
      || buc_die "Failed to write resolved vessel path"
    return 0
  fi
  if test -n "${z_arg}" && test -d "${RBRR_VESSEL_DIR}/${z_arg}" && test -f "${RBRR_VESSEL_DIR}/${z_arg}/${RBCC_rbrv_file}"; then
    printf '%s' "${RBRR_VESSEL_DIR}/${z_arg}" > "${ZRBFC_VESSEL_RESOLVED_DIR_FILE}" \
      || buc_die "Failed to write resolved vessel path"
    return 0
  fi

  # Resolution failed — list available vessels and die
  local z_sigils=""
  z_sigils=$(rbrv_list_capture) || buc_die "No vessels found"
  buc_step "Available vessels:"
  local z_sigil=""
  for z_sigil in ${z_sigils}; do
    buc_bare "        ${z_sigil}"
  done
  if test -z "${z_arg}"; then
    buc_die "Vessel argument required (sigil or path)"
  fi
  buc_die "Vessel not found: ${z_arg}"
}

zrbfc_load_vessel() {
  zrbfc_sentinel

  local z_vessel_dir="$1"

  buc_log_args 'Validate vessel directory exists'
  test -d "${z_vessel_dir}" || buc_die "Vessel directory not found: ${z_vessel_dir}"

  buc_log_args 'Check for rbrv.env file'
  local z_vessel_env="${z_vessel_dir}/${RBCC_rbrv_file}"
  test -f "${z_vessel_env}" || buc_die "Vessel configuration not found: ${z_vessel_env}"

  buc_log_args 'Source vessel configuration'
  source "${z_vessel_env}" || buc_die "Failed to source vessel config: ${z_vessel_env}"

  buc_log_args 'Validate vessel directory matches sigil'
  local z_vessel_dir_clean="${z_vessel_dir%/}"  # Strip any trailing slash
  local z_dir_name="${z_vessel_dir_clean##*/}"  # Extract directory name
  buc_log_args "  z_vessel_dir = ${z_vessel_dir}"
  buc_log_args "  z_dir_name   = ${z_dir_name}"
  test "${z_dir_name}" = "${RBRV_SIGIL}" || buc_die "Vessel sigil '${RBRV_SIGIL}' does not match directory name '${z_dir_name}'"

  buc_log_args 'Validate vessel path matches expected pattern'
  local z_expected_vessel_dir="${RBRR_VESSEL_DIR}/${RBRV_SIGIL}"
  local z_vessel_realpath=""
  z_vessel_realpath=$(cd "${z_vessel_dir}" && pwd) || buc_die "Failed to resolve vessel directory path"
  local z_expected_realpath=""
  z_expected_realpath=$(cd "${z_expected_vessel_dir}" && pwd) || buc_die "Failed to resolve expected vessel path"
  test "${z_vessel_realpath}" = "${z_expected_realpath}" || buc_die "Vessel directory '${z_vessel_dir}' does not match expected location '${z_expected_vessel_dir}'"

  buc_log_args 'Store loaded vessel info for use by commands'
  echo "${RBRV_SIGIL}" > "${ZRBFC_VESSEL_SIGIL_FILE}" || buc_die "Failed to store vessel sigil"

  buc_info "Loaded vessel: ${RBRV_SIGIL}"
}

# eof
