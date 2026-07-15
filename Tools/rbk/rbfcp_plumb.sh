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
# Recipe Bottle Foundry Core - plumb cluster (guard-free, sourced by rbfck_):
# render a hallmark's trust posture (full and compact) from its GAR about/vouch
# arks - the rbw-fpf / rbw-fpc surface.

set -euo pipefail

######################################################################
# Plumb (zrbfc_* / rbfc_*)

# Internal: core plumb logic shared by full and compact modes.
# Queries GAR directly via Registry API — no local docker required.
# Authenticates as Retriever. Vessel is resolved from the hallmark's vouch ark.
# Args: hallmark mode
zrbfc_plumb_core() {
  zrbfc_sentinel

  local -r z_express="${1:-}"
  local -r z_mode="${2}"

  # Relay-then-read (RBr_3e7): forward the chain baton before any read or failure point.
  buf_relay || buc_die "Failed to relay chained facts"

  # Resolve the hallmark express-or-chain: an express argument wins; absent, fall
  # back to the hallmark a prior build (ordain or kludge) handed forward through
  # the depth-1 chain — so a no-arg plumb immediately after a build inspects the
  # just-built hallmark.
  local z_hallmark=""
  z_hallmark=$(buf_elect_fact_capture "${z_express}" "${RBF_FACT_HALLMARK}") \
    || buc_reject "${BUBC_band_chain}" "No hallmark — pass one or run a build (ordain/kludge) immediately before plumb"

  buc_step "Resolving vessel from vouch ark"
  local z_vessel=""
  z_vessel=$(rbfc_vessel_for_hallmark_capture "${z_hallmark}") \
    || buc_die "Failed to resolve vessel for hallmark: ${z_hallmark}"
  buc_info "Resolved hallmark to vessel: ${z_vessel}"

  rbfc_require_vessel_sigil "${z_vessel}"

  # Load vessel config (sets RBRV_VESSEL_MODE, RBRV_BIND_IMAGE, etc.)
  local -r z_vessel_dir="${RBRR_VESSEL_DIR}/${z_vessel}"
  zrbfc_load_vessel "${z_vessel_dir}"

  buc_step "Authenticating as Retriever"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_retriever}") \
    || buc_die "Failed to get Retriever OAuth token"

  local -r z_extract="${BURD_TEMP_DIR}/plumb"
  mkdir -p "${z_extract}" || buc_die "Failed to create extraction directory"
  local z_has_about=false
  local z_has_vouch=false

  # Fetch about ark from GAR (tag = hallmark)
  buc_step "Fetching about ark from GAR"
  local -r z_about_pkg="${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_ABOUT}"
  local -r z_about_dir="${BURD_TEMP_DIR}/plumb_about"
  if zrbfc_gar_extract_artifact "${z_token}" "${z_about_pkg}" "${z_hallmark}" "${z_about_dir}"; then
    z_has_about=true
    cp "${z_about_dir}"/* "${z_extract}/" 2>/dev/null || true
  fi

  # Fetch vouch ark for content (vessel resolution already extracted it once above)
  buc_step "Fetching vouch ark from GAR"
  local -r z_vouch_pkg="${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_VOUCH}"
  local -r z_vouch_dir="${BURD_TEMP_DIR}/plumb_vouch"
  if zrbfc_gar_extract_artifact "${z_token}" "${z_vouch_pkg}" "${z_hallmark}" "${z_vouch_dir}"; then
    z_has_vouch=true
    cp "${z_vouch_dir}"/* "${z_extract}/" 2>/dev/null || true
  fi

  # Bind vessels: fallback to static display if no about ark
  if test "${RBRV_VESSEL_MODE}" = "rbnve_bind" && test "${z_has_about}" = "false"; then
    zrbfc_plumb_show_bind "${z_vessel}" "${z_hallmark}" "${z_mode}"
    return 0
  fi

  # Require about ark for non-bind vessels
  if test "${z_has_about}" = "false"; then
    buc_die "About ark not found in GAR: ${z_about_pkg}:${z_hallmark}"
  fi

  # Resolved-base labels (conjure only): read back from the first built
  # platform's attest tag; rivet RBr_b4e.
  if test "${RBRV_VESSEL_MODE}" = "rbnve_conjure" && test -n "${RBRV_CONJURE_PLATFORMS:-}"; then
    buc_step "Reading resolved-base labels from attest image config"
    local z_first_plat="${RBRV_CONJURE_PLATFORMS//,/ }"
    z_first_plat="${z_first_plat%% *}"
    local z_attest_suffix="${z_first_plat#linux/}"
    z_attest_suffix="${z_attest_suffix//\//}"
    local -r z_attest_pkg="${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_ATTEST}"
    local -r z_attest_tag="${z_hallmark}-${z_attest_suffix}"
    zrbfc_image_config_fetch "${z_token}" "${z_attest_pkg}" "${z_attest_tag}" \
      "${z_extract}/attest_config.json" \
      || buc_info "Resolved-base labels not available (attest ${z_attest_tag} absent — pre-resolved-base build?)"
  fi

  # Display results
  if test "${z_mode}" = "compact"; then
    zrbfc_plumb_show_compact "${z_vessel}" "${z_hallmark}" "${z_extract}" "${z_has_vouch}"
  else
    zrbfc_plumb_show_full "${z_vessel}" "${z_hallmark}" "${z_extract}" "${z_has_vouch}"
  fi
}

# Internal: display bind vessel info
# Args: vessel hallmark mode
zrbfc_plumb_show_bind() {
  zrbfc_sentinel

  local -r z_vessel="$1"
  local -r z_hallmark="$2"
  local -r z_mode="$3"

  if test "${z_mode}" = "compact"; then
    echo ""
    echo "=== ${z_vessel} / ${z_hallmark} ==="
    echo "  Type: bind | Trust: digest-pin only"
    test -n "${RBRV_BIND_IMAGE:-}" && echo "  Source: ${RBRV_BIND_IMAGE}"
    echo "  No SLSA provenance, SBOM, or build transcript (not built by GCB)"
    echo ""
    return 0
  fi

  echo ""
  echo "================================================================"
  echo "  HALLMARK PLUMB: ${z_vessel} / ${z_hallmark}"
  echo "================================================================"
  echo ""
  echo "  Vessel type:  BIND (external image pinned by digest)"
  echo "  Trust model:  Digest-pin only"
  echo ""
  test -n "${RBRV_BIND_IMAGE:-}" && echo "  Bind source:  ${RBRV_BIND_IMAGE}"
  echo ""
  echo "  TRUST BOUNDARY"
  echo "  This is a bind vessel. The image was not built by Google Cloud"
  echo "  Build. No SLSA provenance, no SBOM, and no build transcript"
  echo "  exist because GCB did not produce this image."
  echo ""
  echo "  Trust is based solely on digest pinning of a known-good"
  echo "  external image from its source registry."
  echo ""
  echo "================================================================"
  echo ""
}

# Internal: shared section rendering used by both compact and full modes
# Args: extract_dir has_vouch
# Outputs: vessel type, source, builder, SLSA, SBOM summary, vouch results
zrbfc_plumb_show_sections() {
  zrbfc_sentinel

  local -r z_dir="$1"
  local -r z_has_vouch="$2"

  local -r z_bi="${z_dir}/build_info.json"
  local -r z_sbom="${z_dir}/sbom.json"
  local -r z_vs="${z_dir}/vouch_summary.json"
  local -r z_bkmeta="${z_dir}/buildkit_metadata.json"

  # Determine vessel mode from build_info.json
  local z_vessel_mode="rbnve_conjure"
  if test -f "${z_bi}"; then
    local z_mode_raw
    jq -r '.mode // "rbnve_conjure"' "${z_bi}" > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null \
      || echo "rbnve_conjure" > "${ZRBFC_SCRATCH_FILE}"
    z_mode_raw=$(<"${ZRBFC_SCRATCH_FILE}")
    z_vessel_mode="${z_mode_raw}"
  fi

  if test -f "${z_bi}" && test "${z_vessel_mode}" = "rbnve_bind"; then
    # ── Bind vessel sections ──────────────────────────────────────────
    # Batch extract bind fields from build_info.json
    local z_bi_moniker="" z_bi_source_img="" z_bi_mirror_ts="" z_bi_hallmark=""
    local z_bi_image_uri="" z_bi_git_repo="" z_bi_git_branch="" z_bi_git_commit=""
    jq -r '
      (.moniker // "?"),
      (.source.image_ref // "?"),
      (.build.inscribe_timestamp // "?"),
      (.build.hallmark // "?"),
      (.image.uri // "?"),
      (.git.repo // "?"),
      (.git.branch // "?"),
      (.git.commit // "?")
    ' "${z_bi}" > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null || true
    { read -r z_bi_moniker
      read -r z_bi_source_img
      read -r z_bi_mirror_ts
      read -r z_bi_hallmark
      read -r z_bi_image_uri
      read -r z_bi_git_repo
      read -r z_bi_git_branch
      read -r z_bi_git_commit
    } < "${ZRBFC_SCRATCH_FILE}"

    echo ""
    echo "  -- Vessel Type -------------------------------------------------"
    echo "  How this image was produced."
    echo ""
    echo "  Mode:           bind (upstream image mirrored to GAR)"
    echo "  Moniker:        ${z_bi_moniker}"

    echo ""
    echo "  -- Upstream Source -----------------------------------------------"
    echo "  The digest-pinned upstream image that was mirrored."
    echo ""
    echo "  Source image:   ${z_bi_source_img}"
    echo "  Trust model:    digest-pin (image identity is the digest itself)"

    echo ""
    echo "  -- Mirror -------------------------------------------------------"
    echo "  When the image was mirrored from upstream into GAR."
    echo ""
    echo "  Mirror time:    ${z_bi_mirror_ts}"
    echo "  Hallmark:   ${z_bi_hallmark}"
    echo "  Image URI:      ${z_bi_image_uri}"

    echo ""
    echo "  -- Git Context --------------------------------------------------"
    echo "  The repository state when the mirror operation was performed."
    echo ""
    echo "  Repository:     ${z_bi_git_repo}"
    echo "  Branch:         ${z_bi_git_branch}"
    echo "  Commit:         ${z_bi_git_commit}"

    echo ""
    echo "  -- Trust --------------------------------------------------------"
    echo "  Bind vessels are NOT built by Cloud Build. Trust comes from the"
    echo "  digest pin in rbrv.env — the image is exactly the bytes specified."
    echo ""
    echo "  SLSA provenance:  not applicable (no build step)"
    echo "  Verification:     image digest matches the pin in the vessel definition"

  elif test -f "${z_bi}"; then
    # ── Conjure vessel sections ───────────────────────────────────────
    # Batch extract conjure fields from build_info.json
    local z_platform="" z_qemu="" z_cj_moniker=""
    local z_cj_git_repo="" z_cj_git_branch="" z_cj_git_commit=""
    local z_cj_build_id="" z_cj_build_ts="" z_cj_inscribe_ts="" z_cj_image_uri=""
    local z_slsa_level="" z_slsa_invocation="" z_slsa_builder=""
    jq -r '
      (.platform // "unknown"),
      (.qemu_used // "false"),
      (.moniker // "?"),
      (.git.repo // "?"),
      (.git.branch // "?"),
      (.git.commit // "?"),
      (.build.build_id // "?"),
      (.build.timestamp // "?"),
      (.build.inscribe_timestamp // "?"),
      (.image.uri // "?"),
      (.slsa.build_level // "?"),
      (.slsa.build_invocation_id // "?"),
      (.slsa.provenance_builder_id // "?")
    ' "${z_bi}" > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null || true
    { read -r z_platform
      read -r z_qemu
      read -r z_cj_moniker
      read -r z_cj_git_repo
      read -r z_cj_git_branch
      read -r z_cj_git_commit
      read -r z_cj_build_id
      read -r z_cj_build_ts
      read -r z_cj_inscribe_ts
      read -r z_cj_image_uri
      read -r z_slsa_level
      read -r z_slsa_invocation
      read -r z_slsa_builder
    } < "${ZRBFC_SCRATCH_FILE}"

    echo ""
    echo "  -- Vessel Type -------------------------------------------------"
    echo "  How this image was produced and for which CPU architecture."
    echo ""
    echo "  Mode:           conjure (built by Google Cloud Build)"
    local z_strategy="native"
    if test "${z_qemu}" = "true"; then z_strategy="emulated (QEMU)"; fi
    echo "  Platform:       ${z_platform} (host-platform view)"
    echo "  Build strategy: ${z_strategy}"
    echo "  Moniker:        ${z_cj_moniker}"

    echo ""
    echo "  -- Source -------------------------------------------------------"
    echo "  The git repository, branch, and commit that produced this build."
    echo ""
    echo "  Repository:     ${z_cj_git_repo}"
    echo "  Branch:         ${z_cj_git_branch}"
    echo "  Commit:         ${z_cj_git_commit}"

    echo ""
    echo "  -- Builder ------------------------------------------------------"
    echo "  The Cloud Build job that executed this build, with timestamps."
    echo ""
    echo "  Build ID:       ${z_cj_build_id}"
    echo "  Build time:     ${z_cj_build_ts}"
    echo "  Inscribe time:  ${z_cj_inscribe_ts}"
    echo "  Image URI:      ${z_cj_image_uri}"

    echo ""
    echo "  -- SLSA Provenance ----------------------------------------------"
    echo "  Cryptographic proof linking this exact image digest to its build."
    echo ""
    echo "  Build level:    ${z_slsa_level}"
    echo "  Invocation ID:  ${z_slsa_invocation}"
    echo "  Builder ID:     ${z_slsa_builder}"
    echo "  Predicate types:"
    jq -r '.slsa.provenance_predicate_types[]?' "${z_bi}" 2>/dev/null | while IFS= read -r z_pt; do
      echo "                    ${z_pt}"
    done

    echo ""
    echo "  SLSA Build L${z_slsa_level} attests:"
    echo "    + This digest was produced by this Cloud Build invocation"
    echo "    + From this source repo and commit"
    echo "    + On Google's hosted builder (tamper-resistant environment)"
    echo ""
    echo "  SLSA Build L${z_slsa_level} does NOT attest:"
    echo "    - Base image security or supply chain"
    echo "    - Package integrity within the image"
    echo "    - Absence of vulnerabilities"
    echo "    - Correctness or security of the Dockerfile"
  else
    echo ""
    echo "  build_info.json not found in -about artifact"
  fi

  # Base image section — conjure only (bind has no Dockerfile)
  if test "${z_vessel_mode}" != "rbnve_bind"; then
    echo ""
    echo "  -- Base Image ---------------------------------------------------"
    echo "  The upstream image this build started FROM and the OS syft detected."
    echo ""
    local -r z_recipe="${z_dir}/recipe.txt"
    if test -f "${z_recipe}"; then
      local z_from_line=""
      local z_recipe_line
      while IFS= read -r z_recipe_line; do
        case "${z_recipe_line}" in [Ff][Rr][Oo][Mm]\ *) z_from_line="${z_recipe_line}"; break ;; esac
      done < "${z_recipe}" 2>/dev/null
      if test -n "${z_from_line}"; then
        echo "  Dockerfile FROM: ${z_from_line#FROM }"
      fi
    fi
    if test -f "${z_sbom}"; then
      local z_distro_name="" z_distro_ver=""
      jq -r '(.distro.name // empty), (.distro.version // empty)' "${z_sbom}" \
        > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null || true
      { read -r z_distro_name; read -r z_distro_ver; } < "${ZRBFC_SCRATCH_FILE}"
      if test -n "${z_distro_name}"; then
        echo "  Detected distro: ${z_distro_name} ${z_distro_ver}"
      fi
    fi

    # Resolved base (signed); rivet RBr_b4e.
    local -r z_attest_config="${z_dir}/attest_config.json"
    if test -f "${z_attest_config}"; then
      local z_rb_n=""
      local z_rb_val=""
      local z_rb_any="false"
      local z_rb_stderr=""
      for z_rb_n in 1 2 3; do
        # (.config.Labels // {}) tolerates an image with no labels (null) in-jq, so
        # only a malformed config or a jq fault reaches the guard. buc_warn (not
        # buc_die) is deliberate: plumb is a read-only trust-posture display, and a
        # single unreadable optional label must not abort a report already in flight.
        z_rb_stderr="${BURD_TEMP_DIR}/plumb_resolved_base_${z_rb_n}_stderr.txt"
        jq -r --arg k "${RBGC_IMAGE_LABEL_RESOLVED_BASE}_${z_rb_n}" \
          '(.config.Labels // {})[$k] // empty' "${z_attest_config}" \
          > "${ZRBFC_SCRATCH_FILE}" 2>"${z_rb_stderr}" \
          || buc_warn "Could not read ${RBGC_IMAGE_LABEL_RESOLVED_BASE}_${z_rb_n} from attest config — see ${z_rb_stderr}"
        z_rb_val=$(<"${ZRBFC_SCRATCH_FILE}")
        if test -n "${z_rb_val}"; then
          echo "  Resolved base ${z_rb_n} (signed): ${z_rb_val}"
          z_rb_any="true"
        fi
      done
      if test "${z_rb_any}" = "false"; then
        echo "  Resolved base:   (no rbi_resolved_base_n labels — pre-resolved-base build)"
      fi
    fi
  fi

  # Build output — conjure only (bind has no buildx step)
  if test "${z_vessel_mode}" != "rbnve_bind" && test -f "${z_bkmeta}"; then
    echo ""
    echo "  -- Build Output -------------------------------------------------"
    echo "  The container image manifest produced by this buildx invocation."
    echo ""
    local z_bk_digest="" z_bk_mediatype="" z_bk_ref="" z_bk_imgname=""
    jq -r '
      (."containerimage.digest" // ""),
      (."containerimage.descriptor".mediaType // ""),
      (."buildx.build.ref" // ""),
      (."image.name" // "")
    ' "${z_bkmeta}" > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null || true
    { read -r z_bk_digest
      read -r z_bk_mediatype
      read -r z_bk_ref
      read -r z_bk_imgname
    } < "${ZRBFC_SCRATCH_FILE}"
    test -n "${z_bk_digest}"    && echo "  Output digest:  ${z_bk_digest}"
    test -n "${z_bk_mediatype}" && echo "  Media type:     ${z_bk_mediatype}"
    test -n "${z_bk_ref}"       && echo "  Build ref:      ${z_bk_ref}"
    test -n "${z_bk_imgname}"   && echo "  Image name:     ${z_bk_imgname}"
    # Per-platform digests if present
    local z_bk_platforms=""
    jq -r 'keys[] | select(contains("/"))' "${z_bkmeta}" > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null || true
    z_bk_platforms=$(<"${ZRBFC_SCRATCH_FILE}")
    if test -n "${z_bk_platforms}"; then
      echo "  Per-platform digests:"
      local z_bk_plat=""
      local z_bk_pd=""
      while IFS= read -r z_bk_plat; do
        jq -r --arg p "${z_bk_plat}" '.[$p]["containerimage.digest"] // empty' "${z_bkmeta}" \
          > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null || true
        z_bk_pd=$(<"${ZRBFC_SCRATCH_FILE}")
        test -n "${z_bk_pd}" && echo "    ${z_bk_plat}: ${z_bk_pd}"
      done <<< "${z_bk_platforms}"
    fi
  fi

  # Build cache delta — conjure only
  if test "${z_vessel_mode}" != "rbnve_bind"; then
    local -r z_cache_before="${z_dir}/cache_before.json"
    local -r z_cache_after="${z_dir}/cache_after.json"
    if test -f "${z_cache_after}"; then
      echo ""
      echo "  -- Build Cache Delta --------------------------------------------"
      echo "  Images on the Cloud Build worker after vs before this build."
      echo ""
      local z_before_count="n/a"
      local z_after_count=""
      if test -f "${z_cache_before}"; then
        jq '.host_daemon_images | length' "${z_cache_before}" > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null \
          || echo "?" > "${ZRBFC_SCRATCH_FILE}"
        z_before_count=$(<"${ZRBFC_SCRATCH_FILE}")
      fi
      jq '.host_daemon_images | length' "${z_cache_after}" > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null \
        || echo "?" > "${ZRBFC_SCRATCH_FILE}"
      z_after_count=$(<"${ZRBFC_SCRATCH_FILE}")
      echo "  Images before: ${z_before_count}"
      echo "  Images after:  ${z_after_count}"
      if test -f "${z_cache_before}"; then
        local z_new_images=""
        jq -r --slurpfile before "${z_cache_before}" '
          ($before[0].host_daemon_images // [] | map(.ID) | unique) as $before_ids |
          [(.host_daemon_images // [])[] |
           select(.ID as $id | $before_ids | index($id) | not)] |
          group_by(.ID) |
          map(.[0] |
            (if (.Repository | split("/") | length) > 2 then
              (.Repository | split("/") | .[-1])
            else .Repository end) as $short |
            [$short, .Tag, .Size, .ID[7:19]] | @tsv) |
          .[]
        ' "${z_cache_after}" > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null || true
        z_new_images=$(<"${ZRBFC_SCRATCH_FILE}")
        if test -n "${z_new_images}"; then
          local z_new_count=0
          local z_count_line=""
          while IFS= read -r z_count_line; do
            z_new_count=$((z_new_count + 1))
          done <<< "${z_new_images}"
          echo ""
          echo "  New images (${z_new_count} unique):"
          printf '%s\n' "${z_new_images}" | while IFS=$'\t' read -r z_repo z_tag z_size z_id; do
            echo "    ${z_id}  ${z_repo}:${z_tag}  ${z_size}"
          done
        else
          echo "  No new images (cache unchanged)"
        fi
      fi
    fi
  fi

  # SBOM — present for both bind and conjure (if syft was available)
  echo ""
  echo "  -- SBOM Summary (syft) ------------------------------------------"
  echo "  Software bill of materials: every package syft found installed."
  echo ""
  if test -f "${z_sbom}"; then
    local z_pkg_count=""
    jq '.artifacts | length' "${z_sbom}" > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null \
      || echo "?" > "${ZRBFC_SCRATCH_FILE}"
    z_pkg_count=$(<"${ZRBFC_SCRATCH_FILE}")
    echo "  Package count:  ${z_pkg_count}"

    echo "  Package types:"
    jq -r '
      [.artifacts[]?.type // empty] | group_by(.) |
      map({type: .[0], count: length}) |
      sort_by(-.count)[] |
      "    \(.count)\t\(.type)"
    ' "${z_sbom}" 2>/dev/null || echo "    (unable to parse)"

    echo ""
    echo "  Syft inventories installed packages. This is not a security"
    echo "  assessment, vulnerability scan, or license audit."
  else
    echo "  sbom.json not found in -about artifact"
  fi

  # Vouch — branched by vessel mode
  echo ""
  echo "  -- Vouch Results ------------------------------------------------"
  if test "${z_vessel_mode}" = "rbnve_bind"; then
    echo "  Bind verification: was the mirrored image verified against its digest pin?"
    echo ""
    if test "${z_has_vouch}" = "true" && test -f "${z_vs}"; then
      local z_vf_method="" z_vf_result="" z_vf_pin="" z_vf_gar=""
      local z_vf_match="" z_vf_ts="" z_vf_source=""
      jq -r '
        (.verification.method // "?"),
        (.verification.result // .verification.verdict // "?"),
        (.verification.pin_digest // .verification.pinned_digest // "?"),
        (.verification.gar_digest // .verification.actual_digest // "?"),
        (.verification.digest_match // "?"),
        (.verification.timestamp // "?"),
        (.verification.source_image // .verification.bind_source // "?")
      ' "${z_vs}" > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null || true
      { read -r z_vf_method
        read -r z_vf_result
        read -r z_vf_pin
        read -r z_vf_gar
        read -r z_vf_match
        read -r z_vf_ts
        read -r z_vf_source
      } < "${ZRBFC_SCRATCH_FILE}"
      echo "  Method:      ${z_vf_method}"
      echo "  Verdict:     ${z_vf_result}"
      echo "  Pin digest:  ${z_vf_pin}"
      echo "  GAR digest:  ${z_vf_gar}"
      echo "  Match:       ${z_vf_match}"
      echo "  Timestamp:   ${z_vf_ts}"
      echo "  Source:      ${z_vf_source}"
    else
      echo "  Vouch artifact not found in GAR"
    fi
  elif test "${z_vessel_mode}" = "rbnve_graft"; then
    echo "  Graft acknowledgment: no provenance chain — GRAFTED verdict"
    echo ""
    if test "${z_has_vouch}" = "true" && test -f "${z_vs}"; then
      local z_gf_verdict="" z_gf_source="" z_gf_method=""
      jq -r '
        (.verification.verdict // "?"),
        (.verification.graft_source // "?"),
        (.verification.method // "?")
      ' "${z_vs}" > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null || true
      { read -r z_gf_verdict
        read -r z_gf_source
        read -r z_gf_method
      } < "${ZRBFC_SCRATCH_FILE}"
      echo "  Verdict:     ${z_gf_verdict}"
      echo "  Method:      ${z_gf_method}"
      echo "  Source:      ${z_gf_source}"
    else
      echo "  Vouch artifact not found in GAR"
    fi
  else
    echo "  Independent SLSA verification: did this image pass provenance checks?"
    echo ""
    if test "${z_has_vouch}" = "true" && test -f "${z_vs}"; then
      local z_verifier_url="" z_verifier_sha=""
      jq -r '(.verifier.url // "?"), (.verifier.sha256 // "?")' "${z_vs}" \
        > "${ZRBFC_SCRATCH_FILE}" 2>/dev/null || true
      { read -r z_verifier_url; read -r z_verifier_sha; } < "${ZRBFC_SCRATCH_FILE}"
      echo "  Verifier:"
      echo "    URL:    ${z_verifier_url}"
      echo "    SHA256: ${z_verifier_sha}"
      echo ""
      echo "  Per-platform verdicts:"
      jq -r '.platforms[]? | "    \(.platform): \(.verdict)"' "${z_vs}" 2>/dev/null \
        || echo "    (unable to parse)"
    else
      echo "  Vouch artifact not found in GAR"
    fi
  fi
}

# Internal: display compact vessel info (conjure or bind)
# Args: vessel hallmark extract_dir has_vouch
zrbfc_plumb_show_compact() {
  zrbfc_sentinel

  local -r z_vessel="$1"
  local -r z_hallmark="$2"
  local -r z_dir="$3"
  local -r z_has_vouch="$4"

  echo ""
  echo "================================================================"
  echo "  HALLMARK PLUMB: ${z_vessel} / ${z_hallmark}"
  echo "================================================================"

  zrbfc_plumb_show_sections "${z_dir}" "${z_has_vouch}"

  echo ""
  echo "================================================================"
  echo ""
}

# Internal: display full vessel info (conjure or bind)
# Adds per-package inventory and Dockerfile (conjure only) to the compact sections.
# Args: vessel hallmark extract_dir has_vouch
zrbfc_plumb_show_full() {
  zrbfc_sentinel

  local -r z_vessel="$1"
  local -r z_hallmark="$2"
  local -r z_dir="$3"
  local -r z_has_vouch="$4"

  local -r z_sbom="${z_dir}/sbom.json"

  echo ""
  echo "================================================================"
  echo "  HALLMARK PLUMB (FULL): ${z_vessel} / ${z_hallmark}"
  echo "================================================================"

  zrbfc_plumb_show_sections "${z_dir}" "${z_has_vouch}"

  echo ""
  echo "  -- Package Inventory --------------------------------------------"
  echo "  Every package syft detected, sorted by ecosystem type."
  echo ""
  if test -f "${z_sbom}"; then
    printf "    %-12s %-36s %s\n" "TYPE" "NAME" "VERSION"
    printf "    %-12s %-36s %s\n" "----" "----" "-------"
    jq -r '
      .artifacts[]? |
      [.type // "?", .name // "?", .version // "?"] |
      @tsv
    ' "${z_sbom}" 2>/dev/null | sort | while IFS=$'\t' read -r z_type z_name z_ver; do
      printf "    %-12s %-36s %s\n" "${z_type}" "${z_name}" "${z_ver}"
    done
  else
    echo "    sbom.json not found in -about artifact"
  fi

  echo ""
  echo "  -- Package Licensing & Identity ---------------------------------"
  echo "  License and Package URL for each package (for compliance review)."
  echo ""
  if test -f "${z_sbom}"; then
    printf "    %-36s %-20s %s\n" "NAME" "LICENSE" "PURL"
    printf "    %-36s %-20s %s\n" "----" "-------" "----"
    jq -r '
      .artifacts[]? |
      [
        (.name // "?"),
        ((.licenses // []) | map(.value // .expression // empty) | join(", ") | if . == "" then "-" else . end),
        (.purl // "-")
      ] |
      @tsv
    ' "${z_sbom}" 2>/dev/null | sort | while IFS=$'\t' read -r z_name z_lic z_purl; do
      printf "    %-36s %-20s %s\n" "${z_name}" "${z_lic}" "${z_purl}"
    done
  else
    echo "    sbom.json not found in -about artifact"
  fi

  local -r z_recipe="${z_dir}/recipe.txt"
  if test -f "${z_recipe}"; then
    echo ""
    echo "  -- Recipe (Dockerfile) ------------------------------------------"
    echo "  The exact Dockerfile used to build this image."
    echo ""
    while IFS= read -r z_line; do
      echo "    ${z_line}"
    done < "${z_recipe}"
  fi

  echo ""
  echo "================================================================"
  echo ""
}

rbfc_plumb_full() {
  zrbfc_sentinel

  local -r z_express="${BUZ_FOLIO:-}"

  buc_doc_brief "Plumb a hallmark's trust posture (full detail)"
  buc_doc_param "hallmark" "Full hallmark (e.g., c260305133650-r260305160530); optional — absent, falls back to the hallmark the prior build chained forward"
  buc_doc_shown || return 0

  zrbfc_plumb_core "${z_express}" "full"
}

rbfc_plumb_compact() {
  zrbfc_sentinel

  local -r z_express="${BUZ_FOLIO:-}"

  buc_doc_brief "Plumb a hallmark's trust posture (compact summary)"
  buc_doc_param "hallmark" "Full hallmark (e.g., c260305133650-r260305160530); optional — absent, falls back to the hallmark the prior build chained forward"
  buc_doc_shown || return 0

  zrbfc_plumb_core "${z_express}" "compact"
}

# eof
