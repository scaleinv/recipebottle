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
# Recipe Bottle Handbook Onboarding - Director Graft Mode
#
# Teaches graft mode using rbev-graft-demo: push a locally-built
# image to the Depot. The Director owns the entire build; SLSA
# cannot vouch for this image. The Vouch verdict reads GRAFTED —
# an explicit signal that provenance stops at the local machine.
# No project Dockerfile, no Pouch, no Cloud Build for the image
# itself (about+vouch metadata still runs on the reliquary), no
# Nameplate, no Crucible — this vessel exists as teaching contrast
# in the trust hierarchy across the three ordain modes.

set -euo pipefail

test -z "${ZRBHODG_SOURCED:-}" || return 0
ZRBHODG_SOURCED=1

rbho_director_graft() {
  zrbho_sentinel

  buc_doc_brief "${RBHO_TRACK_GRAFT} — push locally-built image, inspect GRAFTED Vouch verdict"
  buc_doc_shown || return 0

  local -r z_vessel="rbev-graft-demo"
  local -r z_vessel_rbrv="${RBRR_VESSEL_DIR}/${z_vessel}/${RBCC_rbrv_file}"
  local -r z_local_tag="graft-busybox:local"


  local z_has_depot=0
  if test -f "${RBCC_rbrd_file}"; then
    local z_line=""
    while IFS= read -r z_line; do
      case "${z_line}" in RBRD_DEPOT_MONIKER=?*) z_has_depot=1; break ;; esac
    done < "${RBCC_rbrd_file}"
  fi

  local z_vessel_ready=0
  if test -f "${z_vessel_rbrv}"; then
    local z_mode=""
    z_mode=$(zrbho_po_extract_capture "${z_vessel_rbrv}" "RBRV_VESSEL_MODE") || z_mode=""
    test "${z_mode}" = "rbnve_graft" && z_vessel_ready=1
  fi

  local z_vessel_yoked=0
  if test -f "${z_vessel_rbrv}"; then
    local z_vessel_stamp=""
    z_vessel_stamp=$(zrbho_po_extract_capture "${z_vessel_rbrv}" "RBRV_RELIQUARY") || z_vessel_stamp=""
    test -n "${z_vessel_stamp}" && z_vessel_yoked=1
  fi

  local z_grafted_installed=0
  if command -v docker >/dev/null 2>&1; then
    local z_project_id=""
    local z_region=""
    if test -f "${RBCC_rbrd_file}"; then
      z_project_id=$(zrbho_po_extract_capture "${RBCC_rbrd_file}" "RBRD_DEPOT_MONIKER") || z_project_id=""
      z_region=$(zrbho_po_extract_capture "${RBCC_rbrd_file}" "RBRD_GCP_REGION") || z_region=""
    fi
    if test -n "${z_region}" && test -n "${z_project_id}"; then
      local -r z_gar_prefix="${z_region}${RBGC_GAR_HOST_SUFFIX}/${z_project_id}/"
      local -r z_df_out="${ZRBHO_DOCKER_IMAGES_PREFIX}9_graft_repotag.txt"
      local -r z_df_err="${ZRBHO_DOCKER_STDERR_PREFIX}9_graft_repotag.txt"
      if docker images --format "{{.Repository}}:{{.Tag}}" \
           > "${z_df_out}" 2>"${z_df_err}"; then
        local z_line=""
        while IFS= read -r z_line || test -n "${z_line}"; do
          case "${z_line}" in
            "${z_gar_prefix}"*"${z_vessel}:g"[0-9]*) z_grafted_installed=1; break ;;
          esac
        done < "${z_df_out}"
      fi
    fi
  fi

  buyy_link_yawp "${RBRR_PUBLIC_DOCS_URL}" "Vessel" "${z_vessel}"; local -r z_lk_vessel="${z_buym_yelp}"

  buh_section "Graft — Push a Local Image to the Depot"
  buh_e
  buh_line "${RBYC_CONJURE} and ${RBYC_BIND} teach images whose ${RBYC_PROVENANCE} the"
  buh_line "project can attest. ${RBYC_GRAFT} teaches the opposite case: the"
  buh_line "${RBYC_DIRECTOR} builds an image on their own machine and pushes it to"
  buh_line "the ${RBYC_DEPOT} as-is. No project Dockerfile, no ${RBYC_POUCH}, no SLSA"
  buh_line "${RBYC_PROVENANCE} — Cloud Build never sees the build, only the pushed"
  buh_line "image. About+vouch metadata still runs on ${RBYC_RELIQUARY} tools after"
  buh_line "the push to record the GRAFTED verdict."
  buh_e
  buh_line "This track grafts ${z_lk_vessel} — a teaching ${RBYC_VESSEL} whose sole"
  buh_line "purpose is demonstrating the least-trusted ${RBYC_ORDAIN} mode. You"
  buh_line "build a trivial image locally, graft it, and read the ${RBYC_VOUCH}"
  buh_line "verdict that honestly reports GRAFTED — provenance stops at the"
  buh_line "local machine."
  buh_e

  buh_line "Prerequisites:"
  buh_e
  if test "${z_has_depot}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${RBYC_DEPOT} configured (RBRD_DEPOT_MONIKER populated)"
  else
    buh_line "${RBYC_PROBE_NO}${RBYC_DEPOT} not configured — the ${RBYC_PAYOR} must establish the ${RBYC_DEPOT}:"
    buh_tt "      " "${RBZ_ONBOARD_PAYOR_HB}"
  fi
  if test "${z_vessel_ready}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${z_lk_vessel} ${RBYC_REGIME} present (RBRV_VESSEL_MODE=rbnve_graft)"
  else
    buyy_cmd_yawp "${z_vessel_rbrv}"; local -r z_lk_rbrv_missing="${z_buym_yelp}"
    buh_line "${RBYC_PROBE_NO}${z_lk_vessel} ${RBYC_REGIME} missing or not a graft vessel: ${z_lk_rbrv_missing}"
  fi
  buh_e

  if test "${z_has_depot}" = "0" || test "${z_vessel_ready}" = "0"; then
    buh_error "Complete the prerequisites above before continuing."
    buh_e
    buh_tt "Return to start: " "${RBZ_ONBOARD_START_HERE}"
    buh_e
    return 0
  fi

  buh_section "Why Graft exists"
  buh_e
  buh_line "${RBYC_GRAFT} is the development and prototyping path — you have an"
  buh_line "image on your workstation, you want it in the ${RBYC_DEPOT}, and"
  buh_line "forcing a Cloud Build roundtrip would slow you down. The trade"
  buh_line "is honest: the resulting ${RBYC_HALLMARK} carries no SLSA chain"
  buh_line "because Cloud Build never ran."
  buh_e
  buh_line "Three ${RBYC_ORDAIN} modes, three trust contracts:"
  buh_e
  buh_line "  ${RBYC_CONJURE}  Cloud Build constructs the image from the project's"
  buh_line "            Dockerfile. Trust the build chain (SLSA ${RBYC_PROVENANCE})."
  buh_line "  ${RBYC_BIND}     Mirror an upstream image by digest. Trust the"
  buh_line "            upstream publisher; the digest pins what you got."
  buh_line "  ${RBYC_GRAFT}    Push a locally-built image. Trust the local machine"
  buh_line "            and the ${RBYC_DIRECTOR} who operated it."
  buh_e
  buh_line "${RBYC_GRAFT} is not a failure mode — it is the mode you pick when"
  buh_line "a locally-built image is the right answer. ${RBYC_VOUCH} will report"
  buh_line "GRAFTED so anyone reading the ${RBYC_DEPOT} downstream can see the"
  buh_line "trust level at a glance."
  buh_e

  buh_step_style "Step " " — "

  buh_step1 "Build a local image"
  buh_e
  buh_line "${z_lk_vessel} ships with no Dockerfile. The ${RBYC_VESSEL} ${RBYC_REGIME}"
  buh_line "declares RBRV_VESSEL_MODE=rbnve_graft and names the local image tag the"
  buh_line "${RBYC_GRAFT} operation will push — everything else about the image"
  buh_line "is your concern. Any local Docker image works; we use busybox as"
  buh_line "a deliberately trivial target so the focus stays on the trust"
  buh_line "model, not the image contents."
  buh_e
  buh_line "Pull and tag busybox under a teaching identifier:"
  buh_e
  buh_code "   docker pull busybox:latest"
  buh_code "   docker tag busybox:latest ${z_local_tag}"
  buh_e
  buyy_cmd_yawp "${z_vessel_rbrv}"; local -r z_lk_rbrv="${z_buym_yelp}"
  buyy_cmd_yawp "RBRV_GRAFT_IMAGE"; local -r z_lk_rbrv_field="${z_buym_yelp}"
  buh_line "Then open ${z_lk_rbrv} and set ${z_lk_rbrv_field} to the tag you chose:"
  buh_e
  buh_code "   RBRV_GRAFT_IMAGE=${z_local_tag}"
  buh_e
  buh_line "${RBYC_GRAFT} reads this value and looks up that tag in your local"
  buh_line "Docker image cache at ${RBYC_ORDAIN} time. The tag is the handoff"
  buh_line "between what you built and what the ${RBYC_DEPOT} receives."
  buh_e

  buh_step1 "Yoke every ${RBYC_VESSEL} to a ${RBYC_RELIQUARY}"
  buh_e
  buh_line "Every ${RBYC_ORDAIN}-path ${RBYC_VESSEL} — ${RBYC_CONJURE}, ${RBYC_BIND}, and"
  buh_line "${RBYC_GRAFT} — needs a ${RBYC_RELIQUARY} touchmark in its ${RBYC_RBRV}. ${RBYC_GRAFT}"
  buh_line "skips Cloud Build for the image push, but the about+vouch metadata"
  buh_line "that follows runs on ${RBYC_RELIQUARY} tool images (gcloud, docker,"
  buh_line "alpine, syft) just like the other modes."
  buh_e
  buh_line "If you completed ${RBHO_TRACK_FIRST_BUILD}, your ${RBYC_RELIQUARY} is already"
  buh_line "conclaved. Otherwise conclave it now — once per ${RBYC_DEPOT}, shared"
  buh_line "across every ${RBYC_VESSEL}:"
  buh_e
  buh_tt "   " "${RBZ_CONCLAVE_RELIQUARY}"
  buh_e
  buyy_cmd_yawp "r260324193326"; local -r z_ds_example="${z_buym_yelp}"
  buh_line "Conclave prints a stamp (e.g., ${z_ds_example}). Yoke wildcard-fans the"
  buh_line "stamp into every ${RBYC_VESSEL}'s ${RBYC_RBRV} under \${RBRR_VESSEL_DIR}"
  buh_line "in one pass — there is no per-vessel argument:"
  buh_e
  buh_tt "   " "${RBZ_YOKE_RELIQUARY}" "" " <stamp>"
  buh_e
  buh_line "Yoke validates the stamp once against GAR, then rewrites RBRV_RELIQUARY"
  buh_line "in every ${RBYC_VESSEL}'s ${RBYC_RBRV}. Commit the changes."
  buh_e
  buh_line "Reminder: yoking links the new ${RBYC_RELIQUARY} into the ${RBYC_VESSEL}"
  buh_line "${RBYC_REGIME}, but existing ${RBYC_VESSEL} images still embed the old tool"
  buh_line "versions until you rebuild them via ${RBYC_ORDAIN}."
  buh_e
  if test "${z_vessel_yoked}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${z_lk_vessel} ${RBYC_RELIQUARY} touchmark set"
  else
    buh_line "${RBYC_PROBE_NO}${z_lk_vessel} ${RBYC_RELIQUARY} touchmark not set — yoke above before ${RBYC_ORDAIN}"
  fi
  buh_e

  buh_step1 "${RBYC_GRAFT} — push the local image"
  buh_e
  buh_line "${RBYC_ORDAIN} reads RBRV_VESSEL_MODE from the ${RBYC_RBRV} and routes"
  buh_line "accordingly. For ${RBYC_GRAFT}, that means: look up RBRV_GRAFT_IMAGE"
  buh_line "in your local Docker image cache, tag it for the ${RBYC_DEPOT}'s"
  buh_line "GAR repository, and push directly. No Dockerfile is read. No ${RBYC_POUCH}"
  buh_line "is assembled. After the push, a combined Cloud Build job runs the"
  buh_line "about steps (syft ${RBYC_SBOM}, build_info) followed by ${RBYC_VOUCH} steps to"
  buh_line "record the GRAFTED verdict."
  buh_e
  buh_line "The ${RBYC_HALLMARK} format encodes two timestamps: the image's own"
  buh_line "creation time (from ${RBYC_DEPOT} layer metadata) and the push time."
  buh_line "Both come from the host — there is no server-side notary."
  buh_e
  buh_line "${RBYC_ORDAIN}:"
  buh_e
  buh_tt "   " "${RBZ_ORDAIN_HALLMARK}" "" " ${z_vessel}"
  buh_e
  buh_line "Wall-clock: a few minutes — the image push completes in seconds, and"
  buh_line "the combined about+vouch Cloud Build job that follows takes the rest."
  buh_e

  buh_step1 "Inspect the ${RBYC_VOUCH} verdict"
  buh_e
  buh_line "${RBYC_VOUCH} is mode-aware. For ${RBYC_CONJURED} ${RBYC_HALLMARKS} it verifies"
  buh_line "the SLSA ${RBYC_PROVENANCE} chain. For ${RBYC_BIND} it attests the"
  buh_line "digest-pin relationship to the upstream image. For ${RBYC_GRAFT}"
  buh_line "there is nothing to verify — no build record, no upstream digest,"
  buh_line "just an image the ${RBYC_DIRECTOR} asserted is theirs. The verdict"
  buh_line "records that honestly as GRAFTED."
  buh_e
  buh_line "${RBYC_VOUCH} the ${RBYC_HALLMARKS}:"
  buh_e
  buh_tt "   " "${RBZ_VOUCH_HALLMARKS}"
  buh_e
  buh_line "Then ${RBYC_TALLY} to read each ${RBYC_HALLMARK}'s health:"
  buh_e
  buh_tt "   " "${RBZ_TALLY_HALLMARKS}"
  buh_e
  buh_line "Look for the ${z_lk_vessel} ${RBYC_HALLMARK} with verdict GRAFTED. The"
  buh_line "verdict is not a warning and not a defect — it is the ${RBYC_DEPOT}"
  buh_line "telling anyone reading it that this image's trust chain ends at"
  buh_line "the local machine that pushed it."
  buh_e
  if test "${z_grafted_installed}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${z_lk_vessel} grafted ${RBYC_HALLMARK} present in the local ${RBYC_DEPOT} cache"
  else
    buh_line "${RBYC_PROBE_NO}No grafted ${RBYC_HALLMARK} for ${z_lk_vessel} seen locally — run ${RBYC_ORDAIN} above"
  fi
  buh_e

  buh_section "What you learned"
  buh_e
  buh_line "You completed the least-trusted ${RBYC_ORDAIN} mode end to end:"
  buh_e
  buh_line "  1. Built a local image — your machine, your Docker, your call"
  buh_line "  2. ${RBYC_GRAFT} pushed it to the ${RBYC_DEPOT} — bytes as they left your workstation"
  buh_line "  3. ${RBYC_VOUCH} reports GRAFTED — honest signal that SLSA cannot cover this"
  buh_e
  buh_line "The three ${RBYC_ORDAIN} modes now form a trust hierarchy you can"
  buh_line "read at a glance from the ${RBYC_VOUCH} verdict: ${RBYC_CONJURE} (SLSA),"
  buh_line "${RBYC_BIND} (digest-pin), ${RBYC_GRAFT} (GRAFTED). A ${RBYC_NAMEPLATE} can"
  buh_line "mix modes freely because runtime containment is enforced by the"
  buh_line "${RBYC_SENTRY}, not by the build chain."
  buh_e
  buh_line "${z_lk_vessel} has no ${RBYC_NAMEPLATE} and never runs in a ${RBYC_CRUCIBLE}"
  buh_line "— it is pure teaching contrast. For production ${RBYC_GRAFT} usage,"
  buh_line "the pattern is the same: declare RBRV_VESSEL_MODE=rbnve_graft, point"
  buh_line "RBRV_GRAFT_IMAGE at your local tag, ${RBYC_ORDAIN}, and ${RBYC_VOUCH}"
  buh_line "will record GRAFTED against that ${RBYC_HALLMARK}."
  buh_e

  buh_tt "Return to start: " "${RBZ_ONBOARD_START_HERE}"
  buh_e
}

# eof
