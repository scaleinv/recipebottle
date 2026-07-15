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
# Recipe Bottle Federation Regime - Validator Module

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBRF_SOURCED:-}" || buc_die "Module rbrf multiply sourced - check sourcing hierarchy"
ZRBRF_SOURCED=1

######################################################################
# Internal Functions (zrbrf_*)

zrbrf_kindle() {
  test -z "${ZRBRF_KINDLED:-}" || buc_die "Module rbrf already kindled"

  # No defaults set — buv uses ${!varname:-} for safe indirect expansion under set -u.
  # Unset variables are detected distinctly from empty by zbuv_check_capture.

  # Enroll all RBRF variables — single source of truth for validation and rendering

  buv_regime_enroll RBRF

  # The manor pool's org / pool id / session duration are manor-level and live in
  # the sibling RBRW regime (RBSRW) — the one-pool Model relocated them out of the
  # per-foedus federation regime. RBRF now carries only the per-foedus provider-side
  # trust: this foedus IS a provider under the manor's one pool.
  buv_group_enroll "Provider Identity"
  buv_string_enroll  RBRF_PROVIDER_ID          4   32  "Workforce pool provider ID — the external IdP trust root within the manor's one pool, and the per-foedus discriminator distinguishing one foedus from another"

  # RBRF_MECHANISM is the one discriminator that changes the required-field shape;
  # modeled on RBRV_VESSEL_MODE. The interactive group (device flow) and programmatic
  # group (uploaded JWKS) below are gated on it.
  buv_group_enroll "Acquisition Mechanism"
  buv_enum_enroll    RBRF_MECHANISM                   "Token-acquisition mechanism: rbnfe_interactive (device flow) or rbnfe_programmatic (self-supplied JWT)" \
                     rbnfe_interactive rbnfe_programmatic

  # Vendor-agnostic trust core — present under both mechanisms (RBSRF).
  buv_group_enroll "IdP Trust (core)"
  buv_string_enroll  RBRF_IDP_ISSUER           8  512  "OIDC issuer URI of the external IdP (resolvable under interactive; self-declared https identifier matched against the JWT iss under programmatic)"
  buv_string_enroll  RBRF_IDP_CLIENT_ID        1  256  "Public client (application) ID registered at the IdP (device-flow client under interactive; must equal the JWT aud under programmatic)"
  buv_string_enroll  RBRF_ATTRIBUTE_MAPPING    1  512  "Workforce provider attribute mapping — must map google.subject"

  buv_group_enroll "Interactive Mechanism"
  buv_gate_enroll    RBRF_MECHANISM  rbnfe_interactive
  buv_string_enroll  RBRF_IDP_SCOPE            5  256  "Device-flow OAuth scope — must request openid, must not request offline_access"
  buv_string_enroll  RBRF_IDP_DEVICE_ENDPOINT  8  512  "IdP device authorization endpoint (RFC 8628) — Leg 1 device-code request"
  buv_string_enroll  RBRF_IDP_TOKEN_ENDPOINT   8  512  "IdP token endpoint — Leg 1 device-code polling"

  buv_group_enroll "Programmatic Mechanism"
  buv_gate_enroll    RBRF_MECHANISM  rbnfe_programmatic
  buv_string_enroll  RBRF_IDP_JWKS_JSON        1 8192  "Uploaded public JWKS GCP validates self-supplied JWTs against (REST oidc.jwksJson); ephemeral key re-synced per charge by the orchestrator, committed nowhere"
  # The caller's self-supply set (RBSRF): the reachable grant POST target, the two
  # secret-path references (never the material — sourced regime vars land in process
  # env, so secret VALUES may not ride them), and the three committed assertion facts.
  buv_string_enroll  RBRF_GRANT_ENDPOINT       8  512  "Reachable RFC 7523 grant token-endpoint URL the signed assertion is POSTed to — orchestrator-rendered per charge; https:// or a loopback http:// (cleartext tolerated on loopback only)"
  buv_string_enroll  RBRF_ASSERTER_KEY_FILE    1  512  "Repo-root-relative path to the asserter's private signing key — the RFC 7523 caller signs its assertion with it (path reference, never the material)"
  buv_string_enroll  RBRF_CLIENT_SECRET_FILE   1  512  "Repo-root-relative path to the confidential client's secret the grant authenticates with at the token endpoint (path reference, never the material)"
  buv_string_enroll  RBRF_ASSERTER_KID         1  128  "Asserter key id the assertion JWT header kid carries, matched by the IdP against its registered asserting key (committed assertion fact)"
  buv_string_enroll  RBRF_ASSERTER_ISSUER      1  512  "The asserting party's issuer — the assertion iss, matched by the IdP against its registered asserting trust (committed assertion fact; distinct from RBRF_IDP_ISSUER, which the assertion aud targets)"
  buv_string_enroll  RBRF_ASSERTER_SUBJECT     1  256  "The external subject the assertion sub carries — the identity the IdP resolves to its federated-linked user (committed assertion fact; NOT the GCP-side federated subject)"

  # Guard against unexpected RBRF_ variables not in enrollment
  buv_scope_sentinel RBRF RBRF_

  # Lock all enrolled RBRF_ variables against mutation
  buv_lock RBRF

  readonly ZRBRF_KINDLED=1
}

zrbrf_sentinel() {
  test "${ZRBRF_KINDLED:-}" = "1" || buc_die "Module rbrf not kindled - call zrbrf_kindle first"
}

# Enforce all RBRF enrollment validations and custom format checks
zrbrf_enforce() {
  zrbrf_sentinel

  buv_vet RBRF

  # The manor pool's org, pool id, and session duration validate in the sibling
  # RBRW regime (RBSRW), not here — RBRF validates only the per-foedus provider trust.
  [[ "${RBRF_PROVIDER_ID}" =~ ^[a-z][a-z0-9-]{2,30}[a-z0-9]$ ]] \
    || buc_reject "${BUBC_band_regime}" "Invalid RBRF_PROVIDER_ID: ${RBRF_PROVIDER_ID} (GCP provider id: lowercase letter-led, [a-z0-9-], no trailing hyphen, 4-32 chars)"

  [[ "${RBRF_IDP_ISSUER}" =~ ^https:// ]] \
    || buc_reject "${BUBC_band_regime}" "RBRF_IDP_ISSUER must be an https:// URI: ${RBRF_IDP_ISSUER}"

  # https required under both mechanisms (RBSRF: under programmatic GCP still
  # demands the https scheme even though it never resolves the issuer).
  case "${RBRF_ATTRIBUTE_MAPPING}" in
    *google.subject*) ;;
    *) buc_reject "${BUBC_band_regime}" "RBRF_ATTRIBUTE_MAPPING must map google.subject: ${RBRF_ATTRIBUTE_MAPPING}" ;;
  esac

  # Mechanism-gated checks — only the active group's fields are set (buv gating
  # leaves the inactive group unset), so each group's custom validation is guarded
  # behind RBRF_MECHANISM. buv_vet has already proven RBRF_MECHANISM is one of the
  # enrolled enum values.
  case "${RBRF_MECHANISM}" in
    rbnfe_interactive)
      [[ "${RBRF_IDP_DEVICE_ENDPOINT}" =~ ^https:// ]] \
        || buc_reject "${BUBC_band_regime}" "RBRF_IDP_DEVICE_ENDPOINT must be an https:// URI: ${RBRF_IDP_DEVICE_ENDPOINT}"
      [[ "${RBRF_IDP_TOKEN_ENDPOINT}" =~ ^https:// ]] \
        || buc_reject "${BUBC_band_regime}" "RBRF_IDP_TOKEN_ENDPOINT must be an https:// URI: ${RBRF_IDP_TOKEN_ENDPOINT}"
      # OIDC requires openid; the human-present premise forbids offline_access — a
      # refresh token would let a run begin outside a live sitting.
      case " ${RBRF_IDP_SCOPE} " in
        *" openid "*) ;;
        *) buc_reject "${BUBC_band_regime}" "RBRF_IDP_SCOPE must request the openid scope: ${RBRF_IDP_SCOPE}" ;;
      esac
      case " ${RBRF_IDP_SCOPE} " in
        *offline_access*) buc_reject "${BUBC_band_regime}" "RBRF_IDP_SCOPE must not request offline_access — the no-refresh-token premise (a live human avows at each run)" ;;
      esac
      ;;
    rbnfe_programmatic)
      # The uploaded snapshot must parse as a JWKS with at least one key; the
      # strict RSA-member strip (kty/kid/use/alg/n/e) is the orchestrator's job
      # before it writes this value, so affiance uploads it verbatim.
      printf '%s' "${RBRF_IDP_JWKS_JSON}" | jq -e '(.keys | type) == "array" and (.keys | length) > 0' >/dev/null 2>&1 \
        || buc_reject "${BUBC_band_regime}" "RBRF_IDP_JWKS_JSON must be a JWKS object with a non-empty keys array: ${RBRF_IDP_JWKS_JSON}"

      # The reachable grant endpoint: https, or a loopback http:// (the
      # loopback-http escape from the https gate) — cleartext tolerated ONLY for
      # localhost / 127.0.0.1, the local test crucible; a non-loopback http:// is
      # rejected. This field's charge-time render admits loopback cleartext,
      # deliberately unlike the interactive RBRF_IDP_TOKEN_ENDPOINT's https-only
      # committed fact (RBSRF rbrf_grant_endpoint).
      case "${RBRF_GRANT_ENDPOINT}" in
        https://*) ;;
        http://localhost|http://localhost:*|http://localhost/*) ;;
        http://127.0.0.1|http://127.0.0.1:*|http://127.0.0.1/*) ;;
        *) buc_reject "${BUBC_band_regime}" "RBRF_GRANT_ENDPOINT must be an https:// URI or a loopback http:// URI (localhost / 127.0.0.1 only): ${RBRF_GRANT_ENDPOINT}" ;;
      esac

      # The two secret-path references are repo-root-relative, never absolute —
      # the material lives in a file the accessor reads by path, never inline in
      # this regime (RBSRF / RBSFK two-keys custody). Presence and non-emptiness
      # are the enrollment floor; this bars an absolute path (a production foedus's
      # ../station-fenced form stays relative and is admitted).
      case "${RBRF_ASSERTER_KEY_FILE}" in
        /*) buc_reject "${BUBC_band_regime}" "RBRF_ASSERTER_KEY_FILE must be a repo-root-relative path, not absolute: ${RBRF_ASSERTER_KEY_FILE}" ;;
      esac
      case "${RBRF_CLIENT_SECRET_FILE}" in
        /*) buc_reject "${BUBC_band_regime}" "RBRF_CLIENT_SECRET_FILE must be a repo-root-relative path, not absolute: ${RBRF_CLIENT_SECRET_FILE}" ;;
      esac

      # The three assertion facts (kid, issuer, subject) need only be present and
      # non-empty — the enrollment min-length floor already enforces that, so no
      # custom check here (RBSRF: "present non-empty strings").
      ;;
  esac
}

# eof
