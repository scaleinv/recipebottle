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
# Recipe Bottle Lode - cloud-dispatched delete body: the shared backbone behind
# banish (Lode) and abjure (hallmark). It composes a one-row delete recipe (the
# rbgjl06 package-delete step) plus a substitutions blob (GAR coordinates + the
# space-joined package list) and rides the build-assembly spine, blocking until
# the build is terminal. The build runs as Director (repoAdmin/delete); the
# in-pool step deletes each package by convergence and verifies absence (rbgjl06:
# fire deletes, poll the package GET to 404 — no single call's verdict trusted),
# so the build's outcome IS the delete outcome — no host-issued trust-200 DELETE.
#
# Homed in the rbld family because it rides zrbld_spine_dispatch (a base-level
# home would be circular: the spine sits above rbfc, which both delete callers
# source). It is the cinch-blessed "narrow cross into made-side delete" — abjure
# (rbfl) cross-sources this body and the spine; banish (rbld) sources them
# natively. Sentinel is zrbfc_sentinel, not zrbld_sentinel, so the function runs
# in either process (zrbld_kindle runs only in the rbld process).

set -euo pipefail

# Multiple inclusion detection — multiply-sourced (rbld0_lode for banish,
# rbfl0_ledger for abjure), so it carries its own guard (BCG "the
# single-guard rule, and its one exception"). rbld and rbfl are never
# co-furnished, so the guard is the documented backstop, not a live fire.
test -z "${ZRBLDD_SOURCED:-}" || buc_die "Module rbldd multiply sourced - check sourcing hierarchy"
ZRBLDD_SOURCED=1

######################################################################
# Cloud delete dispatch (zrbld_*)

# Internal: dispatch a Director-run cloud build that deletes a list of GAR
# packages, blocking until terminal. The build runs the rbgjl06 step, which
# loops the package list in-pool — one build per call, never one build per
# package (so an N-package abjure is a single build). The Director SA email (the
# build's run-as identity) is derived from the Director mantle SA; the step
# path is resolved relative to this file so it works in either furnishing process
# without depending on a kindle constant. The caller supplies its own forensic
# temp prefix so files land in the caller's namespace.
# Args: token label temp_prefix package...
zrbld_cloud_delete_dispatch() {
  zrbfc_sentinel

  local -r z_token="${1:?Token required}";              shift
  local -r z_label="${1:?Label required}";              shift
  local -r z_temp_prefix="${1:?Temp prefix required}";  shift
  test "$#" -ge 1 || buc_die "zrbld_cloud_delete_dispatch: at least one package required"
  local -r z_packages="$*"

  buc_log_args "Deriving Director mantle service-account email for the delete build run-as identity"
  local -r z_director_sa="${RBCC_account_mantle_director}@${RBDC_DEPOT_PROJECT_ID}.${RBGC_SA_EMAIL_DOMAIN}"

  local -r z_step_path="${BASH_SOURCE[0]%/*}/rbgjl/rbgjl06-package-delete.py"
  test -f "${z_step_path}" || buc_die "Delete step script not found: ${z_step_path}"

  buc_log_args "Composing ${z_label} delete substitutions blob"
  local -r z_subs_file="${z_temp_prefix}delete_subs.json"
  jq -n \
    --arg zjq_api_base "${ZRBFC_GAR_API_BASE}" \
    --arg zjq_pkg_base "${ZRBFC_GAR_PACKAGE_BASE}" \
    --arg zjq_packages "${z_packages}" \
    '{
      _RBGL_GAR_API_BASE:     $zjq_api_base,
      _RBGL_GAR_PACKAGE_BASE: $zjq_pkg_base,
      _RBGL_DELETE_PACKAGES:  $zjq_packages
    }' > "${z_subs_file}" \
    || buc_die "Failed to compose ${z_label} delete substitutions blob"

  local -r z_recipe_row="${z_step_path}|${ZRBFC_DELETE_BUILDER}|package-delete|python3"

  zrbld_spine_dispatch \
    "${z_token}" "${z_director_sa}" "${z_label}" "${ZRBFC_BUILD_POLL_CEILING_DELETE}" \
    "${z_subs_file}" "${z_temp_prefix}" \
    "${z_recipe_row}"
}

# eof
