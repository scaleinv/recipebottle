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
# Recipe Bottle Auth - RBRO credential load and mantle role token mint

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBA_SOURCED:-}" || buc_die "Module rba multiply sourced - check sourcing hierarchy"
ZRBA_SOURCED=1

######################################################################
# Internal Functions (zrba_*)

zrba_kindle() {
  test -z "${ZRBA_KINDLED:-}" || buc_die "Module rba already kindled"

  # Ensure dependency kindled first (rba mints tokens via rbgo)
  zrbgo_sentinel

  # Federation protocol constants — RFC 8628 device flow (Leg 1) + RFC 8693 STS
  # exchange (Leg 2). Pure protocol invariants with no config dependency, so they
  # set unconditionally; the per-trust audience is built from RBRF_* at Leg 2, not
  # here. The federated path is opt-in: only rba_avow and its legs read these,
  # and they guard on zrbrf_sentinel / zrbcc_sentinel, so the keyfile-only
  # consumers that source rba are untouched.
  readonly ZRBA_STS_ENDPOINT="https://sts.googleapis.com/v1/token"
  readonly ZRBA_STS_GRANT_TYPE="urn:ietf:params:oauth:grant-type:token-exchange"
  readonly ZRBA_STS_REQUESTED_TOKEN_TYPE="urn:ietf:params:oauth:token-type:access_token"
  readonly ZRBA_STS_SUBJECT_TOKEN_TYPE="urn:ietf:params:oauth:token-type:id_token"
  readonly ZRBA_STS_SCOPE="https://www.googleapis.com/auth/cloud-platform"
  readonly ZRBA_DEVICE_GRANT_TYPE="urn:ietf:params:oauth:grant-type:device_code"

  # RFC 7523 JWT-authorization grant — the programmatic Leg 1's grant_type, the
  # no-human sibling of the device-code grant above.
  readonly ZRBA_JWT_BEARER_GRANT_TYPE="urn:ietf:params:oauth:grant-type:jwt-bearer"

  # Sitting cache tuning: skew (treat the federated token as spent this many
  # seconds before its stated expiry) and the device-flow poll ceiling (device
  # codes self-expire in ~15 min).
  readonly ZRBA_SITTING_SKEW_SEC=60
  readonly ZRBA_DEVICE_POLL_MAX_SEC=900

  # Proactive runway floor (RBS0 rbtf_sitting): the blanket required-runway
  # default the avow sitting-reuse gate demands, sized so an admitted sitting
  # outlives the worst-case cloud build (~95 min) with margin. Per-operation
  # bounds ride the rba_avow parameter seam; none are populated until one
  # earns its existence.
  readonly ZRBA_SITTING_RUNWAY_FLOOR_SEC=7200

  # Programmatic (RFC 7523) assertion tuning: the self-supplied JWT's lifetime and
  # the grant scope. Each mint carries a fresh jti and a short exp — single-use.
  readonly ZRBA_PROG_ASSERTION_TTL_SEC=300
  readonly ZRBA_PROG_ASSERTION_SCOPE="openid"

  # Per-invocation scratch for the leg curls — BURD_TEMP_DIR (process lifetime),
  # never the sitting cache, which must outlive one invocation (see rba_avow).
  readonly ZRBA_FED_DEVICE_RESPONSE_FILE="${BURD_TEMP_DIR}/rba_fed_device.json"
  readonly ZRBA_FED_TOKEN_RESPONSE_FILE="${BURD_TEMP_DIR}/rba_fed_token.json"
  readonly ZRBA_FED_STS_RESPONSE_FILE="${BURD_TEMP_DIR}/rba_fed_sts.json"
  readonly ZRBA_FED_DON_RESPONSE_FILE="${BURD_TEMP_DIR}/rba_fed_don.json"
  readonly ZRBA_FED_CURL_STDERR_FILE="${BURD_TEMP_DIR}/rba_fed_curl_stderr.txt"
  readonly ZRBA_FED_JQ_STDERR_FILE="${BURD_TEMP_DIR}/rba_fed_jq_stderr.txt"
  readonly ZRBA_FED_OPENSSL_STDERR_FILE="${BURD_TEMP_DIR}/rba_fed_openssl_stderr.txt"

  # The don's request body is non-secret JSON (the scope list); it is composed
  # here rather than string-interpolated at the call site.
  readonly ZRBA_FED_DON_BODY_FILE="${BURD_TEMP_DIR}/rba_fed_don_body.json"

  # Non-secret scalar fields parsed out of the leg responses land in these temp
  # files: BCG bars $() on external commands, so jq/date write a file and the
  # value is read back with $(<file). The id, federated, and mantle tokens are
  # never among them — jq emits each straight to its function's stdout. The only
  # token-bearing temp files are the STS and don curl responses above (the
  # federated and mantle tokens respectively): both are per-invocation
  # BURD_TEMP_DIR scratch, never the persistent sitting cache, which holds the
  # federated token alone — the mantle token is never cached anywhere.
  readonly ZRBA_FED_SITTING_EXPIRY_FILE="${BURD_TEMP_DIR}/rba_fed_sitting_expiry.txt"
  readonly ZRBA_FED_SITTING_NOW_FILE="${BURD_TEMP_DIR}/rba_fed_sitting_now.txt"
  readonly ZRBA_FED_AVOW_NOW_FILE="${BURD_TEMP_DIR}/rba_fed_avow_now.txt"
  readonly ZRBA_FED_RUNWAY_EXPIRY_FILE="${BURD_TEMP_DIR}/rba_fed_runway_expiry.txt"
  readonly ZRBA_FED_RUNWAY_NOW_FILE="${BURD_TEMP_DIR}/rba_fed_runway_now.txt"
  readonly ZRBA_FED_DEVICE_CODE_FILE="${BURD_TEMP_DIR}/rba_fed_device_code.txt"
  readonly ZRBA_FED_USER_CODE_FILE="${BURD_TEMP_DIR}/rba_fed_user_code.txt"
  readonly ZRBA_FED_VERIFY_URI_FILE="${BURD_TEMP_DIR}/rba_fed_verify_uri.txt"
  readonly ZRBA_FED_INTERVAL_FILE="${BURD_TEMP_DIR}/rba_fed_interval.txt"
  readonly ZRBA_FED_POLL_ERROR_FILE="${BURD_TEMP_DIR}/rba_fed_poll_error.txt"
  readonly ZRBA_FED_EXPIRES_IN_FILE="${BURD_TEMP_DIR}/rba_fed_expires_in.txt"
  readonly ZRBA_FED_DON_CODE_FILE="${BURD_TEMP_DIR}/rba_fed_don_code.txt"
  readonly ZRBA_FED_DON_ERROR_FILE="${BURD_TEMP_DIR}/rba_fed_don_error.txt"

  # Programmatic Leg-1 (RFC 7523 mint) scratch. The JWT header/payload and their
  # base64url encodings, the signing input, the raw+encoded signature, and the
  # assembled assertion are all NON-secret (public JWT parts) — the one durable
  # secret, the asserter private key, is read only by openssl via its regime PATH
  # and never lands here, and the client secret is read only by curl via its file
  # reference. PROG_TOKEN_RESPONSE bears the minted id_token: like the STS and don
  # responses it is per-invocation BURD_TEMP_DIR scratch, never the sitting cache,
  # and jq emits the id_token from it straight to stdout (never a shell var).
  readonly ZRBA_FED_PROG_NOW_FILE="${BURD_TEMP_DIR}/rba_fed_prog_now.txt"
  readonly ZRBA_FED_PROG_HEADER_FILE="${BURD_TEMP_DIR}/rba_fed_prog_header.json"
  readonly ZRBA_FED_PROG_PAYLOAD_FILE="${BURD_TEMP_DIR}/rba_fed_prog_payload.json"
  readonly ZRBA_FED_PROG_HEADER_B64_FILE="${BURD_TEMP_DIR}/rba_fed_prog_header_b64.txt"
  readonly ZRBA_FED_PROG_PAYLOAD_B64_FILE="${BURD_TEMP_DIR}/rba_fed_prog_payload_b64.txt"
  readonly ZRBA_FED_PROG_SIGNING_FILE="${BURD_TEMP_DIR}/rba_fed_prog_signing.txt"
  readonly ZRBA_FED_PROG_SIG_RAW_FILE="${BURD_TEMP_DIR}/rba_fed_prog_sig_raw.bin"
  readonly ZRBA_FED_PROG_SIG_B64_FILE="${BURD_TEMP_DIR}/rba_fed_prog_sig_b64.txt"
  readonly ZRBA_FED_PROG_ASSERTION_FILE="${BURD_TEMP_DIR}/rba_fed_prog_assertion.jwt"
  readonly ZRBA_FED_PROG_TOKEN_RESPONSE_FILE="${BURD_TEMP_DIR}/rba_fed_prog_token.json"
  readonly ZRBA_FED_PROG_ERROR_FILE="${BURD_TEMP_DIR}/rba_fed_prog_error.txt"

  readonly ZRBA_KINDLED=1
}

zrba_sentinel() {
  test "${ZRBA_KINDLED:-}" = "1" || buc_die "Module rba not kindled - call zrba_kindle first"
}

######################################################################
# External / RBTOE Pattern Functions

# The credential accessor — the single place credential material is resolved.
# Keyed by identity (governor | director | retriever): ensures a live sitting
# (avowal) then dons the matching mantle SA, minting a short-lived mantle
# access token. No call site outside this function touches credential material
# (source-side grep-gated); the production callers and their bearer-blind
# downstream are unchanged — the keyfile→federation swap lives entirely here.
#
# Deliberately NOT a pure _capture: rba_avow is folded in so callers never
# learn the avowal dance, so this accessor emits rba_avow's buc_step
# progress — the device-flow prompt included — to stderr and may buc_die on a
# failed avowal. The stdout contract
# still holds — only the mantle token reaches stdout (avow writes stderr
# only; the don emits the token straight to stdout) — and the reveille-tier
# credless guard's in-band buc_reject still propagates: avow's exit
# terminates the caller's command substitution with the credless band code,
# which the caller's `|| buc_die` re-exits through the band membrane. The sitting
# cache rba_avow writes is a file, so it survives this command-substitution
# subshell and the next caller takes the cache-hit path.
rba_token_capture() {
  zrba_sentinel
  zrbcc_sentinel

  local -r z_identity="${1:-}"

  # Validate up front so a typo'd identity dies before an interactive avowal.
  # The identity is the pallium-sprued mantle token (rbpa_governor, …), THE
  # canonical form — no bare-role alias is accepted (RBCC_mantle_* is the home).
  case "${z_identity}" in
    "${RBCC_mantle_governor}"|"${RBCC_mantle_director}"|"${RBCC_mantle_retriever}") ;;
    *) buc_die "rba_token_capture: unknown mantle token '${z_identity}' (expected ${RBCC_mantle_governor} | ${RBCC_mantle_director} | ${RBCC_mantle_retriever})" ;;
  esac

  rba_avow
  rba_don_capture "${z_identity}"
}

######################################################################
# Federation branch — avowal (Leg 1) + STS exchange (Leg 2)
#
# The accessor's federated-token path. Leg 1 obtains an IdP id_token by one of two
# mechanism-gated arms (RBRF_MECHANISM): the interactive device flow (a human avows,
# RFC 8628) or the programmatic RFC 7523 grant (a self-supplied JWT, no human —
# RBSFA). Leg 2 exchanges that id_token at Google STS for a workforce federated
# access token, mechanism-invariant; that federated token alone is cached,
# per-sitting. The mantle token (Leg 3, the don) is a separate artifact, separately
# scoped, and never cached — it is not built here. The persisted sitting cache is the
# clean producer/consumer seam between this path and the don, and its key is already
# pool+provider, so an interactive and a programmatic foedus never cross sittings.
#
# Federation config is read from two regimes under the one-pool Model: the manor
# pool id from RBRW_* (rbrw_regime, manor-level) and the per-foedus provider from
# RBRF_* (rbrf_regime). The leg curls reuse RBCC curl timeouts and rbgo's
# transient-curl classifier. Callers kindle rbrw + rbrf + rbcc before invoking
# rba_avow; the functions guard on their sentinels.

# Resolve the per-session sitting cache path. Session-scoped — it spans tabtarget
# processes within one operator session — tmpfs-preferred, keyed by the trust so
# switching pools never crosses sittings. Dir 0700; the file is written 0600.
zrba_sitting_path_capture() {
  zrba_sentinel
  zrbrw_sentinel
  zrbrf_sentinel

  local z_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
  z_dir="${z_dir%/}/rbf-sitting"
  mkdir -p  "${z_dir}" || return 1
  chmod 700 "${z_dir}" || return 1
  printf '%s/%s.%s.json' "${z_dir}" "${RBRW_WORKFORCE_POOL_ID}" "${RBRF_PROVIDER_ID}"
}

# Echo the cached federated token if present and not within skew of expiry;
# return 1 on any miss (absent, malformed, or expired).
zrba_sitting_read_capture() {
  zrba_sentinel

  local z_path
  z_path=$(zrba_sitting_path_capture) || return 1
  test -f "${z_path}" || return 1

  jq -r '.expiry_epoch // 0' "${z_path}" \
     > "${ZRBA_FED_SITTING_EXPIRY_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || return 1
  local -r z_expiry=$(<"${ZRBA_FED_SITTING_EXPIRY_FILE}")
  [[ "${z_expiry}" =~ ^[0-9]+$ ]] || return 1

  date +%s > "${ZRBA_FED_SITTING_NOW_FILE}" || return 1
  local -r z_now=$(<"${ZRBA_FED_SITTING_NOW_FILE}")
  test -n "${z_now}" || return 1
  test "${z_expiry}" -gt "$(( z_now + ZRBA_SITTING_SKEW_SEC ))" || return 1

  # Federated token (secret): jq emits it straight to stdout, never through a
  # shell var or temp file. select(length > 0) yields no output and a non-zero jq
  # exit when the token is absent or empty — the capture miss.
  jq -er '.federated_token // empty | select(length > 0)' "${z_path}" 2>"${ZRBA_FED_JQ_STDERR_FILE}"
}

# Echo the cached sitting subject (the avowed oid) if present; return 1 on any
# miss. Informational mirror of zrba_sitting_read_capture — the muniment-trail
# subject (decoded best-effort at avowal, non-load-bearing), not a
# credential, so no expiry gate: identity, not a token. select(length > 0) yields
# a non-zero jq exit for an absent/empty subject — the capture miss.
zrba_sitting_subject_capture() {
  zrba_sentinel

  local z_path
  z_path=$(zrba_sitting_path_capture) || return 1
  test -f "${z_path}" || return 1

  jq -er '.subject // empty | select(length > 0)' "${z_path}" 2>"${ZRBA_FED_JQ_STDERR_FILE}"
}

# A live (unexpired) sitting is cached — status only, no output.
zrba_sitting_live_predicate() {
  zrba_sentinel
  zrba_sitting_read_capture >/dev/null || return 1
  return 0
}

# Echo the cached sitting's remaining runway in whole seconds (stored expiry
# minus now, floored at 0); return 1 on any structural miss (absent cache,
# malformed expiry, failed clock read). A lapsed sitting is runway 0, not a
# miss — liveness and sufficiency judgments belong to the callers.
zrba_sitting_runway_capture() {
  zrba_sentinel

  local z_path
  z_path=$(zrba_sitting_path_capture) || return 1
  test -f "${z_path}" || return 1

  jq -r '.expiry_epoch // 0' "${z_path}" \
     > "${ZRBA_FED_RUNWAY_EXPIRY_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || return 1
  local -r z_expiry=$(<"${ZRBA_FED_RUNWAY_EXPIRY_FILE}")
  [[ "${z_expiry}" =~ ^[0-9]+$ ]] || return 1

  date +%s > "${ZRBA_FED_RUNWAY_NOW_FILE}" || return 1
  local -r z_now=$(<"${ZRBA_FED_RUNWAY_NOW_FILE}")
  [[ "${z_now}" =~ ^[0-9]+$ ]] || return 1

  local z_runway=$(( z_expiry - z_now ))
  test "${z_runway}" -ge 0 || z_runway=0
  printf '%s' "${z_runway}"
}

# Atomically write the sitting cache (federated token + expiry epoch + subject).
# The dir is 0700 (owner-only traversal); chmod 600 + temp-then-rename keeps the
# file owner-only and never partially visible under its stable name.
zrba_sitting_write() {
  zrba_sentinel

  local -r z_token="${1:-}"
  local -r z_expiry_epoch="${2:-}"
  local -r z_subject="${3:-}"

  local z_path
  z_path=$(zrba_sitting_path_capture) || return 1
  local -r z_tmp="${z_path}.tmp.$$"

  jq -n --arg t "${z_token}" --argjson e "${z_expiry_epoch}" --arg s "${z_subject}" \
     '{federated_token: $t, expiry_epoch: $e, subject: $s}' \
     > "${z_tmp}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || return 1
  chmod 600 "${z_tmp}" || return 1
  mv -f "${z_tmp}" "${z_path}" || return 1
}

# Best-effort: decode the federated subject (oid, else sub) from the IdP id_token
# payload. Informational only — cached toward the muniment trail, never load-bearing.
zrba_idtoken_subject_capture() {
  zrba_sentinel

  local z_payload="${1#*.}"
  z_payload="${z_payload%%.*}"
  test -n "${z_payload}" || return 1
  z_payload="${z_payload//-/+}"
  z_payload="${z_payload//_/\/}"
  case $(( ${#z_payload} % 4 )) in
    2) z_payload="${z_payload}==" ;;
    3) z_payload="${z_payload}="  ;;
  esac

  # Decode and select in one pipeline (capture-final): the decoded id_token
  # payload exists only in the pipe, never in a var or temp file. pipefail makes
  # a base64 or jq failure fail the pipeline, which the caller tolerates.
  printf '%s' "${z_payload}" \
    | openssl enc -base64 -d -A 2>"${ZRBA_FED_OPENSSL_STDERR_FILE}" \
    | jq -r '.oid // .sub // empty' 2>"${ZRBA_FED_JQ_STDERR_FILE}"
}

# Best-effort clipboard copy of the device-flow user code at avowal-prompt
# emission. Custody rule: ONLY the user code ever rides this path — never the
# device code, the federated token, or a mantle token. The user code is
# display-safe by design (RBS0 rbtf_avow: possession grants nothing without
# the human's own IdP sign-in); accepted residual: clipboard sync/history may
# spread the single-use ~15-minute code to synced devices. Convenience only,
# never load-bearing — no tool found or a failed copy degrades to
# display-only, and only a successful copy is announced (it replaces the
# operator's prior clipboard contents). Mechanism is the BUK platform
# normalizer buc_clipboard_copy_predicate; its optional probe-and-skip tools
# are inventoried in RBS0 per BCG Command Dependency Discipline.
zrba_user_code_clipboard() {
  local -r z_code="${1:?zrba_user_code_clipboard: user code required}"

  if buc_clipboard_copy_predicate "${z_code}"; then
    buc_step "    (code copied to your clipboard)"
  elif test -n "${z_buc_clipboard_tool}"; then
    buc_log_args "Clipboard copy via ${z_buc_clipboard_tool} failed; user code display-only"
  else
    buc_log_args "No clipboard tool present; user code display-only"
  fi
  return 0
}

# Leg 1 — device-flow avowal (RFC 8628). Requests a device + user code,
# surfaces the verification URL and code as a yawp on the progress stream,
# polls the IdP token endpoint until the human approves, and echoes the OIDC
# id_token. The id_token is never persisted — Leg 2 consumes it in-process.
zrba_leg1_idtoken_capture() {
  zrba_sentinel
  zrbrf_sentinel
  zrbcc_sentinel

  local z_curl_status=0
  curl -sS -X POST "${RBRF_IDP_DEVICE_ENDPOINT}"         \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
    --max-time        "${RBCC_CURL_MAX_TIME_SEC}"        \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${RBRF_IDP_CLIENT_ID}"   \
    --data-urlencode "scope=${RBRF_IDP_SCOPE}"           \
    > "${ZRBA_FED_DEVICE_RESPONSE_FILE}" 2>"${ZRBA_FED_CURL_STDERR_FILE}" || z_curl_status=$?
  test "${z_curl_status}" -eq 0 \
    || { buc_log_args "Device-code request failed (curl ${z_curl_status}); see ${ZRBA_FED_CURL_STDERR_FILE}"; return 1; }

  jq -r '.device_code // empty' "${ZRBA_FED_DEVICE_RESPONSE_FILE}" \
     > "${ZRBA_FED_DEVICE_CODE_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || return 1
  local -r z_device_code=$(<"${ZRBA_FED_DEVICE_CODE_FILE}")
  jq -r '.user_code // empty' "${ZRBA_FED_DEVICE_RESPONSE_FILE}" \
     > "${ZRBA_FED_USER_CODE_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || return 1
  local -r z_user_code=$(<"${ZRBA_FED_USER_CODE_FILE}")
  jq -r '.verification_uri // .verification_url // empty' "${ZRBA_FED_DEVICE_RESPONSE_FILE}" \
     > "${ZRBA_FED_VERIFY_URI_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || return 1
  local -r z_verification_uri=$(<"${ZRBA_FED_VERIFY_URI_FILE}")
  jq -r '.interval // 5' "${ZRBA_FED_DEVICE_RESPONSE_FILE}" \
     > "${ZRBA_FED_INTERVAL_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || return 1
  local z_interval=$(<"${ZRBA_FED_INTERVAL_FILE}")
  test -n "${z_device_code}"      || return 1
  test -n "${z_user_code}"        || return 1
  test -n "${z_verification_uri}" || return 1
  [[ "${z_interval}" =~ ^[0-9]+$ ]] || z_interval=5

  # Surface the prompt as a yawp on the shared progress stream — console, log,
  # and any watching relay alike — so a headless-but-human-reachable caller can
  # complete the sign-in. The user code rides the stream deliberately: RFC 8628
  # designs it for open display (possession grants nothing without the human's
  # own IdP sign-in, and a substituted sign-in cannot pass admission), so the
  # retired /dev/tty emission and its headless fail-fast gate defended no
  # threat. Spec home: RBS0 rbtf_avow.
  buyy_href_yawp "${z_verification_uri}" "${z_verification_uri}"; local -r z_uri_yp="${z_buym_yelp}"
  buyy_ui_yawp   "${z_user_code}";                                local -r z_code_yp="${z_buym_yelp}"
  buc_step "Avowal — sign in to open your sitting:"
  buc_step "    ${z_uri_yp}"
  buc_step "    code: ${z_code_yp}"
  zrba_user_code_clipboard "${z_user_code}"
  buc_log_args "Avowal prompt emitted; polling for sign-in"

  local z_elapsed=0
  local z_err=""
  while test "${z_elapsed}" -lt "${ZRBA_DEVICE_POLL_MAX_SEC}"; do
    sleep "${z_interval}" || return 1
    z_elapsed=$(( z_elapsed + z_interval ))

    z_curl_status=0
    curl -sS -X POST "${RBRF_IDP_TOKEN_ENDPOINT}"            \
      --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}"   \
      --max-time        "${RBCC_CURL_MAX_TIME_SEC}"          \
      -H "Content-Type: application/x-www-form-urlencoded"   \
      --data-urlencode "grant_type=${ZRBA_DEVICE_GRANT_TYPE}" \
      --data-urlencode "client_id=${RBRF_IDP_CLIENT_ID}"     \
      --data-urlencode "device_code=${z_device_code}"        \
      > "${ZRBA_FED_TOKEN_RESPONSE_FILE}" 2>"${ZRBA_FED_CURL_STDERR_FILE}" || z_curl_status=$?
    if test "${z_curl_status}" -ne 0; then
      rbgo_curl_status_is_transient_predicate "${z_curl_status}" \
        || { buc_log_args "Device-flow poll failed (curl ${z_curl_status})"; return 1; }
      continue
    fi

    # id_token present → jq emits it (secret) straight to stdout and we finish,
    # with no token landing in a var or temp file. select(length > 0) yields a
    # non-zero jq exit for an absent/empty token, keeping it on the polling path.
    if jq -er '.id_token // empty | select(length > 0)' \
         "${ZRBA_FED_TOKEN_RESPONSE_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}"; then
      return 0
    fi

    jq -r '.error // empty' "${ZRBA_FED_TOKEN_RESPONSE_FILE}" \
       > "${ZRBA_FED_POLL_ERROR_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || : > "${ZRBA_FED_POLL_ERROR_FILE}"
    z_err=$(<"${ZRBA_FED_POLL_ERROR_FILE}")
    case "${z_err}" in
      authorization_pending) ;;
      slow_down)             z_interval=$(( z_interval + 5 )) ;;
      *)                     buc_log_args "Device-flow authorization failed: ${z_err:-no id_token in response}"; return 1 ;;
    esac
  done

  buc_log_args "Device-flow timed out after ${ZRBA_DEVICE_POLL_MAX_SEC}s without approval"
  return 1
}

# base64url-encode a file's bytes (RFC 7515): standard base64 via openssl (the
# declared dependency — base64/tr are evicted, BCG Command Dependency Discipline),
# then +/=->-_ stripped by bash parameter expansion. A non-secret transform over
# public JWT parts. Args: $1 input file, $2 the raw-base64 scratch file (unique per
# part, forensic). Echoes the b64url string or returns 1.
zrba_b64url_capture() {
  zrba_sentinel

  local -r z_in="${1:-}"
  local -r z_raw="${2:-}"

  openssl enc -base64 -A -in "${z_in}" > "${z_raw}" 2>"${ZRBA_FED_OPENSSL_STDERR_FILE}" || return 1
  local z_b64=$(<"${z_raw}")
  test -n "${z_b64}" || return 1
  z_b64="${z_b64//+/-}"
  z_b64="${z_b64//\//_}"
  z_b64="${z_b64//=/}"
  printf '%s' "${z_b64}"
}

# Leg 1 (programmatic) — the RFC 7523 JWT-authorization grant. The no-human sibling
# of the device-flow avowal: mint a subject id_token by signing an assertion with the
# caged asserter private key and POSTing it to the reachable grant endpoint, the
# confidential client authenticated by its secret. Echoes the OIDC id_token; Leg 2
# consumes it in-process, never persisted. Reads its inputs solely from the
# programmatic RBRF_ self-supply fields (RBSFA/RBSRF) — it never learns "Keycloak".
#
# Custody (BCG / RBSFK two-keys): the asserter private key is read ONLY by openssl
# via its regime PATH and never enters a shell var; the client secret is read ONLY by
# curl via its file reference (--data-urlencode name@file) and never enters a shell
# var or the argument list; the minted id_token is emitted by jq straight to stdout,
# never through a var. The assertion and its parts are public (a signed JWT), so they
# ride files and vars freely — only the two durable secrets are fenced.
zrba_leg1_programmatic_idtoken_capture() {
  zrba_sentinel
  zrbrf_sentinel
  zrbcc_sentinel

  # The two secret-path references (never the material). cwd is the repo root
  # (dispatch normalizes it), so these repo-root-relative paths resolve here.
  local -r z_key_file="${RBRF_ASSERTER_KEY_FILE}"
  local -r z_secret_file="${RBRF_CLIENT_SECRET_FILE}"
  test -f "${z_key_file}" \
    || { buc_log_args "Asserter key file absent: ${z_key_file} (RBRF_ASSERTER_KEY_FILE)"; return 1; }
  test -f "${z_secret_file}" \
    || { buc_log_args "Client secret file absent: ${z_secret_file} (RBRF_CLIENT_SECRET_FILE)"; return 1; }

  # Fresh assertion timestamps: BCG bars $() on external commands, so date writes a
  # file read back with the $(<file) builtin. exp = iat + TTL; a unique jti per mint
  # (one-time use — Keycloak disables reuse by default, RBSFK).
  date +%s > "${ZRBA_FED_PROG_NOW_FILE}" || return 1
  local -r z_iat=$(<"${ZRBA_FED_PROG_NOW_FILE}")
  [[ "${z_iat}" =~ ^[0-9]+$ ]] || return 1
  local -r z_exp=$(( z_iat + ZRBA_PROG_ASSERTION_TTL_SEC ))
  local -r z_jti="rba-${z_iat}-$$"

  # Compose the non-secret JWT header and payload as JSON via jq (safe quoting of the
  # regime-sourced values). aud = RBRF_IDP_ISSUER — the assertion aud is cinched to
  # that existing field, no separate field (RBSFA); the IdP resolves the asserter
  # subject to its federated-linked user through the realm's asserting-trust link.
  jq -cn --arg kid "${RBRF_ASSERTER_KID}" \
     '{alg:"RS256",typ:"JWT",kid:$kid}' \
     > "${ZRBA_FED_PROG_HEADER_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" \
    || { buc_log_args "Failed to compose the assertion header; see ${ZRBA_FED_JQ_STDERR_FILE}"; return 1; }
  jq -cn --arg iss "${RBRF_ASSERTER_ISSUER}" --arg sub "${RBRF_ASSERTER_SUBJECT}" \
     --arg aud "${RBRF_IDP_ISSUER}" --argjson iat "${z_iat}" --argjson exp "${z_exp}" \
     --arg jti "${z_jti}" \
     '{iss:$iss,sub:$sub,aud:$aud,iat:$iat,exp:$exp,jti:$jti}' \
     > "${ZRBA_FED_PROG_PAYLOAD_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" \
    || { buc_log_args "Failed to compose the assertion payload; see ${ZRBA_FED_JQ_STDERR_FILE}"; return 1; }

  # base64url the header and payload (non-secret).
  local z_h64
  z_h64=$(zrba_b64url_capture "${ZRBA_FED_PROG_HEADER_FILE}" "${ZRBA_FED_PROG_HEADER_B64_FILE}") \
    || { buc_log_args "Failed to base64url the assertion header; see ${ZRBA_FED_OPENSSL_STDERR_FILE}"; return 1; }
  local z_p64
  z_p64=$(zrba_b64url_capture "${ZRBA_FED_PROG_PAYLOAD_FILE}" "${ZRBA_FED_PROG_PAYLOAD_B64_FILE}") \
    || { buc_log_args "Failed to base64url the assertion payload; see ${ZRBA_FED_OPENSSL_STDERR_FILE}"; return 1; }

  # Signing input = <b64url header>.<b64url payload>, to a file (the thing signed).
  printf '%s.%s' "${z_h64}" "${z_p64}" > "${ZRBA_FED_PROG_SIGNING_FILE}" || return 1

  # RS256-sign with the asserter private key BY PATH (never a shell var); raw binary
  # signature to a file, then base64url it.
  openssl dgst -sha256 -sign "${z_key_file}" -binary "${ZRBA_FED_PROG_SIGNING_FILE}" \
     > "${ZRBA_FED_PROG_SIG_RAW_FILE}" 2>"${ZRBA_FED_OPENSSL_STDERR_FILE}" \
    || { buc_log_args "Assertion signing failed; see ${ZRBA_FED_OPENSSL_STDERR_FILE}"; return 1; }
  local z_sig
  z_sig=$(zrba_b64url_capture "${ZRBA_FED_PROG_SIG_RAW_FILE}" "${ZRBA_FED_PROG_SIG_B64_FILE}") \
    || { buc_log_args "Failed to base64url the assertion signature; see ${ZRBA_FED_OPENSSL_STDERR_FILE}"; return 1; }

  # Assemble the assertion = signing_input.signature, to a file curl reads by
  # reference (keeps it off the argument list; single-use, short-lived).
  printf '%s.%s' "$(<"${ZRBA_FED_PROG_SIGNING_FILE}")" "${z_sig}" \
     > "${ZRBA_FED_PROG_ASSERTION_FILE}" || return 1

  # POST the RFC 7523 grant. The client secret and the assertion both ride by FILE
  # REFERENCE (--data-urlencode name@file), so neither the secret nor the assertion
  # enters a shell var or the argument list.
  local z_curl_status=0
  curl -sS -X POST "${RBRF_GRANT_ENDPOINT}"                      \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}"         \
    --max-time        "${RBCC_CURL_MAX_TIME_SEC}"                \
    -H "Content-Type: application/x-www-form-urlencoded"         \
    --data-urlencode "grant_type=${ZRBA_JWT_BEARER_GRANT_TYPE}"  \
    --data-urlencode "client_id=${RBRF_IDP_CLIENT_ID}"           \
    --data-urlencode "scope=${ZRBA_PROG_ASSERTION_SCOPE}"        \
    --data-urlencode "client_secret@${z_secret_file}"            \
    --data-urlencode "assertion@${ZRBA_FED_PROG_ASSERTION_FILE}" \
    > "${ZRBA_FED_PROG_TOKEN_RESPONSE_FILE}" 2>"${ZRBA_FED_CURL_STDERR_FILE}" || z_curl_status=$?
  test "${z_curl_status}" -eq 0 \
    || { buc_log_args "RFC 7523 grant POST failed (curl ${z_curl_status}); see ${ZRBA_FED_CURL_STDERR_FILE}"; return 1; }

  # id_token (secret): jq emits it straight to stdout, never through a shell var or
  # temp file. select(length > 0) yields a non-zero jq exit for an absent/empty token
  # — the mint miss; the forensic log then surfaces the grant's own error string.
  local z_jq_status=0
  jq -er '.id_token // empty | select(length > 0)' \
     "${ZRBA_FED_PROG_TOKEN_RESPONSE_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || z_jq_status=$?
  test "${z_jq_status}" -eq 0 || {
    jq -r '.error // empty' "${ZRBA_FED_PROG_TOKEN_RESPONSE_FILE}" \
       > "${ZRBA_FED_PROG_ERROR_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || : > "${ZRBA_FED_PROG_ERROR_FILE}"
    local -r z_err=$(<"${ZRBA_FED_PROG_ERROR_FILE}")
    buc_log_args "RFC 7523 grant returned no id_token (error: ${z_err:-none}); see ${ZRBA_FED_PROG_TOKEN_RESPONSE_FILE}"
    return 1
  }
}

# Leg 2 — STS token exchange (RFC 8693). Exchanges the IdP id_token for a Google
# workforce federated access token. Unauthenticated POST; audience = the provider
# resource name; nothing else — no userProject, no auth header (spike F3). Echoes
# "<federated_token> <expires_in>".
zrba_leg2_federated_capture() {
  zrba_sentinel
  zrbrw_sentinel
  zrbrf_sentinel
  zrbcc_sentinel

  local -r z_idtoken="${1:-}"
  test -n "${z_idtoken}" || return 1

  local -r z_audience="//iam.googleapis.com/locations/global/workforcePools/${RBRW_WORKFORCE_POOL_ID}/providers/${RBRF_PROVIDER_ID}"

  local z_curl_status=0
  curl -sS -X POST "${ZRBA_STS_ENDPOINT}"                                    \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}"                     \
    --max-time        "${RBCC_CURL_MAX_TIME_SEC}"                            \
    -H "Content-Type: application/x-www-form-urlencoded"                     \
    --data-urlencode "grant_type=${ZRBA_STS_GRANT_TYPE}"                     \
    --data-urlencode "audience=${z_audience}"                                \
    --data-urlencode "scope=${ZRBA_STS_SCOPE}"                               \
    --data-urlencode "requested_token_type=${ZRBA_STS_REQUESTED_TOKEN_TYPE}" \
    --data-urlencode "subject_token_type=${ZRBA_STS_SUBJECT_TOKEN_TYPE}"     \
    --data-urlencode "subject_token=${z_idtoken}"                            \
    > "${ZRBA_FED_STS_RESPONSE_FILE}" 2>"${ZRBA_FED_CURL_STDERR_FILE}" || z_curl_status=$?
  test "${z_curl_status}" -eq 0 \
    || { buc_log_args "STS exchange failed (curl ${z_curl_status}); see ${ZRBA_FED_CURL_STDERR_FILE}"; return 1; }

  jq -r '.expires_in // 0' "${ZRBA_FED_STS_RESPONSE_FILE}" \
     > "${ZRBA_FED_EXPIRES_IN_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || return 1
  local z_expires=$(<"${ZRBA_FED_EXPIRES_IN_FILE}")
  [[ "${z_expires}" =~ ^[0-9]+$ ]] || z_expires=0

  # Federated access token (secret): jq emits "<token> <expires_in>" straight to
  # stdout, the validated expiry passed in as a jq arg, so the token never passes
  # through a shell var or temp file. select(length > 0) yields a non-zero jq exit
  # for an absent/empty token, and the forensic log rides that exit status.
  local z_status=0
  jq -er --argjson e "${z_expires}" \
     '(.access_token // "") | select(length > 0) | "\(.) \($e)"' \
     "${ZRBA_FED_STS_RESPONSE_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || z_status=$?
  test "${z_status}" -eq 0 \
    || { buc_log_args "STS exchange returned no access_token; see ${ZRBA_FED_STS_RESPONSE_FILE}"; return 1; }
}

# Open a fresh sitting: run Legs 1+2 and atomically cache the result. The
# mechanism-gated fresh path shared by rba_avow (on a cache miss) and
# rba_novate (unconditionally). Leg 1 is gated on RBRF_MECHANISM: the
# interactive arm is the device-flow avowal (a human signs in; the prompt rides
# the progress stream, so a terminal operator and a headless-but-human-reachable
# relay complete the same sign-in — no terminal gate, human presence enforced by
# the IdP sign-in, and a truly unattended miss polls to the bounded device-code
# expiry and dies loud); the programmatic arm is the RFC 7523 grant (no human,
# no sitting to open — a self-supplied JWT, RBSFA). Leg 2 (STS) and the sitting
# cache are mechanism-invariant, so only the id_token's origin differs.
zrba_sitting_open() {
  zrba_sentinel
  zrbrf_sentinel
  zrbcc_sentinel

  # Leg 1 — mechanism-gated. buv_vet has already proven RBRF_MECHANISM is one of the
  # two enum values, but a bare-case fallthrough dies loud rather than silently.
  local z_idtoken
  case "${RBRF_MECHANISM}" in
    rbnfe_interactive)
      buc_step "Opening a sitting via device-flow avowal"
      z_idtoken=$(zrba_leg1_idtoken_capture) \
        || buc_die "Avowal failed at Leg 1 (device flow); see the transcript"
      ;;
    rbnfe_programmatic)
      buc_step "Acquiring a sitting via the RFC 7523 programmatic grant"
      z_idtoken=$(zrba_leg1_programmatic_idtoken_capture) \
        || buc_die "Acquisition failed at Leg 1 (RFC 7523 grant); see the transcript"
      ;;
    *)
      buc_die "rba_avow: unknown RBRF_MECHANISM '${RBRF_MECHANISM}' (expected rbnfe_interactive | rbnfe_programmatic)"
      ;;
  esac

  local z_fed
  z_fed=$(zrba_leg2_federated_capture "${z_idtoken}") || buc_die "Avowal failed at Leg 2 (STS exchange); see the transcript"

  local -r z_federated="${z_fed%% *}"
  local -r z_expires_in="${z_fed##* }"
  [[ "${z_expires_in}" =~ ^[0-9]+$ ]] || buc_die "Leg 2 returned a non-numeric expiry: ${z_expires_in}"

  date +%s > "${ZRBA_FED_AVOW_NOW_FILE}" || buc_die "Failed to read the clock"
  local -r z_now=$(<"${ZRBA_FED_AVOW_NOW_FILE}")
  test -n "${z_now}" || buc_die "Empty clock reading"
  local -r z_expiry_epoch=$(( z_now + z_expires_in ))

  local z_subject
  z_subject=$(zrba_idtoken_subject_capture "${z_idtoken}") || z_subject=""

  zrba_sitting_write "${z_federated}" "${z_expiry_epoch}" "${z_subject}" \
    || buc_die "Avowal succeeded but caching the sitting failed"

  buc_step "Sitting opened (federated token expires in ${z_expires_in}s)"
}

# rba_avow — the avowal accessor step. Ensures a live sitting with sufficient
# runway; its side effect is the per-session cache, and consumers read the
# federated token with zrba_sitting_read_capture. Cache-hit → gate the
# remaining runway, then reuse. Miss/expired → open a fresh sitting
# (zrba_sitting_open). The suite-head seam stands: an automated run avows once
# at suite head; cases thereafter take the cache-hit path.
#
# Runway gate (RBS0 rbtf_sitting): on the reuse path ONLY — automatic for
# every federated command since every accessor site funnels through here,
# never a per-command preflight step — the cached sitting's remaining runway
# must clear the required floor. A shorter sitting is turned away with the
# named band rejection advising novate; a freshly-opened sitting has full
# runway by construction, so the fresh path is ungated. The required runway
# arrives as the optional first argument, defaulting to the blanket floor —
# the parameterized seam; no per-operation bound is populated until one earns
# its existence.
rba_avow() {
  zrba_sentinel
  zrbrf_sentinel
  zrbcc_sentinel

  local -r z_required_runway="${1:-${ZRBA_SITTING_RUNWAY_FLOOR_SEC}}"
  [[ "${z_required_runway}" =~ ^[0-9]+$ ]] \
    || buc_die "rba_avow: required runway must be a non-negative integer of seconds, got '${z_required_runway}'"

  # Credless guard — the reveille tier must never touch the IdP or the network.
  # Mirrors the Payor OAuth token-mint guard (rbgp_payor.sh) so the federated
  # path honors the same invariant, under either mechanism arm.
  test "${BURE_TWEAK_NAME:-}" != "${RBCC_tweak_credless_guard}" \
    || buc_reject "${BUBC_band_credless}" "Credless guard: sitting acquisition refused — this run carries the reveille-tier guard (reveille cases must never reach the IdP)"

  if zrba_sitting_live_predicate; then
    local z_runway
    z_runway=$(zrba_sitting_runway_capture) \
      || buc_die "Live sitting became unreadable while gauging its runway"
    test "${z_runway}" -ge "${z_required_runway}" \
      || buc_reject "${BUBC_band_runway}" "Sitting runway too short: ${z_runway}s remain, ${z_required_runway}s required — novate to open a fresh full-window sitting (rbw-aN), then re-run"
    buc_step "Sitting already live — reusing the cached federated token (runway ${z_runway}s)"
    return 0
  fi

  buc_step "No live sitting — opening a fresh one"
  zrba_sitting_open
}

# rba_novate — the force-fresh renewal act (RBS0 rbtf_novate): a deliberate
# avowal that bypasses the sitting-reuse branch and atomically overwrites any
# standing sitting with a freshly-opened, full-window one (novation:
# extinguish-by-replacement, riding zrba_sitting_write's temp-then-rename).
# The remedy the runway floor names when it turns a short sitting away.
# Renewal-only by decision: no release or clear verb exists anywhere — the
# fresh sitting extinguishing the old is the entire mechanism.
rba_novate() {
  zrba_sentinel
  zrbrf_sentinel
  zrbcc_sentinel

  # Credless guard — novation is a sitting acquisition, so the reveille-tier
  # invariant holds here exactly as at the rba_avow entry.
  test "${BURE_TWEAK_NAME:-}" != "${RBCC_tweak_credless_guard}" \
    || buc_reject "${BUBC_band_credless}" "Credless guard: sitting acquisition refused — this run carries the reveille-tier guard (reveille cases must never reach the IdP)"

  buc_step "Novating the sitting — opening a fresh one, extinguishing any preexisting sitting"
  zrba_sitting_open
}

######################################################################
# Federation branch — the don (Leg 3)
#
# rba_don_capture — the impersonation act, as a capture. The federation-path
# sibling of rba_token_capture: resolves a usable bearer token for an identity,
# here by minting a mantle service-account access token from the cached federated
# token via iamcredentials generateAccessToken. Emits the mantle token on stdout
# once on success; failure returns 1, except the Leg-3 403 admission deficit,
# which returns the distinguished BUBC_band_admission code — never buc_die,
# never stderr (BCG capture contract); the consuming verb supplies the loud
# buc_die (or a band-aware buc_reject) over the returned code, and the
# forensic lines below carry the operator instruction it dies with
# (matching rba_avow's "failed at Leg N; see the transcript" division of
# labor). The unknown-identity guard buc_dies — a caller bug, not a runtime
# condition — exactly as rba_token_capture does.
#
# Custody: the mantle token reaches only this function's stdout (jq straight to
# stdout, never a shell var) and the per-invocation curl response (BURD_TEMP_DIR,
# process lifetime, like the Leg-2 STS response) — never the persistent sitting
# cache. It carries exactly one mantle's authority and self-expires (1 h default
# ceiling, spike V1); donning again re-mints. A long run re-dons mid-flight while
# the sitting lives; the re-mint ceiling is the sitting itself — the
# cached-federated-token read below returns 1 once the sitting lapses, carrying the
# avow instruction.
#
# The reveille-tier credless guard lives at the avowal entry (rba_avow): no
# verb dons without a live sitting, and the sitting read below returns 1 when none
# is cached, so a credless run never reaches the mint.
rba_don_capture() {
  zrba_sentinel
  zrbrf_sentinel
  zrbcc_sentinel
  zrbgc_sentinel
  zrbdc_sentinel

  local -r z_identity="${1:-}"

  # Resolve the pallium-sprued mantle token to its mantle SA-name fragment. The
  # sprued token (rbpa_governor) is THE identity form every caller passes; the
  # underscore it carries never reaches the SA-id — it is consumed here and only
  # the bare rbma-<role> fragment composes the SA email below.
  local z_mantle_account
  case "${z_identity}" in
    "${RBCC_mantle_governor}")  z_mantle_account="${RBCC_account_mantle_governor}"  ;;
    "${RBCC_mantle_director}")  z_mantle_account="${RBCC_account_mantle_director}"  ;;
    "${RBCC_mantle_retriever}") z_mantle_account="${RBCC_account_mantle_retriever}" ;;
    *) buc_die "rba_don_capture: unknown mantle token '${z_identity}' (expected ${RBCC_mantle_governor} | ${RBCC_mantle_director} | ${RBCC_mantle_retriever})" ;;
  esac

  # The mantle SA lives in the depot project; the depot is also the quota project
  # named in the x-goog-user-project header below (spike F2). Raw email in the
  # path, matching the spike — the ':generateAccessToken' custom-method suffix
  # must stay literal, so the email is not urlencoded here.
  local -r z_mantle_email="${z_mantle_account}@${RBDC_DEPOT_PROJECT_ID}.${RBGC_SA_EMAIL_DOMAIN}"
  local -r z_don_url="${RBGC_API_ROOT_IAMCREDENTIALS}${RBGC_IAMCREDENTIALS_V1}/projects/-/serviceAccounts/${z_mantle_email}${RBGC_IAMCREDENTIALS_GENERATE_ACCESS_TOKEN_SUFFIX}"
  buc_log_args "Donning the ${z_identity} mantle: ${z_mantle_email}"

  # The bearer is the cached federated token. A miss (absent or within skew of
  # expiry) is the re-mint ceiling — the sitting has lapsed; the forensic line
  # carries the avow instruction and the caller fails loud on the return 1.
  local z_federated
  z_federated=$(zrba_sitting_read_capture) || {
    buc_log_args "Sitting lapsed — no live federated token is cached; avow to open a fresh sitting, then re-run (the mantle re-mint is capped by the sitting, not by the mantle token's own lifetime)"
    return 1
  }

  # Non-secret request body: cloud-platform scope, default lifetime (1 h ceiling).
  jq -n --arg scope "${RBGC_SCOPE_CLOUD_PLATFORM}" '{scope: [$scope]}' \
     > "${ZRBA_FED_DON_BODY_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || {
    buc_log_args "Failed to compose the don request body; see ${ZRBA_FED_JQ_STDERR_FILE}"
    return 1
  }

  # Single generateAccessToken call. -o writes the response (mantle token) to the
  # curl-response scratch; -w prints the HTTP code to stdout, captured to a file.
  local z_curl_status=0
  curl -sS -X POST "${z_don_url}"                        \
    --connect-timeout "${RBCC_CURL_CONNECT_TIMEOUT_SEC}" \
    --max-time        "${RBCC_CURL_MAX_TIME_SEC}"        \
    -H "Authorization: Bearer ${z_federated}"            \
    -H "x-goog-user-project: ${RBDC_DEPOT_PROJECT_ID}"   \
    -H "Content-Type: application/json"                  \
    --data "@${ZRBA_FED_DON_BODY_FILE}"                  \
    -o "${ZRBA_FED_DON_RESPONSE_FILE}"                   \
    -w '%{http_code}'                                    \
    > "${ZRBA_FED_DON_CODE_FILE}" 2>"${ZRBA_FED_CURL_STDERR_FILE}" || z_curl_status=$?
  test "${z_curl_status}" -eq 0 || {
    buc_log_args "Leg 3 (don) curl failed (exit ${z_curl_status}); see ${ZRBA_FED_CURL_STDERR_FILE}"
    return 1
  }

  local -r z_code=$(<"${ZRBA_FED_DON_CODE_FILE}")
  case "${z_code}" in
    200) ;;
    403)
      jq -r '.error.message // empty' "${ZRBA_FED_DON_RESPONSE_FILE}" \
         > "${ZRBA_FED_DON_ERROR_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" \
         || : > "${ZRBA_FED_DON_ERROR_FILE}"
      local -r z_errmsg=$(<"${ZRBA_FED_DON_ERROR_FILE}")
      # Deliberately not retried here (RBr_7a9, RBr_b93).
      buc_log_args "Leg 3 (don) denied (HTTP 403) for mantle ${z_mantle_email}: ${z_errmsg} — either an admission deficit (brevet the avowed citizen onto the mantle: tokenCreator on the mantle SA + serviceUsageConsumer on the depot project) or, immediately after gird/brevet, a just-written grant still propagating (wait a minute and retry); not retried here"
      return "${BUBC_band_admission}" ;;
    *)
      buc_log_args "Leg 3 (don) failed (HTTP ${z_code}) for mantle ${z_mantle_email}; see ${ZRBA_FED_DON_RESPONSE_FILE}"
      return 1 ;;
  esac

  # Mantle access token (secret): jq emits it straight to stdout, never through a
  # shell var or the persistent cache. select(length > 0) yields a non-zero jq
  # exit for an absent/empty token, and the forensic line rides that exit status.
  local z_jq_status=0
  jq -er '.accessToken // empty | select(length > 0)' \
     "${ZRBA_FED_DON_RESPONSE_FILE}" 2>"${ZRBA_FED_JQ_STDERR_FILE}" || z_jq_status=$?
  test "${z_jq_status}" -eq 0 || {
    buc_log_args "Leg 3 (don) returned no accessToken; see ${ZRBA_FED_DON_RESPONSE_FILE}"
    return 1
  }
}

# RBTOE: RBRO Load Pattern
# Thin wrapper: defensively sources rbro_regime.sh (callers don't need to know
# its path, which moved under AAD's payor/ subdirectory migration), then
# delegates to rbro_load. The uniform rba_* load-through-utility convention is
# the load-bearing reason this wrapper exists.
rba_rbro_load() {
  zrba_sentinel

  buc_log_args "Loading RBRO OAuth credentials"

  # Source regime module if not already loaded
  if test -z "${ZRBRO_SOURCED:-}"; then
    source "${BASH_SOURCE[0]%/*}/rbro_regime.sh"
  fi

  # Delegate to regime's canonical load
  rbro_load

  buc_log_args "RBRO validation successful"
}

# eof
