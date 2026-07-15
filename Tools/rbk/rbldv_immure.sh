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
# Recipe Bottle Lode - podvm body (guard-free cluster, sourced by rbld0_lode):
#   immure  — wall in the selected podman-machine disk leaves of one quay family into
#             a Lode (Director credentials)
#   presage — show what immure would capture for one quay family (read-only dry-run:
#             family resolution + leaf selection, no credential or network touch)
# The podvm kind rides the capture-assembly spine (rblds_): this body owns only the
# kind-specific data — the immure recipe (anon-quay index select + gcrane cp-by-digest
# + blob-residency guard + vouch-push) and the substitutions blob — and composes them
# through zrbld_spine_dispatch / zrbld_spine_extract_single. No build-submission or
# step-composition machinery lives here.
#
# Shape: opaque-blob (like wsl/underpin) x multi-member (like reliquary/conclave). Each
# selected disk leaf is a single-platform OCI artifact (empty config + one zstd blob);
# the cohort of leaves rides as N member tags within one GAR package. One verb spans
# BOTH quay families (podvm-wsl: quay.io/podman/machine-os-wsl, podvm-native:
# quay.io/podman/machine-os) via the family argument — not two verbs.
#
# Recorded-at-acquisition grade: quay rotates podvm out within days and publishes no
# durable checksum, so RB attests only the leaf digest captured (trust-on-first-
# acquisition). Cloud-side only; the workstation assembles no bytes, only the
# declarative family + version + curated leaf-set.

set -euo pipefail

# Immure is capture-pure: it writes no consumer config. It hands the captured
# touchmark forward through one bare single-form chaining fact
# (RBF_FACT_LODE_TOUCHMARK) via the depth-1 cross-tabtarget chain; a consumer
# decodes the podvm kind from the touchmark prefix. The provenance envelope lives
# only in GAR (:rbi_vouch tag, pushed cloud-side by rbgjl02), never host-side.
# Consumption (a host's `podman machine init` from the captured seed) is a
# separate, deferred layer that reads this fact — not part of immure.

######################################################################
# Internal Helpers (zrbld_*)

# Internal: resolve the family argument to its (kind-letter, quay-family, selection,
# brand) tuple. The brand IS the operator-typed argument and the envelope kind field.
# Both families are wired; podvm-wsl is fixture-proven recurring (picket tier), and
# podvm-native carries full 8-leaf curation (see rbgc_constants podvm selection block).
# Args: family   Sets: z_kind, z_quay_family, z_selection (caller-scoped locals)
zrbld_immure_resolve_family() {
  zrbld_sentinel
  local -r zz_family="${1:?Family required}"
  case "${zz_family}" in
    "${RBGC_LODE_BRAND_PODVM_WSL}")
      z_kind="${RBGC_LODE_KIND_PODVM_WSL}"
      z_quay_family="${RBGC_LODE_PODVM_FAMILY_WSL}"
      z_selection="${RBGC_LODE_PODVM_WSL_SELECTION}"
      ;;
    "${RBGC_LODE_BRAND_PODVM_NATIVE}")
      z_kind="${RBGC_LODE_KIND_PODVM_NATIVE}"
      z_quay_family="${RBGC_LODE_PODVM_FAMILY_NATIVE}"
      z_selection="${RBGC_LODE_PODVM_NATIVE_SELECTION}"
      ;;
    *)
      buc_die "Unknown podvm family '${zz_family}' (expected ${RBGC_LODE_BRAND_PODVM_WSL} or ${RBGC_LODE_BRAND_PODVM_NATIVE})"
      ;;
  esac
}

# Internal: compose the immure capture recipe (anon-quay index select + gcrane
# cp-by-digest + blob-residency guard + vouch-push) and its substitutions blob, then
# ride the capture spine to submit and poll. The spine owns the capture-domain build
# knobs (mason SA, TETHER pool, regime timeout); this body chooses only the recipe,
# the substitutions, and the heavy capture poll ceiling (the multi-GB leaf copies
# want the larger budget). Four steps across three builders: index-select rides the
# gcloud builder (python3 — parses the upstream OCI index, which the no-jq bash GCB
# discipline does not cover; rbgjl06 precedent); gcrane cp and the vouch-push ride the
# floating gcrane builder (busybox); the residency HEAD rides the Debian docker builder
# (curl, allowlisted). The recipe-row ORDER is part of the contract: vouch (rbgjl02)
# runs strictly after residency (rbgjl09) — the vouch artifact never precedes the
# anti-hollow-mirror guard. podvm is vessel-less (no reliquary slot), so its gcrane
# rides the floating bootstrap builder, same tier as conclave/wsl — pinning defers to
# the bootstrap-builder digest-pin itch (RBS0 rbsk_pinning_boundary).
# Args: token brand quay_family version selection stamp preserved
#   preserved — compact JSON array of already-captured members (refresh add-only);
#               "[]" for a fresh capture. Passed through as _RBGL_PODVM_PRESERVED so
#               the select step splices them in without re-resolving upstream.
zrbld_immure_submit() {
  zrbld_sentinel

  local -r z_token="${1:?Token required}"
  local -r z_brand="${2:?Brand required}"
  local -r z_quay_family="${3:?Family required}"
  local -r z_version="${4:?Version required}"
  local -r z_selection="${5:?Selection required}"
  local -r z_stamp="${6:?Stamp required}"
  local -r z_preserved="${7:-[]}"

  buc_step "Constructing immure capture recipe"
  local -r z_gar_host="${RBGD_GAR_LOCATION}${RBGC_GAR_HOST_SUFFIX}"
  local -r z_gar_path="${RBGD_GAR_PROJECT_ID}/${RBDC_GAR_REPOSITORY}"

  # Recipe rows: script_path|builder_image|id|entrypoint, pre-resolved for the spine.
  # Select on the gcloud builder (python3 — index parse); residency on the Debian docker
  # builder (curl HEAD); cp + vouch on the floating gcrane builder (busybox). The gcrane
  # builder reads public quay anonymously and pushes GAR ambiently (google.Keychain ->
  # Mason SA).
  local -r z_recipe=(
    "${ZRBLD_RBGJL_STEPS_DIR}/rbgjl07-immure-select.py|${ZRBLD_GCLOUD_BUILDER}|immure-select|python3"
    "${ZRBLD_RBGJL_STEPS_DIR}/rbgjl08-immure-capture.sh|${ZRBLD_GCRANE_BUILDER}|immure-capture|busybox"
    "${ZRBLD_RBGJL_STEPS_DIR}/rbgjl09-immure-residency.sh|${ZRBLD_GOOGLE_DOCKER_BUILDER}|immure-residency|bash"
    "${ZRBLD_RBGJL_STEPS_DIR}/rbgjl02-assemble-push-vouch.sh|${ZRBLD_GCRANE_BUILDER}|assemble-push-vouch|busybox"
  )

  buc_log_args "Composing immure substitutions blob"
  local -r z_subs_file="${ZRBLD_IMMURE_PREFIX}subs.json"
  jq -n \
    --arg zjq_gar_host     "${z_gar_host}" \
    --arg zjq_gar_path     "${z_gar_path}" \
    --arg zjq_lodes_root   "${RBGL_LODES_ROOT}" \
    --arg zjq_tag_sprue    "${RBGC_LODE_TAG_SPRUE}" \
    --arg zjq_tag_vouch    "${RBGC_LODE_TAG_VOUCH}" \
    --arg zjq_trust_grade  "${RBGC_LODE_TRUST_RECORDED}" \
    --arg zjq_vouch_schema "${RBGC_LODE_VOUCH_SCHEMA}" \
    --arg zjq_acquired_by  "${RBGD_MASON_EMAIL}" \
    --arg zjq_stamp        "${z_stamp}" \
    --arg zjq_brand        "${z_brand}" \
    --arg zjq_family       "${z_quay_family}" \
    --arg zjq_version      "${z_version}" \
    --arg zjq_selection    "${z_selection}" \
    --arg zjq_preserved    "${z_preserved}" \
    '{
      _RBGL_GAR_HOST:        $zjq_gar_host,
      _RBGL_GAR_PATH:        $zjq_gar_path,
      _RBGL_LODES_ROOT:      $zjq_lodes_root,
      _RBGL_TAG_SPRUE:       $zjq_tag_sprue,
      _RBGL_TAG_VOUCH:       $zjq_tag_vouch,
      _RBGL_TRUST_GRADE:     $zjq_trust_grade,
      _RBGL_VOUCH_SCHEMA:    $zjq_vouch_schema,
      _RBGL_ACQUIRED_BY:     $zjq_acquired_by,
      _RBGL_LODE_STAMP:      $zjq_stamp,
      _RBGL_PODVM_BRAND:     $zjq_brand,
      _RBGL_PODVM_FAMILY:    $zjq_family,
      _RBGL_PODVM_VERSION:   $zjq_version,
      _RBGL_PODVM_SELECTION: $zjq_selection,
      _RBGL_PODVM_PRESERVED: $zjq_preserved
    }' > "${z_subs_file}" \
    || buc_die "Failed to compose immure substitutions blob"

  zrbld_spine_dispatch \
    "${z_token}" "${RBGD_MASON_EMAIL}" "Immure" "${ZRBFC_BUILD_POLL_CEILING_CAPTURE_HEAVY}" \
    "${z_subs_file}" "${ZRBLD_IMMURE_PREFIX}" \
    "${z_recipe[@]}"
}

######################################################################
# External Functions (rbld_*)

rbld_presage() {
  zrbld_sentinel

  buc_doc_brief "Presage an immure — show what it would capture for one quay family (read-only, no credential or network touch)"
  buc_doc_param "family"  "Quay family — ${RBGC_LODE_BRAND_PODVM_WSL} or ${RBGC_LODE_BRAND_PODVM_NATIVE}"
  buc_doc_param "version" "Optional version tag (e.g. 5.6) — when present, leaves render as full upstream origins"
  buc_doc_shown || return 0

  local -r z_brand="${BUZ_FOLIO:-}"
  test -n "${z_brand}" || buc_die "family argument required (${RBGC_LODE_BRAND_PODVM_WSL} or ${RBGC_LODE_BRAND_PODVM_NATIVE})"
  local -r z_version="${1:-}"

  local z_kind="" z_quay_family="" z_selection=""
  zrbld_immure_resolve_family "${z_brand}"
  buc_info "Presage: immure ${z_brand} -> ${z_quay_family} (kind ${z_kind}), leaves: ${z_selection}"

  local z_leaf=""
  local z_count=0
  for z_leaf in ${z_selection}; do
    z_count=$((z_count + 1))
    if test -n "${z_version}"; then
      buc_info "  would capture: ${z_quay_family}:${z_version} leaf ${z_leaf}"
    else
      buc_info "  would capture leaf: ${z_leaf}"
    fi
  done

  buc_success "Presage complete: immure ${z_brand} would capture ${z_count} leaves into ${RBGL_LODES_ROOT}/${z_kind}<stamp>"
}

rbld_immure() {
  zrbld_sentinel

  buc_doc_brief "Wall in the selected podman-machine disk leaves of one quay family into a Lode (podvm kind, rbi_ld capture)"
  buc_doc_param "family"          "Quay family — ${RBGC_LODE_BRAND_PODVM_WSL} or ${RBGC_LODE_BRAND_PODVM_NATIVE}"
  buc_doc_param "version|--refresh <touchmark>" \
    "Fresh: version tag (e.g. 5.6); Refresh: literal '--refresh' followed by existing touchmark"
  buc_doc_shown || return 0

  # Dirty-tree guard — capture composes its cloud step bodies from the working
  # tree; the Lode's provenance envelope must be the product of committed code.
  bug_require_clean_tree_creed "${RBCC_creed_clean_capture}"

  # BUZ_FOLIO carries the family argument (param1 channel). $1 is either the
  # version (fresh) or the literal '--refresh' (refresh mode) with $2 as the
  # existing touchmark. Refresh reuses the same stamp (no version bump possible);
  # the locked version is derived from any member's rblv_origin in the existing envelope.
  local -r z_brand="${BUZ_FOLIO:-}"
  test -n "${z_brand}" || buc_die "family argument required (${RBGC_LODE_BRAND_PODVM_WSL} or ${RBGC_LODE_BRAND_PODVM_NATIVE})"

  local z_mode="fresh"
  local z_version=""
  local z_stamp=""

  if [ "${1:-}" = "--refresh" ]; then
    z_mode="refresh"
    local -r z_touchmark="${2:-}"
    test -n "${z_touchmark}" || buc_die "touchmark required after --refresh (e.g. vw260610095327)"
    z_stamp="${z_touchmark}"
    buc_info "Immure REFRESH mode: reusing existing Lode ${z_touchmark}"
  else
    z_version="${1:-}"
    test -n "${z_version}" || buc_die "version argument required (e.g. 5.6), or use --refresh <touchmark> for refresh mode"
  fi

  local z_kind="" z_quay_family="" z_selection=""
  zrbld_immure_resolve_family "${z_brand}"
  buc_info "Immure family resolved: ${z_brand} -> ${z_quay_family} (kind ${z_kind}), leaves: ${z_selection}"

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  # Fresh mode: mint a new stamp and compute the preserved substitution (empty — no
  # prior envelope exists). Refresh mode: reuse the existing stamp and compute the
  # present-set from the existing GAR envelope + member tags.
  local z_preserved_members="[]"
  if [ "${z_mode}" = "fresh" ]; then
    # Mint the Lode stamp on the host: <kind-letter><YYMMDDHHMMSS>. The host owns
    # the stamp so the touchmark is known before the build for the capture-file.
    # podvm kind-letters are two characters (vw/vn).
    z_stamp="${z_kind}${BURD_NOW_STAMP:2:6}${BURD_NOW_STAMP:9:6}"
    buc_info "Immure FRESH: ${z_brand} (${z_quay_family}:${z_version}), stamp: ${z_stamp}"
  else
    # Refresh: derive locked version from the existing envelope and compute the
    # present-set (enveloped + orphan members) to pass as _RBGL_PODVM_PRESERVED.
    buc_step "Computing present-set for refresh (reading existing :rbi_vouch envelope)"
    local -r z_vouch_dir="${ZRBLD_IMMURE_PREFIX}refresh_vouch"
    rm -rf "${z_vouch_dir}" || buc_die "Failed to clear refresh vouch scratch dir"
    local -r z_pkg="${RBGL_LODES_ROOT}/${z_stamp}"
    zrbfc_gar_extract_artifact "${z_token}" "${z_pkg}" "${RBGC_LODE_TAG_VOUCH}" "${z_vouch_dir}" \
      || buc_die "No :${RBGC_LODE_TAG_VOUCH} at ${z_pkg} — touchmark not present or not yet vouched"
    local -r z_vouch_json="${z_vouch_dir}/vouch.json"
    test -f "${z_vouch_json}" || buc_die "vouch.json missing in :${RBGC_LODE_TAG_VOUCH} artifact for ${z_stamp}"

    # Derive the locked version from any member's rblv_origin (format "<family>:<version>").
    z_version=$(jq -r '(.rblv_members // [])[0].rblv_origin | split(":")[1] // empty' "${z_vouch_json}") \
      || buc_die "Failed to derive version from existing envelope for ${z_stamp}"
    test -n "${z_version}" || buc_die "Existing envelope carries no rblv_origin in rblv_members — cannot derive version"
    buc_info "Refresh locked to version: ${z_version} (from existing envelope)"
    buc_info "Refresh stamp (reused): ${z_stamp}"

    # Compute the present-set: members already in the existing envelope (preserve verbatim)
    # plus any orphan tags in GAR (tag present but absent from envelope → recover).
    # SOURCE OF TRUTH = the GAR package's member tags (never the envelope alone).
    # Architecture H: the full present-set is passed as ONE substitution to the select step.
    # Ceiling note: worst case 8 members ≈ 2.7 KB < 4000-byte substitution limit (CBh_103).
    # A future widening past ~11 members must fall to in-pool recovery instead.
    local -r z_tags_url="${ZRBFC_GAR_API_BASE}/${ZRBFC_GAR_PACKAGE_BASE}/packages/${z_pkg//\//%2F}/tags?pageSize=1000"
    local -r z_tags_infix="rbld_immure_refresh_tags"
    rbuh_json "GET" "${z_tags_url}" "${z_token}" "${z_tags_infix}"
    rbuh_require_ok "List tags for ${z_stamp}" "${z_tags_infix}"
    local -r z_resp_file="${ZRBUH_PREFIX}${z_tags_infix}${ZRBUH_POSTFIX_JSON}"

    # Versions carry createTime (tags do not); fetch them too and join. An orphan is a
    # tag the crashed run cp'd but never enveloped — recover its digest from the tag's
    # own version reference and its rblv_acquired_at from that version's createTime.
    # Recorded grade attests a digest AT a time, so the time is load-bearing here, not
    # forensic decoration; rblv_capture_build stays null (the crashed build is gone).
    local -r z_versions_url="${ZRBFC_GAR_API_BASE}/${ZRBFC_GAR_PACKAGE_BASE}/packages/${z_pkg//\//%2F}/versions?pageSize=1000"
    local -r z_versions_infix="rbld_immure_refresh_versions"
    rbuh_json "GET" "${z_versions_url}" "${z_token}" "${z_versions_infix}"
    rbuh_require_ok "List versions for ${z_stamp}" "${z_versions_infix}"
    local -r z_versions_file="${ZRBUH_PREFIX}${z_versions_infix}${ZRBUH_POSTFIX_JSON}"

    # Build the preserved-member JSON array (the present-set). Enveloped members ride
    # verbatim (their true per-member times stand); orphan tags are recovered honestly.
    # SOURCE OF TRUTH = the GAR tags, never the envelope alone.
    local -r z_preserved_file="${ZRBLD_IMMURE_PREFIX}preserved.json"
    jq -n \
      --arg sprue "${RBGC_LODE_TAG_SPRUE}" \
      --arg vouch "${RBGC_LODE_TAG_VOUCH}" \
      --arg family "${z_quay_family}" \
      --arg version "${z_version}" \
      --slurpfile tags_resp "${z_resp_file}" \
      --slurpfile vers_resp "${z_versions_file}" \
      --argjson existing_members "$(jq '.rblv_members // []' "${z_vouch_json}")" \
      '
        # sprued non-vouch tags, each carrying its digest (the tag -> version ref)
        ( [ $tags_resp[0].tags[]?
            | { tag: (.name | sub(".*/tags/"; "")),
                digest: ((.version // "") | sub(".*/versions/"; "")) }
            | select(.tag != $vouch and (.tag | startswith($sprue))) ] ) as $gar
        # digest -> createTime
        | ( [ $vers_resp[0].versions[]?
              | { (.name | sub(".*/versions/"; "")): .createTime } ] | add // {} ) as $vtime
        # rblv_name -> existing envelope member
        | ( $existing_members | map({(.rblv_name): .}) | add // {} ) as $env
        | [ $gar[]
            | if $env[.tag] then
                $env[.tag]
              else
                { rblv_name: .tag,
                  rblv_origin: ($family + ":" + $version),
                  rblv_digest: .digest,
                  rblv_verification: "recorded",
                  rblv_tags: [.tag],
                  rblv_acquired_at: ($vtime[.digest] // null),
                  rblv_capture_build: null }
              end ]
      ' > "${z_preserved_file}" \
      || buc_die "Failed to compute present-set for refresh of ${z_stamp}"

    z_preserved_members=$(jq -c '.' "${z_preserved_file}") \
      || buc_die "Failed to compact preserved-member JSON"
    local z_pcount=""
    z_pcount=$(jq 'length' "${z_preserved_file}") \
      || buc_die "Failed to count preserved members"
    buc_info "Present-set computed: ${z_pcount} existing members to preserve/recover"
  fi

  buc_info "Lode: ${RBGL_LODES_ROOT}/${z_stamp}"

  zrbld_immure_submit "${z_token}" "${z_brand}" "${z_quay_family}" "${z_version}" \
    "${z_selection}" "${z_stamp}" "${z_preserved_members}"
  # Shared single-slot extract (rblds_): the select step (step 0) authors the
  # output; the capture, residency, and vouch-push steps write none.
  zrbld_spine_extract_single "${ZRBLD_IMMURE_PREFIX}" "${z_brand}" "Immure"

  buc_success "Immure (${z_mode}) complete: ${z_quay_family}:${z_version} -> ${RBGL_LODES_ROOT}/${z_stamp}"
}

# eof
