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
# Recipe Bottle Foundry Core - step-assembly cluster (guard-free, sourced by
# rbfck_): resolve reliquary tool-image refs and assemble the about, vouch, and
# preflight Cloud Build step JSON arrays.

set -euo pipefail

######################################################################
# Step Assembly (zrbfc_*)

# Internal: Resolve tool image references from the reliquary-kind (conclave) Lode.
# Must be called after vessel load (reads RBRV_RELIQUARY — the conclave touchmark).
# Sets module-level z_rbfc_tool_* mutable kindle state for downstream step assembly.
# Idempotent — safe to call multiple times per invocation.
#
# Conclave Lode layout: each ref composes RBGC_LODE_TAG_SPRUE onto the bare
# RBGC_RELIQUARY_TOOL_* seed to address its member tag on the one package — the
# seeds stay inputs, the resolved ref a build consumes is always the :rbi_<tool> tag.
zrbfc_resolve_tool_images() {
  zrbfc_sentinel

  local -r z_reliquary="${RBRV_RELIQUARY:-}"
  test -n "${z_reliquary}" \
    || buc_die "RBRV_RELIQUARY is required — run conclave to capture a reliquary Lode first"

  local -r z_lode_pkg="${ZRBFC_REGISTRY_HOST}/${ZRBFC_REGISTRY_PATH}/${RBGL_LODES_ROOT}/${z_reliquary}"
  z_rbfc_tool_gcloud="${z_lode_pkg}:${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_GCLOUD}"
  z_rbfc_tool_docker="${z_lode_pkg}:${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_DOCKER}"
  z_rbfc_tool_alpine="${z_lode_pkg}:${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_ALPINE}"
  z_rbfc_tool_syft="${z_lode_pkg}:${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_SYFT}"
  z_rbfc_tool_binfmt="${z_lode_pkg}:${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_BINFMT}"
  z_rbfc_tool_gcrane="${z_lode_pkg}:${RBGC_LODE_TAG_SPRUE}${RBGC_RELIQUARY_TOOL_GCRANE}"
  buc_log_args "Tool images resolved from reliquary Lode: ${RBGL_LODES_ROOT}/${z_reliquary}"
}

# Internal: assemble about step scripts into JSON array file
# Args: output_file temp_prefix
# Reads ZRBFC_RBGJA_STEPS_DIR and z_rbfc_tool_* image refs from module state
zrbfc_assemble_about_steps() {
  zrbfc_sentinel

  local -r z_output_file="$1"
  local -r z_temp_prefix="$2"

  # Step definitions: script|builder|entrypoint|id
  # Delimiter is | because image refs contain colons (sha256 digests)
  local -r z_about_step_defs=(
    "rbgja01-discover-platforms.py|${z_rbfc_tool_gcloud}|python3|discover-platforms"
    "rbgja02-syft-per-platform.sh|${z_rbfc_tool_docker}|bash|syft-per-platform"
    "rbgja03-build-info-per-platform.py|${z_rbfc_tool_gcloud}|python3|build-info-per-platform"
    "rbgja04-assemble-push-about.sh|${z_rbfc_tool_docker}|bash|assemble-push-about"
  )

  echo "[]" > "${z_output_file}" || buc_die "Failed to initialize about steps JSON"

  local z_adef=""
  local z_ascript=""
  local z_abuilder=""
  local z_aentrypoint=""
  local z_aid=""
  local z_ascript_path=""
  local z_abody_file=""
  local z_aescaped_file=""
  local z_asteps_file=""
  local z_abody=""
  local z_ashebang=""

  for z_adef in "${z_about_step_defs[@]}"; do
    IFS='|' read -r z_ascript z_abuilder z_aentrypoint z_aid <<< "${z_adef}"
    z_ascript_path="${ZRBFC_RBGJA_STEPS_DIR}/${z_ascript}"
    z_abody_file="${z_temp_prefix}${z_aid}_body.txt"
    z_aescaped_file="${z_temp_prefix}${z_aid}_escaped.txt"
    z_asteps_file="${z_temp_prefix}${z_aid}_steps.json"

    test -f "${z_ascript_path}" || buc_die "About step script not found: ${z_ascript_path}"

    buc_log_args "Reading script body for ${z_aid} (skip shebang)"
    zrbfc_write_script_body "${z_ascript_path}" "${z_abody_file}" \
      || buc_die "Failed to read about step script: ${z_ascript_path}"
    z_abody=$(<"${z_abody_file}")
    test -n "${z_abody}" || buc_die "Empty about script body: ${z_ascript_path}"

    buc_log_args "Baking pinned image refs into script text"
    z_abody="${z_abody//\$\{ZRBF_TOOL_SYFT\}/${z_rbfc_tool_syft}}"

    case "${z_aentrypoint}" in
      bash)    z_ashebang="#!/bin/bash" ;;
      sh)      z_ashebang="#!/bin/sh" ;;
      python3) z_ashebang="#!/usr/bin/env python3" ;;
      *)       buc_die "Unknown entrypoint: ${z_aentrypoint}" ;;
    esac
    printf '%s\n%s' "${z_ashebang}" "${z_abody}" > "${z_aescaped_file}" \
      || buc_die "Failed to write about script body for ${z_aid}"

    buc_log_args "Appending about step ${z_aid} to JSON array"
    jq \
      --arg name "${z_abuilder}" \
      --arg id "${z_aid}" \
      --rawfile script "${z_aescaped_file}" \
      '. + [{name: $name, id: $id, script: $script}]' \
      "${z_output_file}" > "${z_asteps_file}" \
      || buc_die "Failed to append about step ${z_aid} to JSON"
    mv "${z_asteps_file}" "${z_output_file}" \
      || buc_die "Failed to update about steps JSON for ${z_aid}"
  done
}

# Internal: assemble vouch step scripts into JSON array file
# Args: output_file temp_prefix
# Reads ZRBFC_RBGJV_STEPS_DIR and z_rbfc_tool_* image refs from module state
zrbfc_assemble_vouch_steps() {
  zrbfc_sentinel

  local -r z_output_file="$1"
  local -r z_temp_prefix="$2"

  # Step definitions: script|builder|entrypoint|id
  # Delimiter is | because image refs contain colons (sha256 digests)
  local -r z_vouch_step_defs=(
    "rbgjv01-download-verifier.sh|${z_rbfc_tool_alpine}|sh|prepare-keys"
    "rbgjv02-verify-provenance.py|${z_rbfc_tool_gcloud}|python3|verify-provenance"
    "rbgjv03-assemble-push-vouch.sh|${z_rbfc_tool_docker}|bash|assemble-push-vouch"
  )

  echo "[]" > "${z_output_file}" || buc_die "Failed to initialize vouch steps JSON"

  local z_vdef=""
  local z_vscript=""
  local z_vbuilder=""
  local z_ventrypoint=""
  local z_vid=""
  local z_vscript_path=""
  local z_vbody_file=""
  local z_vescaped_file=""
  local z_vsteps_file=""
  local z_vbody=""
  local z_vshebang=""

  for z_vdef in "${z_vouch_step_defs[@]}"; do
    IFS='|' read -r z_vscript z_vbuilder z_ventrypoint z_vid <<< "${z_vdef}"
    z_vscript_path="${ZRBFC_RBGJV_STEPS_DIR}/${z_vscript}"
    z_vbody_file="${z_temp_prefix}${z_vid}_body.txt"
    z_vescaped_file="${z_temp_prefix}${z_vid}_escaped.txt"
    z_vsteps_file="${z_temp_prefix}${z_vid}_steps.json"

    test -f "${z_vscript_path}" || buc_die "Vouch step script not found: ${z_vscript_path}"

    buc_log_args "Reading script body for ${z_vid} (skip shebang)"
    zrbfc_write_script_body "${z_vscript_path}" "${z_vbody_file}" \
      || buc_die "Failed to read vouch step script: ${z_vscript_path}"
    zrbfc_expand_includes "${z_vbody_file}" "${ZRBFC_RBGJS_SNIPPETS_DIR}" \
      || buc_die "Failed to expand snippet includes in vouch step: ${z_vscript_path}"
    z_vbody=$(<"${z_vbody_file}")
    test -n "${z_vbody}" || buc_die "Empty vouch script body: ${z_vscript_path}"

    case "${z_ventrypoint}" in
      bash)    z_vshebang="#!/bin/bash" ;;
      sh)      z_vshebang="#!/bin/sh" ;;
      python3) z_vshebang="#!/usr/bin/env python3" ;;
      *)       buc_die "Unknown entrypoint: ${z_ventrypoint}" ;;
    esac
    printf '%s\n%s' "${z_vshebang}" "${z_vbody}" > "${z_vescaped_file}" \
      || buc_die "Failed to write vouch script body for ${z_vid}"

    buc_log_args "Appending vouch step ${z_vid} to JSON array"
    jq \
      --arg name "${z_vbuilder}" \
      --arg id "${z_vid}" \
      --rawfile script "${z_vescaped_file}" \
      '. + [{name: $name, id: $id, script: $script}]' \
      "${z_output_file}" > "${z_vsteps_file}" \
      || buc_die "Failed to append vouch step ${z_vid} to JSON"
    mv "${z_vsteps_file}" "${z_output_file}" \
      || buc_die "Failed to update vouch steps JSON for ${z_vid}"
  done
}

# Internal: assemble single-step preflight JSON array file
# Args: output_file temp_prefix
# Reads ZRBFC_RBGJR_STEPS_DIR and z_rbfc_tool_alpine from module state.
# Single step prepends to every ordain-path Cloud Build job (conjure, bind,
# graft) as defense-in-depth: validates reliquary GAR-presence from
# the worker pool's vantage before expensive work runs.
zrbfc_assemble_preflight_step() {
  zrbfc_sentinel

  local -r z_output_file="$1"
  local -r z_temp_prefix="$2"

  local -r z_pscript_path="${ZRBFC_RBGJR_STEPS_DIR}/rbgjr01-reliquary-preflight.sh"
  local -r z_pbody_file="${z_temp_prefix}preflight_body.txt"
  local -r z_pescaped_file="${z_temp_prefix}preflight_escaped.txt"
  local -r z_psteps_file="${z_temp_prefix}preflight_steps.json"

  test -f "${z_pscript_path}" || buc_die "Preflight step script not found: ${z_pscript_path}"

  buc_log_args "Reading preflight step script (skip shebang)"
  zrbfc_write_script_body "${z_pscript_path}" "${z_pbody_file}" \
    || buc_die "Failed to read preflight step script: ${z_pscript_path}"
  local z_pbody=""
  z_pbody=$(<"${z_pbody_file}")
  test -n "${z_pbody}" || buc_die "Empty preflight script body"

  printf '#!/bin/sh\n%s' "${z_pbody}" > "${z_pescaped_file}" \
    || buc_die "Failed to write escaped preflight script body"

  echo "[]" > "${z_output_file}" || buc_die "Failed to initialize preflight steps JSON"
  jq \
    --arg name "${z_rbfc_tool_alpine}" \
    --arg id "reliquary-preflight" \
    --rawfile script "${z_pescaped_file}" \
    '. + [{name: $name, id: $id, script: $script}]' \
    "${z_output_file}" > "${z_psteps_file}" \
    || buc_die "Failed to build preflight step JSON"
  mv "${z_psteps_file}" "${z_output_file}" \
    || buc_die "Failed to finalize preflight step JSON"
}

# eof
