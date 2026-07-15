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
# Recipe Bottle Google OAuth - base64url primitives, curl-transient classifier, docker login

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBGO_SOURCED:-}" || buc_die "Module rbgo multiply sourced - check sourcing hierarchy"
ZRBGO_SOURCED=1

######################################################################
# Internal Functions (zrbgo_*)

zrbgo_kindle() {
  test -z "${ZRBGO_KINDLED:-}" || buc_die "Module rbgo already kindled"

  # Validate required tools (rehomed from rbl_Locator.sh)
  command -v openssl >/dev/null 2>&1 || buc_die "openssl not found - required for JWT signing and encoding"
  command -v curl    >/dev/null 2>&1 || buc_die "curl not found - required for OAuth exchange"
  command -v jq      >/dev/null 2>&1 || buc_die "jq not found - required for JSON parsing"

  buc_log_args "Ensure RBGC is kindled first"
  zrbgc_sentinel

  buc_log_args "Check environment"
  zburd_sentinel

  readonly ZRBGO_KINDLED=1
}

zrbgo_sentinel() {
  test "${ZRBGO_KINDLED:-}" = "1" || buc_die "Module rbgo not kindled - call zrbgo_kindle first"
}

######################################################################
# Base64 primitives — generic openssl wrappers.
#
# Stateless — no sentinel; safe to call from any module regardless of
# kindle order. rbgo base64url-encodes JWT material; rbgg/rbgp decode SA
# private keys and rbfd decodes Cloud Build step outputs. The -A flag
# (suppress line wrapping) is load-bearing on every site and lives only
# here, so it cannot be silently dropped on one path.

rbgo_base64_decode_string_to_file() {
  local -r z_b64="${1:-}"
  local -r z_output="${2:-}"
  test -n "${z_b64}"    || return 1
  test -n "${z_output}" || return 1
  printf '%s' "${z_b64}" | openssl enc -base64 -d -A > "${z_output}" || return 1
}

rbgo_base64_decode_file_to_file() {
  local -r z_input="${1:-}"
  local -r z_output="${2:-}"
  test -n "${z_input}"  || return 1
  test -n "${z_output}" || return 1
  test -f "${z_input}"  || return 1
  openssl enc -base64 -d -A < "${z_input}" > "${z_output}" || return 1
}

rbgo_base64_encode_string_capture() {
  local -r z_input="${1:-}"
  printf '%s' "${z_input}" | openssl enc -base64 -A
}

rbgo_base64_encode_file_capture() {
  local -r z_file="${1:-}"
  test -f "${z_file}" || return 1
  openssl enc -base64 -A < "${z_file}"
}

# Stateless — no sentinel; safe to call from any module regardless of kindle order.
rbgo_curl_status_is_transient_predicate() {
  case "${1:-}" in
    7|28|35|56) return 0 ;;
    *)          return 1 ;;
  esac
}

######################################################################
# External Functions (rbgo_*)

# Authenticate the host docker client to a GAR registry with bounded retry on
# the moby/moby#44350 premature-timeout transient (see
# RBGC_DOCKER_LOGIN_TRANSIENT_SIGNATURE). docker login is the lone login/pull/push
# verb with no internal retry and a hardcoded 15s daemon->registry auth timeout;
# against a healthy-but-slow backend it fails where the endpoint is in fact fine.
# This mirrors the curl-transient tolerance in rbgu_http_json: retry only the
# surveyed signature, fail fast on everything else (real auth failures emit
# "unauthorized" and do not match), so clean-failure semantics are preserved.
# Stateless (no sentinel) — safe to call from any module regardless of kindle
# order, like rbgu_curl_status_is_transient_predicate.
#
# A second Palisade neighbor lives here for headless Cygwin: Docker Desktop's
# wincred helper cannot persist the credential auth just succeeded for
# (RBGC_DOCKER_WINCRED_HEADLESS_SIGNATURE), and Windows docker ignores an empty
# credsStore, so config alone cannot divert the store to the file store. On
# that exact signature the function bends ONCE: auth already succeeded, so it
# writes the credential straight into docker's base64 file store at
# ${HOME}/.docker/config.json (the `auths` map, the form WSL uses) and returns
# success. The caller's `docker push` reads that credential from the file, so
# the push completes without ever touching the Windows vault.
# Args: token registry_host
rbgo_docker_login() {
  local -r z_token="${1:?rbgo_docker_login: token required}"
  local -r z_host="${2:?rbgo_docker_login: registry host required}"

  local z_attempt=0
  local z_stderr_file=""
  local z_rc=0
  local z_auth_b64=""

  while :; do
    z_attempt=$((z_attempt + 1))
    z_stderr_file="${BURD_TEMP_DIR}/rbgo_docker_login_${z_attempt}_stderr.txt"

    z_rc=0
    printf '%s' "${z_token}" \
      | docker login -u oauth2accesstoken --password-stdin "https://${z_host}" \
          > /dev/null 2>"${z_stderr_file}" \
      || z_rc=$?

    test "${z_rc}" -ne 0 || break

    buc_log_pipe < "${z_stderr_file}"

    # Palisade bend (docker's own credential store): under headless Cygwin the
    # wincred helper cannot persist the credential auth just succeeded for, and
    # an empty credsStore does not divert Windows docker to the file store
    # (verified — the CLI still detects wincred). Auth already succeeded, so
    # write the credential into the base64 file store ourselves — the on-disk
    # `auths` form WSL uses and `docker push` reads directly — and treat login
    # as done. credsStore is intentionally omitted so retrieval reads the file.
    # A real auth failure emits "unauthorized", never matches, and falls through
    # to the surveyed-transient / fail-fast handling below.
    if [[ "$(<"${z_stderr_file}")" == *"${RBGC_DOCKER_WINCRED_HEADLESS_SIGNATURE}"* ]]; then
      buc_warn "Docker wincred helper cannot persist headless (no interactive Windows logon); writing the authenticated credential to the base64 file store in \${HOME}/.docker/config.json. REMOVE this bend when the host gains a working credential vault."
      z_auth_b64=$(rbgo_base64_encode_string_capture "oauth2accesstoken:${z_token}") \
        || buc_die "Cannot base64-encode the docker credential for the file-store bend"
      mkdir -p "${HOME}/.docker" \
        || buc_die "Cannot create ${HOME}/.docker for the credential-store bend"
      printf '{"auths":{"%s":{"auth":"%s"}}}' "${z_host}" "${z_auth_b64}" > "${HOME}/.docker/config.json" \
        || buc_die "Cannot write ${HOME}/.docker/config.json credential-store bend"
      return 0
    fi

    [[ "$(<"${z_stderr_file}")" == *"${RBGC_DOCKER_LOGIN_TRANSIENT_SIGNATURE}"* ]] \
      || buc_die "Docker login to ${z_host} failed — see ${z_stderr_file}"

    test "${z_attempt}" -lt "${RBGC_HTTP_TRANSIENT_RETRY_ATTEMPTS}" \
      || buc_die "Docker login to ${z_host} failed after ${RBGC_HTTP_TRANSIENT_RETRY_ATTEMPTS} attempts (transient daemon->registry timeout, moby#44350) — see ${z_stderr_file}"

    buc_warn "Docker login transient (attempt ${z_attempt}/${RBGC_HTTP_TRANSIENT_RETRY_ATTEMPTS}, moby#44350 timeout) — retrying in ${RBGC_HTTP_TRANSIENT_RETRY_SLEEP_SEC}s"
    sleep "${RBGC_HTTP_TRANSIENT_RETRY_SLEEP_SEC}"
  done
}

# eof
