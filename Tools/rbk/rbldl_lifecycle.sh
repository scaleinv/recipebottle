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
# Recipe Bottle Lode - lifecycle REST (guard-free cluster, sourced by rbld0_lode):
#   divine — enumerate every Lode by touchmark (read-only)
#   augur  — inspect one Lode: member tags + decoded rbi_vouch envelope (read-only)
#   banish — delete a whole Lode (Director credentials)

set -euo pipefail

######################################################################
# External Functions (rbld_*)

rbld_divine() {
  zrbld_sentinel

  buc_doc_brief "Divine Lodes — enumerate every Lode by touchmark (read-only)"
  buc_doc_shown || return 0

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  buc_step "Enumerating Lodes under ${RBGL_LODES_ROOT}/"
  zrbfc_list_anchors_capture "${z_token}" "${RBGL_LODES_ROOT}"

  if ! test -s "${ZRBFC_PACKAGE_LIST_FILE}"; then
    buc_info "No Lodes found under ${RBGL_LODES_ROOT}/"
    buc_success "Divine complete — 0 Lodes"
    return 0
  fi

  # Kind-letter legend, printed once so rows carry no repeated per-row column.
  # A touchmark's leading letter is its kind (b260602075327 -> bole); the
  # reader decodes the prefix from this key. One entry per implemented kind.
  local -r z_kind_fmt="    %-3s %-13s %s\n"
  echo ""
  printf "  Kinds (touchmark prefix):\n"
  printf "${z_kind_fmt}" "${RBGC_LODE_KIND_BOLE}"         "bole"         "upstream OCI image, consumed as a FROM line"
  printf "${z_kind_fmt}" "${RBGC_LODE_KIND_RELIQUARY}"    "reliquary"    "date-cohort of build-tool images"
  printf "${z_kind_fmt}" "${RBGC_LODE_KIND_WSL}"          "wsl"          "vendor-published rootfs tarball, opaque-blob member"
  printf "${z_kind_fmt}" "${RBGC_LODE_KIND_PODVM_WSL}"    "podvm-wsl"    "podman machine-os-wsl disk leaves, opaque-blob cohort"
  printf "${z_kind_fmt}" "${RBGC_LODE_KIND_PODVM_NATIVE}" "podvm-native" "podman machine-os disk leaves, opaque-blob cohort"

  # Load the touchmark list fully before iterating: the per-Lode tags fetch
  # spawns curl (via rbuh), and a child touching stdin would consume the
  # loop's remaining input. Load-then-iterate keeps that FD closed.
  local z_touchmarks=()
  local z_touch=""
  while IFS= read -r z_touch || test -n "${z_touch}"; do
    test -n "${z_touch}" || continue
    z_touchmarks+=("${z_touch}")
  done < "${ZRBFC_PACKAGE_LIST_FILE}"

  local -r z_row_fmt="  %-15s %s\n"
  echo ""
  printf "${z_row_fmt}" "TOUCHMARK" "IMAGE"
  printf "${z_row_fmt}" "---------------" "--------------------------------------"

  local z_idx=0
  local z_pkg=""
  local z_pkg_encoded=""
  local z_tags_url=""
  local z_enum_infix=""
  local z_resp_file=""
  local z_image_file=""
  local z_image=""
  for z_idx in "${!z_touchmarks[@]}"; do
    z_touch="${z_touchmarks[$z_idx]}"

    # One tags-list per Lode. The IMAGE column adapts to the Lode's member
    # scheme (the touchmark prefix names the kind; see the legend above). A
    # single-image Lode (bole) shows its unsprued fingerprint tag
    # <sanitized-origin>-<sha10>, located via the sha10 taken from the
    # rbi_sha256-<hex> member tag so Director semantic names (also unsprued)
    # cannot masquerade as the fingerprint. A clean-scheme cohort (reliquary)
    # carries no digest/fingerprint layer, so it has no single fingerprint to
    # show — report its member count instead (every non-:rbi_vouch tag is a
    # member). Per-Lode infix preserves each response for forensics.
    z_pkg="${RBGL_LODES_ROOT}/${z_touch}"
    z_pkg_encoded="${z_pkg//\//%2F}"
    z_tags_url="${ZRBFC_GAR_API_BASE}/${ZRBFC_GAR_PACKAGE_BASE}/packages/${z_pkg_encoded}/tags?pageSize=1000"
    z_enum_infix="rbld_divine_enum_${z_idx}"
    rbuh_json "GET" "${z_tags_url}" "${z_token}" "${z_enum_infix}"
    rbuh_require_ok "List tags for Lode ${z_touch}" "${z_enum_infix}"
    z_resp_file="${ZRBUH_PREFIX}${z_enum_infix}${ZRBUH_POSTFIX_JSON}"

    z_image_file="${ZRBLD_DIVINE_PREFIX}enum_${z_idx}_image.txt"
    jq -r --arg dp "${RBGC_LODE_TAG_DIGEST_PREFIX}" --arg vouch "${RBGC_LODE_TAG_VOUCH}" '
      [.tags[]?.name | sub(".*/tags/"; "")] as $names
      | ([$names[] | select(startswith($dp)) | ltrimstr($dp)[0:10]][0]) as $sha10
      | ([$names[] | select((startswith("rbi_") | not) and ($sha10 != null) and endswith("-" + $sha10))][0]) as $fingerprint
      | if $fingerprint != null then $fingerprint
        else "(cohort: \([$names[] | select(. != $vouch)] | length) members)"
        end
    ' "${z_resp_file}" > "${z_image_file}" \
      || buc_die "Failed to summarize Lode ${z_touch}"
    z_image=$(<"${z_image_file}")
    test -n "${z_image}" || buc_die "Empty summary extraction for Lode ${z_touch}"

    printf "${z_row_fmt}" "${z_touch}" "${z_image}"
  done
  echo ""
  buc_info "Total Lodes: ${#z_touchmarks[@]}"
  buc_success "Divine complete"
}

rbld_augur() {
  zrbld_sentinel

  local -r z_express="${BUZ_FOLIO:-}"

  buc_doc_brief "Augur a Lode — inspect member tags and decode its rbi_vouch provenance envelope (read-only)"
  buc_doc_param "touchmark" "Lode stamp to inspect (e.g., b260602120000); optional — absent, falls back to the touchmark any capture chained forward"
  buc_doc_shown || return 0

  # Relay-then-read (RBr_3e7): forward the chain baton before any read or failure point.
  buf_relay || buc_die "Failed to relay chained facts"

  # Resolve the touchmark express-or-chain: an express argument wins; absent, fall
  # back to the touchmark any capture handed forward through the depth-1 chain — so
  # a no-arg augur immediately after a capture inspects the just-captured Lode.
  local z_touchmark=""
  z_touchmark=$(buf_elect_fact_capture "${z_express}" "${RBF_FACT_LODE_TOUCHMARK}") \
    || buc_reject "${BUBC_band_chain}" "No touchmark — pass one (param1) or run any Lode capture immediately before augur"

  # Assert a KNOWN Lode kind by decoding the touchmark's kind-letter prefix — the
  # single home for touchmark kind decode, shared with feoff/yoke. Unlike those
  # one-kind gates, augur accepts ANY known kind: it inspects every Lode kind. This
  # replaces augur's former regex shape-check, which proved well-formedness but never
  # that the prefix named a real kind (the decoder is the sole kind channel).
  local z_kind=""
  z_kind=$(zrbld_decode_touchmark_kind_capture "${z_touchmark}") \
    || buc_reject "${BUBC_band_chain}" "Touchmark '${z_touchmark}' has no recognizable Lode kind prefix (expected <kind><YYMMDDHHMMSS>, e.g. b260602120000)"

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  local -r z_pkg="${RBGL_LODES_ROOT}/${z_touchmark}"
  local -r z_pkg_encoded="${z_pkg//\//%2F}"

  # Member tags — every tag on the Lode package. An empty package is the
  # "Lode not present" signal (matches divine's enumerate contract).
  buc_step "Fetching member tags for Lode ${z_pkg}"
  local -r z_tags_url="${ZRBFC_GAR_API_BASE}/${ZRBFC_GAR_PACKAGE_BASE}/packages/${z_pkg_encoded}/tags?pageSize=1000"
  local -r z_tags_infix="rbld_augur_tags"
  rbuh_json "GET" "${z_tags_url}" "${z_token}" "${z_tags_infix}"
  # A banished or never-captured Lode answers 404 here — the user named a
  # touchmark absent from the registry, knowable only after this round-trip.
  # Map 404 to the vacant band (as summon/plumb map their own 404s); any other
  # non-OK status stays infra-generic through rbuh_require_ok.
  local z_tags_code=""
  z_tags_code=$(rbuh_code_capture "${z_tags_infix}") \
    || buc_die "Failed to read tags HTTP code for Lode ${z_touchmark}"
  test "${z_tags_code}" != "404" \
    || buc_reject "${BUBC_band_vacant}" "No Lode at ${z_pkg} — touchmark names no package in the registry"
  rbuh_require_ok "List tags for Lode ${z_touchmark}" "${z_tags_infix}"

  local -r z_resp_file="${ZRBUH_PREFIX}${z_tags_infix}${ZRBUH_POSTFIX_JSON}"
  local -r z_tags_file="${ZRBLD_AUGUR_PREFIX}tags.txt"
  jq -r '.tags[]?.name | sub(".*/tags/"; "")' "${z_resp_file}" > "${z_tags_file}" \
    || buc_die "Failed to extract member tags for Lode ${z_touchmark}"
  test -s "${z_tags_file}" \
    || buc_reject "${BUBC_band_vacant}" "No member tags found under ${z_pkg} — Lode not present in registry"

  local z_tags=()
  local z_tag=""
  while IFS= read -r z_tag || test -n "${z_tag}"; do
    test -n "${z_tag}" || continue
    z_tags+=("${z_tag}")
  done < "${z_tags_file}"

  echo ""
  printf "  Member tags (%s):\n" "${#z_tags[@]}"
  for z_tag in "${z_tags[@]}"; do
    printf "    %s\n" "${z_tag}"
  done

  # Provenance envelope — extract the :rbi_vouch FROM-scratch artifact and read
  # its vouch.json layer. This is the inspect depth divine never carried: the
  # acquisition facts and the honest trust-grade posture. The same gcrane-pushed
  # single-layer image rbgjl02 wrote (vouch.json at image root).
  buc_step "Decoding provenance envelope (:${RBGC_LODE_TAG_VOUCH})"
  local -r z_vouch_dir="${ZRBLD_AUGUR_PREFIX}vouch"
  rm -rf "${z_vouch_dir}" || buc_die "Failed to clear vouch scratch dir: ${z_vouch_dir}"
  zrbfc_gar_extract_artifact "${z_token}" "${z_pkg}" "${RBGC_LODE_TAG_VOUCH}" "${z_vouch_dir}" \
    || buc_die "No :${RBGC_LODE_TAG_VOUCH} envelope at ${z_pkg} — not a vouched Lode (capture incomplete or a legacy artifact)"
  local -r z_vouch_json="${z_vouch_dir}/vouch.json"
  test -f "${z_vouch_json}" \
    || buc_die "Envelope artifact present but vouch.json missing for ${z_touchmark}"

  # Kind name comes from the envelope's own rblv_kind field — the kind-agnostic source
  # (a new Lode kind needs no change here; the prefix letter is shown as a cross-check).
  local z_trust=""
  z_trust=$(jq -r '.rblv_trust_grade // "(absent)"' "${z_vouch_json}") \
    || buc_die "Failed to read rblv_trust_grade from envelope for ${z_touchmark}"

  echo ""
  printf "  Provenance envelope (:%s):\n" "${RBGC_LODE_TAG_VOUCH}"
  jq -r '
    "    Kind:          \(.rblv_kind // "(absent)")",
    "    Lode:          \(.rblv_lode // "(absent)")",
    "    Schema:        \(.rblv_schema // "(absent)")",
    "    Acquired at:   \(.rblv_acquired_at // "(absent)")",
    "    Acquired by:   \(.rblv_acquired_by // "(absent)")",
    "    Capture build: \(.rblv_capture_build // "(absent)")",
    "    Git commit:    \(.rblv_git_commit // "(absent)")",
    "    Signature:     \(if .rblv_signature == null then "(unsigned)" else .rblv_signature end)",
    "    Trust grade:   \(.rblv_trust_grade // "(absent)")",
    "",
    "    Members (\((.rblv_members // []) | length)):",
    ((.rblv_members // [])[] |
      "      \(.rblv_name // "(unnamed)")",
      "        origin:       \(.rblv_origin // "(absent)")",
      "        digest:       \(.rblv_digest // "(absent)")",
      "        verification: \(.rblv_verification // "(absent)")",
      "        tags:         \((.rblv_tags // []) | join(", "))")
  ' "${z_vouch_json}" \
    || buc_die "Failed to render provenance envelope for ${z_touchmark}"

  # Honest trust posture — never over-claim what the upstream permits (the Pale).
  echo ""
  case "${z_trust}" in
    "${RBGC_LODE_TRUST_VERIFIED}")
      printf "  Trust posture: %s\n" "${z_trust}"
      printf "    Bytes remain re-checkable against the published upstream — an OCI\n"
      printf "    content-address on a durable registry, or a vendor-published checksum.\n"
      ;;
    "${RBGC_LODE_TRUST_RECORDED}")
      printf "  Trust posture: %s\n" "${z_trust}"
      printf "    RB attests only the digest observed at capture: the upstream offers no\n"
      printf "    durable re-checkable reference, so the claim never implies the bytes\n"
      printf "    remain verifiable against a vanished source.\n"
      ;;
    *)
      printf "  Trust posture: %s (unrecognized grade — displayed verbatim)\n" "${z_trust}"
      ;;
  esac

  echo ""
  buc_success "Augur complete — Lode ${z_touchmark}"
}

rbld_banish() {
  zrbld_sentinel

  local -r z_touchmark="${BUZ_FOLIO:-}"

  buc_doc_brief "Banish a Lode — delete the whole rbi_ld/<touchmark> GAR package"
  buc_doc_param "touchmark" "Lode stamp to delete (e.g., b260602120000)"
  buc_doc_shown || return 0

  test -n "${z_touchmark}" || buc_die "Touchmark parameter required"

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  local -r z_pkg="${RBGL_LODES_ROOT}/${z_touchmark}"
  local -r z_pkg_encoded="${z_pkg//\//%2F}"

  # Verify presence before delete so banish reports a clean not-found.
  buc_step "Verifying Lode present: ${z_pkg}"
  local -r z_tags_url="${ZRBFC_GAR_API_BASE}/${ZRBFC_GAR_PACKAGE_BASE}/packages/${z_pkg_encoded}/tags?pageSize=1"
  local -r z_probe_infix="rbld_banish_probe"
  rbuh_json "GET" "${z_tags_url}" "${z_token}" "${z_probe_infix}"
  rbuh_require_ok "Probe Lode ${z_touchmark}" "${z_probe_infix}"

  local z_tag_count=""
  z_tag_count=$(rbuh_json_field_capture "${z_probe_infix}" '(.tags // []) | length') \
    || buc_die "Failed to count tags for ${z_pkg}"
  test "${z_tag_count}" -gt 0 \
    || buc_die "No Lode found at ${z_pkg} — nothing to banish"

  buc_require "Will banish the whole Lode ${z_pkg} (cloud-dispatched delete)" "yes"

  # Cloud-dispatched delete: a Director-run build deletes the package in-pool by
  # convergence (GAR's parent-before-child FAILED_PRECONDITION; absence-poll to
  # 404 is the only success signal) — the build's success IS the delete outcome,
  # closing the host trust-200 LRO gap; see RBSCB and rbgjl06.
  buc_step "Dispatching cloud delete for Lode package: ${z_pkg}"
  zrbld_cloud_delete_dispatch "${z_token}" "Banish" "${ZRBLD_BANISH_PREFIX}" "${z_pkg}"

  echo ""
  buc_success "Lode banished: ${z_touchmark}"
}

# eof
