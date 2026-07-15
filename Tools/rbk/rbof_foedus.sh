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
# Recipe Bottle Foedus — test-bed cardinality verbs over the moorings foedera
# library. Three atomic, first-class toothings:
#
#   descry  (rbw-jd) — read a named foedus's provider presence under the one
#                      manor pool (healthy, or a named deficit). Read-only,
#                      payor-credentialed, mutates nothing. Contract: RBSFD.
#   instate (rbw-jI) — re-point the active-foedus selector RBRR_ACTIVE_FOEDUS in
#                      rbrr.env via an atomic single-field rewrite. No clean-tree
#                      gate, no commit, no Manor mutation, no sitting reset.
#                      Contract: RBSFI.
#   canvass (rbw-jc) — enumerate every foedus the manor holds (providers.list
#                      under the one workforce pool), emitting one fact file per
#                      foedus and marking the regime-selected one. Read-only,
#                      payor-credentialed. Contract: RBS0 {rbtf_canvass}.
#
# None of them founds or dissolves a foedus — that is the federation manor
# verbs' (affiance/jilt) concern. The reuse-if-valid-else-establish decision
# lives in the fixture that composes these atoms, never folded into a fat verb.

set -euo pipefail

######################################################################
# Internal (zrbof_*)

zrbof_kindle() {
  test -z "${ZRBOF_KINDLED:-}" || buc_die "Module rbof already kindled"

  readonly ZRBOF_KINDLED=1
}

zrbof_sentinel() {
  test "${ZRBOF_KINDLED:-}" = "1" || buc_die "Module rbof not kindled - call zrbof_kindle first"
}

# Echo the discovered foedus identities (rbef_ subdirectory names), space-
# separated, or "(none)". Pure — for embedding in a rejection message so a bad
# or missing identity fails by listing the available ones (RBSFD/RBSFI shape).
zrbof_list_foedera() {
  local z_avail=""
  local z_entry=""
  for z_entry in "${RBCC_foedera_dir}"/rbef_*/; do
    test -d "${z_entry}" || continue
    z_entry="${z_entry%/}"
    z_avail="${z_avail} ${z_entry##*/}"
  done
  if test -n "${z_avail}"; then
    printf '%s\n' "${z_avail# }"
  else
    printf '%s\n' "(none)"
  fi
}

# Validate that a foedus identity resolves to a library subdirectory holding an
# rbrf.env, rejecting in the GIVEN band (each verb owns its own precision band)
# and listing the discovered foedera. Runs in the caller's process — NEVER a
# command substitution — so buc_reject's band-coded exit propagates to the
# dispatch boundary.
zrbof_require_foedus() {
  local -r z_foedus="${1:-}"
  local -r z_band="${2:-}"
  local -r z_avail="$(zrbof_list_foedera)"

  test -n "${z_foedus}" \
    || buc_reject "${z_band}" "Foedus identity required (param1). Available foedera: ${z_avail}"
  [[ "${z_foedus}" == rbef_* ]] \
    || buc_reject "${z_band}" "Foedus identity must bear the rbef_ sprue: ${z_foedus}. Available foedera: ${z_avail}"
  test -d "${RBCC_foedera_dir}/${z_foedus}" \
    || buc_reject "${z_band}" "No foedus subdirectory '${z_foedus}' in the foedera library. Available foedera: ${z_avail}"

  # A subdirectory can stand without its regime file: rbef_keycloak commits only an
  # rbrf.env.template until the test facility renders its git-ignored live regime
  # (RBSRF's one sanctioned deviation), so the two tests name distinct states.
  local z_rbrf=""
  z_rbrf=$(rbcc_rbrf_file_capture "${z_foedus}") \
    || buc_reject "${z_band}" "Failed to resolve the regime path for foedus '${z_foedus}'"
  test -f "${z_rbrf}" \
    || buc_reject "${z_band}" "Foedus '${z_foedus}' has no rbrf.env. Available foedera: ${z_avail}"
}

# Extract one RBRF_ assignment value from a foedus's rbrf.env by PARSING the file
# (never sourcing — the active foedus's RBRF_* are already kindled readonly, and
# a descry subject may differ from the active one). Echoes the bare value or
# returns 1; the caller guards with || buc_reject.
zrbof_rbrf_field_capture() {
  local -r z_file="${1:-}"
  local -r z_var="${2:-}"
  local z_line=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    if [[ "${z_line}" == ${z_var}=* ]]; then
      printf '%s' "${z_line#*=}"
      return 0
    fi
  done < "${z_file}"
  return 1
}

######################################################################
# Descry (rbof_descry) — read-only provider-grain health probe of a named foedus.

rbof_descry() {
  zrbof_sentinel

  # The foedus operand arrives via the BUZ_FOLIO env channel (param1 colophon).
  local -r z_foedus="${BUZ_FOLIO:-}"

  buc_doc_brief "Descry a standing foedus — read its provider's presence under the manor pool (healthy, or a named deficit); read-only"
  buc_doc_param "foedus" "Foedus identity — the rbef_ subdirectory name of a standing foedus in the moorings foedera library"
  buc_doc_shown || return 0

  zrbof_require_foedus "${z_foedus}" "${BUBC_band_descry}"

  # The manor pool coordinates (org / pool) are manor-level under the one-pool
  # Model — read them from the manor's RBRW regime file, the same for every foedus.
  # The provider is the per-foedus discriminator and stays in the inspected
  # foedus's own rbrf.env.
  local z_rbrf=""
  z_rbrf=$(rbcc_rbrf_file_capture "${z_foedus}") \
    || buc_reject "${BUBC_band_descry}" "Failed to resolve the regime path for foedus '${z_foedus}'"
  local z_org=""
  local z_pool=""
  local z_provider=""
  z_org=$(zrbof_rbrf_field_capture "${RBCC_rbrw_file}" "RBRW_ORG_ID") \
    || buc_reject "${BUBC_band_descry}" "Manor workforce regime carries no RBRW_ORG_ID: ${RBCC_rbrw_file}"
  z_pool=$(zrbof_rbrf_field_capture "${RBCC_rbrw_file}" "RBRW_WORKFORCE_POOL_ID") \
    || buc_reject "${BUBC_band_descry}" "Manor workforce regime carries no RBRW_WORKFORCE_POOL_ID: ${RBCC_rbrw_file}"
  z_provider=$(zrbof_rbrf_field_capture "${z_rbrf}" "RBRF_PROVIDER_ID") \
    || buc_reject "${BUBC_band_descry}" "Foedus '${z_foedus}' rbrf.env carries no RBRF_PROVIDER_ID: ${z_rbrf}"

  buc_step "Descry foedus ${z_foedus} — provider ${z_provider} under pool ${z_pool} (organizations/${z_org})"

  # Payor OAuth — the same credential affiance/jilt use to work the org-level
  # workforce pool (workforcePools.get is org-scoped; the payor holds it). The
  # credless guard rides inside this capture: a reveille-tier run rejects here
  # before any credential touch.
  local z_token=""
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  local -r z_iam_root="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}"
  local -r z_pools_base="${z_iam_root}/locations/global/workforcePools"

  # Confirm the manor pool coordinates (descry's half of the RBRW sync guard,
  # RBSFD): the read confirms a live pool stands under the org at the expected
  # id. No live pool at the coordinate — absent (404) or soft-deleted (200,
  # state DELETED, squatting the id through the ~30-day purge window) — is the
  # coordinate-drift deficit: a reported verdict, not an error (the RB pool may
  # stand under a different id; the manor-setup finisher reconciles). A broken
  # read (any other code) is descry's OWN error, not a verdict — reject in
  # descry's band.
  buc_step "Confirm manor pool coordinates"
  rbuh_json "GET" "${z_pools_base}/${z_pool}" "${z_token}" "descry_pool_get"
  local z_pool_code=""
  z_pool_code=$(rbuh_code_capture "descry_pool_get") \
    || buc_reject "${BUBC_band_descry}" "No HTTP code from workforcePools.get for pool ${z_pool}"

  local z_pool_state=""
  local z_verdict=""
  case "${z_pool_code}" in
    200)
      z_pool_state=$(rbuh_json_field_capture "descry_pool_get" ".state // \"${RBGC_STATE_UNSPECIFIED}\"") \
        || z_pool_state="${RBGC_STATE_UNSPECIFIED}"
      if test "${z_pool_state}" = "${RBGC_STATE_DELETED}"; then
        z_verdict="coordinate-drift"
      fi
      ;;
    404)
      z_verdict="coordinate-drift"
      ;;
    *)
      buc_reject "${BUBC_band_descry}" "Unexpected HTTP ${z_pool_code} reading workforce pool ${z_pool} — descry cannot determine health"
      ;;
  esac

  # Read the provider's presence — the foedus verdict proper (a foedus IS a
  # provider under the one manor pool, RBSFD). Only reached when the pool
  # coordinates confirmed; a coordinate-drift deficit already IS the verdict.
  # 200 present / 404 absent; any other code is a broken read.
  if test -z "${z_verdict}"; then
    buc_step "Read provider presence"
    rbuh_json "GET" "${z_pools_base}/${z_pool}/providers/${z_provider}" "${z_token}" "descry_provider_get"
    local z_provider_code=""
    z_provider_code=$(rbuh_code_capture "descry_provider_get") \
      || buc_reject "${BUBC_band_descry}" "No HTTP code from providers.get for provider ${z_provider}"
    case "${z_provider_code}" in
      200) z_verdict="healthy" ;;
      404) z_verdict="provider-absent" ;;
      *)   buc_reject "${BUBC_band_descry}" "Unexpected HTTP ${z_provider_code} reading provider ${z_provider} — descry cannot determine health" ;;
    esac
  fi

  # Report the verdict (NOT a gate — a deficit is a successful read, reported
  # for the fixture to branch on). The verdict rides a fact file keyed by foedus
  # so the reuse-or-establish fixture can chain it.
  buf_write_fact_multi "${z_foedus}" "${RBCC_fact_ext_foedus_health}" "${z_verdict}"

  if test "${z_verdict}" = "healthy"; then
    buc_success "Foedus ${z_foedus} is HEALTHY — provider ${z_provider} present under pool ${z_pool}"
  else
    buc_warn "Foedus ${z_foedus} is NOT healthy — verdict '${z_verdict}' (provider ${z_provider}, pool ${z_pool})"
  fi
}

######################################################################
# Canvass (rbof_canvass) — read-only enumeration of the manor's foedera.

rbof_canvass() {
  zrbof_sentinel

  buc_doc_brief "Canvass the manor's foedera — enumerate every provider under the one workforce pool, emitting per-foedus fact files and marking the regime-selected one; read-only"
  buc_doc_shown || return 0

  # The manor's ONE workforce pool id is manor-level (RBRW) — the same for every
  # foedus — so read it from the manor's RBRW regime file. The active selector
  # (RBRR_ACTIVE_FOEDUS) must still name a real library foedus (that is the
  # selection the emitted facts mark), so validate it; it no longer carries the
  # pool coordinates. A selector pointing at no library foedus is corrupt repo
  # regime, not a canvass verdict.
  local -r z_active="${RBRR_ACTIVE_FOEDUS:-}"
  test -n "${z_active}" || buc_die "RBRR_ACTIVE_FOEDUS is empty — the repo regime selects no active foedus"
  local z_active_rbrf=""
  z_active_rbrf=$(rbcc_rbrf_file_capture "${z_active}") \
    || buc_die "Failed to resolve the regime path for the active foedus '${z_active}'"
  test -f "${z_active_rbrf}" || buc_die "Active foedus '${z_active}' has no rbrf.env in the foedera library: ${z_active_rbrf}"

  local z_pool=""
  z_pool=$(zrbof_rbrf_field_capture "${RBCC_rbrw_file}" "RBRW_WORKFORCE_POOL_ID") \
    || buc_die "Manor workforce regime carries no RBRW_WORKFORCE_POOL_ID: ${RBCC_rbrw_file}"

  # Correlation map: every library foedus's configured provider id. A listed
  # provider matching one of these ids IS that foedus (the canvass→rbef_
  # mapping); an unmatched provider is still a foedus the manor holds — the
  # Manor, not the library, is the authoritative registry of what exists.
  local -a z_lib_foedus=()
  local -a z_lib_provider=()
  local z_entry=""
  local z_lib_name=""
  local z_lib_rbrf=""
  local z_lib_pid=""
  for z_entry in "${RBCC_foedera_dir}"/rbef_*/; do
    test -d "${z_entry}" || continue
    z_entry="${z_entry%/}"
    z_lib_name="${z_entry##*/}"
    z_lib_rbrf=$(rbcc_rbrf_file_capture "${z_lib_name}") || continue
    test -f "${z_lib_rbrf}" || continue
    z_lib_pid=$(zrbof_rbrf_field_capture "${z_lib_rbrf}" "RBRF_PROVIDER_ID") || continue
    z_lib_foedus+=("${z_lib_name}")
    z_lib_provider+=("${z_lib_pid}")
  done

  buc_step "Canvass foedera — providers under pool ${z_pool}"

  # Payor OAuth — listing the org pool's providers is the same org-level
  # authority affiance/jilt wield; depot mantles cannot reach it. The credless
  # guard rides inside this capture.
  local z_token=""
  z_token=$(zrbgp_authenticate_capture) || buc_die "Failed to authenticate as Payor via OAuth"

  local -r z_iam_root="${RBGC_API_ROOT_IAM}${RBGC_IAM_V1}"
  local -r z_providers_base="${z_iam_root}/locations/global/workforcePools/${z_pool}/providers"
  local -r z_nl=$'\n'

  buc_info ""
  buc_info "=== FOEDUS CANVASS ==="
  printf "%-24s %-24s %-12s %s\n" "FOEDUS" "PROVIDER" "STATE" "SELECTED"

  # Per-iteration synthesized locals (BCG exception 2 — declare outside, assign inside)
  local z_page=1
  local z_page_token=""
  local z_url=""
  local z_tok_enc=""
  local z_infix=""
  local z_code=""
  local z_count=0
  local z_index=0
  local z_p_name=""
  local z_p_id=""
  local z_p_state=""
  local z_matched=""
  local z_selected=""
  local z_stem=""
  local z_fact_value=""
  local z_i=0
  local z_total=0
  local z_matched_count=0
  local z_selected_seen=false
  local z_pool_absent=false

  # Paginated providers.list under the one manor pool. A 404 is the pool itself
  # absent from the Manor (no pool, so no foedera stand) — a reported verdict,
  # not an error; any other non-200 is a broken read.
  while :; do
    z_url="${z_providers_base}"
    if test -n "${z_page_token}"; then
      z_tok_enc=$(rbuh_urlencode_capture "${z_page_token}") \
        || buc_die "Failed to URL-encode providers.list pageToken"
      z_url="${z_url}?pageToken=${z_tok_enc}"
    fi

    z_infix="canvass_providers_list_${z_page}"
    rbuh_json "GET" "${z_url}" "${z_token}" "${z_infix}"
    z_code=$(rbuh_code_capture "${z_infix}") \
      || buc_die "No HTTP code from providers.list under pool ${z_pool}"
    case "${z_code}" in
      200) ;;
      404) z_pool_absent=true; break ;;
      *)   buc_die "Unexpected HTTP ${z_code} from providers.list under pool ${z_pool}" ;;
    esac

    z_count=$(rbuh_json_field_capture "${z_infix}" '.workforcePoolProviders // [] | length') \
      || z_count=0

    z_index=0
    while test "${z_index}" -lt "${z_count}"; do
      z_p_name=$(rbuh_json_field_capture "${z_infix}" ".workforcePoolProviders[${z_index}].name") \
        || { z_index=$((z_index + 1)); continue; }
      z_p_id="${z_p_name##*/}"
      z_p_state=$(rbuh_json_field_capture "${z_infix}" ".workforcePoolProviders[${z_index}].state // \"${RBGC_STATE_UNSPECIFIED}\"") \
        || z_p_state="${RBGC_STATE_UNSPECIFIED}"

      # Correlate the provider id against the library's configured ids.
      z_matched=""
      z_i=0
      while test "${z_i}" -lt "${#z_lib_foedus[@]}"; do
        if test "${z_lib_provider[${z_i}]}" = "${z_p_id}"; then
          z_matched="${z_lib_foedus[${z_i}]}"
          break
        fi
        z_i=$((z_i + 1))
      done

      if test -n "${z_matched}" && test "${z_matched}" = "${z_active}"; then
        z_selected=true
        z_selected_seen=true
      else
        z_selected=false
      fi

      # One fact file per foedus: stem is the matched rbef_ library name, or
      # the bare provider id when the Manor holds a provider the library does
      # not know.
      z_stem="${z_matched:-${z_p_id}}"
      z_fact_value="provider=${z_p_id}${z_nl}state=${z_p_state}${z_nl}selected=${z_selected}"
      buf_write_fact_multi "${z_stem}" "${RBCC_fact_ext_foedus}" "${z_fact_value}"

      printf "%-24s %-24s %-12s %s\n" "${z_matched:--}" "${z_p_id}" "${z_p_state}" "${z_selected}"
      z_total=$((z_total + 1))
      test -z "${z_matched}" || z_matched_count=$((z_matched_count + 1))

      z_index=$((z_index + 1))
    done

    z_page_token=$(rbuh_json_field_capture "${z_infix}" '.nextPageToken') \
      || z_page_token=""
    test -n "${z_page_token}" || break
    z_page=$((z_page + 1))
  done

  if test "${z_pool_absent}" = "true"; then
    buc_warn "Workforce pool ${z_pool} is absent from the Manor — no pool, so no foedera stand"
    buc_success "Canvass complete — manor holds no foedera (pool absent)"
    return 0
  fi

  buc_info ""
  buc_info "=== SUMMARY ==="
  buc_info "Foedera (providers): ${z_total}"
  buc_info "In library:          ${z_matched_count}"
  buc_info "Unmatched:           $((z_total - z_matched_count))"

  if test "${z_total}" -eq 0; then
    buc_success "Canvass complete — manor holds no foedera under pool ${z_pool}"
    return 0
  fi

  if test "${z_selected_seen}" = "true"; then
    buc_success "Canvass complete — ${z_total} foedera; regime-selected foedus ${z_active} stands in the Manor"
  else
    buc_warn "Regime-selected foedus ${z_active} has no standing provider in the Manor"
    buc_success "Canvass complete — ${z_total} foedera; the regime-selected foedus is not among them"
  fi
}

######################################################################
# Instate (rbof_instate) — re-point the active-foedus selector.

rbof_instate() {
  zrbof_sentinel

  local -r z_foedus="${BUZ_FOLIO:-}"

  buc_doc_brief "Instate a standing foedus as active — re-point the RBRR_ACTIVE_FOEDUS selector in rbrr.env (atomic, uncommitted; the operator commits)"
  buc_doc_param "foedus" "Foedus identity — the rbef_ subdirectory name of a standing foedus in the moorings foedera library"
  buc_doc_shown || return 0

  zrbof_require_foedus "${z_foedus}" "${BUBC_band_instate}"

  # Atomic single-field rewrite of the active-foedus selector, reusing the
  # durable-config-link mechanics (feoff/yoke/anoint): substitute the matching
  # assignment, pass the rest through unchanged, write a temp file then rename.
  # No other field is touched; no clean-tree gate (instate writes the very change
  # the operator is about to commit); not committed; no Manor mutation; no
  # sitting reset (re-signing against the new foedus is avow's concern). RBSFI.
  local -r z_file="${RBCC_rbrr_file}"
  test -f "${z_file}" || buc_die "Repo regime file not found: ${z_file}"

  local -r z_var="RBRR_ACTIVE_FOEDUS"
  local -r z_line_new="${z_var}=${z_foedus}"
  local -r z_tmp="${BURD_TEMP_DIR}/rbof_instate_rbrr.env.new"
  local z_line=""
  local z_found=false
  while IFS= read -r z_line || test -n "${z_line}"; do
    if [[ "${z_line}" == ${z_var}=* ]]; then
      printf '%s\n' "${z_line_new}"; z_found=true
    else
      printf '%s\n' "${z_line}"
    fi
  done < "${z_file}" > "${z_tmp}" \
    || buc_die "Failed to rewrite ${z_file} for ${z_var}"

  # Unlike feoff (replace-or-append), the selector is a required enrolled field
  # that must already exist — a missing assignment is a corrupt repo regime, not
  # an append site.
  test "${z_found}" = "true" \
    || buc_die "No ${z_var} assignment in ${z_file} — the selector must be enrolled and present before instate can re-point it"

  mv "${z_tmp}" "${z_file}" || buc_die "Failed to finalize ${z_file}"

  buc_success "Instated ${z_foedus} as the active foedus: ${z_var}=${z_foedus}"
  buc_info "Commit the rbrr.env change with your usual git workflow; the authenticate-against-active consumers (avow, the accessor, the federated-access and mantle-access probes) require the selector committed before they run."
}

# eof
