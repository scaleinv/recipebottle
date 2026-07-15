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
# Recipe Bottle Keycloak orchestrator — the synthetic programmatic-federation
# test facility's lifecycle, ONE coherent BCG module in the rbx family. Two
# toothings on the keycloak-facility bondstone:
#
#   setup    (rbw-qjK) — stand the facility up: gate a clean tree, charge the
#                        fdkyclk crucible, poll Keycloak ready, fetch its
#                        ephemeral public JWKS into the git-IGNORED live rbrf.env,
#                        then affiance rbef_keycloak. Uppercase K: setup mutates
#                        cloud BY CALLING affiance.
#   teardown (rbw-qjQ) — tear it down: jilt rbef_keycloak, then quench the
#                        crucible. Idempotent (jilt/quench tolerate absent state).
#
# The module COMPOSES existing verbs — charge/quench (rbob) and affiance/jilt
# (rbgp) — reaching each solely through its tabtarget (the CLI-as-gateway path,
# which plumbs the folio channel the verbs read). It never reimplements affiance
# or jilt, never speaks GCP REST, and never holds the payor credential: its only
# HTTP is the local-crucible JWKS fetch, the one bridge. Cloud mutation flows
# exclusively through the called manor verbs (RBSMA/RBSMJ).
#
# The module is BLIND to the realm JSON — it names its vessel and foedus by
# reference and never reads realm contents (affiliation by reference, never
# ownership), so affiance never learns "Keycloak". It renders TWO fields into the
# ignored live rbrf.env per charge, both from facility knowledge (nameplate port,
# facility constants), never from realm contents: the ephemeral realm signing key's
# public half (the twiddle, uploaded to the provider by affiance's programmatic
# re-sync arm, RBSMA) and the reachable RFC 7523 grant endpoint (the loopback POST
# target the accessor reads, RBSRF rbrf_grant_endpoint — accessor-facing, never
# uploaded to GCP). Contract sources: RBSMA/RBSMJ, RBSFK, RBSRF, RBSPB.

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBXK_SOURCED:-}" || buc_die "Module rbxk multiply sourced - check sourcing hierarchy"
ZRBXK_SOURCED=1

# Tinder constants (pure string literals / tinder-on-tinder — available at source
# time). The facility's fixed identity: the crucible moniker, the foedus folio it
# affiances, and the baked realm name (matches fdkyclk-realm.json). The poll
# budget covers Keycloak boot plus --import-realm on a cold charge.
RBXK_moniker="fdkyclk"
RBXK_foedus="rbef_keycloak"
RBXK_realm="fdkyclk"
RBXK_poll_max_attempts="30"
RBXK_poll_interval_sec="5"

######################################################################
# Internal Functions (zrbxk_*)

zrbxk_kindle() {
  test -z "${ZRBXK_KINDLED:-}" || buc_die "Module rbxk already kindled"

  # Dispatch-provided directories this module leans on.
  buv_dir_exists "${BURD_TEMP_DIR}"
  test -n "${BURD_TABTARGET_DIR:-}" || buc_die "BURD_TABTARGET_DIR is unset — the orchestrator composes verbs through their tabtargets"

  # The live regime is the keycloak foedus's rbrf.env in the moorings foedera
  # library, resolved through the rbcc resolver by NAME: this module never sources
  # rbrr.env, so the active-foedus selector is not live here and the foedus is
  # named explicitly. The committed template is that same path plus a .template
  # suffix — the suffix is the only fact this module owns, so the template can
  # never drift from the regime filename. It carries the vendor-agnostic core;
  # setup renders the git-IGNORED live file the folio-addressed verbs source
  # (RBSRF's one sanctioned ships-committed deviation).
  local z_live=""
  z_live=$(rbcc_rbrf_file_capture "${RBXK_foedus}") \
    || buc_die "Failed to resolve the ${RBXK_foedus} federation regime path"
  readonly ZRBXK_LIVE="${z_live}"
  readonly ZRBXK_TEMPLATE="${ZRBXK_LIVE}.template"

  # The crucible nameplate regime — parsed (never sourced) for the host-side
  # Keycloak port, so a port change in the nameplate propagates here (ACG:
  # reference the home).
  readonly ZRBXK_NAMEPLATE_RBRN="${RBCC_moorings_dir}/${RBXK_moniker}/${RBCC_rbrn_file}"

  # JWKS bridge temp files (non-secret — public keys only).
  readonly ZRBXK_JWKS_RAW="${BURD_TEMP_DIR}/rbxk_jwks_raw.json"
  readonly ZRBXK_JWKS_STRIPPED="${BURD_TEMP_DIR}/rbxk_jwks_stripped.json"
  readonly ZRBXK_HTTP_CODE="${BURD_TEMP_DIR}/rbxk_http_code.txt"

  test -f "${ZRBXK_TEMPLATE}" || buc_die "Keycloak foedus template missing: ${ZRBXK_TEMPLATE}"
  test -f "${ZRBXK_NAMEPLATE_RBRN}" || buc_die "Keycloak nameplate regime missing: ${ZRBXK_NAMEPLATE_RBRN}"

  readonly ZRBXK_KINDLED=1
}

zrbxk_sentinel() {
  test "${ZRBXK_KINDLED:-}" = "1" || buc_die "Module rbxk not kindled - call zrbxk_kindle first"
}

# Echo the host-side Keycloak base URL (http://localhost:<workstation-port>),
# parsing RBRN_ENTRY_PORT_WORKSTATION from the nameplate regime (never sourcing —
# the RBRN_ kindle graph is not this module's, and one field is all we need).
# Echoes the base URL or returns 1; the caller guards with || buc_die.
zrbxk_kc_base_capture() {
  local z_line=""
  local z_port=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    if [[ "${z_line}" == RBRN_ENTRY_PORT_WORKSTATION=* ]]; then
      z_port="${z_line#*=}"
      break
    fi
  done < "${ZRBXK_NAMEPLATE_RBRN}"
  test -n "${z_port}" || return 1
  printf 'http://localhost:%s' "${z_port}"
}

# Resolve a single executable tabtarget by COLOPHON glob under BURD_TABTARGET_DIR
# — robust against frontispiece renames (the colophon is the stable identifier),
# mirroring buym's own tabtarget glob. An imprint tabtarget carries the moniker as
# its filename tail (rbw-cC.Charge.fdkyclk.sh); a param1 tabtarget does not
# (rbw-mA.PayorAffiancesManor.sh). Echoes the path or returns 1 on zero/multiple/
# non-executable matches (an unmatched glob stays literal and fails the -x test).
zrbxk_resolve_tt_capture() {
  local -r z_colophon="${1:-}"
  local -r z_moniker="${2:-}"
  local -a z_hits=()
  if test -n "${z_moniker}"; then
    z_hits=("${BURD_TABTARGET_DIR}/${z_colophon}."*".${z_moniker}.sh")
  else
    z_hits=("${BURD_TABTARGET_DIR}/${z_colophon}."*".sh")
  fi
  test "${#z_hits[@]}" -eq 1 || return 1
  test -x "${z_hits[0]:-}" || return 1
  printf '%s' "${z_hits[0]}"
}

# Invoke a composed tabtarget as a subprocess and gate on its exit. Args:
#   $1 colophon (e.g. rbw-cC)   $2 moniker ("" for a param1 tabtarget)
#   $3.. forwarded to the tabtarget (e.g. the foedus folio for affiance/jilt).
# Never piped (TabTarget Invocation Discipline) — the tabtarget self-logs; we
# only read its exit code.
zrbxk_run_tabtarget() {
  zrbxk_sentinel
  local -r z_colophon="${1:-}"
  local -r z_moniker="${2:-}"
  test -n "${z_colophon}" || buc_die "zrbxk_run_tabtarget: colophon required"
  shift 2 || buc_die "zrbxk_run_tabtarget: colophon and moniker (possibly empty) required"

  local z_tt=""
  z_tt=$(zrbxk_resolve_tt_capture "${z_colophon}" "${z_moniker}") \
    || buc_die "No unique executable tabtarget for colophon ${z_colophon} (moniker '${z_moniker}') under ${BURD_TABTARGET_DIR}"

  buc_log_args "Invoking composed tabtarget: ${z_tt##*/} $*"
  local z_rc=0
  "${z_tt}" "$@" || z_rc=$?
  test "${z_rc}" -eq 0 || buc_die "Composed tabtarget ${z_tt##*/} failed (exit ${z_rc})"
}

# Poll the realm's certs endpoint until it answers 200 (Keycloak booted and the
# realm imported), bounded by the tinder poll budget. A cold charge boots the
# server AND runs --import-realm, so a transient connection-refused / 404 early
# is expected; we die loud only after the budget.
zrbxk_poll_ready() {
  zrbxk_sentinel

  buc_step "Poll Keycloak realm ${RBXK_realm} ready"
  local z_base=""
  z_base=$(zrbxk_kc_base_capture) \
    || buc_die "Failed to resolve Keycloak base URL from nameplate ${ZRBXK_NAMEPLATE_RBRN}"
  local -r z_url="${z_base}/realms/${RBXK_realm}/protocol/openid-connect/certs"

  local z_attempt=1
  local z_code="000"
  while test "${z_attempt}" -le "${RBXK_poll_max_attempts}"; do
    local z_curl_status=0
    curl -s -o /dev/null -w '%{http_code}' "${z_url}" > "${ZRBXK_HTTP_CODE}" || z_curl_status=$?
    z_code="000"
    if test "${z_curl_status}" -eq 0; then
      z_code=$(<"${ZRBXK_HTTP_CODE}")
    fi
    if test "${z_code}" = "200"; then
      buc_info "Keycloak realm ${RBXK_realm} ready (HTTP 200) after ${z_attempt} attempt(s)"
      return 0
    fi
    buc_log_args "Attempt ${z_attempt}/${RBXK_poll_max_attempts}: HTTP ${z_code} — sleeping ${RBXK_poll_interval_sec}s"
    sleep "${RBXK_poll_interval_sec}"
    z_attempt=$((z_attempt + 1))
  done

  buc_die "Keycloak realm ${RBXK_realm} not ready after ${RBXK_poll_max_attempts} attempts (last HTTP ${z_code}) at ${z_url}"
}

# The one bridge: fetch the realm's signing JWKS and strip it to the strict RSA
# public-key members GCP's uploaded-JWKS parser accepts (kty/kid/use/alg/n/e);
# an exporter's x5c/x5t cert fields are rejected (misleadingly as "Only RSA, EC
# key types are supported"), so they are stripped before upload. Compact (-c) so
# the rendered regime value is one line. (RBSMA jwksJson NOTE; proof fetch_jwks.)
zrbxk_fetch_jwks() {
  zrbxk_sentinel

  buc_step "Fetch and strip the Keycloak JWKS (the bridge)"
  local z_base=""
  z_base=$(zrbxk_kc_base_capture) \
    || buc_die "Failed to resolve Keycloak base URL from nameplate ${ZRBXK_NAMEPLATE_RBRN}"
  local -r z_certs_url="${z_base}/realms/${RBXK_realm}/protocol/openid-connect/certs"

  # Body to a temp file, code captured separately (BCG: single external command,
  # failures visible in the temp file afterward).
  local z_curl_status=0
  curl -s -o "${ZRBXK_JWKS_RAW}" -w '%{http_code}' "${z_certs_url}" > "${ZRBXK_HTTP_CODE}" || z_curl_status=$?
  test "${z_curl_status}" -eq 0 || buc_die "Keycloak certs fetch failed (curl exit ${z_curl_status}) at ${z_certs_url}"
  local z_code="000"
  z_code=$(<"${ZRBXK_HTTP_CODE}")
  test "${z_code}" = "200" || buc_die "Keycloak certs fetch returned HTTP ${z_code} at ${z_certs_url}"

  jq -c '{keys: [.keys[] | select(.use=="sig") | {kty, use, kid, alg, n, e}]}' \
    "${ZRBXK_JWKS_RAW}" > "${ZRBXK_JWKS_STRIPPED}" \
    || buc_die "Failed to strip Keycloak JWKS to RSA members"

  # A non-empty keys array is the floor — an empty strip means no signing key yet.
  jq -e '(.keys | length) > 0' "${ZRBXK_JWKS_STRIPPED}" >/dev/null \
    || buc_die "Stripped JWKS carries no signing keys — realm ${RBXK_realm} exposes no sig key"

  buc_info "JWKS fetched and stripped to RSA members: ${ZRBXK_JWKS_STRIPPED}"
}

# Render the git-IGNORED live rbrf.env from the committed template plus the two
# rendered fields — the fresh public JWKS and the reachable grant endpoint. Because
# the live file is untracked, this leaves the working tree clean — so affiance's own
# clean-tree gate passes untouched (no hoist, no skip).
zrbxk_render_live() {
  zrbxk_sentinel

  buc_step "Render the ignored live regime ${ZRBXK_LIVE}"
  test -f "${ZRBXK_TEMPLATE}" || buc_die "Keycloak foedus template missing: ${ZRBXK_TEMPLATE}"
  test -f "${ZRBXK_JWKS_STRIPPED}" || buc_die "Stripped JWKS absent — fetch must precede render: ${ZRBXK_JWKS_STRIPPED}"

  local z_jwks=""
  z_jwks="$(<"${ZRBXK_JWKS_STRIPPED}")"    # bash builtin file read; compact one-line JWKS

  # The reachable RFC 7523 grant POST target — the realm's token endpoint on the
  # local crucible, composed from the nameplate port (facility knowledge), never
  # from realm contents. This is the loopback POST target RBSFK pins as local,
  # distinct from the fictional https frontend issuer RBRF_IDP_ISSUER carries.
  local z_base=""
  z_base=$(zrbxk_kc_base_capture) \
    || buc_die "Failed to resolve Keycloak base URL from nameplate ${ZRBXK_NAMEPLATE_RBRN}"
  local -r z_grant_endpoint="${z_base}/realms/${RBXK_realm}/protocol/openid-connect/token"

  # Live regime = the committed template body (its trailing '# eof' dropped by the
  # read loop — a bash builtin, per BCG command discipline) plus the two rendered
  # assignments, then a fresh '# eof'. Neither the JWKS (JSON) nor the endpoint URL
  # carries single quotes, so the single-quoted assignments are safe.
  local z_tline=""
  {
    while IFS= read -r z_tline || test -n "${z_tline}"; do
      if test "${z_tline}" = "# eof"; then continue; fi
      printf '%s\n' "${z_tline}"
    done < "${ZRBXK_TEMPLATE}"
    printf '\n'
    printf '# Ephemeral public JWKS (the twiddle) — orchestrator-rendered per charge; committed nowhere (RBSFK).\n'
    printf "RBRF_IDP_JWKS_JSON='%s'\n" "${z_jwks}"
    printf '\n'
    printf '# Reachable RFC 7523 grant endpoint (the loopback POST target) — orchestrator-rendered\n'
    printf '# per charge from the nameplate port; never from realm contents (RBSRF rbrf_grant_endpoint).\n'
    printf "RBRF_GRANT_ENDPOINT='%s'\n" "${z_grant_endpoint}"
    printf '\n# eof\n'
  } > "${ZRBXK_LIVE}" || buc_die "Failed to render live regime: ${ZRBXK_LIVE}"

  buc_info "Rendered ${ZRBXK_LIVE} (git-ignored) with a fresh JWKS and grant endpoint ${z_grant_endpoint}"
}

######################################################################
# External Functions (rbxk_*)

rbxk_setup() {
  zrbxk_sentinel

  buc_doc_brief "Stand up the Keycloak programmatic test facility — charge the Crucible, render its ephemeral JWKS into the ignored live regime, and affiance rbef_keycloak (RBSMA)"
  buc_doc_shown || return 0

  # Clean-tree gate FIRST — the precision-band creed variant (BCG Precision
  # Exit-Code Band). The orchestrator gates up-front precisely to honor affiance's
  # OWN clean-tree requirement BEFORE charging a crucible: affiance (which this
  # facility calls) refuses a dirty tree because the seated provider must answer to
  # a committed name, so reuse its very creed (ACG: reference the home) rather than
  # mint a near-duplicate. Gating here fails fast, before charge, instead of after.
  bug_require_clean_tree_creed "${RBCC_creed_clean_affiance}"

  buc_step "Charge the ${RBXK_moniker} Crucible"
  zrbxk_run_tabtarget "rbw-cC" "${RBXK_moniker}"

  zrbxk_poll_ready
  zrbxk_fetch_jwks
  zrbxk_render_live

  # Affiance the named foedus through its tabtarget (folio channel). The live
  # rbrf.env is untracked, so affiance's clean-tree gate passes; its programmatic
  # re-sync arm patches the fresh JWKS into a standing provider (RBSMA).
  buc_step "Affiance ${RBXK_foedus}"
  zrbxk_run_tabtarget "rbw-mA" "" "${RBXK_foedus}"

  buc_success "Keycloak facility up — Crucible ${RBXK_moniker} charged, ${RBXK_foedus} affianced with a fresh JWKS"
}

rbxk_teardown() {
  zrbxk_sentinel

  buc_doc_brief "Tear down the Keycloak programmatic test facility — jilt rbef_keycloak, then quench the Crucible (idempotent)"
  buc_doc_shown || return 0

  # Jilt the foedus, then quench. jilt is operator-confirmed (dangerous — it
  # dissolves a trust), but a test-facility teardown is a deliberate, often
  # fixture-driven (unattended) act, so pass the confirm-skip seam (RBSMJ). Both
  # verbs are idempotent: jilt tolerates an already-absent provider, quench an
  # already-quenched crucible, so teardown converges however far setup got.
  buc_step "Jilt ${RBXK_foedus}"
  local z_jilt_tt=""
  z_jilt_tt=$(zrbxk_resolve_tt_capture "rbw-mJ" "") \
    || buc_die "No unique executable tabtarget for colophon rbw-mJ under ${BURD_TABTARGET_DIR}"
  local z_rc=0
  BURE_CONFIRM=skip "${z_jilt_tt}" "${RBXK_foedus}" || z_rc=$?
  test "${z_rc}" -eq 0 || buc_die "Jilt tabtarget ${z_jilt_tt##*/} failed (exit ${z_rc})"

  buc_step "Quench the ${RBXK_moniker} Crucible"
  zrbxk_run_tabtarget "rbw-cQ" "${RBXK_moniker}"

  buc_success "Keycloak facility down — ${RBXK_foedus} jilted, Crucible ${RBXK_moniker} quenched"
}

# eof
