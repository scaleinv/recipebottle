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
# Recipe Bottle Lode - build-assembly spine (guard-free cluster, sourced by
# rbld0_lode for the capture kinds and cross-sourced by rbfl0_ledger for
# made-side abjure): the data-driven Cloud Build composer shared by every Lode
# capture kind AND by the tool-plane GAR-delete builds (banish/abjure). Takes a
# recipe (ordered, pre-resolved step rows) plus an opaque substitutions blob,
# composes the Build resource, submits, polls, and decodes a step's
# buildStepOutputs slot. Owns NO kind knowledge: the recipe and the substitutions
# are data; the only build knobs a body chooses (poll ceiling, run-as identity)
# are passed in. The build's run-as serviceAccount is caller-supplied — capture
# bodies pass Mason (writer-only, the identity that runs untrusted upstream
# bytes), the delete body passes Director (repoAdmin, the only identity that may
# delete) — so the spine carries no identity constant of its own; the remaining
# spine-owned build constants (TETHER pool, regime build timeout) are
# environment, not identity. Built on the rbfcb_ build primitives
# (write-script-body, wait-build-completion), which it calls rather than absorbs.
#
# Sentinel is zrbfc_sentinel, not zrbld_sentinel: the spine binds nothing rbld
# beyond its function prefix (it reads only rbfc/rbgd/rbrr/rbdc state, plus — in
# the single-slot extract — the rbgc fact keys and the buf_ fact machinery, both
# furnished by rbld0_cli and rbfl0_cli alike), so it is callable by any
# rbfc-furnished module — which is what lets abjure ride it from the separate
# rbfl process. rbld and rbfl are never co-furnished, so the single
# cross-source raises no double-source.
#
# Contract: RBSCJ "Capture Composition Contract".

set -euo pipefail

# Multiple inclusion detection — this cluster is multiply-sourced (rbld0_lode for
# the capture kinds, rbfl0_ledger for made-side abjure), so unlike the
# single-entry guard-free clusters it carries its own guard (BCG "the single-guard
# rule, and its one exception"). rbld and rbfl are never co-furnished, so the guard
# never fires in practice; it is the documented backstop against a future co-furnish.
test -z "${ZRBLDS_SOURCED:-}" || buc_die "Module rblds multiply sourced - check sourcing hierarchy"
ZRBLDS_SOURCED=1

######################################################################
# Build-assembly spine (zrbld_spine_*)

# Internal: dispatch-time substitution-coverage check. A capture step reads
# automapped _RBGL_* substitution registers; a reference to a key the body's
# substitutions blob never defines expands to empty inside the build and corrupts
# the capture silently — the one composition fault that is neither guarded in-step
# (unlike the /workspace handoff, which the steps test -f for themselves) nor cheap
# to surface (it costs the whole cook). The _RBGL_* references in a step body ARE
# its substitution requires — no separate declaration to drift from the code — so
# this scans the include-expanded body for them on non-comment lines and returns 1
# at the first reference absent from the blob's keys, logging the offending
# register. Sentinel-free return-1 primitive, like the rbfcb_ build primitives the
# dispatch loop already rides; the caller buc_die's with the step identity.
#
# Coverage is flat by design (RBSCJ "Substitution-coverage check"): substitutions
# automap into every step, so there is no cross-step ordering; the /workspace
# inter-step channel keeps its own in-step guards and is out of scope.
#
# This check is also why the build sets options.substitutionOption ALLOW_LOOSE (below):
# a python step reads its substitutions as automapped env vars, never as textual
# ${_RBGL_*} expansions, so Cloud Build's default MUST_MATCH would reject those keys as
# "not matched in the template" the moment a recipe MIXES a python step (env-read subs)
# with bash steps (textual-ref subs) — the immure case (python select + bash cp/residency/
# vouch). ALLOW_LOOSE lifts that, and this dispatch-time scan is its safe replacement:
# it independently catches the inverse fault (a step ${}-referencing a key the blob omits)
# that MUST_MATCH would otherwise have caught.
#
# Args: keys_file expanded_body_file
zrbld_spine_validate() {
  local -r z_keys_file="${1:?Substitution keys file required}"
  local -r z_body_file="${2:?Expanded body file required}"

  test -f "${z_keys_file}" || return 1
  test -f "${z_body_file}" || return 1

  # Keys as newline-bounded text for builtin whole-line membership tests. Empty
  # keys (a blob declaring no registers) is legitimate — no test -n.
  local -r z_keys=$(<"${z_keys_file}")
  local -r z_keys_blob=$'\n'"${z_keys}"$'\n'

  # Load the body, then iterate — the file is closed before the scan begins.
  local z_lines=()
  local z_line=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    z_lines+=("${z_line}")
  done < "${z_body_file}"

  local z_i=0
  local z_rest=""
  local z_ref=""
  for z_i in "${!z_lines[@]}"; do
    z_line="${z_lines[$z_i]}"

    # Full-line comments only — a _RBGL_ token in a leading-# comment is
    # documentation, not a read; a trailing inline mention stays conservative.
    [[ ! "${z_line}" =~ ^[[:space:]]*# ]] || continue

    # Each _RBGL_* token by repeated leftmost match; strip through the match so
    # the next token on the line surfaces.
    z_rest="${z_line}"
    while [[ "${z_rest}" =~ _RBGL_[A-Z0-9_]+ ]]; do
      z_ref="${BASH_REMATCH[0]}"
      case "${z_keys_blob}" in
        *$'\n'"${z_ref}"$'\n'*) ;;
        *) buc_log_args "Uncovered substitution register: ${z_ref}"; return "${BUBC_band_recipe}" ;;
      esac
      z_rest="${z_rest#*"${z_ref}"}"
    done
  done

  return 0
}

# Internal: compose, submit, and poll a Lode capture Cloud Build from a recipe
# plus an opaque substitutions blob.
#
# A recipe row is a |-delimited 4-tuple: script_path|builder_image|id|entrypoint
#   - script_path:   absolute path to the step script, pre-resolved by the body
#                    (the spine owns no steps-directory knowledge)
#   - builder_image: the step's builder image ref (colons allowed — hence the
#                    | delimiter, since image tags/digests contain colons)
#   - id:            the Cloud Build step id
#   - entrypoint:    bash | sh | busybox | python3 — selects the composed shebang
#                    line (busybox -> /busybox/sh, the only shell in distroless
#                    :debug builder images such as gcrane:debug)
#
# The substitutions file holds a JSON object the spine slots into the Build
# envelope's `substitutions` field; the spine reads no key from it and adds
# exactly one — _RBGL_GIT_COMMIT, the dispatching HEAD commit (see below). The
# envelope shape (serviceAccount, options.automapSubstitutions, options.substitutionOption,
# options.logging, options.pool, timeout) is the spine's; the run-as identity is caller-supplied
# (an SA email the spine composes into the depot-project resource path), and the
# environment knobs (TETHER pool, regime timeout) are spine-owned constants.
#
# Args: token sa_email label poll_ceiling subs_file temp_prefix recipe_row...
zrbld_spine_dispatch() {
  zrbfc_sentinel

  local -r z_token="${1:?Token required}";                  shift
  local -r z_sa_email="${1:?Service-account email required}"; shift
  local -r z_label="${1:?Label required}";                  shift
  local -r z_poll_ceiling="${1:?Poll ceiling required}";    shift
  local -r z_subs_file="${1:?Substitutions file required}"; shift
  local -r z_temp_prefix="${1:?Temp prefix required}";      shift
  test "$#" -ge 1 || buc_die "zrbld_spine_dispatch: recipe requires at least one step row"

  test -s "${z_subs_file}" || buc_die "Substitutions file missing or empty: ${z_subs_file}"

  # Stamp the dispatching HEAD commit into the blob — dispatch provenance, spine-owned
  # like the pool and timeout (environment, not kind knowledge). The shared vouch-push
  # step (rbgjl02) splices it into every envelope, so each kind inherits the field with
  # no per-body edit. Honesty rides the upstream gate: every capture verb runs
  # bug_require_clean_tree_creed before composing, so HEAD names committed code by
  # construction. Recipes without the vouch step (the delete builds) carry the key
  # unread — ALLOW_LOOSE automaps it; the coverage check below is refs-need-keys only.
  zrbfc_ensure_git_metadata
  local -r z_git_commit=$(<"${ZRBFC_GIT_COMMIT_FILE}")
  test -n "${z_git_commit}" || buc_die "Empty git commit from ${ZRBFC_GIT_COMMIT_FILE}"
  local -r z_subs_stamped_file="${z_temp_prefix}subs_stamped.json"
  jq --arg zjq_commit "${z_git_commit}" '. + {_RBGL_GIT_COMMIT: $zjq_commit}' \
    "${z_subs_file}" > "${z_subs_stamped_file}" \
    || buc_die "Failed to stamp git commit into substitutions blob"

  # Read the substitutions blob's keys once for the dispatch-time coverage check;
  # the per-step scan rides the composition loop below, where each step body is
  # already include-expanded (zrbld_spine_validate). A JSON object cannot carry
  # duplicate keys, so no dedup is needed.
  local -r z_keys_file="${z_temp_prefix}subs_keys.txt"
  jq -r 'keys[]' "${z_subs_stamped_file}" > "${z_keys_file}" \
    || buc_die "Failed to read substitution keys from ${z_subs_stamped_file}"

  buc_step "Composing ${z_label} Cloud Build steps from recipe"
  local -r z_steps_file="${z_temp_prefix}steps.json"
  echo "[]" > "${z_steps_file}" || buc_die "Failed to initialize ${z_label} steps JSON"

  local z_row=""
  local z_script_path=""
  local z_builder=""
  local z_id=""
  local z_entrypoint=""
  local z_body_file=""
  local z_escaped_file=""
  local z_steps_built=""
  local z_body=""
  local z_shebang=""
  for z_row in "$@"; do
    IFS='|' read -r z_script_path z_builder z_id z_entrypoint <<<"${z_row}"
    test -n "${z_script_path}" || buc_die "Recipe row missing script_path: ${z_row}"
    test -n "${z_builder}"     || buc_die "Recipe row missing builder_image: ${z_row}"
    test -n "${z_id}"          || buc_die "Recipe row missing id: ${z_row}"
    test -f "${z_script_path}" || buc_die "Step script not found: ${z_script_path}"

    z_body_file="${z_temp_prefix}${z_id}_body.txt"
    z_escaped_file="${z_temp_prefix}${z_id}_escaped.txt"
    z_steps_built="${z_temp_prefix}${z_id}_steps.json"

    zrbfc_write_script_body "${z_script_path}" "${z_body_file}" \
      || buc_die "Failed to read step script: ${z_script_path}"
    zrbfc_expand_includes "${z_body_file}" "${ZRBFC_RBGJS_SNIPPETS_DIR}" \
      || buc_die "Failed to expand snippet includes in step: ${z_script_path}"
    z_body=$(<"${z_body_file}")
    test -n "${z_body}" || buc_die "Empty step script body: ${z_script_path}"

    zrbld_spine_validate "${z_keys_file}" "${z_body_file}" \
      || buc_die "Recipe step '${z_id}' references a substitution register absent from the composition blob (see transcript)"

    case "${z_entrypoint}" in
      bash)    z_shebang="#!/bin/bash" ;;
      sh)      z_shebang="#!/bin/sh" ;;
      busybox) z_shebang="#!/busybox/sh" ;;
      python3) z_shebang="#!/usr/bin/env python3" ;;
      *)       buc_die "Unknown entrypoint '${z_entrypoint}' in recipe row: ${z_row}" ;;
    esac
    printf '%s\n%s' "${z_shebang}" "${z_body}" > "${z_escaped_file}" \
      || buc_die "Failed to write escaped step body for ${z_id}"

    jq \
      --arg name "${z_builder}" \
      --arg id "${z_id}" \
      --rawfile script "${z_escaped_file}" \
      '. + [{name: $name, id: $id, script: $script}]' \
      "${z_steps_file}" > "${z_steps_built}" \
      || buc_die "Failed to append step ${z_id}"
    mv "${z_steps_built}" "${z_steps_file}" \
      || buc_die "Failed to update steps JSON for ${z_id}"
  done

  buc_log_args "Composing ${z_label} Build resource JSON"
  local -r z_build_file="${z_temp_prefix}build.json"
  local -r z_run_as_sa="projects/${RBDC_DEPOT_PROJECT_ID}/serviceAccounts/${z_sa_email}"

  jq -n \
    --slurpfile zjq_steps   "${z_steps_file}" \
    --slurpfile zjq_subs    "${z_subs_stamped_file}" \
    --arg       zjq_sa      "${z_run_as_sa}" \
    --arg       zjq_pool    "${RBDC_POOL_TETHER}" \
    --arg       zjq_timeout "${RBRR_GCB_TIMEOUT}" \
    '{
      steps: $zjq_steps[0],
      substitutions: $zjq_subs[0],
      serviceAccount: $zjq_sa,
      options: {
        automapSubstitutions: true,
        substitutionOption: "ALLOW_LOOSE",
        logging: "CLOUD_LOGGING_ONLY",
        pool: { name: $zjq_pool }
      },
      timeout: $zjq_timeout
    }' > "${z_build_file}" \
    || buc_die "Failed to compose ${z_label} build JSON"

  buc_log_args "${z_label} build JSON: ${z_build_file}"

  rbrd_check "${z_token}"

  buc_step "Submitting ${z_label} Cloud Build"
  rbuh_json "POST" "${ZRBFC_GCB_PROJECT_BUILDS_URL}" "${z_token}" \
    "lode_build_create" "${z_build_file}"
  rbuh_require_ok "${z_label} build submission" "lode_build_create"

  local z_build_id
  z_build_id=$(rbuh_json_field_capture "lode_build_create" '.metadata.build.id') \
    || buc_die "Failed to capture build ID from builds.create response"
  test -n "${z_build_id}" || buc_die "Build ID empty in builds.create response"
  echo "${z_build_id}" > "${ZRBFC_BUILD_ID_FILE}" || buc_die "Failed to persist build ID"

  local -r z_console_url="${ZRBFC_CLOUD_QUERY_BASE};region=${RBGD_GCB_REGION}/${z_build_id}?project=${RBGD_GCB_PROJECT_ID}"
  buc_info "${z_label} Cloud Build submitted: ${z_build_id}"
  buc_link "Click to " "Open build in Cloud Console" "${z_console_url}"

  zrbfc_wait_build_completion "${z_poll_ceiling}" "${z_label}"
}

# Internal: decode the base64 JSON payload a step wrote to its buildStepOutputs
# slot into a destination file. The step index is the only generic parameter;
# what the decoded JSON means (its member-envelope shape) is the body's
# knowledge, not the spine's. Reads ZRBFC_BUILD_STATUS_FILE (the terminal build
# result registered by zrbfc_wait_build_completion).
# Args: step_index dest_file
zrbld_spine_extract() {
  zrbfc_sentinel

  local -r z_step_index="${1:?Step index required}"
  local -r z_dest_file="${2:?Destination file required}"
  local -r z_b64_file="${z_dest_file}.b64"

  jq -r ".results.buildStepOutputs[${z_step_index}] // empty" "${ZRBFC_BUILD_STATUS_FILE}" \
    > "${z_b64_file}" || buc_die "Failed to extract buildStepOutputs[${z_step_index}] from build result"
  test -s "${z_b64_file}" || buc_die "No buildStepOutputs[${z_step_index}] in build result — step produced no output"

  rbgo_base64_decode_file_to_file "${z_b64_file}" "${z_dest_file}" \
    || buc_die "Failed to decode buildStepOutputs[${z_step_index}] base64"
  test -s "${z_dest_file}" || buc_die "Empty decoded buildStepOutputs[${z_step_index}]"
}

# Internal: the shared single-slot capture extract for the one-Lode kinds
# (underpin, conclave, immure): decode step 0's buildStepOutputs slot, require
# the host-minted stamp in rbls_slot_1 (dumping the present keys when absent, so
# a slot-shape drift self-diagnoses), and emit the one bare single-form chaining
# fact (the touchmark value). The brand parameter is now only the display label
# (the kind name) — the chain carries no kind-brand fact, so the spine still owns
# no kind knowledge. The provenance envelope is NOT read
# host-side: it lives only in GAR (:rbi_vouch, pushed cloud-side), so the host
# hands forward only the touchmark a consumer needs. Bole stays on its own
# extract (rbldb_): its multi-slot 1..3 continue-on-empty loop is genuinely
# different shape. Consolidated from three byte-parallel per-kind copies after
# the rbls_ sprue sweep missed one of them and broke the picket suite same-day
# (memo-20260610-heat-BH-extract-keys-triplication).
# Args: prefix brand label
#   prefix — the kind's temp-file prefix (ZRBLD_*_PREFIX)
#   brand  — kind name for the display label (RBGC_LODE_BRAND_* / immure's family)
#   label  — display word for messages, matching the dispatch label (e.g. "Underpin")
zrbld_spine_extract_single() {
  zrbfc_sentinel

  local -r z_prefix="${1:?Prefix required}"
  local -r z_brand="${2:?Brand required}"
  local -r z_label="${3:?Label required}"

  buc_step "Extracting capture results from build step outputs"

  local -r z_output_file="${z_prefix}output.json"
  zrbld_spine_extract 0 "${z_output_file}"

  buc_log_args "${z_label} output:"
  buc_log_pipe < "${z_output_file}"

  local -r z_stamp_file="${z_prefix}stamp.txt"
  jq -r '.rbls_slot_1.rbls_stamp // empty' "${z_output_file}" > "${z_stamp_file}" \
    || buc_die "Failed to read stamp from ${z_label} output"
  local -r z_stamp=$(<"${z_stamp_file}")
  local -r z_keys_file="${z_prefix}output_keys.txt"
  jq -cr 'keys' "${z_output_file}" > "${z_keys_file}" \
    || buc_die "Failed to read keys from ${z_label} output"
  local -r z_keys=$(<"${z_keys_file}")
  test -n "${z_stamp}" || buc_die "${z_label} output carried no stamp in rbls_slot_1 (keys present: ${z_keys})"

  buf_write_fact_single "${RBF_FACT_LODE_TOUCHMARK}" "${z_stamp}" \
    || buc_die "Failed to write touchmark fact for ${z_stamp}"
  buc_success "${z_label} captured Lode ${z_stamp} — touchmark fact emitted (${z_brand})"
}

# eof
