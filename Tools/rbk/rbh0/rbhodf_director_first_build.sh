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
# Recipe Bottle Handbook Onboarding - Director First Cloud Build

set -euo pipefail

test -z "${ZRBHODF_SOURCED:-}" || return 0
ZRBHODF_SOURCED=1

rbho_director_first_build() {
  zrbho_sentinel

  buc_doc_brief "${RBHO_TRACK_FIRST_BUILD} — conclave, conjure, tour, summon, abjure"
  buc_doc_shown || return 0

  local -r z_vessel="rbev-sentry-deb-tether"

  local z_has_depot=0
  if test -f "${RBCC_rbrd_file}"; then
    local z_line=""
    while IFS= read -r z_line; do
      case "${z_line}" in RBRD_DEPOT_MONIKER=?*) z_has_depot=1; break ;; esac
    done < "${RBCC_rbrd_file}"
  fi

  local z_conjure_summoned=0
  if command -v docker >/dev/null 2>&1; then
    local z_project_id=""
    local z_region=""
    if test -f "${RBCC_rbrd_file}"; then
      z_project_id=$(zrbho_po_extract_capture "${RBCC_rbrd_file}" "RBRD_DEPOT_MONIKER") || z_project_id=""
      z_region=$(zrbho_po_extract_capture "${RBCC_rbrd_file}" "RBRD_GCP_REGION") || z_region=""
    fi
    if test -n "${z_region}" && test -n "${z_project_id}"; then
      local -r z_gar_prefix="${z_region}${RBGC_GAR_HOST_SUFFIX}/${z_project_id}/"
      local -r z_df_out="${ZRBHO_DOCKER_IMAGES_PREFIX}5_repotag.txt"
      local -r z_df_err="${ZRBHO_DOCKER_STDERR_PREFIX}7_repotag.txt"
      if docker images --format "{{.Repository}}:{{.Tag}}" \
           > "${z_df_out}" 2>"${z_df_err}"; then
        local z_line=""
        while IFS= read -r z_line || test -n "${z_line}"; do
          case "${z_line}" in
            "${z_gar_prefix}"*"${z_vessel}:c"[0-9]*) z_conjure_summoned=1; break ;;
          esac
        done < "${z_df_out}"
      fi
    fi
  fi

  buyy_link_yawp "${RBRR_PUBLIC_DOCS_URL}" "Vessel" "${z_vessel}"; local -r z_lk_vessel_name="${z_buym_yelp}"

  buh_section "${RBHO_TRACK_FIRST_BUILD}"
  buh_e
  buh_line "This track walks you through the complete ${RBYC_CONJURE} lifecycle:"
  buh_line "provision the builder toolchain, ${RBYC_ORDAIN} your first ${RBYC_VESSEL} via"
  buh_line "Cloud Build, inspect the result, pull it locally, and clean up."
  buh_e
  buh_line "You will build ${z_lk_vessel_name} — the same ${RBYC_SENTRY} you"
  buh_line "already know from the ${RBYC_CRUCIBLE} track, but this time built by"
  buh_line "Google Cloud Build with full SLSA ${RBYC_PROVENANCE}."
  buh_e

  buh_line "Prerequisites (live probes of this machine — [*] holds, [ ] needs action):"
  buh_e
  if test "${z_has_depot}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${RBYC_DEPOT} configured (RBRD_DEPOT_MONIKER populated)"
  else
    buh_line "${RBYC_PROBE_NO}${RBYC_DEPOT} not configured — the ${RBYC_PAYOR} must establish the ${RBYC_DEPOT}:"
    buh_tt "      " "${RBZ_ONBOARD_PAYOR_HB}"
  fi
  buh_e

  if test "${z_has_depot}" = "0"; then
    buh_error "Complete the prerequisites above before continuing."
    buh_e
    buh_tt "Return to start: " "${RBZ_ONBOARD_START_HERE}"
    buh_e
    return 0
  fi

  buh_line "Configure this handbook session:"
  buh_e
  buh_code "   export ${RBYC_HANDBOOK_VESSEL_NAME}=${z_vessel}"
  buh_e
  buh_line "This sets the ${RBYC_VESSEL} you will build throughout the track."
  buh_line "The remaining steps reference it by name."
  buh_e

  buh_step_style "Step " " — "

  buh_step1 "Conclave the ${RBYC_RELIQUARY}"
  buh_e
  buh_line "The ${RBYC_RELIQUARY} is a set of six builder tool images (gcloud,"
  buh_line "docker, alpine, syft, binfmt, gcrane) that Cloud Build uses during"
  buh_line "${RBYC_VESSEL} construction. Without it, the ${RBYC_CONJURE} preflight"
  buh_line "check fails."
  buh_e
  buh_line "Think of it as installing the toolchain before your first build."
  buh_line "This is a one-time operation — once conclaved, the ${RBYC_RELIQUARY}"
  buh_line "stays in the ${RBYC_DEPOT} until you choose to refresh it."
  buh_e
  buh_line "Periodically re-conclave to pick up newer tool versions. All ${RBYC_VESSELS}"
  buh_line "share the same ${RBYC_RELIQUARY} — one conclave updates the toolchain"
  buh_line "for every build."
  buh_e
  buh_line "If you have uncommitted changes, commit them first — capture and"
  buh_line "build commands refuse on a dirty working tree, so every artifact"
  buh_line "traces to a committed state."
  buh_e
  buh_line "Conclave:"
  buh_e
  buh_tt "   " "${RBZ_CONCLAVE_RELIQUARY}"
  buh_e
  buh_line "This captures the tool images from upstream into the ${RBYC_DEPOT}'s"
  buh_line "GAR namespace (Google Artifact Registry — where the ${RBYC_DEPOT} stores"
  buh_line "all its images). Takes 2-5 minutes depending on network speed."
  buh_e
  buyy_cmd_yawp "r260324193326";                   local -r z_ds_example="${z_buym_yelp}"
  buh_line "When conclave completes, it prints a ${RBYC_RELIQUARY} touchmark"
  buh_line "(e.g., ${z_ds_example}). Yoke wildcard-fans that touchmark into every"
  buh_line "${RBYC_VESSEL}'s ${RBYC_REGIME} under \${RBRR_VESSEL_DIR} in one pass —"
  buh_line "there is no per-vessel argument:"
  buh_e
  buh_tt "   " "${RBZ_YOKE_RELIQUARY}" "" " <touchmark>"
  buh_e
  buh_line "Yoke validates the touchmark once against GAR, then rewrites RBRV_RELIQUARY"
  buh_line "in every ${RBYC_VESSEL}'s rbrv.env. Commit the changes — ${RBYC_ORDAIN}"
  buh_line "refuses to build from an uncommitted tree."
  buh_e
  buh_line "Reminder: yoking links the new ${RBYC_RELIQUARY} into the ${RBYC_VESSEL}"
  buh_line "${RBYC_REGIME}, but existing ${RBYC_VESSEL} images still embed the old tool"
  buh_line "versions until you rebuild them via ${RBYC_ORDAIN}."
  buh_e

  buh_step1 "${RBYC_CONJURE} the ${RBYC_SENTRY}"
  buh_e
  buh_line "${RBYC_CONJURE} is the build mode where Cloud Build constructs a"
  buh_line "${RBYC_VESSEL} image from the project's Dockerfile and build context."
  buh_e
  buh_line "${RBYC_ORDAIN} is the command that triggers the full pipeline —"
  buh_line "it reads the ${RBYC_VESSEL} ${RBYC_RBRV} ${RBYC_REGIME} to determine the mode"
  buh_line "(${RBYC_CONJURE}, ${RBYC_BIND}, or ${RBYC_GRAFT}) and acts accordingly."
  buh_line "To see which mode a ${RBYC_VESSEL} is in, render its ${RBYC_REGIME}:"
  buh_e
  buh_tt "   " "${RBZ_RENDER_VESSEL}" "" " ${RBYC_HANDBOOK_VESSEL_REF}"
  buh_e
  buh_line "Trigger the build:"
  buh_e
  buh_tt "   " "${RBZ_ORDAIN_HALLMARK}" "" " ${RBYC_HANDBOOK_VESSEL_REF}"
  buh_e
  buh_line "This builds on the ${RBYC_TETHERED} pool — Cloud Build has"
  buh_line "public internet access and pulls base images from upstream"
  buh_line "registries during the build. (The ${RBYC_AIRGAP} track removes"
  buh_line "that dependency.)"
  buh_e
  buh_line "The pipeline:"
  buh_e
  buh_line "  1. The host mints a ${RBYC_HALLMARK} — a timestamped tag"
  buh_line "     identifying this build"
  buh_line "  2. A ${RBYC_POUCH} (build context archive) is pushed to GAR"
  buh_line "  3. Cloud Build constructs the image across platforms"
  buh_line "  4. SLSA ${RBYC_PROVENANCE} is generated per platform digest"
  buh_line "  5. ${RBYC_VOUCH} verifies the ${RBYC_PROVENANCE} chain"
  buh_e
  buh_warn "Wall-clock: ~15-20 minutes for a 3-platform build."
  buh_line "The command blocks until Cloud Build finishes. Use the time"
  buh_line "to read ahead — the next steps explain what to look for."
  buh_e
  buh_line "While it runs, a status line ticks every few seconds — QUEUED,"
  buh_line "then WORKING, then SUCCESS, once per build phase. Success runs"
  buh_line "${RBYC_VOUCH} automatically and ends with 'Vouch complete' plus a"
  buh_line "'This hallmark feeds:' roster of follow-on commands, each shown"
  buh_line "with your new ${RBYC_HALLMARK} already filled in."
  buh_e
  buh_line "On failure, the command stops with a red ERROR naming the phase"
  buh_line "and its Cloud Build status. Follow the 'Open build in Cloud"
  buh_line "Console' link printed at submission to read the build log, fix,"
  buh_line "and re-run ${RBYC_ORDAIN} — each run mints a fresh ${RBYC_HALLMARK}, so a"
  buh_line "failed attempt never blocks the next."
  buh_e

  buh_step1 "Capture the ${RBYC_HALLMARK}"
  buh_e
  buh_line "When ${RBYC_ORDAIN} completes, it writes the ${RBYC_HALLMARK}"
  buh_line "to the ${RBYC_OUTPUT} directory — a fixed-path staging area"
  buh_line "that each ${RBYC_TABTARGET} clears and recreates on entry."
  buh_line "Read the ${RBYC_HALLMARK} from the fact file and export it so"
  buh_line "you can copy-paste the commands in the remaining steps:"
  buh_e
  buh_code "   export ${RBYC_HANDBOOK_HALLMARK_NAME}=\$(cat ${BURD_OUTPUT_DIR}/${RBF_FACT_HALLMARK})"
  buh_e

  buh_step1 "Tour the ${RBYC_HALLMARK} artifacts"
  buh_e
  buh_line "Every ${RBYC_CONJURED} ${RBYC_HALLMARK} produces a set of arks"
  buh_line "in GAR under ${RBGC_GAR_CATEGORY_HALLMARKS}/{hallmark}/. Each basename serves a specific role:"
  buh_e
  buyy_cmd_yawp "${RBGC_GAR_CATEGORY_HALLMARKS}/{hallmark}/${RBGC_ARK_BASENAME_POUCH}:{hallmark}";        local -r z_sfx_pouch="${z_buym_yelp}"
  buyy_cmd_yawp "${RBGC_GAR_CATEGORY_HALLMARKS}/{hallmark}/${RBGC_ARK_BASENAME_IMAGE}:{hallmark}";        local -r z_sfx_image="${z_buym_yelp}"
  buyy_cmd_yawp "${RBGC_GAR_CATEGORY_HALLMARKS}/{hallmark}/${RBGC_ARK_BASENAME_ATTEST}:{hallmark}-{arch}"; local -r z_sfx_attest="${z_buym_yelp}"
  buyy_cmd_yawp "${RBGC_GAR_CATEGORY_HALLMARKS}/{hallmark}/${RBGC_ARK_BASENAME_ABOUT}:{hallmark}";        local -r z_sfx_about="${z_buym_yelp}"
  buyy_cmd_yawp "${RBGC_GAR_CATEGORY_HALLMARKS}/{hallmark}/${RBGC_ARK_BASENAME_VOUCH}:{hallmark}";        local -r z_sfx_vouch="${z_buym_yelp}"
  buyy_cmd_yawp "${RBGC_GAR_CATEGORY_HALLMARKS}/{hallmark}/${RBGC_ARK_BASENAME_DIAGS}:{hallmark}";        local -r z_sfx_diags="${z_buym_yelp}"
  buh_line "   ${z_sfx_pouch}"
  buh_line "      A FROM SCRATCH OCI image pushed from host to GAR before"
  buh_line "      the build. Contains the Dockerfile, scripts, and"
  buh_line "      configuration Cloud Build needs. Identical for ${RBYC_TETHERED}"
  buh_line "      and ${RBYC_AIRGAP} builds — the pool determines network"
  buh_line "      access, not the ${RBYC_POUCH}."
  buh_e
  buh_line "   ${z_sfx_image}"
  buh_line "      The consumer image — a multiplatform manifest list."
  buh_line "      This is what you pull and run."
  buh_e
  buh_line "   ${z_sfx_attest}"
  buh_line "      Per-platform ${RBYC_PROVENANCE}-carrying image (one per platform)."
  buh_line "      Shares all layers with -image — only the manifest differs."
  buh_line "      These carry the GCB-attested digests used by ${RBYC_VOUCH} —"
  buh_line "      and they are the only arks that do: the classic Docker image"
  buh_line "      store re-serializes manifests, so a pulled image's digest no"
  buh_line "      longer matches what GCB attested. Durable — they persist"
  buh_line "      alongside the other arks until ${RBYC_ABJURE} deletes the ${RBYC_HALLMARK}."
  buh_e
  buh_line "   ${z_sfx_about}"
  buh_line "      ${RBYC_SBOM} (software bill of materials) + build info."
  buh_e
  buh_line "   ${z_sfx_vouch}"
  buh_line "      SLSA ${RBYC_PROVENANCE} verification record."
  buh_e
  buh_line "   ${z_sfx_diags}"
  buh_line "      Diagnostics from the build."
  buh_e
  buh_line "Inspect them:"
  buh_e

  buh_step2 "${RBYC_TALLY}"
  buh_e
  buh_line "${RBYC_TALLY} lists all ${RBYC_HALLMARKS} and their health state:"
  buh_e
  buh_tt "   " "${RBZ_TALLY_HALLMARKS}"
  buh_e
  buh_line "Look for your ${RBYC_HALLMARK} with health state 'vouched' — that"
  buh_line "means SLSA ${RBYC_PROVENANCE} was verified."
  buh_e

  buh_step2 "${RBYC_VOUCH}"
  buh_e
  buh_line "${RBYC_VOUCH} verifies SLSA ${RBYC_PROVENANCE} for each platform"
  buh_line "digest in the ${RBYC_HALLMARK}. The ${RBYC_ORDAIN} pipeline runs ${RBYC_VOUCH}"
  buh_line "automatically. If a build was interrupted before ${RBYC_VOUCH}"
  buh_line "completed, run this to reattempt ${RBYC_VOUCH} on untreated ${RBYC_HALLMARKS}:"
  buh_e
  buh_tt "   " "${RBZ_VOUCH_HALLMARKS}"
  buh_e
  buh_line "The ${RBYC_CONJURE} verdict is full SLSA — Cloud Build produced"
  buh_line "this image, and the ${RBYC_PROVENANCE} chain proves it."
  buh_e

  buh_step2 "${RBYC_PLUMB}"
  buh_e
  buh_line "${RBYC_PLUMB} displays the ${RBYC_SBOM}, build info, and Dockerfile"
  buh_line "that produced the ${RBYC_HALLMARK}. Two modes:"
  buh_e
  buh_tt "   " "${RBZ_PLUMB_FULL}" "" " ${RBYC_HANDBOOK_VESSEL_REF} ${RBYC_HANDBOOK_HALLMARK_REF}"
  buh_line "   Full ${RBYC_PROVENANCE} display — ${RBYC_SBOM} packages, build parameters,"
  buh_line "   Dockerfile content."
  buh_e
  buh_tt "   " "${RBZ_PLUMB_COMPACT}" "" " ${RBYC_HANDBOOK_VESSEL_REF} ${RBYC_HANDBOOK_HALLMARK_REF}"
  buh_line "   Compact summary — one-line-per-artifact overview."
  buh_e

  buh_step1 "${RBYC_SUMMON} the ${RBYC_HALLMARK}"
  buh_e
  buh_line "${RBYC_SUMMON} pulls a set of images affiliated with a"
  buh_line "${RBYC_HALLMARK} that has been ${RBYC_VOUCHED} to your local"
  buh_line "Docker image cache:"
  buh_e
  buh_tt "   " "${RBZ_SUMMON_HALLMARK}" "" " ${RBYC_HANDBOOK_VESSEL_REF} ${RBYC_HANDBOOK_HALLMARK_REF}"
  buh_e
  buyy_cmd_yawp "${RBGC_GAR_CATEGORY_HALLMARKS}/{hallmark}/${RBGC_ARK_BASENAME_IMAGE}:{hallmark}"; local -r z_sfx_img2="${z_buym_yelp}"
  buh_line "   ${z_sfx_img2}"
  buh_line "   is a multiplatform manifest list."
  buh_line "   Docker resolves it to the image matching your host"
  buh_line "   architecture — the same image that ${RBYC_CHARGE} uses when"
  buh_line "   starting a ${RBYC_CRUCIBLE} from cloud-built ${RBYC_HALLMARKS}."
  buh_e

  if test "${z_conjure_summoned}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${RBYC_CONJURED} ${RBYC_SENTRY} image found locally (via ${RBYC_SUMMON})"
  else
    buh_line "${RBYC_PROBE_NO}No ${RBYC_CONJURED} ${RBYC_SENTRY} image found locally — run ${RBYC_SUMMON} above"
  fi
  buh_e

  buh_step1 "${RBYC_ABJURE} and ${RBYC_REKON} — ${RBYC_HALLMARK} lifecycle"
  buh_e
  buh_line "${RBYC_REKON} lists the ark basenames present under a"
  buh_line "${RBYC_HALLMARK}'s GAR subtree. Run it before and after ${RBYC_ABJURE}"
  buh_line "to see the full lifecycle:"
  buh_e
  buh_tt "   " "${RBZ_REKON_HALLMARK}" "" " ${RBYC_HANDBOOK_HALLMARK_REF}"
  buh_e
  buh_line "You should see all six durable arks for your ${RBYC_HALLMARK}:"
  buyy_cmd_yawp "${RBGC_ARK_BASENAME_POUCH}, ${RBGC_ARK_BASENAME_IMAGE}, ${RBGC_ARK_BASENAME_ATTEST}, ${RBGC_ARK_BASENAME_ABOUT}, ${RBGC_ARK_BASENAME_VOUCH}, ${RBGC_ARK_BASENAME_DIAGS}"; local -r z_sfx_list="${z_buym_yelp}"
  buh_line "   ${z_sfx_list}"
  buh_e
  buh_line "${RBYC_ABJURE} removes all artifacts for a ${RBYC_HALLMARK}"
  buh_line "from GAR. This is permanent — the ${RBYC_HALLMARK} and all its"
  buh_line "tags are deleted:"
  buh_e
  buh_tt "   " "${RBZ_ABJURE_HALLMARK}" "" " ${RBYC_HANDBOOK_VESSEL_REF} ${RBYC_HANDBOOK_HALLMARK_REF}"
  buh_e
  buh_line "After ${RBYC_ABJURE}, run ${RBYC_REKON} again:"
  buh_e
  buh_tt "   " "${RBZ_REKON_HALLMARK}" "" " ${RBYC_HANDBOOK_HALLMARK_REF}"
  buh_e
  buh_line "The tags for your ${RBYC_HALLMARK} should be gone. The image is no"
  buh_line "longer in the ${RBYC_DEPOT}."
  buh_e

  buh_step1 "The pattern"
  buh_e
  buh_line "Every ${RBYC_CONJURED} ${RBYC_HALLMARK} is a structured bundle of six arks in"
  buh_line "GAR under ${RBGC_GAR_CATEGORY_HALLMARKS}/{hallmark}/. Know the six basenames"
  buh_line "and you can tour any ${RBYC_HALLMARK} by hand."
  buh_e
  buh_line "   ${RBGC_ARK_BASENAME_POUCH}    build context pushed to GAR before the build"
  buh_line "   ${RBGC_ARK_BASENAME_IMAGE}    consumer multiplatform manifest — what you pull and run"
  buh_line "   ${RBGC_ARK_BASENAME_ATTEST}   per-platform ${RBYC_PROVENANCE}-carrying image (one per architecture)"
  buh_line "   ${RBGC_ARK_BASENAME_ABOUT}    ${RBYC_SBOM} plus build info"
  buh_line "   ${RBGC_ARK_BASENAME_VOUCH}    SLSA ${RBYC_PROVENANCE} verification record"
  buh_line "   ${RBGC_ARK_BASENAME_DIAGS}    diagnostics from the build"
  buh_e
  buyy_tt_yawp "${RBZ_PLUMB_FULL}";     local -r z_tt_plumb_full="${z_buym_yelp}"
  buyy_tt_yawp "${RBZ_PLUMB_COMPACT}";  local -r z_tt_plumb_compact="${z_buym_yelp}"
  buh_line "${RBYC_PLUMB} is the pattern-driven inspector — ${z_tt_plumb_full}"
  buh_line "walks every ark, ${z_tt_plumb_compact} names them at a glance."
  buh_e

  buh_tt "Return to start: " "${RBZ_ONBOARD_START_HERE}"
  buh_e
}

# eof
