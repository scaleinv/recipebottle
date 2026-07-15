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
# Recipe Bottle Google Verification - JWT SA and Payor OAuth access verification

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBGV_SOURCED:-}" || buc_die "Module rbgv multiply sourced - check sourcing hierarchy"
ZRBGV_SOURCED=1

######################################################################
# Internal Functions (zrbgv_*)

zrbgv_kindle() {
  test -z "${ZRBGV_KINDLED:-}" || buc_die "Module rbgv already kindled"

  buc_log_args "Ensure dependencies are kindled first"
  zrbgc_sentinel
  zrbgo_sentinel
  zrbuh_sentinel
  zrbgp_sentinel

  # Kindle-constant temp file paths for forensic visibility
  readonly ZRBGV_AR_RESP_FILE="${BURD_TEMP_DIR}/rbgv_ar_resp.json"
  readonly ZRBGV_AR_CODE_FILE="${BURD_TEMP_DIR}/rbgv_ar_code.txt"
  readonly ZRBGV_AR_STDERR_FILE="${BURD_TEMP_DIR}/rbgv_ar_stderr.txt"
  readonly ZRBGV_CRM_RESP_FILE="${BURD_TEMP_DIR}/rbgv_crm_resp.json"
  readonly ZRBGV_CRM_CODE_FILE="${BURD_TEMP_DIR}/rbgv_crm_code.txt"
  readonly ZRBGV_CRM_STDERR_FILE="${BURD_TEMP_DIR}/rbgv_crm_stderr.txt"

  # Transient-5xx retry policy: 3 attempts with initial 2s backoff doubling each retry (worst-case +6s)
  readonly ZRBGV_HTTP_RETRY_ATTEMPTS=3
  readonly ZRBGV_HTTP_RETRY_INITIAL_DELAY_SEC=2

  readonly ZRBGV_KINDLED=1
}

zrbgv_sentinel() {
  test "${ZRBGV_KINDLED:-}" = "1" || buc_die "Module rbgv not kindled - call zrbgv_kindle first"
}

# Convert milliseconds to a decimal seconds string suitable for sleep
zrbgv_ms_to_sleep_capture() {
  zrbgv_sentinel

  local z_ms="${1}"

  buc_log_args "Converting ${z_ms}ms to sleep duration"

  # Compute whole seconds and remainder milliseconds using integer arithmetic
  local z_sec=$(( z_ms / 1000 ))
  local z_rem=$(( z_ms % 1000 ))

  # Format as decimal with three fractional digits (sleep accepts e.g. 1.500)
  printf '%d.%03d' "${z_sec}" "${z_rem}"
}

# HTTP GET with bounded exponential-backoff retry on transient 5xx responses.
# On any non-5xx response (including auth errors), populates z_code_file and returns.
# On curl-network failure or exhausted 5xx retries, buc_die. The caller evaluates
# the final HTTP status via its own case-switch on the populated z_code_file.
zrbgv_http_get_with_5xx_retry() {
  zrbgv_sentinel

  local -r z_label="${1}"
  local -r z_url="${2}"
  local -r z_token="${3}"
  local -r z_resp_file="${4}"
  local -r z_code_file="${5}"
  local -r z_stderr_file="${6}"

  local z_attempt=1
  local z_delay="${ZRBGV_HTTP_RETRY_INITIAL_DELAY_SEC}"
  local z_curl_status=0
  local z_code=""

  while test "${z_attempt}" -le "${ZRBGV_HTTP_RETRY_ATTEMPTS}"; do
    buc_log_args "${z_label}: HTTP GET attempt ${z_attempt}/${ZRBGV_HTTP_RETRY_ATTEMPTS}"

    z_curl_status=0
    rbuh_request "GET" "${z_url}" "${z_token}"          \
                      "${z_resp_file}" "${z_code_file}" "${z_stderr_file}" \
      || z_curl_status=$?

    buc_log_args "${z_label}: curl exit status ${z_curl_status}"
    buc_log_pipe < "${z_stderr_file}"

    test "${z_curl_status}" -eq 0 \
      || buc_die "${z_label}: curl failed (network/SSL/DNS) — see ${z_stderr_file}"

    z_code=$(<"${z_code_file}") || buc_die "${z_label}: failed to read HTTP code file"
    test -n "${z_code}" || buc_die "${z_label}: empty HTTP code from curl"

    case "${z_code}" in
      500|502|503|504)
        if test "${z_attempt}" -lt "${ZRBGV_HTTP_RETRY_ATTEMPTS}"; then
          buc_step "${z_label}: transient HTTP ${z_code}, retrying in ${z_delay}s (attempt ${z_attempt}/${ZRBGV_HTTP_RETRY_ATTEMPTS})"
          sleep "${z_delay}"
          z_delay=$(( z_delay * 2 ))
          z_attempt=$(( z_attempt + 1 ))
        else
          buc_die "${z_label}: repeated transient HTTP ${z_code} after ${ZRBGV_HTTP_RETRY_ATTEMPTS} attempts — see ${z_resp_file}"
        fi
        ;;
      *)
        return 0
        ;;
    esac
  done
}

# Execute one Artifact Registry repositories.list call under an already-minted
# mantle token (the donned Leg-3 token, not a JWT-SA token). This is the
# spike-V3-proven attributable call (ADMIN_READ): it both confirms the donned
# token reaches AR and writes the use-hop Data-Access audit entry that carries
# the federate's principalSubject — the entry rbgp_attribution_trail reads back.
# Pure observation: reuses the kindle-constant ZRBGV_AR_* forensic files and
# prints the resulting HTTP code; the verdict lives in the caller.
zrbgv_mantle_ar_call_capture() {
  zrbgv_sentinel

  local -r z_token="${1}"
  test -n "${z_token}" || buc_die "zrbgv_mantle_ar_call_capture: mantle token required"

  test -n "${RBDC_DEPOT_PROJECT_ID:-}" || buc_die "RBDC_DEPOT_PROJECT_ID is not set"
  test -n "${RBRD_GCP_REGION:-}"       || buc_die "RBRD_GCP_REGION is not set"

  local -r z_url="${RBGC_API_ROOT_ARTIFACTREGISTRY}${RBGC_ARTIFACTREGISTRY_V1}/projects/${RBDC_DEPOT_PROJECT_ID}/locations/${RBRD_GCP_REGION}${RBGC_PATH_REPOSITORIES}"

  buc_log_args "Mantle AR repositories.list against ${RBDC_DEPOT_PROJECT_ID}/${RBRD_GCP_REGION}"
  zrbgv_http_get_with_5xx_retry        \
    "Mantle AR repositories.list"      \
    "${z_url}"                         \
    "${z_token}"                       \
    "${ZRBGV_AR_RESP_FILE}"            \
    "${ZRBGV_AR_CODE_FILE}"            \
    "${ZRBGV_AR_STDERR_FILE}"

  local z_code
  z_code=$(<"${ZRBGV_AR_CODE_FILE}") || buc_die "Failed to read mantle AR HTTP code file"
  test -n "${z_code}"                || buc_die "Empty HTTP code from mantle AR curl"

  printf '%s\n' "${z_code}"
}

# Execute one CRM projects.get probe iteration for the Payor OAuth flow.
# Writes response to ZRBGV_CRM_RESP_FILE, HTTP code to ZRBGV_CRM_CODE_FILE,
# and stderr to ZRBGV_CRM_STDERR_FILE (kindle-constant paths for forensic visibility).
zrbgv_payor_crm_probe_once() {
  zrbgv_sentinel

  local z_iteration="${1}"

  buc_log_args "Payor OAuth probe iteration ${z_iteration}"

  buc_log_args "Authenticate via Payor OAuth refresh token flow"
  local z_token
  z_token=$(zrbgp_authenticate_capture) \
    || buc_die "Failed to obtain Payor OAuth access token (iteration ${z_iteration})"
  test -n "${z_token}" || buc_die "Empty Payor OAuth access token (iteration ${z_iteration})"

  buc_log_args "Build CRM projects.get URL"
  test -n "${RBRP_PAYOR_PROJECT_ID:-}" || buc_die "RBRP_PAYOR_PROJECT_ID is not set"

  local -r z_crm_url="${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/projects/${RBRP_PAYOR_PROJECT_ID}"
  local -r z_crm_label="Payor OAuth probe iteration ${z_iteration}"

  buc_log_args "Call CRM projects.get on payor project (with transient-5xx retry)"
  zrbgv_http_get_with_5xx_retry \
    "${z_crm_label}"            \
    "${z_crm_url}"              \
    "${z_token}"                \
    "${ZRBGV_CRM_RESP_FILE}"    \
    "${ZRBGV_CRM_CODE_FILE}"    \
    "${ZRBGV_CRM_STDERR_FILE}"

  local z_code
  z_code=$(<"${ZRBGV_CRM_CODE_FILE}") || buc_die "Failed to read CRM HTTP code file"
  test -n "${z_code}"                 || buc_die "Empty HTTP code from CRM curl"

  buc_log_args "CRM projects.get HTTP ${z_code} for Payor iteration ${z_iteration}"

  case "${z_code}" in
    200)
      buc_step "Payor OAuth probe iteration ${z_iteration}: OK (HTTP ${z_code})"
      ;;
    401|403)
      buc_die "Payor OAuth probe iteration ${z_iteration}: access denied (HTTP ${z_code})"
      ;;
    *)
      local z_err=""
      if jq -e . "${ZRBGV_CRM_RESP_FILE}" >/dev/null 2>&1; then
        z_err=$(jq -r '.error.message // "Unknown error"' "${ZRBGV_CRM_RESP_FILE}" 2>/dev/null) || z_err="Unknown error"
      else
        z_err="Non-JSON response (HTTP ${z_code})"
      fi
      buc_die "Payor OAuth probe iteration ${z_iteration}: unexpected HTTP ${z_code}: ${z_err}"
      ;;
  esac
}

######################################################################
# External Functions (rbgv_*)

# Probe: Payor OAuth Access Probe
#
# For each iteration:
#   1. Authenticate via zrbgp_authenticate_capture (RBRO refresh token -> access token)
#   2. Call CRM projects.get on payor project to verify token works
#   3. Sleep for configured delay
rbgv_payor_oauth_probe() {
  zrbgv_sentinel

  local z_count="${1:-1}"
  local z_delay_ms="${2:-0}"

  buc_doc_brief "Probe Payor OAuth access against Cloud Resource Manager (CRM) projects.get"
  buc_doc_param "count"    "Number of iterations (default: 1)"
  buc_doc_param "delay_ms" "Milliseconds to sleep between iterations (default: 0)"
  buc_doc_shown || return 0

  test -n "${z_count}" || buc_die "count parameter required"

  buc_step "Payor OAuth access probe: count=${z_count} delay_ms=${z_delay_ms}"

  local z_iter=1
  while test "${z_iter}" -le "${z_count}"; do
    buc_step "Payor OAuth probe iteration ${z_iter}/${z_count}"

    zrbgv_payor_crm_probe_once "${z_iter}"

    if test "${z_iter}" -lt "${z_count}" && test "${z_delay_ms}" -gt 0; then
      local z_sleep
      z_sleep=$(zrbgv_ms_to_sleep_capture "${z_delay_ms}")
      buc_log_args "Sleeping ${z_sleep}s (${z_delay_ms}ms) before next iteration"
      sleep "${z_sleep}"
    fi

    z_iter=$(( z_iter + 1 ))
  done

  buc_step "Payor OAuth access probe complete: iterations=${z_count}"
}

# eof
