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
# Recipe Bottle Foundry Core - build-host primitives (wait-build-completion,
# git-metadata, write-script-body, native-path). Relocated verbatim from the
# former rbfc_FoundryCore.sh monolith; sourced by the rbfc kindle-entry (rbfck_)
# so every consumer reaches them unchanged, and sourced directly by the Rust
# fast-path driver and the capture spine. Reads ZRBFC_* kindle constants at call
# time; write-script-body and native-path are kindle-independent and carry no
# sentinel.

set -euo pipefail

# Sourced-guard (silent skip — reached via rbfc and, later, the capture spine)
test -z "${ZRBFCB_SOURCED:-}" || return 0
ZRBFCB_SOURCED=1

# zrbfc_redon_tick — one mid-flight re-don attempt, on the poll's cadence
# (RBS0 rbsk_human_present). The don alone, never the avow-folding accessor,
# so a lapsed sitting fails loud here instead of re-entering the interactive
# avowal mid-loop. Called in the process frame, never `$()`: it announces on
# the progress stream and its deaths must exit the run. Result rides the
# z_rbfc_redon_token result-global: the fresh mantle token when the re-don
# lands, empty when the don failed transiently while the sitting is still
# live (the caller keeps its prior token and retries next poll; the status
# poll's consecutive-failure counter stays the backstop). A lapsed sitting
# buc_dies with the open-a-sitting advisory; the don's admission deficit
# buc_rejects on its band. Sentinel-free by design — reads no ZRBFC kindle
# state (callees guard their own kindles) — so the lapse branch stays
# unit-testable without a live build.
zrbfc_redon_tick() {
  local -r z_label="${1:?zrbfc_redon_tick: label required}"
  local -r z_poll_tag="${2:?zrbfc_redon_tick: poll tag required}"

  z_rbfc_redon_token=""

  local z_don_rc=0
  local z_minted=""
  z_minted=$(rba_don_capture "${RBCC_mantle_director}") || z_don_rc=$?

  if test "${z_don_rc}" -eq 0; then
    z_rbfc_redon_token="${z_minted}"
    buc_info "${z_label}: Re-donned the director mantle mid-flight (${z_poll_tag})"
    return 0
  fi

  test "${z_don_rc}" -ne "${BUBC_band_admission}" \
    || buc_reject "${BUBC_band_admission}" "${z_label}: re-don denied mid-build — the director admission was revoked while the build ran; brevet the citizen back onto the mantle, then re-run"

  if zrba_sitting_live_predicate; then
    buc_warn "${z_label}: mid-flight re-don failed transiently (${z_poll_tag}) — keeping the prior token; retrying next poll"
    return 0
  fi

  buc_die "${z_label}: sitting lapsed mid-build — the mantle cannot be re-donned; open a sitting (rbw-aa or rbw-aN), then re-run"
}

zrbfc_wait_build_completion() {
  zrbfc_sentinel

  local z_max_polls="${1:?zrbfc_wait_build_completion: max_polls required}"
  local z_label="${2:?zrbfc_wait_build_completion: label required}"

  buc_step "${z_label}: Waiting for build completion"

  local z_build_id=""
  z_build_id=$(<"${ZRBFC_BUILD_ID_FILE}") || buc_die "No build ID found"
  test -n "${z_build_id}" || buc_die "Build ID file empty"

  buc_log_args 'Get fresh token for polling'
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") || buc_die "Failed to get GCB OAuth token"

  # Re-don cadence — kindled default, or the BURE test seam's override so a
  # short real build exercises the tick (BUS0 Tweak Mechanism; a malformed
  # value dies loud, any other tweak occupying the slot rides inert).
  local z_redon_cadence="${ZRBFC_BUILD_POLL_REDON_CADENCE}"
  if test "${BURE_TWEAK_NAME:-}" = "${RBCC_tweak_redon_cadence}"; then
    z_redon_cadence="${BURE_TWEAK_VALUE:-}"
    [[ "${z_redon_cadence}" =~ ^[1-9][0-9]*$ ]] \
      || buc_die "redon cadence tweak: BURE_TWEAK_VALUE must be a positive poll count, got '${z_redon_cadence}'"
    buc_log_args "redon cadence tweak: cadence forced to ${z_redon_cadence} polls"
  fi

  local z_status="PENDING"
  local z_polls=0
  local z_polls_since_don=0
  local z_queue_polls=0
  local z_exec_polls=0
  local z_seen_working=0
  local z_phase=""
  local z_phase_polls=0
  local z_phase_ceiling=0
  local z_consecutive_failures=0
  local z_response_file=""
  local z_code_file=""
  local z_stderr_file=""
  local z_err_check_file=""
  local z_status_check_file=""
  local z_last_good_response=""
  local z_curl_rc=0

  while true; do
    case "${z_status}" in PENDING|QUEUED|WORKING) : ;; *) break;; esac
    sleep "${ZRBFC_BUILD_POLL_INTERVAL_SEC}"

    z_polls=$((z_polls + 1))

    # Two clocks: queue polls (pre-WORKING) charge the shared queue ceiling;
    # execution polls (post first-WORKING) charge the per-kind z_max_polls.
    if test "${z_seen_working}" -eq 0; then
      z_queue_polls=$((z_queue_polls + 1))
      z_phase="queue"
      z_phase_polls="${z_queue_polls}"
      z_phase_ceiling="${ZRBFC_BUILD_POLL_CEILING_QUEUE}"
      if test "${z_queue_polls}" -gt "${ZRBFC_BUILD_POLL_CEILING_QUEUE}"; then
        buc_tabtarget "${RBZ_QUOTA_BUILD}"
        buc_die "${z_label}: pool never took the build — still queued after ${ZRBFC_BUILD_POLL_CEILING_QUEUE} queue polls; the worker pool never started execution"
      fi
    else
      z_exec_polls=$((z_exec_polls + 1))
      z_phase="exec"
      z_phase_polls="${z_exec_polls}"
      z_phase_ceiling="${z_max_polls}"
      test "${z_exec_polls}" -le "${z_max_polls}" \
        || buc_die "${z_label}: Build timeout after ${z_max_polls} execution polls"
    fi

    # Cadence tick — re-don before the status fetch so the fetch always rides
    # a token younger than the mantle ceiling. An empty result is the tick's
    # tolerated-transient outcome: counter untouched, and the since-don count
    # stays past the cadence so the next poll retries.
    z_polls_since_don=$((z_polls_since_don + 1))
    if test "${z_polls_since_don}" -ge "${z_redon_cadence}"; then
      zrbfc_redon_tick "${z_label}" "poll ${z_polls}; cadence ${z_redon_cadence}"
      if test -n "${z_rbfc_redon_token}"; then
        z_token="${z_rbfc_redon_token}"
        z_rbfc_redon_token=""
        z_polls_since_don=0
      fi
    fi

    z_response_file="${ZRBFC_POLL_RESPONSE_PREFIX}${z_polls}.json"
    z_code_file="${ZRBFC_POLL_CODE_PREFIX}${z_polls}.txt"
    z_stderr_file="${ZRBFC_POLL_STDERR_PREFIX}${z_polls}.txt"
    z_err_check_file="${ZRBFC_POLL_ERR_CHECK_PREFIX}${z_polls}.txt"
    z_status_check_file="${ZRBFC_POLL_STATUS_PREFIX}${z_polls}.txt"

    buc_log_args "Fetch build status (poll ${z_polls}; ${z_phase} ${z_phase_polls}/${z_phase_ceiling})"
    z_curl_rc=0
    rbuh_request "GET" "${ZRBFC_GCB_PROJECT_BUILDS_URL}/${z_build_id}" \
                      "${z_token}"                                          \
                      "${z_response_file}" "${z_code_file}" "${z_stderr_file}" \
      || z_curl_rc=$?

    if test "${z_curl_rc}" -ne 0; then
      z_consecutive_failures=$((z_consecutive_failures + 1))
      buc_warn "Curl failed (rc=${z_curl_rc}; ${z_consecutive_failures}/${ZRBFC_BUILD_POLL_RETRY_TOLERANCE} consecutive) — see ${z_stderr_file}"
      buc_log_pipe < "${z_stderr_file}"
      test "${z_consecutive_failures}" -ge "${ZRBFC_BUILD_POLL_RETRY_TOLERANCE}" \
        && buc_die "Failed to get build status after ${ZRBFC_BUILD_POLL_RETRY_TOLERANCE} consecutive failures (last rc=${z_curl_rc}; see ${z_stderr_file})"
      continue
    fi

    if ! test -s "${z_response_file}"; then
      z_consecutive_failures=$((z_consecutive_failures + 1))
      buc_warn "Empty response (poll ${z_polls}; ${z_consecutive_failures}/${ZRBFC_BUILD_POLL_RETRY_TOLERANCE} consecutive) — see ${z_response_file}"
      test "${z_consecutive_failures}" -ge "${ZRBFC_BUILD_POLL_RETRY_TOLERANCE}" \
        && buc_die "Empty build status after ${ZRBFC_BUILD_POLL_RETRY_TOLERANCE} consecutive failures"
      continue
    fi

    jq -r '.error.code // empty' "${z_response_file}" > "${z_err_check_file}" 2>/dev/null
    if test -s "${z_err_check_file}"; then
      z_consecutive_failures=$((z_consecutive_failures + 1))
      buc_warn "HTTP error $(<"${z_err_check_file}") (poll ${z_polls}; ${z_consecutive_failures}/${ZRBFC_BUILD_POLL_RETRY_TOLERANCE} consecutive) — see ${z_response_file}"
      test "${z_consecutive_failures}" -ge "${ZRBFC_BUILD_POLL_RETRY_TOLERANCE}" \
        && buc_die "HTTP errors after ${ZRBFC_BUILD_POLL_RETRY_TOLERANCE} consecutive failures"
      continue
    fi

    z_consecutive_failures=0

    jq -r '.status' "${z_response_file}" > "${z_status_check_file}" || buc_die "Failed to extract status (poll ${z_polls})"
    z_status=$(<"${z_status_check_file}")
    test -n "${z_status}" || buc_die "Status is empty (poll ${z_polls})"

    z_last_good_response="${z_response_file}"

    buc_info "${z_label}: ${z_status} (poll ${z_polls}; ${z_phase} ${z_phase_polls}/${z_phase_ceiling})"

    if test "${z_status}" = "WORKING" && test "${z_seen_working}" -eq 0; then
      z_seen_working=1
      buc_info "${z_label}: QUEUED→WORKING after ${z_queue_polls} queue polls (execution budget ${z_max_polls} polls)"
    fi

    if test "${z_seen_working}" -eq 0 && test "$(( z_queue_polls % 20 ))" -eq 0; then
      buc_warn "Build queued longer than normal (${z_queue_polls} queue polls) — another build may be holding the private pool"
      buc_tabtarget "${RBZ_QUOTA_BUILD}"
    fi
  done

  test -n "${z_last_good_response}" \
    || buc_die "${z_label}: no successful poll observed"
  cp "${z_last_good_response}" "${ZRBFC_BUILD_STATUS_FILE}" \
    || buc_die "Failed to register winner response at ${ZRBFC_BUILD_STATUS_FILE}"

  test "${z_status}" = "SUCCESS" || buc_die "${z_label}: Build failed with status: ${z_status}"

  # Extract build wall-clock timing from terminal status response
  jq -r '.startTime // empty' "${ZRBFC_BUILD_STATUS_FILE}" > "${ZRBFC_BUILD_START_FILE}"
  jq -r '.finishTime // empty' "${ZRBFC_BUILD_STATUS_FILE}" > "${ZRBFC_BUILD_FINISH_FILE}"
  local z_start_time=""
  z_start_time=$(<"${ZRBFC_BUILD_START_FILE}")
  local z_finish_time=""
  z_finish_time=$(<"${ZRBFC_BUILD_FINISH_FILE}")

  if test -n "${z_start_time}" && test -n "${z_finish_time}"; then
    local z_start_clean="${z_start_time%%.*}"
    z_start_clean="${z_start_clean%%Z}"
    local z_finish_clean="${z_finish_time%%.*}"
    z_finish_clean="${z_finish_clean%%Z}"
    local z_start_epoch=""
    z_start_epoch=$(date -d "${z_start_clean}Z" '+%s' 2>/dev/null) \
      || z_start_epoch=$(date -j -f '%Y-%m-%dT%H:%M:%S' "${z_start_clean}" '+%s' 2>/dev/null) \
      || z_start_epoch=""
    local z_finish_epoch=""
    z_finish_epoch=$(date -d "${z_finish_clean}Z" '+%s' 2>/dev/null) \
      || z_finish_epoch=$(date -j -f '%Y-%m-%dT%H:%M:%S' "${z_finish_clean}" '+%s' 2>/dev/null) \
      || z_finish_epoch=""
    if test -n "${z_start_epoch}" && test -n "${z_finish_epoch}"; then
      local -r z_duration=$((z_finish_epoch - z_start_epoch))
      local -r z_minutes=$((z_duration / 60))
      local -r z_seconds=$((z_duration % 60))
      buc_info "${z_label}: Wall clock ${z_minutes}m ${z_seconds}s"
    fi
  fi

  buc_success "${z_label}: Build completed successfully"
}

# Internal: capture git metadata to module temp files (idempotent)
# No args — reads from git, writes to ZRBFC_GIT_*_FILE kindle constants
zrbfc_ensure_git_metadata() {
  zrbfc_sentinel

  # Idempotent — skip if already captured
  test ! -s "${ZRBFC_GIT_COMMIT_FILE}" || return 0

  buc_log_args "Capturing git metadata to temp files"

  local -r z_remote_file="${ZRBFC_GIT_PREFIX}remote.txt"
  local -r z_url_file="${ZRBFC_GIT_PREFIX}url.txt"

  git rev-parse HEAD > "${ZRBFC_GIT_COMMIT_FILE}" \
    || buc_die "Failed to get git commit"
  test -s "${ZRBFC_GIT_COMMIT_FILE}" || buc_die "Empty git commit file"

  git rev-parse --abbrev-ref HEAD > "${ZRBFC_GIT_BRANCH_FILE}" \
    || buc_die "Failed to get git branch"
  test -s "${ZRBFC_GIT_BRANCH_FILE}" || buc_die "Empty git branch file"

  git remote > "${z_remote_file}" \
    || buc_die "Failed to list git remotes"
  local z_remote=""
  read -r z_remote < "${z_remote_file}" \
    || buc_die "Failed to read git remote from ${z_remote_file}"
  test -n "${z_remote}" || buc_die "No git remotes found"

  git config --get "remote.${z_remote}.url" > "${z_url_file}" \
    || buc_die "Failed to get git repo URL"

  local z_url=""
  z_url=$(<"${z_url_file}")
  test -n "${z_url}" || buc_die "Empty git repo URL from ${z_url_file}"
  local z_repo="${z_url#*://*/}"
  z_repo="${z_repo%.git}"
  echo "${z_repo}" > "${ZRBFC_GIT_REPO_FILE}" \
    || buc_die "Failed to write derived git repo"
}

# Internal: write a script's body (everything after the shebang line) to a file
# using only builtins — the portable replacement for `tail -n +2 src > dst`.
# Returns non-zero if the source is unreadable or the destination unwritable.
zrbfc_write_script_body() {
  local -r z_src="$1"
  local -r z_dst="$2"
  local z_line
  local z_seen_shebang=""
  test -r "${z_src}" || return 1
  : > "${z_dst}"     || return 1
  while IFS= read -r z_line || [ -n "${z_line}" ]; do
    if [ -z "${z_seen_shebang}" ]; then
      z_seen_shebang=1
      continue
    fi
    printf '%s\n' "${z_line}" >> "${z_dst}"
  done < "${z_src}"
  return 0
}

# Internal: expand "#@rbgjs_include <name>" markers in a step body file IN PLACE.
# Each marker line (any leading indentation tolerated) is replaced by the body of
# <snippets_dir>/rbgjs-<name>.sh with its leading shebang stripped — the same
# shebang-strip rule zrbfc_write_script_body applies. A body with no markers is
# rewritten unchanged (a no-op), so every assembler may call this for every step.
# This is the host side of the shared cloud-step library (RBSCJ "Composed-snippet
# library"): a snippet reads shell vars the kind sets before the marker and is
# blind to substitution names, which is what lets one snippet serve callers with
# disjoint _RBGx_ substitution sets. Pure primitive — args only, no kindle state,
# no sentinel — so it stays unit-testable alongside zrbfc_write_script_body.
# Returns non-zero if the body is unreadable, the snippets dir is missing, a
# marker names no snippet, or a named snippet file is absent (crash-fast: the
# caller dies, no silent skip).
# Args: body_file snippets_dir
zrbfc_expand_includes() {
  local -r z_body_file="$1"
  local -r z_snippets_dir="$2"
  test -f "${z_body_file}"    || return 1
  test -d "${z_snippets_dir}" || return 1

  local -r z_tmp="${z_body_file}.expanded"
  : > "${z_tmp}" || return 1

  local z_line=""
  local z_trimmed=""
  local z_name=""
  local z_snippet=""
  local z_sline=""
  local z_seen_shebang=""
  while IFS= read -r z_line || [ -n "${z_line}" ]; do
    z_trimmed="${z_line#"${z_line%%[![:space:]]*}"}"
    case "${z_trimmed}" in
      '#@rbgjs_include '*)
        z_name="${z_trimmed#'#@rbgjs_include '}"
        z_name="${z_name%%[[:space:]]*}"
        test -n "${z_name}" || return 1
        z_snippet="${z_snippets_dir}/rbgjs-${z_name}.sh"
        test -f "${z_snippet}" || return 1
        z_seen_shebang=""
        while IFS= read -r z_sline || [ -n "${z_sline}" ]; do
          if [ -z "${z_seen_shebang}" ]; then
            z_seen_shebang=1
            case "${z_sline}" in '#!'*) continue ;; esac
          fi
          printf '%s\n' "${z_sline}" >> "${z_tmp}"
        done < "${z_snippet}"
        ;;
      *)
        printf '%s\n' "${z_line}" >> "${z_tmp}"
        ;;
    esac
  done < "${z_body_file}"

  mv "${z_tmp}" "${z_body_file}" || return 1
  return 0
}

# eof
